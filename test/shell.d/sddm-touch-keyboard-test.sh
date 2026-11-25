#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

qt_bin=/usr/lib/qt6/bin
runner="$qt_bin/qmltestrunner"
if [[ ! -x $runner ]]; then
  skip "Qt 6 qmltestrunner is unavailable"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work"/{home,runtime,imports/QtQuick,plugins}
chmod 700 "$work/runtime"
cp "$SHELL_TEST_DIR/sddm-touch-keyboard/"*.qml "$work/"
ln -s "$ROOT/default/sddm/omarchy" "$work/theme"

export HOME="$work/home" XDG_RUNTIME_DIR="$work/runtime" LC_ALL=C.UTF-8
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_PLATFORMTHEME=
export QT_IM_MODULE=qtvirtualkeyboard QT_VIRTUALKEYBOARD_DESKTOP_DISABLE=1
unset QT_IM_MODULES

run_case() {
  local runner=$1 test_case=$2 description=$3
  local output
  output=$(timeout 15 "$runner" -input "$work" -o -,txt "SddmTouchKeyboard::$test_case" 2>&1) ||
    fail "$description" "$output"
  printf '%s\n' "$output"
  pass "$description"
}

# Give the copied runner a Qt import tree without VirtualKeyboard. This tests
# a real missing import even when the module is installed on the test host.
qt_qml=$("$qt_bin/qtpaths" --query QT_INSTALL_QML)
qt_plugins=$("$qt_bin/qtpaths" --query QT_INSTALL_PLUGINS)
cp "$runner" "$work/"
ln -s "$qt_qml/QtQml" "$qt_qml/QtTest" "$work/imports/"
ln -s "$qt_qml/QtQuick/"{qmldir,libqtquick2plugin.so,Window} "$work/imports/QtQuick/"
ln -s "$qt_plugins/platforms" "$work/plugins/"
printf '[Paths]\nQmlImports=%s/imports\nPlugins=%s/plugins\n' "$work" "$work" >"$work/qt.conf"
QML_IMPORT_PATH= QML2_IMPORT_PATH= QT_PLUGIN_PATH= \
  run_case "$work/qmltestrunner" test_withoutKeyboard "touch leaves physical sign-in working without Qt Virtual Keyboard"

IFS=: read -r -a extra_imports <<<"${QML_IMPORT_PATH:-}"
for imports in "$qt_qml" "${extra_imports[@]}"; do
  if [[ -f $imports/QtQuick/VirtualKeyboard/qmldir ]]; then
    run_case "$runner" test_withKeyboard "touch signs in and reopens the native keyboard after its hide key"
    exit 0
  fi
done
skip "Qt Virtual Keyboard is unavailable"
