# 01 · Pin actions to commit SHAs

## The exposure

A tag like `@v4` is a label pointing at a commit. The label belongs to the
publisher, not to you. When it moves, your pipeline follows it on the next
run, with no commit in your repository and no signal in your logs.

This is what happened to `tj-actions/changed-files` in March 2025 (every tag
from v1 to v45.0.7 rewritten to a single malicious commit) and to
`aquasecurity/trivy-action` in March 2026 (76 of 77 tags force-pushed to a
credential stealer inside about twelve hours).

## The change

Reference the commit instead of the label. See `before.yml` and `after.yml`.

Use the **full 40-character SHA**. Short SHAs are ambiguous and GitHub does
not treat them as immutable references.

## Keeping pins current

Add `dependabot.yml` to `.github/`. Without an update process, pinning trades
one problem for another: you stop receiving silent malicious updates, and you
also stop receiving security fixes.

Dependabot understands the `# v4.2.2` trailing comment convention and will
maintain it, so the file stays readable.

## Resolving a SHA

```bash
../../tools/pin.sh actions/checkout v4
```

Or rewrite a whole workflow file in place:

```bash
../../tools/pin.sh --write .github/workflows/build.yml
```

## What this does not fix

Pinning protects you from the reference changing under you. It does not tell
you whether the code at that commit was trustworthy when you pinned it.
