#!/usr/bin/env bash
#
# pin.sh - resolve a GitHub Actions tag to the commit SHA it points at.
#
#   ./tools/pin.sh actions/checkout v4
#       -> actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
#
#   ./tools/pin.sh --write .github/workflows/build.yml
#       rewrites every mutable `uses:` in the file to a pinned SHA and
#       appends a `# <tag>` comment. The original is kept as <file>.bak.
#
# Uses `git ls-remote`, not the GitHub API: no token, no rate limit, no jq,
# and it works anywhere git does.
#
# Annotated tags point at a tag object rather than a commit. ls-remote
# exposes the underlying commit as `<ref>^{}`, so we prefer that line when
# it exists. Lightweight tags have no `^{}` line and resolve directly.

set -uo pipefail

die() { echo "pin.sh: $*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git not found"

# resolve <owner/repo> <tag-or-branch> -> 40-hex commit sha (empty if unknown)
resolve() {
  local repo="$1" ref="$2" url out sha
  url="https://github.com/$repo"

  out=$(git ls-remote "$url" "refs/tags/$ref" "refs/tags/$ref^{}" 2>/dev/null) || true

  # Annotated tag: the ^{} line is the commit. Prefer it.
  sha=$(printf '%s\n' "$out" | awk '/\^\{\}$/ { print $1; exit }')

  # Lightweight tag: single line, already a commit.
  [ -z "$sha" ] && sha=$(printf '%s\n' "$out" | awk 'NF { print $1; exit }')

  # Not a tag? Try a branch.
  if [ -z "$sha" ]; then
    sha=$(git ls-remote "$url" "refs/heads/$ref" 2>/dev/null | awk 'NF { print $1; exit }')
  fi

  # Only ever emit something that looks like a commit.
  if printf '%s' "$sha" | grep -qE '^[0-9a-f]{40}$'; then
    printf '%s' "$sha"
  fi
}

# ---------------------------------------------------------------- --write
if [ "${1:-}" = "--write" ]; then
  FILE="${2:-}"
  [ -f "$FILE" ] || die "no such file: ${FILE:-<none>}"

  cp "$FILE" "$FILE.bak"
  changed=0 failed=0

  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ uses:[[:space:]]*([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)@([A-Za-z0-9._/-]+) ]]; then
      repo="${BASH_REMATCH[1]}"; ref="${BASH_REMATCH[2]}"

      if [[ "$ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
        echo "$line"                       # already pinned
        continue
      fi

      sha=$(resolve "$repo" "$ref")
      if [ -n "$sha" ]; then
        new="${line%%#*}"                  # drop any existing trailing comment
        new="${new/$repo@$ref/$repo@$sha}"
        new="${new%"${new##*[![:space:]]}"}"   # right-trim
        printf '%s # %s\n' "$new" "$ref"
        changed=$((changed + 1))
      else
        echo "$line"
        echo "pin.sh: could not resolve $repo@$ref - left unchanged" >&2
        failed=$((failed + 1))
      fi
      continue
    fi
    echo "$line"
  done < "$FILE.bak" > "$FILE"

  echo "pin.sh: pinned $changed reference(s) in $FILE (original at $FILE.bak)" >&2
  [ "$failed" -gt 0 ] && echo "pin.sh: $failed reference(s) could not be resolved" >&2
  exit 0
fi

# ---------------------------------------------------------------- single
[ $# -eq 2 ] || die "usage: pin.sh <owner/repo> <tag>   |   pin.sh --write <workflow.yml>"

SHA=$(resolve "$1" "$2")
[ -n "$SHA" ] || die "could not resolve $1@$2 (does the tag exist? is the repo public?)"
printf '%s@%s # %s\n' "$1" "$SHA" "$2"
