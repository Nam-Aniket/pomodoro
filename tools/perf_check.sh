#!/bin/zsh
# Performance regression check (23 Oct 2026): the real Tomo panel, idle and in calm focus, in a 1%-opacity
# click-through window; nothing real is hidden, retitled or played. Fails if either goes over 2% CPU.
set -e
cd "$(dirname "$0")/.."
swift build -c release --product Pomodoro >/dev/null
home=$(mktemp -d)
for mode in idle focus; do
  POMODORO_LADDER_SCALE=1000 POMODORO_HOME=$home POMODORO_HIDE_ONLY=none POMODORO_EVENT_NAME=perf.test \
    PERF_APP=$mode .build/release/Pomodoro --perf ${1:-24}
done
