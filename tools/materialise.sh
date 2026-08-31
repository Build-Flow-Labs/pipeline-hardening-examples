#!/usr/bin/env bash
#
# materialise.sh - generate runnable smoke copies of the example workflows.
#
#   ./tools/materialise.sh            regenerate .github/workflows/smoke-*.yml
#   ./tools/materialise.sh --check    fail if the committed copies are stale
#
# WHY THIS EXISTS
#
# GitHub only runs workflows committed under .github/workflows, and the
# after.yml examples cannot run as they stand: their SHAs are all-zero
# placeholders on purpose, one action in them is fictional, and they call
# scripts this repository does not contain. So "do the examples work?" can
# only be answered by committing a derived copy and letting it run.
#
# WHAT THE COPIES ARE WORTH
#
# Every substitution listed in a generated file's header is a place where the
# thing being tested differs from the thing being taught. A green smoke run
# says the skeleton executes on real infrastructure - the trigger, the
# permissions model, the job graph, the real pinned actions, the artifact
# handoff, the checksum verification. It says nothing about the substituted
# lines, which were never real to begin with.
#
# --check compares with SHAs normalised away, so an upstream tag moving does
# not fail CI. Structural drift between an example and its copy does.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

OUT_DIR=".github/workflows"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

die() { echo "materialise.sh: $*" >&2; exit 1; }

# Digest of actionlint 1.7.7, kept in step with tests/install-actionlint.sh.
# Example 05 needs something real to download and verify; example.com has
# nothing to serve.
ACTIONLINT_VERSION="1.7.7"
ACTIONLINT_SHA256="023070a287cd8cccd71515fedc843f1985bf96c436b7effaecce67290e7e0757"

SUBS=()

# rewrite <file> <must-match-ere> <sed-script> <description>
#
# Dies when the pattern no longer matches. If someone edits an example, this
# stops rather than quietly generating a copy that no longer reflects it.
rewrite() {
  local f="$1" require="$2" script="$3" why="$4"
  grep -qE "$require" "$f" || die "example changed: /$require/ no longer matches in $f ($why)"
  sed -E -i "$script" "$f"
  SUBS+=("$why")
}

header() { # header <source> <dest> <proves>
  local src="$1" dest="$2" proves="$3" tmp
  tmp="$(mktemp)"
  {
    echo "# GENERATED - do not edit. Run ./tools/materialise.sh to regenerate."
    echo "#"
    echo "# Source: $src"
    echo "#"
    echo "# A runnable copy of that example, so CI can show the shape executing on"
    echo "# GitHub's runners. It is not the example itself. Each substitution below"
    echo "# is a place where what runs differs from what is taught:"
    echo "#"
    for s in "${SUBS[@]}"; do echo "#   - $s"; done
    echo "#"
    echo "# A green run here shows: $proves"
    echo "# It shows nothing about the substituted lines above."
    cat "$dest"
  } > "$tmp"
  mv "$tmp" "$dest"
}

build_one() { # build_one <source> <dest>
  local src="$1" dest="$2"
  SUBS=()
  ./tests/hydrate.sh "$src" "$dest" >/dev/null || die "could not hydrate $src"
  SUBS+=("placeholder SHAs replaced with the real commit for the same version")

  # The example's "these SHAs are placeholders" note is not true of this copy,
  # and leaving it in would be the one misleading line in the file.
  rewrite "$dest" '^#.*(PLACEHOLDER|pin\.sh|Resolve the real one)' \
    '/^#.*(PLACEHOLDER|pin\.sh|Resolve the real one)/d' \
    "the example's placeholder note is dropped, since this copy carries real SHAs"
}

# In a sed replacement '&' means the whole match, so it has to be escaped
# there. The description is written out plainly for the generated header.
FIXTURE_TEST_SED='cd tests/fixture \&\& npm ci \&\& npm test'
FIXTURE_BUILD_SED='cd tests/fixture \&\& npm ci \&\& npm run build'
FIXTURE_TEST_DESC='npm ci && npm test runs against tests/fixture, a real but trivial project'
FIXTURE_BUILD_DESC='npm ci && npm run build runs against tests/fixture, a real but trivial project'

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# ---------------------------------------------------------------- 01
f="$tmpdir/smoke-01-pin-actions.yml"
build_one examples/01-pin-actions/after.yml "$f"
rewrite "$f" '^name: build$' 's/^name: build$/name: smoke 01 - pin actions/' \
  "workflow renamed so it is distinguishable in the Actions tab"
rewrite "$f" 'npm ci && npm test' "s|npm ci && npm test|$FIXTURE_TEST_SED|" \
  "$FIXTURE_TEST_DESC"
header examples/01-pin-actions/after.yml "$f" \
  "a SHA-pinned checkout and setup-node resolve and run, and the pinned commits are fetchable"

# ---------------------------------------------------------------- 02
f="$tmpdir/smoke-02-least-privilege-tokens.yml"
build_one examples/02-least-privilege-tokens/after.yml "$f"
rewrite "$f" '^name: build$' 's/^name: build$/name: smoke 02 - least privilege tokens/' \
  "workflow renamed so it is distinguishable in the Actions tab"
rewrite "$f" 'npm ci && npm test' "s|npm ci && npm test|$FIXTURE_TEST_SED|" \
  "$FIXTURE_TEST_DESC"
