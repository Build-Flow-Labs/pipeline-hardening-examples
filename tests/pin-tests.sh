#!/usr/bin/env bash
#
# Behaviour tests for tools/pin.sh.
#
# These hit github.com over git, not the API, which is the whole reason
# pin.sh works without a token. They will fail if the network is unavailable;
# that is a real failure for a tool whose only job is resolving remote refs.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
ok()  { printf '  ok    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; fail=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- an annotated tag resolves to the commit, not to the tag object --------
#
# This is the case that is easy to get wrong and silent when you do: an
# annotated tag's ref points at a tag object, and pinning that SHA gives you
# a reference GitHub Actions cannot check out. git/git tags are annotated,
# which makes them a good witness; actions/* tags are all lightweight today.
tag_object=$(git ls-remote https://github.com/git/git refs/tags/v2.43.0 | awk '{print $1}')
commit=$(git ls-remote https://github.com/git/git 'refs/tags/v2.43.0^{}' | awk '{print $1}')
got=$(./tools/pin.sh git/git v2.43.0)

if [ "$got" = "git/git@$commit # v2.43.0" ]; then
  ok "annotated tag resolves to the underlying commit"
elif printf '%s' "$got" | grep -qF "$tag_object"; then
  bad "annotated tag resolved to the TAG OBJECT ($tag_object), not the commit"
else
  bad "annotated tag: unexpected output '$got'"
fi

# --- a lightweight tag resolves directly ----------------------------------
expected=$(git ls-remote https://github.com/actions/checkout refs/tags/v4 | awk '{print $1}')
got=$(./tools/pin.sh actions/checkout v4)
if [ "$got" = "actions/checkout@$expected # v4" ]; then
  ok "lightweight tag resolves to the commit it names"
else
  bad "lightweight tag: got '$got', expected 'actions/checkout@$expected # v4'"
fi

# --- a branch resolves too -------------------------------------------------
got=$(./tools/pin.sh actions/checkout main)
if printf '%s' "$got" | grep -qE '^actions/checkout@[0-9a-f]{40} # main$'; then
  ok "a branch name resolves to its head commit"
else
  bad "branch: got '$got'"
fi

# --- a tag that does not exist fails, loudly and with nothing on stdout ----
out=$(./tools/pin.sh actions/checkout v0-does-not-exist 2>/dev/null)
rc=$?
if [ "$rc" -ne 0 ] && [ -z "$out" ]; then
  ok "a nonexistent tag exits non-zero and prints nothing to stdout"
else
  bad "nonexistent tag: exit $rc, stdout '$out' - a caller could pin that"
fi

# --- wrong usage fails rather than guessing --------------------------------
if ./tools/pin.sh actions/checkout >/dev/null 2>&1; then
  bad "missing argument was accepted"
else
  ok "missing argument is rejected"
fi

# --- --write pins, keeps existing pins, and is idempotent ------------------
cat > "$tmp/wf.yml" <<'YAML'
name: build
on: [push]
permissions: {}
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4.1.0
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
      - uses: nonexistent-org-xyz/nonexistent-action@v9
      - run: 'echo "not a uses: line"'
YAML

./tools/pin.sh --write "$tmp/wf.yml" 2>/dev/null
first=$(cat "$tmp/wf.yml")

if [ -f "$tmp/wf.yml.bak" ]; then
  ok "--write keeps the original as .bak"
else
  bad "--write did not leave a .bak"
fi

if printf '%s' "$first" | grep -qE 'actions/checkout@[0-9a-f]{40} # v4$'; then
  ok "--write pinned a mutable tag"
else
  bad "--write did not pin actions/checkout@v4"
fi

if printf '%s' "$first" | grep -qF 'nonexistent-org-xyz/nonexistent-action@v9'; then
  ok "--write left an unresolvable reference alone"
else
  bad "--write mangled a reference it could not resolve"
fi

if printf '%s' "$first" | grep -qF 'run: '"'"'echo "not a uses: line"'"'"; then
  ok "--write left non-uses lines alone"
else
  bad "--write touched a run: line"
fi

./tools/pin.sh --write "$tmp/wf.yml" 2>/dev/null
if [ "$first" = "$(cat "$tmp/wf.yml")" ]; then
  ok "--write is idempotent"
else
  bad "--write changed the file on a second run"
fi

if python3 -c '
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
raise SystemExit(0 if isinstance(doc, dict) else "not a mapping")
' "$tmp/wf.yml" 2>/dev/null; then
  ok "--write output still parses as YAML"
else
  bad "--write produced something that no longer parses"
fi

echo
[ "$fail" -eq 0 ] && echo "pin.sh behaviour tests passed" || echo "pin.sh behaviour tests FAILED"
exit "$fail"
