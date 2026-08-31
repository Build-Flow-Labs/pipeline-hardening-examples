#!/usr/bin/env bash
#
# audit.sh - answer the five questions from the talk against a repository.
#
#   ./tools/audit.sh [path-to-repo]     (defaults to the current directory)
#
# WHAT THIS IS: a fast, dependency-free first pass over .github/workflows and
# any composite actions in .github/actions, using line matching rather than a
# YAML parser. It will miss things and it will occasionally flag something
# harmless. Treat the output as a list of places to look, not a verdict.
#
# WHAT IT IS NOT: a scanner, a compliance report, or evidence of anything.
# Exposure is not the same as compromise.
#
# WHAT IT CANNOT SEE, measured against 530 workflow files in 14 large public
# repositories (see tests/audit-tests.sh for the regression fixtures):
#
#   - Reusable workflows called with `uses:`. It reads the call, not the
#     workflow being called, so a permissions or checkout problem one hop
#     away is invisible.
#   - The org and repository settings that decide what a token really gets,
#     which is the point of question 2 rather than a gap in it.
#   - Whether a runner label like `ubuntu-x64-large` is a GitHub larger
#     runner or somebody's long-lived box. Only you know that; question 4
#     counts them and asks.
#   - Whether an interpolation sits somewhere a shell will evaluate. It
#     checks `run:` lines and `run:` block scalars, and will miss an
#     injection that reaches a shell by a route this does not model.

set -uo pipefail

REPO="${1:-.}"
WF_DIR="$REPO/.github/workflows"

if [ ! -d "$WF_DIR" ]; then
  echo "No .github/workflows in '$REPO' - nothing to audit."
  exit 0
fi

