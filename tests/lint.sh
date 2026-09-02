#!/usr/bin/env bash
#
# Static checks over everything in the repository.
#
#   - every YAML file parses as a mapping
#   - every workflow file passes actionlint, EXCEPT where a finding is the
#     point of the example (see EXPECTED below)
#   - both tools and these test scripts pass shellcheck
#
# Run from anywhere: ./tests/lint.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
ok()  { printf '  ok    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; fail=1; }

# Some YAML here is deliberately not a workflow. A Dependabot config and a
# composite action each have an entirely different schema, so actionlint
# rejects them as a matter of course. They get parsed, not linted.
is_workflow() {
  case "$(basename "$1")" in
    dependabot.yml|action.yml|action.yaml) return 1 ;;
    *) return 0 ;;
  esac
}

# Files where actionlint SHOULD report something, with the text it must
# report. The 'before' examples are deliberately unsafe and the finding is
# the lesson: if one of these ever goes quiet, someone has tidied the example
# and it has stopped demonstrating the thing it exists to demonstrate.
expected_finding() {
  case "$1" in
    examples/03-quarantine-untrusted-triggers/before.yml)
      printf '%s' '"github.event.pull_request.title" is potentially untrusted' ;;

    # The demo fixture is deliberately unsafe for the same reason.
    demo/legacy-service/.github/workflows/pr-labeler.yml)
      printf '%s' '"github.event.pull_request.title" is potentially untrusted' ;;

    # An artefact of nesting a pretend repository inside a real one, not a
    # defect in the fixture: actionlint resolves a local reusable-workflow
    # path against the root of THIS repository, where that file does not
    # exist. The path is correct from legacy-service's own point of view.
    demo/legacy-service/.github/workflows/release.yml)
      printf '%s' 'could not read reusable workflow file' ;;
    *) printf '' ;;
  esac
}

mapfile -t YAML_FILES < <(find examples .github demo -name '*.yml' -o -name '*.yaml' | sort)

echo "1. YAML parses as a mapping"
for f in "${YAML_FILES[@]}"; do
  if err=$(python3 -c '
import sys, yaml
try:
    with open(sys.argv[1]) as fh:
        doc = yaml.safe_load(fh)
except yaml.YAMLError as exc:
    mark = getattr(exc, "problem_mark", None)
    where = " at line %d" % (mark.line + 1) if mark else ""
    raise SystemExit("%s%s" % (getattr(exc, "problem", exc), where))
if not isinstance(doc, dict):
    raise SystemExit("top level is %s, not a mapping" % type(doc).__name__)
' "$f" 2>&1); then
    ok "$f"
  else
    bad "$f - $err"
  fi
done

echo
echo "2. actionlint"
if ! command -v actionlint >/dev/null 2>&1; then
  bad "actionlint not on PATH (run ./tests/install-actionlint.sh)"
else
  for f in "${YAML_FILES[@]}"; do
    is_workflow "$f" || { ok "$f (not a workflow schema - parsed above)"; continue; }

    out=$(actionlint -no-color -oneline "$f" 2>&1)
    count=$(printf '%s' "$out" | grep -c . )
    exp=$(expected_finding "$f")

    if [ -n "$exp" ]; then
      if ! printf '%s' "$out" | grep -qF "$exp"; then
        bad "$f - expected finding has disappeared: $exp"
      elif [ "$count" -ne 1 ]; then
        bad "$f - expected exactly the one known finding, got $count"
        printf '%s\n' "$out" | sed 's/^/        /'
      else
        ok "$f (known finding still reported)"
      fi
    elif [ "$count" -eq 0 ]; then
      ok "$f"
    else
      bad "$f"
      printf '%s\n' "$out" | sed 's/^/        /'
    fi
  done
fi

echo
echo "3. shellcheck"
if ! command -v shellcheck >/dev/null 2>&1; then
  bad "shellcheck not on PATH"
else
  for f in tools/*.sh tests/*.sh; do
    if out=$(shellcheck -f gcc "$f" 2>&1); then
      ok "$f"
    else
      bad "$f"
      printf '%s\n' "$out" | sed 's/^/        /'
    fi
  done
fi

echo
[ "$fail" -eq 0 ] && echo "static checks passed" || echo "static checks FAILED"
exit "$fail"
