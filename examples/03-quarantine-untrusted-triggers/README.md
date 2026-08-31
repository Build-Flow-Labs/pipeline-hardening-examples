# 03 · Quarantine untrusted triggers

## The exposure

`pull_request_target` runs with the **base** repository's secrets and token,
while the pull request content comes from a **fork**. If the workflow then
checks out and executes that fork's code, untrusted code and credentials are
in the same job. This pattern is known as a "pwn request".

`workflow_run` has the same property and deserves the same treatment.

Two incidents in the talk used this shape:

- **Nx / s1ngularity**, August 2025 — a workflow added five days earlier
  interpolated an unsanitised pull request *title* into a step and ran on
  `pull_request_target`, which supplied a read/write token. The injection
  reached the publish pipeline and leaked the npm token.
- **hackerbot-claw**, February 2026 — a fork PR against a workflow of this
  shape exfiltrated a maintainer token, which was then used to privatise the
  repository and delete all 178 releases.

## The change

Ask what the workflow actually needs.

**Does it need to build or test the contributor's code?** Use
`pull_request`. It gets no secrets and a read-only token, and running fork
code there is fine. See `after.yml`.

**Does it need base-repo privileges for metadata only** — labels, reviewer
assignment, a comment? Keep `pull_request_target`, but do not check out or
execute fork code in that job. See `labeler.yml`.

**Does it need both?** Split it into two workflows. There is no safe way to
do both in one job.

## The injection fix

Never interpolate attacker-controlled text directly into a `run:` block.
`${{ github.event.pull_request.title }}` inside `run:` is substituted before
the shell sees it, so a crafted title becomes shell code. Pass it through
`env:` instead and reference the variable — that is the difference between
the Nx compromise and a working build.

Attacker-controlled fields include the PR title, branch name, body, commit
messages, and author name.

## Verifying

```bash
../../tools/audit.sh /path/to/your/repo
```

lists every workflow using `pull_request_target` or `workflow_run`, and
flags those that also check out fork code.