# Colour only when attached to a terminal.
if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[31m'; Y=$'\033[33m'; G=$'\033[32m'; N=$'\033[0m'
else
  B=""; DIM=""; R=""; Y=""; G=""; N=""
fi

shopt -s nullglob
FILES=("$WF_DIR"/*.yml "$WF_DIR"/*.yaml)
shopt -u nullglob

# Composite actions pull third-party steps too, and a repository whose
# workflows are fully pinned can still reach a movable tag through one of its
# own actions. Question 1 reads these; the rest do not apply to them.
ACTION_FILES=()
for candidate in "$REPO/action.yml" "$REPO/action.yaml"; do
  [ -f "$candidate" ] && ACTION_FILES+=("$candidate")
done
while IFS= read -r a; do
  [ -n "$a" ] && ACTION_FILES+=("$a")
done < <(find "$REPO/.github/actions" \( -name 'action.yml' -o -name 'action.yaml' \) 2>/dev/null)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No workflow files in $WF_DIR"
  exit 0
fi

rel() { printf '%s' "${1#"$REPO"/}"; }

echo "${B}Pipeline audit${N} - $REPO"
if [ ${#ACTION_FILES[@]} -gt 0 ]; then
  echo "${DIM}${#FILES[@]} workflow file(s), ${#ACTION_FILES[@]} composite action(s). Heuristic line matching, not a parser.${N}"
else
  echo "${DIM}${#FILES[@]} workflow file(s). Heuristic line matching, not a parser.${N}"
fi

# ---------------------------------------------------------------- Q1
echo
echo "${B}1. Can anything in our build change without a commit changing?${N}"
echo "${DIM}   Third-party steps referenced by a movable tag or branch.${N}"
mutable_total=0

# A pinned ref may be quoted, so the character after the 40 hex digits can be
# a quote as well as whitespace, end of line or a comment.
PINNED="@[0-9a-fA-F]{40}([\"'[:space:]]|\$|#)"

# `docker://image:tag@sha256:...` is pinned by digest and is as immutable as
# a commit SHA, but the digest is 64 hex digits, not 40.
DIGEST_PINNED="uses:[[:space:]]*[\"']?docker://[^[:space:]]*@sha256:[0-9a-f]{64}"

for f in "${FILES[@]}" ${ACTION_FILES[@]+"${ACTION_FILES[@]}"}; do
  # `uses:` values that are owner/repo@ref where ref is not a 40-hex SHA.
  # Skips local (./) references.
  hits=$(grep -nE '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*[^.][^[:space:]]+@[^[:space:]]+' "$f" 2>/dev/null \
         | grep -vE "$PINNED" \
         | grep -vE "$DIGEST_PINNED" || true)
  if [ -n "$hits" ]; then
    echo "   ${Y}$(rel "$f")${N}"
    while IFS= read -r line; do
      echo "      ${line%%:*}: $(echo "$line" | sed 's/^[0-9]*://' | sed 's/^[[:space:]]*//')"
      mutable_total=$((mutable_total + 1))
    done <<< "$hits"
  fi
done
[ "$mutable_total" -eq 0 ] && echo "   ${G}None found - every third-party step is SHA-pinned.${N}" \
                           || echo "   ${DIM}$mutable_total mutable reference(s). See examples/01-pin-actions.${N}"

# ---------------------------------------------------------------- Q2
echo
echo "${B}2. What could our build tokens do in the worst case?${N}"
echo "${DIM}   No permissions block means the org/repo default applies, which${N}"
echo "${DIM}   is not visible in the file.${N}"
noperm=0
for f in "${FILES[@]}"; do
  if ! grep -qE '^[[:space:]]*permissions:' "$f" 2>/dev/null; then
    echo "   ${Y}$(rel "$f")${N} - no permissions: block anywhere"
    noperm=$((noperm + 1))
  elif grep -qE '^[[:space:]]*(contents|packages|id-token|actions|deployments):[[:space:]]*write' "$f" 2>/dev/null; then
    echo "   ${DIM}$(rel "$f") - declares write scope (check it is per-job)${N}"
  fi
done
[ "$noperm" -eq 0 ] && echo "   ${G}Every workflow declares its permissions.${N}" \
                    || echo "   ${DIM}$noperm workflow(s) with no declaration. See examples/02-least-privilege-tokens.${N}"

# ---------------------------------------------------------------- Q3
echo
echo "${B}3. Which workflows can an outsider influence?${N}"
echo "${DIM}   pull_request_target, workflow_run and issue_comment run with${N}"
echo "${DIM}   base-repo credentials. Checking out fork code in one is the${N}"
echo "${DIM}   pwn request.${N}"
risky=0
for f in "${FILES[@]}"; do
  if grep -qE '^[[:space:]]*(pull_request_target|workflow_run|issue_comment):' "$f" 2>/dev/null; then
    risky=$((risky + 1))
    if grep -qE 'pull_request\.head\.(sha|ref)|github\.event\.workflow_run\.head' "$f" 2>/dev/null; then
      echo "   ${R}$(rel "$f")${N} - untrusted trigger AND checks out fork code"
    else
      echo "   ${Y}$(rel "$f")${N} - untrusted trigger"
    fi
    # Direct interpolation of attacker-controlled text into a shell. Only a
    # shell matters here: the same expression in `env:` or `with:` is the
    # recommended fix, not the problem, so flagging those trains people to
    # ignore the finding.
    if awk '
      /^[[:space:]]*-?[[:space:]]*run:[[:space:]]*[|>]/ {
        inrun = 1; runindent = match($0, /[^[:space:]]/); next
      }
      inrun && /^[[:space:]]*$/ { next }
      inrun && match($0, /[^[:space:]]/) <= runindent { inrun = 0 }
      {
        if ((inrun || $0 ~ /run:/) &&
            $0 ~ /\$\{\{[^}]*(pull_request\.title|pull_request\.body|head_ref|\.head\.ref)/) {
          found = 1
        }
      }
      END { exit !found }
    ' "$f" 2>/dev/null; then
      echo "      ${R}interpolates attacker-controlled text into a shell${N}"
    fi
  fi
done
[ "$risky" -eq 0 ] && echo "   ${G}No untrusted-context triggers.${N}" \
                   || echo "   ${DIM}See examples/03-quarantine-untrusted-triggers.${N}"

# ---------------------------------------------------------------- Q4
echo
echo "${B}4. Which secrets sit in jobs that run third-party code?${N}"
echo "${DIM}   Secrets defined above step level are visible to every step${N}"
echo "${DIM}   in scope, including actions you did not write.${N}"
broad=0
for f in "${FILES[@]}"; do
  # A secrets reference at low indentation is workflow- or job-level env.
  # A `secrets:` block passing named secrets to a reusable workflow lands at
  # the same indentation, so say what was matched rather than asserting it is
  # too broad: enumerating secrets explicitly is the careful version.
  if grep -qE '^[[:space:]]{0,6}[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*\$\{\{[[:space:]]*secrets\.' "$f" 2>/dev/null; then
    n=$(grep -cE '\$\{\{[[:space:]]*secrets\.' "$f" 2>/dev/null)
    echo "   ${Y}$(rel "$f")${N} - $n secret reference(s) above step level"
    broad=$((broad + 1))
  fi
done

# `secrets: inherit` hands the called workflow every secret in the
# repository. It is the broadest form there is and looks like nothing.
inherit=0
for f in "${FILES[@]}"; do
  n=$(grep -cE '^[[:space:]]*secrets:[[:space:]]*inherit[[:space:]]*$' "$f" 2>/dev/null)
  if [ "${n:-0}" -gt 0 ]; then
    [ "$inherit" -eq 0 ] && echo "   ${R}secrets: inherit${N} - the called workflow gets every secret in the repository:"
    echo "      $(rel "$f") - $n job(s)"
    inherit=$((inherit + 1))
  fi
done

if [ "$broad" -eq 0 ] && [ "$inherit" -eq 0 ]; then
  echo "   ${G}No broadly scoped secret definitions found.${N}"
else
  echo "   ${DIM}See examples/04-scope-secrets-and-runners.${N}"
fi

# self-hosted runners
sh_hits=0
for f in "${FILES[@]}"; do
  if grep -qE '^[[:space:]]*runs-on:.*self-hosted' "$f" 2>/dev/null; then
    [ "$sh_hits" -eq 0 ] && echo "   ${Y}Self-hosted runners:${N}"
    echo "      $(rel "$f")"
    sh_hits=$((sh_hits + 1))
  fi
done
[ "$sh_hits" -gt 0 ] && echo "      ${DIM}Confirm these are ephemeral and unreachable from fork PRs.${N}"

# Runner labels that are neither a GitHub-hosted default nor literally
# self-hosted. A larger GitHub runner is ephemeral and fine; a custom label
# pointing at a long-lived box is example 04. This cannot tell which, and
# neither can anyone reading the file - which is the finding.
unknown=$(for f in "${FILES[@]}"; do
    grep -hE '^[[:space:]]*runs-on:' "$f" 2>/dev/null
  done \
  | sed -E 's/^[[:space:]]*runs-on:[[:space:]]*//; s/[[:space:]]*$//' \
  | grep -vE '^\[?["'"'"']?(ubuntu|windows|macos)-[A-Za-z0-9._-]+["'"'"']?\]?$' \
  | grep -vE 'self-hosted|\$\{\{' \
  | sort -u)

if [ -n "$unknown" ]; then
  count=$(printf '%s\n' "$unknown" | grep -c .)
  echo "   ${Y}$count runner label(s) that are not GitHub-hosted defaults:${N}"
  printf '%s\n' "$unknown" | head -5 | sed 's/^/      /'
  [ "$count" -gt 5 ] && echo "      ${DIM}and $((count - 5)) more${N}"
  echo "      ${DIM}Larger GitHub runners are ephemeral; a label pointing at a${N}"
  echo "      ${DIM}long-lived machine is not. The file does not say which.${N}"
fi

# ---------------------------------------------------------------- Q5
echo
echo "${B}5. If a step we depend on was hijacked for twelve hours, would we know?${N}"
echo "${DIM}   Not answerable from workflow files. Ask it of your monitoring:${N}"
echo "${DIM}   would a tag moving on a dependency generate an alert anyone sees?${N}"
if [ "$mutable_total" -gt 0 ]; then
  echo "   ${R}$mutable_total mutable reference(s) above would change silently.${N}"
else
  echo "   ${G}Pinned references cannot change without a commit in this repo.${N}"
fi

echo
echo "${DIM}Exposure is not compromise. These are conditions that increase loss${N}"
echo "${DIM}if a dependency is compromised, not evidence that anything has been.${N}"
