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
has "$out" "Q4 reports broadly scoped secrets"   "secret reference(s) above step level"
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

# --- shapes taken from real repositories ----------------------------------
#
# Every case below was found in a large public repository while checking what
# audit.sh gets right and wrong. They are here so the answers stay put.
mkdir -p "$tmp/real/.github/workflows" "$tmp/real/.github/actions/local"

cat > "$tmp/real/.github/workflows/refs.yml" <<'YAML'
name: refs
on: [push]
permissions: {}
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: 'actions/checkout@11d5960a326750d5838078e36cf38b85af677262'
      - uses: docker://hadolint/hadolint:v2.12.0@sha256:30a8fd2e785ab6176eed53f74769e04f125afb2f74a6c52aef7d463583b6d45e
      - uses: some-org/some-action@v1
YAML

cat > "$tmp/real/.github/workflows/inherit.yml" <<'YAML'
name: inherit
on: [push]
permissions: {}
jobs:
  call:
    uses: ./.github/workflows/other.yml
    secrets: inherit
YAML

cat > "$tmp/real/.github/workflows/env-indirection.yml" <<'YAML'
name: env-indirection
on:
  pull_request_target:
permissions: {}
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - env:
          PR_TITLE: ${{ github.event.pull_request.title }}
        run: echo "$PR_TITLE"
YAML

cat > "$tmp/real/.github/workflows/into-shell.yml" <<'YAML'
name: into-shell
on:
  pull_request_target:
permissions: {}
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - run: |
          echo "Reviewing ${{ github.event.pull_request.title }}"
YAML

cat > "$tmp/real/.github/workflows/comment-trigger.yml" <<'YAML'
name: comment-trigger
on:
  issue_comment:
    types: [created]
permissions: {}
jobs:
  respond:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello
YAML

# A trailing comment on runs-on: is ordinary style, and read naively it makes
# a standard runner label look like a custom one.
cat > "$tmp/real/.github/workflows/commented.yml" <<'YAML'
name: commented
on: [push]
permissions: {}
jobs:
  build:
    runs-on: ubuntu-latest        # ephemeral, discarded after the job
    permissions:
      contents: read
    steps:
      - run: echo hello
  call:
    uses: ./.github/workflows/other.yml
    secrets: inherit              # every secret, with a comment after it
YAML

cat > "$tmp/real/.github/actions/local/action.yml" <<'YAML'
name: local composite
runs:
  using: composite
  steps:
    - uses: third-party/action@v3
      shell: bash
YAML

out=$(./tools/audit.sh "$tmp/real")

echo
echo "4. Shapes found in real repositories"
lacks "$out" "a quoted but SHA-pinned reference is not called mutable" \
      "uses: 'actions/checkout@11d5960a326750d5838078e36cf38b85af677262'"
lacks "$out" "a docker:// image pinned by digest is not called mutable" \
      "docker://hadolint"
has   "$out" "a genuinely movable tag is still reported"        "some-org/some-action@v1"
has   "$out" "a mutable ref inside a composite action is found" "third-party/action@v3"
has   "$out" "composite actions are counted in the header"      "composite action(s)"
has   "$out" "secrets: inherit is reported"                     "secrets: inherit"
has   "$out" "secrets: inherit is found with a comment after it"  "commented.yml"
lacks "$out" "a commented runs-on: is not mistaken for a custom label" \
      "ubuntu-latest        #"
has   "$out" "issue_comment counts as an untrusted trigger"     "comment-trigger.yml"
has   "$out" "interpolation into a run: block is reported"      "interpolates attacker-controlled text into a shell"

# The env: indirection is the fix example 03 teaches. Reporting it as an
# injection teaches people to ignore the finding.
q3=$(printf '%s' "$out" | sed -n '/^3\./,/^4\./p')
n_shell=$(printf '%s' "$q3" | grep -c 'interpolates attacker-controlled text into a shell')
if [ "$n_shell" -eq 1 ]; then
  ok "the env: indirection pattern is not reported as an injection"
else
  bad "expected exactly one injection finding, got $n_shell (env: indirection is the fix, not the bug)"
fi

# --- the demo fixture ------------------------------------------------------
#
# DEMO.md walks through tools/audit.sh against demo/legacy-service, and the
# whole point is that every question has something to say. A demo that has
# quietly stopped demonstrating is worse than no demo, and it would be found
# out on stage rather than here.
out=$(./tools/audit.sh demo/legacy-service)

echo
echo "5. The demo fixture still demonstrates all five questions"
has "$out" "Q1 movable tags, in workflows and in a composite action" \
    "mutable reference(s). See examples/01-pin-actions."
has "$out" "Q1 reaches inside the local composite action" "some-vendor/cache-restore@v1"
has "$out" "Q2 no permissions block anywhere"            "no permissions: block anywhere"
has "$out" "Q3 the pwn request"                          "untrusted trigger AND checks out fork code"
has "$out" "Q3 the PR title reaching a shell"            "interpolates attacker-controlled text into a shell"
has "$out" "Q4 four credentials above step level"        "4 secret reference(s) above step level"
has "$out" "Q4 secrets: inherit"                         "the called workflow gets every secret"
has "$out" "Q4 the self-hosted runner"                   "Self-hosted runners:"
has "$out" "Q5 ties back to the movable references"      "would change silently."

# The fixture must stay inert. It is only safe to keep a deliberate pwn
# request in a public repository because GitHub will not run it from here.
if [ -e ".github/workflows/pr-labeler.yml" ]; then
  bad "the demo pwn request has been copied into .github/workflows, where it WOULD run"
else
  ok "the demo workflows are nested under demo/, where GitHub will not run them"
fi

echo
if [ "$fail" -eq 0 ]; then echo "audit.sh tests passed"; else echo "audit.sh tests FAILED"; fi
exit "$fail"
