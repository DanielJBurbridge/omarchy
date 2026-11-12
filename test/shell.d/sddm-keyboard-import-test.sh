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
grep -q 'detectHandheld' "$greeter" || fail "the greeter does not choose a handheld branch"
grep -q 'styledLogin.source = "LoginForm.qml"' "$greeter" || fail "the handheld branch does not load the virtual keyboard form"
grep -q 'fallbackLogin.active = true' "$greeter" || fail "the laptop branch does not keep the keyboard-less form"
pass "the greeter root has no virtual-keyboard import and falls back when that module is missing"

if ! command -v quickshell >/dev/null 2>&1; then
  skip "quickshell not installed; skipping greeter load without the keyboard module"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/config" "$work/runtime" "$work/home" "$work/theme"
chmod 700 "$work/runtime"
ln -s "$greeter" "$work/theme/Main.qml"
ln -s "$form" "$work/theme/LoginForm.qml"
printf '%s\n' 0 > "$work/theme/handheld-variant"

run_greeter() {
  local marker=$1 pass_line=$2
  printf '%s\n' "$marker" > "$work/theme/handheld-variant"
  cat >"$work/config/shell.qml" <<QML
import QtQuick
import Quickshell

ShellRoot {
  function find(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) {
      var found = find(kids[i], name)
      if (found) return found
    }
    return null
  }
  Component.onCompleted: {
    var component = Qt.createComponent("file://$work/theme/Main.qml", Component.PreferSynchronous)
    if (component.status !== Component.Ready)
      throw new Error("greeter failed to load: " + component.errorString())
    var greeter = component.createObject(null)
    var styled = find(greeter, "loginStyledLoader")
    var fallback = find(greeter, "loginFallbackLoader")
    if ("$marker" === "0") {
      if (styled && styled.active)
        throw new Error("laptop greeter loaded the virtual keyboard")
      if (!fallback || !fallback.active)
        throw new Error("laptop greeter has no keyboard-less form")
      console.log("$pass_line")
    } else {
      if (!styled || !styled.active || String(styled.source).indexOf("LoginForm.qml") === -1)
        throw new Error("handheld greeter did not load the virtual keyboard form")
      if (styled.status === Loader.Error && String(styled.sourceComponent).indexOf("VirtualKeyboard") === -1 && String(component.errorString()).indexOf("VirtualKeyboard") === -1) {
        // Loader.Error is the expected result when the module is absent.
      }
      if (fallback && fallback.active)
        throw new Error("handheld greeter fell back to the keyboard-less form")
      console.log("$pass_line")
    }
    Qt.quit()
  }
}
QML
  HOME="$work/home" XDG_RUNTIME_DIR="$work/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software \
    QT_QUICK_CONTROLS_STYLE=Basic QML_IMPORT_PATH= QML_XHR_ALLOW_FILE_READ=1 \
    timeout 20 quickshell -p "$work/config" --no-color >"$work/log" 2>&1 || true
  if ! grep -q "$pass_line" "$work/log"; then
    cat "$work/log" >&2
    fail "$pass_line"
  fi
}

run_greeter 0 "SDDM_LAPTOP_GREETER_TEST_PASS"
pass "a laptop greeter loads without Qt Virtual Keyboard"
run_greeter 1 "SDDM_HANDHELD_VKB_TEST_PASS"
pass "a handheld greeter loads the virtual keyboard and does not drop it"
