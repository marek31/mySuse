#!/usr/bin/env bash
# Self-check of refresh.sh's step runner (resume / restart / named steps). No root needed: bash test_refresh.sh
set -euo pipefail
source "$(dirname "$0")/refresh.sh"
STATE_DIR=$(mktemp -d)
trap 'rm -rf "$STATE_DIR"' EXIT
RAN=$STATE_DIR/ran
ALL_STEPS=(a b c)
step_a() { echo a >> "$RAN"; }
step_b() { [[ -z ${FAIL_B:-} ]] || exit 1; echo b >> "$RAN"; }   # exit = how die() interrupts a run
step_c() { echo c >> "$RAN"; }
HASH=v1
repo_hash() { echo "$HASH"; }
check() { [[ $(tr -d '\n' < "$RAN") == "$1" ]] || { echo "FAIL $2: ran '$(tr -d '\n' < "$RAN")', expected '$1'"; exit 1; }; : > "$RAN"; }
: > "$RAN"

(FAIL_B=1 run_steps) && { echo "FAIL: interrupted run reported success"; exit 1; }
check a "interrupted run"
run_steps;                   check bc  "resume skips finished steps"
[[ ! -e $STATE_DIR/progress ]] || { echo "FAIL: progress kept after a complete run"; exit 1; }
run_steps;                   check abc "complete run is followed by a full run"
(FAIL_B=1 run_steps) || true; check a  "second interruption"
HASH=v2; run_steps;          check abc "repo change restarts all steps"
run_steps c;                 check c   "named step runs alone"
echo "ok - all step runner checks passed"
