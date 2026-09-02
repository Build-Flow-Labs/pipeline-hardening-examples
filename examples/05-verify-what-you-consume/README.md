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

## Letting your consumers do the same

Everything above is about what you pull in. The other direction is making your
own releases checkable by the people who depend on you.

`attest-provenance.yml` uses
[`actions/attest-build-provenance`](https://github.com/actions/attest-build-provenance)
to sign a statement about an artifact: this file, with this digest, was
produced by this workflow, in this repository, at this commit. A consumer
checks it with:

```bash
gh attestation verify dist/app.tar.gz --repo <owner>/<repo>
```

Two things about the shape of that file are deliberate.

**The signing job runs no build.** `id-token: write` and `attestations: write`
are the ability to sign things as you. In that file they live in a job that
downloads an artifact and attests it, nowhere near `npm ci`. This is
[`04`](../04-scope-secrets-and-runners) applied to a credential that is not a
secret and does not appear in any settings page.

**The split does not make the artifact trustworthy.** If the build job is
compromised it produces a poisoned artifact, and the attest job faithfully
signs the poisoned artifact. What the split buys is narrower: third-party
build code never holds the signing capability, so it cannot sign things of its
own choosing later. Useful, but not integrity. The next section says why.

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
immune.
