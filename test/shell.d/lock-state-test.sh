#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# A locked binding that missed a change once read locked after an unlock, and
# the lock before suspend took that for done, so the machine resumed unlocked.
# The session lock only changes state under a compositor, so nothing offscreen
# can make it disagree with a binding; this reads the source instead, as the
# one guard on a lock that must hold.
run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

assert(
  /function currentlyLocked\(\) \{\s*return lockRequested \|\| sessionLock\.locked \|\| sessionLock\.secure\s*\}/.test(serviceQml),
  'the lock state is read from the session lock itself, not a cached binding'
)
assert(
  /function lock\(\): string \{[\s\S]*?if \(!root\.currentlyLocked\(\) && !root\.beginLock\(\)\) return "failed"/.test(serviceQml)
    && /function isLocked\(\): string \{\s*return root\.currentlyLocked\(\)/.test(serviceQml)
    && /locked: root\.currentlyLocked\(\),/.test(serviceQml),
  'lock, isLocked and status decide from the current lock state'
)

// Exercise the real password failure settlement handlers: PAM can emit both
// onError and onCompleted for a single attempt, which must count once and
// always scrub pendingPassword.
const handleFailureFn = serviceQml.match(/function handlePasswordFailure\(\) \{[\s\S]*?\n  \}/)[0]
const passwordPamBlock = serviceQml.match(/PamContext \{\s*id: passwordPam[\s\S]*?\n  \}/)[0]
const onCompletedBody = passwordPamBlock.match(/onCompleted: function\(result\) \{([\s\S]*?)\n    \}/)[1]
const onErrorBody = passwordPamBlock.match(/onError: function\(error\) \{([\s\S]*?)\n    \}/)[1]

function runPasswordPam(events, lockRequested = true) {
  const ctx = {
    lockRequested,
    authenticatingPassword: true,
    enteredPassword: 'secret',
    pendingPassword: 'secret',
    failedAttempts: 0,
    failureMessage: '',
    unlocked: false,
    woke: 0,
    PamResult: { Success: 0, Failed: 1 },
    I18n: { t: () => ({ arg: v => `Failed (${v})` }), formatNumber: n => String(n) },
    runWake() { this.woke += 1 },
    finishUnlock() { this.unlocked = true }
  }
  ctx.root = ctx
  require('vm').runInNewContext(
    `${handleFailureFn}\nfunction fireCompleted(result) {${onCompletedBody}}\nfunction fireError(error) {${onErrorBody}}`,
    ctx
  )
  for (const [kind, arg] of events) {
    if (kind === 'error') ctx.fireError(arg)
    else ctx.fireCompleted(arg)
  }
  return ctx
}

let attempt = runPasswordPam([['error', 1], ['completed', 1]])
assertEqual(attempt.failedAttempts, 1, 'password onError followed by onCompleted counts a single failure')
assertEqual(attempt.pendingPassword, '', 'password failure scrubs pendingPassword')

attempt = runPasswordPam([['completed', 1], ['error', 1]])
assertEqual(attempt.failedAttempts, 1, 'password onCompleted followed by onError counts a single failure')

attempt = runPasswordPam([['error', 1]], false)
assertEqual(attempt.failedAttempts, 0, 'password error after unlock does not increment failedAttempts')
assertEqual(attempt.pendingPassword, '', 'password error after unlock still scrubs pendingPassword')
assertEqual(attempt.authenticatingPassword, false, 'password error after unlock clears authenticatingPassword')
JS
# Exercise the real one-way producer without a compositor or authentication.
# Restricted agent sandboxes can forbid AF_UNIX; retain static checks there.
if command -v quickshell >/dev/null 2>&1; then
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  mkdir -p "$work/config" "$work/runtime" "$work/home"
  chmod 700 "$work/runtime"
  if python3 - "$work/runtime/probe.sock" 2>/dev/null <<'PY_PROBE'
import socket, sys
with socket.socket(socket.AF_UNIX) as probe:
  probe.bind(sys.argv[1])
PY_PROBE
  then
    cp "$SHELL_TEST_DIR/fixtures/lock-state-socket/shell.qml" "$work/config/shell.qml"
    HOME="$work/home" XDG_RUNTIME_DIR="$work/runtime" HYPRLAND_INSTANCE_SIGNATURE=fixture \
      OMARCHY_PATH="$ROOT" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= \
      QT_QUICK_BACKEND=software timeout 15 quickshell -p "$work/config" --no-color >"$work/log" 2>&1 || {
        cat "$work/log" >&2
        fail "readonly lock-state socket runs"
      }
    if ! grep -q 'LOCK_STATE_SOCKET_TEST_PASS' "$work/log" || grep -q 'LOCK_STATE_SOCKET_TEST_FAIL' "$work/log"; then
      cat "$work/log" >&2
      fail "readonly lock-state socket publishes transitions and closes on death"
    fi
    pass "readonly lock-state socket sends initial state and transitions, rejects writes and closes subscribers"
  else
    skip "AF_UNIX unavailable; skipping readonly lock-state socket runtime check"
  fi
fi
