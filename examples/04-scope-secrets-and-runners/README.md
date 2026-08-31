# 04 · Scope secrets and runners

## The exposure

**Secrets.** Defining secrets at workflow or job level with `env:` puts them
in the environment of every step in scope, including third-party actions.
A compromised step reads the lot. The ChainDrop worm (August 2026) went
further and read the runner's process memory directly via `/proc/pid/mem`,
lifting secrets that never appeared in logs — so log masking is not a
defence here.

**Runners.** A self-hosted runner configured with the default steps is
**non-ephemeral**. A malicious job can start a background process that
outlives it, modify files that persist, and wait for the next workflow to
land on the same machine.

## The change

**Secrets:** move them from workflow-level `env:` to `env:` on the single
step that uses them. Split jobs so the job running third-party code holds no
credentials at all. See `before.yml` and `after.yml`.

**Prefer OIDC** over stored cloud keys where your provider supports it. A
short-lived token minted per run is not worth stealing in the way a
long-lived key is.

**Runners:** if you use self-hosted runners:

- Make them **ephemeral** (`--ephemeral`, or the Actions Runner Controller),
  so each job gets a clean machine.
- Never let them serve **public** repositories where fork PRs can reach them.
- Put them in a segmented network with no standing access to production.
- Do not run them as root, and do not reuse them across trust levels.

## Verifying

```bash
../../tools/audit.sh /path/to/your/repo
```

reports workflow-level secret definitions and any `runs-on: self-hosted`.
