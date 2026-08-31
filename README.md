# Build pipeline hardening: working examples

Companion material for **"What Your SBOM Can't See: Zero-Trust Governance for
Build Pipelines"** (swampUP 2026).

The talk argues that compliance frameworks are explicit about credentials and
access, and vague about build integrity. This repository is the other half:
the configuration changes that close the gap, in a form you can copy.

Everything here is configuration. None of it requires buying anything.

## What's here

| Directory | The change | Talk slide |
|---|---|---|
| [`examples/01-pin-actions`](examples/01-pin-actions) | Reference actions by commit SHA, and keep the pins current automatically | "Pin to full commit SHAs" |
| [`examples/02-least-privilege-tokens`](examples/02-least-privilege-tokens) | Default the build token to read-only, grant write per job | "Default tokens to read-only" |
| [`examples/03-quarantine-untrusted-triggers`](examples/03-quarantine-untrusted-triggers) | Split `pull_request_target` so untrusted code never meets credentials | "Quarantine risky triggers" |
| [`examples/04-scope-secrets-and-runners`](examples/04-scope-secrets-and-runners) | Put secrets only in the jobs that consume them; constrain self-hosted runners | "Scope secrets and runners" |
| [`examples/05-verify-what-you-consume`](examples/05-verify-what-you-consume) | Checksum-verify downloads; alert on tag movement | "Verify what you consume" |
| [`tools/audit.sh`](tools/audit.sh) | Answers the five questions from the talk against your own workflows | "Five questions for Monday" |
| [`tools/pin.sh`](tools/pin.sh) | Resolves a tag to its commit SHA and rewrites `uses:` lines in place | — |
| [`CHECKLIST.md`](CHECKLIST.md) | The five questions, with what a good answer looks like | — |

Each example directory has a `before.yml`, an `after.yml`, and a README
explaining what changed and why.

## Start here

```bash
git clone <this repo>
cd pipeline-hardening-examples
./tools/audit.sh /path/to/your/repo
```

That prints a first-pass answer to the five questions for a repository you
own. It is a heuristic, not a parser (see the caveat in `tools/audit.sh`), so
treat the output as a place to start looking rather than a verdict.

## On the SHAs in these examples

Any commit SHA in this repository is **illustrative and will go stale.** Do
not copy one and assume it is current.

Resolve your own:

```bash
./tools/pin.sh actions/checkout v4
# -> actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4

./tools/pin.sh --write .github/workflows/build.yml   # rewrite a whole file
```

`pin.sh` uses `git ls-remote`, not the GitHub API, so it needs no token, has
no rate limit, and works anywhere git does. It handles annotated tags (which
point at a tag object rather than a commit), lightweight tags, and branches.

This is deliberate. The skill is knowing how to pin and how to keep pins
fresh, not memorising one hash. A pinned reference with no update process is a
snapshot that quietly ages, which is the failure mode
[`01-pin-actions`](examples/01-pin-actions) exists to prevent.

## What this does and does not buy you

Pinning removes the **silent substitution** path: the one where a tag you
already reviewed starts pointing at different code and your pipeline runs it
without anything changing on your side. That was the mechanism in the
tj-actions compromise (March 2025) and in the Trivy tag hijack (March 2026).

It does not protect you from:

- an action that was already malicious at the commit you pinned
- a compromise of the upstream project itself, which is usually how the
  attacker got the ability to move tags in the first place
- malicious artifacts shipped through a different channel, such as a registry
- a poisoned build that produces **validly signed provenance**, which is what
  happened to TanStack in May 2026

These changes move you from badly exposed to substantially less exposed. They
do not move you to zero, and anyone telling you otherwise is selling
something.

## Licence

MIT. See [`LICENSE`](LICENSE). Copy anything here into your own pipelines
without attribution or ceremony.
