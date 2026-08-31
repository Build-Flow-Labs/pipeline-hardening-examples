# 05 · Verify what you consume

## The exposure

Pinning covers the actions named in your workflow. It does not cover what
those steps then fetch at runtime: install scripts, binaries, container
images, packages. `curl | sh` trusts whatever the server returns at that
moment.

## The change

- **Pin the version and verify a digest** before executing anything you
  downloaded. See `verify-download.yml`.
- **Verify signatures** where the project publishes them (`cosign
  verify-blob`, `gpg --verify`, or the ecosystem's own tooling).
- **Pin container images by digest**, not by tag:
  `image: alpine@sha256:...` rather than `image: alpine:3.20`. Tags on
  registries move for the same reasons Git tags do.
- **Alert on tag movement** for the actions you depend on. If a tag you have
  pinned starts pointing somewhere else, that is worth a page — it is the
  earliest signal available and it is how the tj-actions compromise was
  spotted.

## The honest limit

TanStack, May 2026, is the case that bounds this advice. An attacker poisoned
a build cache through an untrusted trigger; the legitimate release workflow
consumed it hours later and published 84 poisoned versions across 42
packages — carrying **valid, signed SLSA Build Level 3 provenance**.

Every verification tool said those packages were fine, and every one of them
was correct about what it was checking. Provenance attests that an artifact
came from a particular build. It cannot attest that the build was
trustworthy.

Verification raises the cost of an attack considerably. It does not make you
immune, and it is worth saying that out loud rather than implying otherwise.
