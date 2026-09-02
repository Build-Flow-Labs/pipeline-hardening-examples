# legacy-service (fictional)

A small, made-up project carrying all five exposures from the talk, so
`tools/audit.sh` has something to find. Nothing here is real: no such service,
no such org, no such secrets.

**These workflows never run.** GitHub only executes workflows in the
repository's own `.github/workflows` directory. This one is nested inside
`demo/`, so it is inert — which is the only reason it is safe to keep a
deliberate "pwn request" in a public repository.

Used by `DEMO.md`, and checked by `tests/audit-tests.sh` so the demo cannot
quietly stop demonstrating anything.