rewrite "$f" '\./scripts/publish-release\.sh' \
  's|\./scripts/publish-release\.sh|echo "stub - this repository publishes no releases"|' \
  "the release script is stubbed; that job is skipped on branch pushes anyway"
header examples/02-least-privilege-tokens/after.yml "$f" \
  "a job restricted to contents: read can still check out and build, which is the claim the example makes"

# ---------------------------------------------------------------- 03
f="$tmpdir/smoke-03-quarantine-untrusted-triggers.yml"
build_one examples/03-quarantine-untrusted-triggers/after.yml "$f"
rewrite "$f" '^name: pr-check$' 's/^name: pr-check$/name: smoke 03 - quarantine untrusted triggers/' \
  "workflow renamed so it is distinguishable in the Actions tab"
rewrite "$f" '^  pull_request:' 's/^  pull_request:(.*)$/  pull_request:\1\n  push:/' \
  "push added alongside pull_request so the copy runs without needing a PR; pull_request is kept, since not being pull_request_target is the lesson"
rewrite "$f" 'npm ci && npm run build' "s|npm ci && npm run build|$FIXTURE_BUILD_SED|" \
  "$FIXTURE_BUILD_DESC"
header examples/03-quarantine-untrusted-triggers/after.yml "$f" \
  "the env-indirection pattern for attacker-controlled text runs correctly, and a pull_request job builds with no secrets available"

# ---------------------------------------------------------------- 04
f="$tmpdir/smoke-04-scope-secrets-and-runners.yml"
build_one examples/04-scope-secrets-and-runners/after.yml "$f"
rewrite "$f" '^name: build-and-deploy$' 's/^name: build-and-deploy$/name: smoke 04 - scope secrets and runners/' \
  "workflow renamed so it is distinguishable in the Actions tab"
rewrite "$f" 'uses: some-org/some-build-action@' \
  's|^([[:space:]]*)- uses: some-org/some-build-action@.*$|\1- run: echo "stub - the third-party build action in the example is fictional"|' \
  "the fictional third-party action is stubbed with an echo; it exists nowhere and cannot be pinned"
rewrite "$f" 'npm ci && npm run build' "s|npm ci && npm run build|$FIXTURE_BUILD_SED|" \
  "$FIXTURE_BUILD_DESC"
rewrite "$f" '\./deploy\.sh' 's|\./deploy\.sh|echo "stub - this repository deploys nothing"|' \
  "the deploy script is stubbed; the step-scoped secret env around it is kept verbatim"
header examples/04-scope-secrets-and-runners/after.yml "$f" \
  "the two-job split really does hand artifacts from a credential-free build job to a deploy job, with secrets scoped to one step"

# ---------------------------------------------------------------- 05
f="$tmpdir/smoke-05-verify-what-you-consume.yml"
build_one examples/05-verify-what-you-consume/verify-download.yml "$f"
rewrite "$f" '^name: install-tooling$' 's/^name: install-tooling$/name: smoke 05 - verify what you consume/' \
  "workflow renamed so it is distinguishable in the Actions tab"
rewrite "$f" 'TOOL_VERSION: "1\.9\.2"' \
  "s|TOOL_VERSION: \"1\\.9\\.2\"|TOOL_VERSION: \"$ACTIONLINT_VERSION\"|" \
  "the illustrative tool is replaced with a real download (actionlint $ACTIONLINT_VERSION), since example.com serves nothing"
rewrite "$f" 'TOOL_SHA256: "9f2c' \
  "s|TOOL_SHA256: \"[0-9a-f]*\"|TOOL_SHA256: \"$ACTIONLINT_SHA256\"|" \
  "the illustrative digest is replaced with that download's real sha256"
# ${TOOL_VERSION} must survive into the generated file as a literal - it is a
# shell variable inside the workflow's run: block, not one of ours.
# shellcheck disable=SC2016
rewrite "$f" 'https://example\.com/releases' \
  's|"https://example\.com/releases/v\$\{TOOL_VERSION\}/tool-linux-amd64\.tar\.gz"|"https://github.com/rhysd/actionlint/releases/download/v${TOOL_VERSION}/actionlint_${TOOL_VERSION}_linux_amd64.tar.gz"|' \
  "the illustrative URL is replaced with that download's real location"
header examples/05-verify-what-you-consume/verify-download.yml "$f" \
  "a real download is verified against a recorded digest before it is unpacked, and a wrong digest would stop the job"

# ---------------------------------------------------------------- emit
normalise() { sed -E 's/@[0-9a-f]{40}/@SHA/g' "$1"; }

status=0
for generated in "$tmpdir"/smoke-*.yml; do
  target="$OUT_DIR/$(basename "$generated")"
  if [ "$CHECK" -eq 1 ]; then
    if [ ! -f "$target" ]; then
      echo "  FAIL  $target is missing - run ./tools/materialise.sh"
      status=1
    elif diff -u <(normalise "$target") <(normalise "$generated") > "$tmpdir/diff" 2>&1; then
      echo "  ok    $target matches its source example"
    else
      echo "  FAIL  $target no longer matches $(basename "$generated" | sed 's/^smoke-//')"
      sed 's/^/        /' "$tmpdir/diff"
      status=1
    fi
  else
    mkdir -p "$OUT_DIR"
    cp "$generated" "$target"
    echo "  wrote $target"
  fi
done

exit "$status"
