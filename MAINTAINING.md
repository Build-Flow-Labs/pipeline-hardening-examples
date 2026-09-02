# Maintaining this repository

The examples are the point; this is the machinery that keeps them honest.
Everything below runs from a fresh clone with bash, git, and nothing else
installed.

## What runs, and when

| | Trigger | What it checks |
|---|---|---|
| [`ci.yml`](.github/workflows/ci.yml) | every push and pull request | the whole suite below |
| `smoke-*.yml` | weekly (Mondays), and on demand | that the example shapes really execute on GitHub's runners |

The smoke copies moved off `push` deliberately. They exist to show the shapes
run on real infrastructure, which a weekly run answers just as well, and it
keeps the Actions tab readable. Everything that can go wrong between Mondays —
a stale version comment, a copy drifting from its example, a broken script —
is caught on every push by `ci.yml` instead.

One consequence worth knowing: **GitHub disables scheduled workflows in a
repository with no activity for 60 days.** If this repository goes quiet for a
couple of months, the weekly smoke runs stop until someone re-enables them in
the Actions tab. `ci.yml` is unaffected — it runs on pushes.

## The four test scripts

Run any of them directly; they are what CI runs.

```bash
./tests/lint.sh               # YAML parses, workflows lint, scripts shellcheck
./tests/example-integrity.sh  # placeholders intact, version comments resolve
./tests/pin-tests.sh          # pin.sh behaviour, including annotated tags
./tests/audit-tests.sh        # audit.sh findings, and the demo fixture
```

`lint.sh` and `example-integrity.sh` need actionlint:

```bash
./tests/install-actionlint.sh    # pinned version, digest verified before use
export PATH="$HOME/.local/bin:$PATH"
```

## Invariants

These are enforced by tests, not by good intentions. If you change something
and one of these fails, the test is probably right.

- **The SHAs in `examples/**/after.yml` are all zeros.** They are deliberately
  invalid so nobody copies a stale hash and ships it. `example-integrity.sh`
  fails if a real 40-character SHA ever appears anywhere under `examples/`.
- **Every placeholder carries a trailing version comment.** It is the only
  record of what the placeholder stands for, and `pin.sh` has nothing to work
  from without it.
- **The `before.yml` examples keep failing actionlint.** The injectable pull
  request title in `03/before.yml` is the lesson. `lint.sh` asserts the finding
  is still reported, so tidying the example breaks the build.
- **The demo workflows stay nested under `demo/`.** GitHub only runs workflows
  in the repository's own `.github/workflows`, which is the only reason a
  deliberate pwn request is safe to keep here. `audit-tests.sh` asserts it.
- **`audit.sh` comes back clean against this repository.** A repository of
  hardening advice with a movable action reference in its own CI is not a good
  look, so the build checks.

## Changing an example

The smoke copies in `.github/workflows/smoke-*.yml` are generated. Do not edit
them:

```bash
./tools/materialise.sh            # regenerate after changing an example
./tools/materialise.sh --check    # what CI runs; fails if they are stale
```

The generator dies rather than guessing if a substitution no longer matches, so
an edit to an example that breaks the mapping is a loud failure and not a
silently stale copy. `--check` compares with SHAs normalised away, so an
upstream tag moving is not a build failure.

## Updating actionlint

Two constants change together, and the digest is the point — a version alone
still trusts whatever the server serves:

- `VERSION` and `SHA256` in [`tests/install-actionlint.sh`](tests/install-actionlint.sh)
- `ACTIONLINT_VERSION` and `ACTIONLINT_SHA256` in [`tools/materialise.sh`](tools/materialise.sh),
  which example 05's smoke copy downloads and verifies

Get the digest by downloading the release and running `sha256sum`, not by
trusting a number someone pasted somewhere.

## Updating the pins

Dependabot raises pull requests for the actions used by `ci.yml` and the smoke
copies, weekly, per [`.github/dependabot.yml`](.github/dependabot.yml). It does
not see `examples/`, whose SHAs are placeholders and must stay that way.

To pin something by hand:

```bash
./tools/pin.sh actions/checkout v4          # resolve one
./tools/pin.sh --write path/to/workflow.yml # rewrite a whole file
```

## Before a talk

[`DEMO.md`](DEMO.md) is the runbook, with a pre-flight checklist. The short
version: fresh clone, and check `./tools/pin.sh actions/checkout v4` returns a
SHA, since that is the only part of the demo that needs the network.
