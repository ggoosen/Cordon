#!/usr/bin/env bash
# Run the full Cordon test suite. Governance tests are opt-in (LLM-driven):
#   CORDON_RUN_LLM_TESTS=1 ./tests/run.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
rc=0
for t in test-boundary.sh test-enforcement.sh test-governance.sh; do
  echo "==== $t ===="
  bash "$HERE/$t" || rc=1
  echo
done
if [ $rc -eq 0 ]; then echo "ALL SUITES PASSED"; else echo "FAILURES — see above"; fi
exit $rc
