#!/usr/bin/env bash
#
# Checks on the example files themselves.
#
#   1. The placeholder SHAs are still placeholders. No real 40-character SHA
#      may appear anywhere under examples/ - a real one would be a hash a
#      reader could copy, which is exactly what the all-zero convention is
#      there to prevent.
#   2. Every placeholder carries a trailing version comment. Without it the
#      placeholder says nothing about what to pin, and tools/pin.sh has
#      nothing to work from.
#   3. Every one of those versions still resolves upstream today, and the
#      hydrated file still passes actionlint. This is the path a reader takes
#      - copy the example, run pin.sh - exercised end to end.
#
# It does not prove the workflows execute. That is what the generated smoke
# workflows in .github/workflows are for; see tools/materialise.sh.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# References that are fictional by design and cannot resolve anywhere.
FICTIONAL="some-org/some-build-action"

fail=0
ok()  { printf '  ok    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; fail=1; }

echo "1. Placeholder SHAs are still placeholders"
if real=$(grep -rnE '@[0-9a-f]{40}' examples/ | grep -vE '@0{40}'); then
  bad "a real commit SHA has appeared under examples/ - the placeholders are deliberate"
  printf '%s\n' "$real" | sed 's/^/        /'
else
  ok "every 40-character ref under examples/ is the all-zero placeholder"
fi

echo
echo "2. Every placeholder says what version it stands for"
placeholders=0
while IFS= read -r hit; do
  placeholders=$((placeholders + 1))
  printf '%s' "$hit" | grep -qE '@0{40}[[:space:]]*#[[:space:]]*[^[:space:]]' \
    || bad "placeholder with no version comment: $hit"
done < <(grep -rn '@0\{40\}' examples/ | grep -E '^[^:]+:[0-9]+:[[:space:]]*-?[[:space:]]*uses:')
[ "$fail" -eq 0 ] && ok "$placeholders placeholder(s), each with a version comment"

echo
echo "3. Hydrating each example the way a reader would"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mapfile -t PLACEHOLDER_FILES < <(grep -rlE '@0{40}' examples/ | sort)
for f in "${PLACEHOLDER_FILES[@]}"; do
  out="$tmp/$(echo "$f" | tr '/' '_')"
  if ! result=$(./tests/hydrate.sh "$f" "$out" 2>&1); then
    bad "$f - hydration failed"
    printf '%s\n' "$result" | sed 's/^/        /'
    continue
  fi

  unresolved=$(printf '%s\n' "$result" | awk '/^UNRESOLVED/ { print $2 }' | grep -vxF "$FICTIONAL")
  if [ -n "$unresolved" ]; then
    bad "$f - version comment no longer resolves upstream: $(echo "$unresolved" | tr '\n' ' ')"
    continue
  fi

  if lint=$(actionlint -no-color -oneline "$out" 2>&1) && [ -z "$lint" ]; then
    n=$(printf '%s\n' "$result" | grep -c '^RESOLVED')
    ok "$f - $n reference(s) resolved, hydrated file lints clean"
  else
    bad "$f - hydrated file does not lint"
    printf '%s\n' "$lint" | sed 's/^/        /'
  fi
done

echo
[ "$fail" -eq 0 ] && echo "example integrity checks passed" || echo "example integrity checks FAILED"
exit "$fail"
