#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# This offscreen check uses the real Qt keyboard plugin and never locks the
# compositor. It also runs on builders without a desktop session.
if command -v quickshell >/dev/null 2>&1; then
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  mkdir -p "$work/config" "$work/runtime" "$work/home"
  chmod 700 "$work/runtime"
  cp "$SHELL_TEST_DIR/fixtures/trusted-auth/shell.qml" "$work/config/shell.qml"
  ln -s "$ROOT/shell/Ui" "$work/config/Ui"
  ln -s "$ROOT/shell/Commons" "$work/config/Commons"
  HOME="$work/home" XDG_RUNTIME_DIR="$work/runtime" \
    OMARCHY_PATH="$ROOT" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= \
    QT_STYLE_OVERRIDE= QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=Basic \
    QT_IM_MODULE=qtvirtualkeyboard QT_IM_MODULES=qtvirtualkeyboard QT_VIRTUALKEYBOARD_DESKTOP_DISABLE=1 \
    timeout 20 quickshell -p "$work/config" --no-color >"$work/log" 2>&1 || {
      cat "$work/log" >&2
      fail "trusted authentication keyboard runs"
    }
  if ! grep -q 'TRUSTED_AUTH_TEST_PASS' "$work/log" || grep -q 'TRUSTED_AUTH_TEST_FAIL' "$work/log"; then
    cat "$work/log" >&2
    fail "trusted authentication keyboard handles password entry and submission"
  fi
  pass "trusted keyboards mask and edit non-US input, submit once and cancel safely"
  rm -rf "$work"
  trap - EXIT
fi

require_quickshell "lock autorepeat test"

run_qml_fixture lock-autorepeat "lock password field drops auto-repeat except Backspace/Delete" Ui Commons
