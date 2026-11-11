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
    && /locked: currentlyLocked\(\),/.test(serviceQml),
  'lock, isLocked and status decide from the current lock state'
)
assert(
  /onLockRequestedChanged: publishState\(\)/.test(serviceQml)
    && /onSecureStateChanged: \{\s*root\.publishState\(\)/.test(serviceQml)
    && /onLockStateChanged: \{\s*root\.publishState\(\)/.test(serviceQml)
    && /readLocked: function\(\) \{ return root\.currentlyLocked\(\) \|\| \(root\.trustedHost && !root\.ownerReady\) \}/.test(serviceQml),
  'the readonly feed re-reads actual state on request, compositor lock and secure transitions'
)

// Run the production service selector: losing the broker substitution would
// silently create a second PAM/session-lock owner in the plugin process.
const vm = require('vm')
const source = fs.readFileSync(path.join(root, 'shell/shell.qml'), 'utf8')
const selector = source.slice(source.indexOf('  function ensureService('), source.indexOf('  function _syncServices('))
for (const [mode, componentReady, expected] of [['0', true, 'Service.qml'], ['1', true, 'Broker.qml'], ['1', false, 'Broker.qml']]) {
  const selected = []
  let created = 0
  const manifest = { __isFirstParty: true, kinds: ['service'], entryPoints: { service: 'Service.qml' } }
  const context = {
    _services: {}, pluginRegistry: { installedPlugins: { 'omarchy.lock': manifest }, entryPointUrl: () => 'Service.qml' },
    Quickshell: { env: () => mode }, Component: { Ready: 1, Loading: 2 }, console: { warn() {} },
    Qt: { createComponent(url) { selected.push(url); return {
      status: componentReady ? 1 : 3, errorString: () => 'unavailable', createObject(parent) { assertEqual(parent, null, 'auth/broker has no public parent'); created++; return {} }
    } } },
    AuthServiceStore: { has: () => false, put() {} },
    shell: { omarchyPath: '/trusted', isAuthenticationService: () => true }
  }
  vm.createContext(context)
  vm.runInContext(selector, context)
  context.ensureService('omarchy.lock')
  assert(selected.length === 1 && selected[0].endsWith(expected), `mode ${mode} selects ${expected} without owner fallback`)
  assertEqual(created, componentReady ? 1 : 0, 'unavailable broker never creates a fallback owner')
}
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

PYTHONDONTWRITEBYTECODE=1 python3 "$SHELL_TEST_DIR/trusted-lock-host-test.py"
