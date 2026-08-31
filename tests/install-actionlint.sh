#!/usr/bin/env bash
#
# Install actionlint at a pinned version, verified against a recorded digest
# before anything is executed.
#
# This is examples/05 applied to our own CI. We do not pipe a remote script
# into a shell, and we do not delegate the install to a third-party action
# whose contents we would then also have to pin and review.
#
#   ./tests/install-actionlint.sh [dest-dir]     (default ~/.local/bin)
#
# When actionlint is bumped, both constants below change together. The digest
# is the whole point: a version alone still trusts whatever the server serves.
set -euo pipefail

VERSION="1.7.7"
SHA256="023070a287cd8cccd71515fedc843f1985bf96c436b7effaecce67290e7e0757"

DEST="${1:-$HOME/.local/bin}"
mkdir -p "$DEST"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/actionlint.tar.gz" \
  "https://github.com/rhysd/actionlint/releases/download/v${VERSION}/actionlint_${VERSION}_linux_amd64.tar.gz"

echo "${SHA256}  $tmp/actionlint.tar.gz" | sha256sum -c -

tar -xzf "$tmp/actionlint.tar.gz" -C "$tmp" actionlint
install -m 0755 "$tmp/actionlint" "$DEST/actionlint"
"$DEST/actionlint" --version
