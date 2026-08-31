#!/usr/bin/env bash
#
# hydrate.sh - turn an example's placeholder pins into real ones, in a copy.
#
#   ./tests/hydrate.sh examples/01-pin-actions/after.yml /tmp/hydrated.yml
#
# The after.yml files carry all-zero SHAs on purpose, so nobody copies a
# stale hash and ships it. That also means they cannot be linted or run as
# they stand. This reverses the placeholder using the trailing version
# comment, then puts the file through tools/pin.sh exactly as a reader would.
#
# It never touches the file it was given. The zeros stay in the repository.
#
# Prints one line per reference:
#   RESOLVED    owner/repo ref sha
#   UNRESOLVED  owner/repo ref
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

SRC="${1:-}"
DEST="${2:-}"
if [ ! -f "$SRC" ] || [ -z "$DEST" ]; then
  echo "usage: hydrate.sh <source.yml> <dest.yml>" >&2
  exit 2
fi

# `@<40 zeros> # v4 - trailing prose` becomes `@v4`: the version comment is
# the only record of what the placeholder stands for.
sed -E 's/@0{40}[[:space:]]*#[[:space:]]*([^[:space:]]+).*$/@\1/' "$SRC" > "$DEST"

./tools/pin.sh --write "$DEST" 2>/dev/null
rm -f "$DEST.bak"

status=0
while IFS= read -r ref; do
  repo="${ref%@*}"; rev="${ref#*@}"
  if printf '%s' "$rev" | grep -qE '^[0-9a-f]{40}$'; then
    printf 'RESOLVED    %s %s\n' "$repo" "$rev"
  else
    printf 'UNRESOLVED  %s %s\n' "$repo" "$rev"
  fi
done < <(grep -oE '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*[^.][^[:space:]]+@[^[:space:]]+' "$DEST" \
         | sed -E 's/^.*uses:[[:space:]]*//')

if grep -q '0\{40\}' "$DEST"; then
  echo "hydrate.sh: placeholder SHAs survived pinning in $DEST" >&2
  status=1
fi
exit "$status"
