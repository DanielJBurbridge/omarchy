#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

script=$ROOT/docs/handheld/research/tools/ally-press-test.sh

bash -n "$script" || fail "ally press test has valid syntax"
pass "ally press test has valid syntax"

grep -F 'Press the LEFT back paddle (M2)' "$script" >/dev/null || fail "the left back paddle is M2"
grep -F 'Press the RIGHT back paddle (M1)' "$script" >/dev/null || fail "the right back paddle is M1"
grep -F 'LEFT back paddle (M1)' "$script" >/dev/null && fail "the left back paddle is not labelled M1"
grep -F 'RIGHT back paddle (M2)' "$script" >/dev/null && fail "the right back paddle is not labelled M2"
pass "paddle prompts name M2 on the left and M1 on the right"

grep -F 'inputplumber.service' "$script" >/dev/null || fail "the press test names inputplumber.service"
grep -F 'systemctl stop' "$script" >/dev/null || fail "the press test stops inputplumber"
grep -F 'systemctl start' "$script" >/dev/null || fail "the press test starts inputplumber"
grep -F 'IP_WAS_ACTIVE' "$script" >/dev/null || fail "the press test restarts inputplumber only when it was active"
grep -F 'IP_RESTORED' "$script" >/dev/null || fail "the press test restore runs once"
grep -F 'trap restore_capture EXIT' "$script" >/dev/null || fail "the press test restores inputplumber on EXIT"
grep -F "trap 'restore_capture; exit 130' INT" "$script" >/dev/null || fail "the press test restores inputplumber on INT"
grep -F "trap 'restore_capture; exit 143' TERM" "$script" >/dev/null || fail "the press test restores inputplumber on TERM"
pass "the press test restores inputplumber from an idempotent trap"
