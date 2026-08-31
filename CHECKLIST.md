# Five questions for Monday

From the talk. Each is answerable from your own workflow files this week.
`tools/audit.sh` gives a first-pass answer to the first four.

---

### 1. Can anything in our build change without a commit changing?

**Look for:** `uses:` referencing a tag or branch rather than a 40-character
commit SHA — in your workflows, and also in any composite actions of your own
under `.github/actions`. A workflow whose every step is pinned can still reach
a movable tag through one of your own actions one hop away.

**A good answer:** every third-party step is SHA-pinned, and Dependabot or
Renovate raises PRs to move those pins.

**A bad answer:** "we pin the important ones." The attacker picks, not you.

→ `examples/01-pin-actions`

---

### 2. What could our build tokens do in the worst case?

**Look for:** workflows with no `permissions:` block. Their real scope comes
from an organisation or repository setting that is not in the file.

**A good answer:** `permissions: {}` at workflow level, specific grants on
the jobs that need them, and the org default set to read-only.

**A bad answer:** "I'd have to check the org settings." That is the finding.

→ `examples/02-least-privilege-tokens`

---

### 3. Which workflows can an outsider influence?

**Look for:** `pull_request_target` and `workflow_run`, and whether those
workflows check out or execute fork code.

**A good answer:** untrusted code runs under `pull_request` with no secrets;
anything needing base-repo privileges touches metadata only.

**A bad answer:** a `pull_request_target` workflow that checks out
`github.event.pull_request.head.sha` and runs a build.

→ `examples/03-quarantine-untrusted-triggers`

---

### 4. Which secrets sit in jobs that run third-party code?

**Look for:** secrets defined at workflow or job level rather than on the
step that consumes them; `secrets: inherit` on a called workflow, which hands
over every secret in the repository at once; and `runs-on: self-hosted`, plus
any runner label that is not a GitHub-hosted default, since the file does not
say whether it points at an ephemeral machine.

**A good answer:** the job running third-party actions holds no credentials
at all; secrets are step-scoped; self-hosted runners are ephemeral and
unreachable from fork PRs.

**A bad answer:** a top-level `env:` block holding four cloud credentials.

→ `examples/04-scope-secrets-and-runners`

---

### 5. If a step we depend on was hijacked for twelve hours, would we know?

**Not answerable from workflow files.** Ask it of your monitoring instead:
if a tag you depend on started pointing somewhere else, would anything
generate an alert, and would a human see it?

Twelve hours is roughly the window the Trivy tag hijack stayed live in March
2026. During it, consuming pipelines completed normally, because the
malicious code ran the real scanner afterwards.

**A good answer:** pinned references, so a change requires a commit in your
repository; plus alerting on dependency tag movement.

**A bad answer:** "our scanner would catch it." It did not, for the people
whose scanner it was.

→ `examples/05-verify-what-you-consume`

---

## The honest framing

These five reduce exposure substantially. They do not eliminate it.

They do not protect against an action that was already malicious at the
commit you pinned, against the upstream compromise that gave the attacker
tag-moving ability in the first place, or against a poisoned build that
produces validly signed provenance — which is what happened to TanStack in
May 2026, where every verification tool reported the packages as clean and
every one of them was correct about what it was checking.

Exposure is not compromise. Carrying these conditions does not mean anything
has happened to you; it means more would happen if a dependency were
compromised.
