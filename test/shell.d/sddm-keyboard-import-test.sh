#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

greeter="$ROOT/default/sddm/omarchy/Main.qml"
form="$ROOT/default/sddm/omarchy/LoginForm.qml"

if grep -q 'import QtQuick.VirtualKeyboard' "$greeter"; then
  fail "the greeter root imports QtQuick.VirtualKeyboard unconditionally"
fi
grep -q 'LoginForm.qml' "$greeter" || fail "the greeter loads the styled form from a separate document"
grep -q 'loginFallbackLoader' "$greeter" || fail "the greeter keeps a sign-in form when the keyboard style cannot load"
grep -q 'import QtQuick.VirtualKeyboard.Styles.Omarchy as Auth' "$form" || fail "the styled sign-in form still provides the virtual keyboard"
pass "the greeter root has no virtual-keyboard import and falls back when that module is missing"

if ! command -v quickshell >/dev/null 2>&1; then
  skip "quickshell not installed; skipping greeter load without the keyboard module"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/config" "$work/runtime" "$work/home"
chmod 700 "$work/runtime"
cat >"$work/config/shell.qml" <<QML
import QtQuick
import Quickshell

ShellRoot {
  Component.onCompleted: {
    var missing = Qt.createComponent("file://$form", Component.PreferSynchronous)
    if (missing.status !== Component.Error || missing.errorString().indexOf("VirtualKeyboard") === -1)
      throw new Error("styled form should fail closed without the keyboard module: " + missing.errorString())
    var root = Qt.createComponent("file://$greeter", Component.PreferSynchronous)
    if (root.status === Component.Error && root.errorString().indexOf("VirtualKeyboard") !== -1)
      throw new Error("greeter root still requires the keyboard module: " + root.errorString())
    console.log("SDDM_KEYBOARD_IMPORT_TEST_PASS")
    Qt.quit()
  }
}
QML

# No QML_IMPORT_PATH: the Omarchy style module is not on the default import path.
# quickshell exits non-zero when nothing is connected to Qt.quit(). The pass
# line is the result that matters.
HOME="$work/home" XDG_RUNTIME_DIR="$work/runtime" \
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software \
  QT_QUICK_CONTROLS_STYLE=Basic QML_IMPORT_PATH= \
  timeout 20 quickshell -p "$work/config" --no-color >"$work/log" 2>&1 || true
if ! grep -q 'SDDM_KEYBOARD_IMPORT_TEST_PASS' "$work/log"; then
  cat "$work/log" >&2
  fail "greeter root loads when QtQuick.VirtualKeyboard is not installed"
fi
pass "the sign-in screen does not depend on QtQuick.VirtualKeyboard being installed"
