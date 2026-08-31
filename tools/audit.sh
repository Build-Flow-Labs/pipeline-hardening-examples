#!/usr/bin/env bash
#
# audit.sh - answer the five questions from the talk against a repository.
#
#   ./tools/audit.sh [path-to-repo]     (defaults to the current directory)
#
# WHAT THIS IS: a fast, dependency-free first pass over .github/workflows,
# using line matching rather than a YAML parser. It will miss things and it
# will occasionally flag something harmless. Treat the output as a list of
# places to look, not a verdict.
#
# WHAT IT IS NOT: a scanner, a compliance report, or evidence of anything.
# Exposure is not the same as compromise.

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

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No workflow files in $WF_DIR"
  exit 0
fi

rel() { printf '%s' "${1#"$REPO"/}"; }

echo "${B}Pipeline audit${N} - $REPO"
echo "${DIM}${#FILES[@]} workflow file(s). Heuristic line matching, not a parser.${N}"

# ---------------------------------------------------------------- Q1
echo
echo "${B}1. Can anything in our build change without a commit changing?${N}"
echo "${DIM}   Third-party steps referenced by a movable tag or branch.${N}"
mutable_total=0
for f in "${FILES[@]}"; do
  # `uses:` values that are owner/repo@ref where ref is not a 40-hex SHA.
  # Skips local (./) and docker:// references.
  hits=$(grep -nE '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*[^.][^[:space:]]+@[^[:space:]]+' "$f" 2>/dev/null \
         | grep -vE '@[0-9a-fA-F]{40}([[:space:]]|$|#)' || true)
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
echo "${DIM}   pull_request_target and workflow_run run with base-repo${N}"
echo "${DIM}   credentials. Checking out fork code in one is the pwn request.${N}"
risky=0
for f in "${FILES[@]}"; do
  if grep -qE '^[[:space:]]*(pull_request_target|workflow_run):' "$f" 2>/dev/null; then
    risky=$((risky + 1))
    if grep -qE 'pull_request\.head\.(sha|ref)|github\.event\.workflow_run\.head' "$f" 2>/dev/null; then
      echo "   ${R}$(rel "$f")${N} - untrusted trigger AND checks out fork code"
    else
      echo "   ${Y}$(rel "$f")${N} - untrusted trigger"
    fi
    # Direct interpolation of attacker-controlled text into a shell.
    if grep -qE '\$\{\{[^}]*(pull_request\.title|pull_request\.body|head_ref|\.head\.ref)' "$f" 2>/dev/null; then
      echo "      ${R}interpolates attacker-controlled text - check it is not inside run:${N}"
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
  if grep -qE '^[[:space:]]{0,6}[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*\$\{\{[[:space:]]*secrets\.' "$f" 2>/dev/null; then
    n=$(grep -cE '\$\{\{[[:space:]]*secrets\.' "$f" 2>/dev/null || echo 0)
    echo "   ${Y}$(rel "$f")${N} - $n secret reference(s), some broadly scoped"
    broad=$((broad + 1))
  fi
done
[ "$broad" -eq 0 ] && echo "   ${G}No broadly scoped secret definitions found.${N}" \
                   || echo "   ${DIM}See examples/04-scope-secrets-and-runners.${N}"

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
