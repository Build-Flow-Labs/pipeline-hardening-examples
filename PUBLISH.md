# Publishing this as a standalone public repo

The GitHub App used by the Claude session is scoped to the study repo and
cannot create repositories, so step 1 is manual. The rest is copy-paste.

## 1. Create the empty repo (on github.com)

New repository → name **`pipeline-hardening-examples`** → **Public** →
do **not** add a README, .gitignore, or licence (this directory has them).

## 2. Push this directory into it

From a clone of the study repo, on the branch holding this work:

```bash
cd /path/to/actions-supply-chain-study

# Copy the directory somewhere outside the study repo
cp -r pipeline-hardening-examples /tmp/phe
cd /tmp/phe

git init -b main
git add .
git commit -m "Working examples for hardening GitHub Actions build pipelines

Five worked examples, one per exposure from the swampUP 2026 talk, each
with a before/after workflow and notes on what the change does and does
not fix. Plus audit.sh, which answers the talk's five questions against a
repository, and pin.sh, which resolves tags to commit SHAs."

git remote add origin git@github.com:Build-Flow-Labs/pipeline-hardening-examples.git
git push -u origin main
```

## 3. Sanity check before publicising the URL

```bash
./tools/audit.sh .          # should run clean against this repo itself
```

Confirm on github.com that the repo is **public** and the licence shows as
MIT in the sidebar.

## 4. Then

- Put the URL on the closing slide of the deck.
- The SHAs in the `after.yml` files are all-zero placeholders by design.
  Leave them; `tools/pin.sh` is how people get real ones.
