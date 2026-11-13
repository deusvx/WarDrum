#!/usr/bin/env bash
# Runs every scenario in tests/scenarios against a tiny stand-in for the game.
# Needs: pip install lupa
# Usage: tests/run_tests.sh            (all of them)
#        tests/run_tests.sh meter      (only scenarios with "meter" in the name)
set -e
cd "$(dirname "$0")"
PY="${PYTHON:-python3}"
"$PY" -I harness.py .. "$1"
