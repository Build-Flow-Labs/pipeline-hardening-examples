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
| [`DEMO.md`](DEMO.md) | A runbook for showing the audit finding something, live | — |
| [`MAINTAINING.md`](MAINTAINING.md) | What CI checks, and the invariants it enforces | — |

Each example directory has a `before.yml`, an `after.yml`, and a README
explaining what changed and why.

## Start here

```bash
git clone <this repo>
cd pipeline-hardening-examples
./tools/audit.sh /path/to/your/repo
```

That prints a first-pass answer to the five questions for a repository you
own. To see it find something rather than come back clean, point it at the
worked-example project that ships with this repository:

```bash
./tools/audit.sh demo/legacy-service
```

[`DEMO.md`](DEMO.md) walks through that as a runbook. It is a heuristic, not a parser (see the caveat in `tools/audit.sh`), so
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

## How this repository is tested

Every push runs [`.github/workflows/ci.yml`](.github/workflows/ci.yml): every
workflow is linted with actionlint, every YAML file is parsed, both scripts go
through shellcheck, and `tools/audit.sh` is run against this repository. If the
CI here ever stops following the advice in these examples, the build says so.

Two things are worth being precise about.

**The `before.yml` files are meant to fail.** actionlint reports the injectable
pull request title in `03/before.yml`, and CI asserts that it still does. If
someone tidies that example, the build breaks — because the example has stopped
demonstrating the thing it exists to demonstrate.

**The `after.yml` files cannot run as they stand.** Their SHAs are
placeholders, one action in them is fictional, and they call scripts this
repository does not contain. CI covers them two ways. It hydrates each one the
way a reader would — reversing the placeholder using the version comment, then
running `pin.sh` — and checks the result still resolves upstream and still
lints. That is the check that notices a version comment going stale. Separately,
`tools/materialise.sh` generates runnable copies into `.github/workflows`, so
the shapes execute on real infrastructure.

Those copies run weekly and on demand rather than on every push — they exist
to show the shapes execute on real infrastructure, which a weekly run answers
just as well, and it keeps the Actions tab readable. Everything that can go
wrong in between is caught on every push by the checks above.

Those copies are not the examples, and the difference matters. Each one lists
its substitutions in its own header, because every substitution is a place
where what runs differs from what is taught. A green smoke run shows the
skeleton works: the trigger, the permissions model, the job graph, the pinned
actions, the artifact handoff between jobs, the checksum verification. It shows
nothing about the substituted lines, which were never real. One example has no
runnable copy at all — `labeler.yml` would mean granting `pull-requests: write`
on a `pull_request_target` trigger in this repository, which is exactly the
thing [`03`](examples/03-quarantine-untrusted-triggers) asks you to think twice
about.

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
