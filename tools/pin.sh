#!/usr/bin/env bash
#
# pin.sh - resolve a GitHub Actions tag to its commit SHA.
#
#   ./tools/pin.sh actions/checkout v4
#       -> actions/checkout@<40-hex>  # v4
#
#   ./tools/pin.sh --write .github/workflows/build.yml
#       rewrites every mutable `uses:` in the file to a pinned SHA,
#       appending a `# <tag>` comment. Writes a .bak alongside.
#
# Uses `gh` if it is authenticated, otherwise curl. Set GITHUB_TOKEN to
# raise the anonymous rate limit.
#
# Annotated tags resolve to the tag object, so this dereferences to the
# commit the tag actually points at.

set -uo pipefail

die() { echo "pin.sh: $*" >&2; exit 1; }

api() {
  local path="$1"
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh api "$path" 2>/dev/null
  elif command -v curl >/dev/null 2>&1; then
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" \
           -H "Accept: application/vnd.github+json" "https://api.github.com/$path" 2>/dev/null
    else
      curl -fsSL -H "Accept: application/vnd.github+json" \
           "https://api.github.com/$path" 2>/dev/null
    fi
  else
    die "need either gh or curl"
  fi
}

json_field() {  # crude extractor, avoids a jq dependency
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

# resolve owner/repo tag -> 40-hex commit sha
resolve() {
  local repo="$1" tag="$2" body sha type
  body=$(api "repos/$repo/git/ref/tags/$tag") || true
  [ -z "$body" ] && { echo ""; return 1; }
  sha=$(printf '%s' "$body" | json_field sha)
  type=$(printf '%s' "$body" | json_field type)
  # An annotated tag points at a tag object; dereference to the commit.
  if [ "$type" = "tag" ]; then
    body=$(api "repos/$repo/git/tags/$sha") || true
    sha=$(printf '%s' "$body" | grep -A3 '"object"' | json_field sha)
  fi
  printf '%s' "$sha"
}

# ---------------------------------------------------------------- rewrite
if [ "${1:-}" = "--write" ]; then
  FILE="${2:-}"
  [ -f "$FILE" ] || die "no such file: ${FILE:-<none>}"
  cp "$FILE" "$FILE.bak"
  changed=0

  while IFS= read -r line; do
    # owner/repo@ref where ref is not already a 40-hex SHA
    if [[ "$line" =~ uses:[[:space:]]*([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)@([A-Za-z0-9._/-]+) ]]; then
      repo="${BASH_REMATCH[1]}"; ref="${BASH_REMATCH[2]}"
      if [[ ! "$ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
        sha=$(resolve "$repo" "$ref")
        if [ -n "$sha" ]; then
          # replace the ref, strip any old trailing comment, add the tag back
          new="${line%%#*}"
          new="${new/$repo@$ref/$repo@$sha}"
          new="${new%"${new##*[![:space:]]}"}"   # rtrim
          printf '%s # %s\n' "$new" "$ref"
          changed=$((changed + 1))
          continue
        else
          echo "$line"
          echo "pin.sh: could not resolve $repo@$ref, left unchanged" >&2
          continue
        fi
      fi
    fi
    echo "$line"
  done < "$FILE.bak" > "$FILE"

  echo "pin.sh: pinned $changed reference(s) in $FILE (original at $FILE.bak)" >&2
  exit 0
fi

# ---------------------------------------------------------------- single
[ $# -eq 2 ] || die "usage: pin.sh <owner/repo> <tag>   |   pin.sh --write <workflow.yml>"
REPO="$1"; TAG="$2"
SHA=$(resolve "$REPO" "$TAG")
[ -n "$SHA" ] || die "could not resolve $REPO@$TAG (rate limited? set GITHUB_TOKEN)"
printf '%s@%s # %s\n' "$REPO" "$SHA" "$TAG"
