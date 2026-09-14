#!/usr/bin/env bash
# Runs every test suite; exits non-zero if any of them fails.
# Run: bash plugins/dev-workflow/tests/run.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
rc=0
for suite in "$here"/*.test.sh; do
  echo "--- $(basename "$suite") ---"
  bash "$suite" || rc=1
done
[ "$rc" -eq 0 ] && echo "=== ALL SUITES PASSED ===" || echo "=== SOME SUITES FAILED ==="
exit $rc
