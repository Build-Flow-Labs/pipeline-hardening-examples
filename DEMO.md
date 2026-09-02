# Live demo runbook

Three commands, about four minutes, one of which needs the network. Everything
here is in this repository, so the demo works from a fresh clone.

```bash
git clone https://github.com/Build-Flow-Labs/pipeline-hardening-examples
cd pipeline-hardening-examples
```

Nothing to install. `audit.sh` and `pin.sh` need only bash and git.

---

## Before you start

- [ ] Fresh clone, or `git pull` — you want the demo to match what the audience
      will find at the URL on the slide.
- [ ] `./tools/pin.sh actions/checkout v4` returns a SHA. This is the only
      network check; if it fails, see **If the network is bad** below.
- [ ] Terminal wide enough for 76 columns, or the audit output wraps badly.
- [ ] `git status` clean, so act 3 does not leave anything behind.

---

## Act 1 — the problem (about 0.1s)

```bash
./tools/audit.sh demo/legacy-service
```

`demo/legacy-service` is a small fictional project that carries all five
exposures. Every question has something to say:

| Question | What it finds |
|---|---|
| 1 | 8 movable tags — including two inside a local composite action, which a workflow-only scan never opens |
| 2 | Four workflows with no `permissions:` block at all |
| 3 | `pull_request_target` checking out fork code, and the PR title reaching a shell |
| 4 | Four credentials above step level, `secrets: inherit`, and a self-hosted runner |
| 5 | Ties back to question 1: those 8 references would change silently |

The composite action is the one to slow down on. `ci.yml` references it as
`./.github/actions/setup`, which looks local and safe, and the movable tags are
one file further in. A repository can look fully pinned and not be.

> The workflows in `demo/legacy-service` never run. GitHub only executes
> workflows in the repository's own `.github/workflows`, and these are nested
> inside `demo/`. Nothing there runs, which is why a deliberate pwn request
> can sit in a public repository at all. `tests/audit-tests.sh` asserts they stay
> there.

---

## Act 2 — the same command, on this repository (about 0.1s)

```bash
./tools/audit.sh .
```

All five questions come back clean. This is the repository the audience is
looking at, audited by the tool they just watched find eight problems.

Worth saying out loud: this is checked on every push. If the CI here ever stops
following the advice in these examples, the build goes red. The advice and the
practice cannot drift apart quietly.

---

## Act 3 — how you get from one to the other (about 2s, needs network)

```bash
cp demo/legacy-service/.github/workflows/ci.yml /tmp/ci.yml
./tools/pin.sh --write /tmp/ci.yml
```

```
pin.sh: could not resolve some-vendor/coverage-reporter@v3 - left unchanged
pin.sh: pinned 3 reference(s) in /tmp/ci.yml (original at /tmp/ci.yml.bak)
pin.sh: 1 reference(s) could not be resolved
```

```bash
grep uses: /tmp/ci.yml
```

```
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
      - uses: ./.github/actions/setup
      - uses: some-vendor/coverage-reporter@v3
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
      - uses: docker/build-push-action@ca052bb54ab0790a636c9b5f226502c73d547a25 # v5
```

Three things happened, and the two failures are the interesting ones:

- Real actions resolved to commits, with the version kept as a trailing comment
  so it stays readable and Dependabot can still raise update PRs.
- `some-vendor/coverage-reporter@v3` does not exist, so it was **left alone**
  and reported. It does not guess.
- `./.github/actions/setup` is local, so there is nothing to pin. Its own
  movable tags are still there — pinning the workflow did not fix the action.
  Say that out loud. It is a real limit.

It uses `git ls-remote`, not the GitHub API: no token, no rate limit.

---

## If the network is bad

Acts 1 and 2 are entirely offline — they only read files. Only act 3 reaches
github.com, and only to resolve tags.

If the wifi is unreliable, put the act 3 output above on a slide and talk
through it rather than typing it. The audit is the part that carries the
argument; the pinning is the part people can read about afterwards.

To check quickly, before you go on:

```bash
./tools/pin.sh actions/checkout v4     # ~0.7s when the network is fine
```

---

## The one question you will be asked

**"Doesn't pinning mean you never get updates?"**

That is what `examples/01-pin-actions/dependabot.yml` is for. Pinning without an
update process is a snapshot that quietly ages, which is a different failure
mode rather than a fix. Pinning plus automated updates gets you currency and
immutability at the same time. This repository does exactly that to its own CI.
