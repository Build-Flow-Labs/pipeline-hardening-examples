# 02 · Default the build token to read-only

## The exposure

The built-in token is injected into every job automatically. With no
`permissions:` block, its scope comes from a repository or organisation
setting that is not visible in the workflow file.

That matters for two reasons. Practically, third-party steps run with
whatever that token can do. Analytically, it means nobody reading your
workflow — including an auditor — can determine the token's real scope from
the file.

In the February 2026 hackerbot-claw campaign, a stolen write-capable token
was used to privatise the Trivy repository and delete all 178 releases. The
difference between a token that reads and one that writes is the difference
between an incident and a catastrophe.

## The change

Set `permissions: {}` at the top of the workflow, then grant per job. See
`before.yml` and `after.yml`.

Also set the organisation-level default to read-only:
**Settings → Actions → General → Workflow permissions → Read repository
contents**. The workflow block protects this repository; the org default
protects the ones nobody has got to yet.

## Common grants

| Need | Grant |
|---|---|
| Clone the repo | `contents: read` |
| Create a release or push a tag | `contents: write` |
| Comment on a PR or issue | `pull-requests: write` / `issues: write` |
| Push a container image to GHCR | `packages: write` |
| Mint an OIDC token for cloud auth | `id-token: write` |

Grant these in the *job* that needs them, never at the top of the file.

## Verifying

```bash
../../tools/audit.sh /path/to/your/repo
```

reports which workflows have no `permissions:` block at all.
