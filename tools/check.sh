#!/bin/zsh
# All offline checks: logic (pomodoro-check), every sound rendered (a buffer overrun traps), then performance.
set -e
cd "$(dirname "$0")/.."
swift build >/dev/null
.build/debug/pomodoro-check
.build/debug/Pomodoro --sound-check
tools/perf_check.sh "${1:-20}"
