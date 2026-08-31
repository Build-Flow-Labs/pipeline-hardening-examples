#!/usr/bin/env bash
#
# Tests for tools/audit.sh, in two parts.
#
#   1. Against fixtures built from the examples themselves: the 'before' set
#      must produce the findings those examples exist to demonstrate, and the
#      'after' set must come back clean. If audit.sh stops flagging what
#      before.yml does, or starts flagging what after.yml does, one of the
#      two is wrong and this says so.
#
#   2. Against this repository: our own workflows must pass the five
#      questions. This is the check PUBLISH.md asks for by hand, made
#      continuous. A repository of hardening advice with a mutable action
#      reference in its own CI is not a good look.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
ok()  { printf '  ok    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; fail=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# has <output> <description> <literal-text>
has() {
  if printf '%s' "$1" | grep -qF "$3"; then ok "$2"; else bad "$2 (expected to see: $3)"; fi
}
lacks() {
  if printf '%s' "$1" | grep -qF "$3"; then bad "$2 (did not expect: $3)"; else ok "$2"; fi
}

# --- the 'before' set: every question should have something to say ---------
mkdir -p "$tmp/before/.github/workflows"
for f in examples/*/before.yml; do
  cp "$f" "$tmp/before/.github/workflows/$(basename "$(dirname "$f")").yml"
done
out=$(./tools/audit.sh "$tmp/before")

echo "1. The 'before' examples, which should light up"
has "$out" "Q1 reports mutable references"       "mutable reference(s). See examples/01-pin-actions."
has "$out" "Q2 reports missing permissions"      "no permissions: block anywhere"
has "$out" "Q3 reports the pwn request shape"    "untrusted trigger AND checks out fork code"
has "$out" "Q3 reports the injectable title"     "interpolates attacker-controlled text"
has "$out" "Q4 reports broadly scoped secrets"   "secret reference(s), some broadly scoped"
has "$out" "Q4 reports the self-hosted runner"   "Self-hosted runners:"
has "$out" "Q5 ties back to the mutable refs"    "would change silently."

# --- the 'after' set: clean, with one deliberate exception -----------------
mkdir -p "$tmp/after/.github/workflows"
for f in examples/*/after.yml examples/03-quarantine-untrusted-triggers/labeler.yml; do
  cp "$f" "$tmp/after/.github/workflows/$(basename "$(dirname "$f")")-$(basename "$f")"
done
out=$(./tools/audit.sh "$tmp/after")

echo
echo "2. The 'after' examples, which should be clean"
has   "$out" "Q1 finds nothing mutable"     "None found - every third-party step is SHA-pinned."
has   "$out" "Q2 finds every file declares" "Every workflow declares its permissions."
has   "$out" "Q4 finds no broad secrets"    "No broadly scoped secret definitions found."
has   "$out" "Q5 is satisfied"              "Pinned references cannot change without a commit in this repo."

# The labeler example keeps pull_request_target on purpose - that is the
# point of it - so Q3 SHOULD name it. What it must not say is that the
# workflow checks out fork code, because it deliberately does not.
has   "$out" "Q3 still names the labeler's untrusted trigger" "untrusted trigger"
lacks "$out" "Q3 does not accuse the labeler of checking out fork code" \
      "untrusted trigger AND checks out fork code"

# --- this repository -------------------------------------------------------
out=$(./tools/audit.sh .)

echo
echo "3. This repository's own workflows"
has "$out" "Q1 clean" "None found - every third-party step is SHA-pinned."
has "$out" "Q2 clean" "Every workflow declares its permissions."
has "$out" "Q3 clean" "No untrusted-context triggers."
has "$out" "Q4 clean" "No broadly scoped secret definitions found."
has "$out" "Q5 clean" "Pinned references cannot change without a commit in this repo."

echo
if [ "$fail" -eq 0 ]; then echo "audit.sh tests passed"; else echo "audit.sh tests FAILED"; fi
exit "$fail"
