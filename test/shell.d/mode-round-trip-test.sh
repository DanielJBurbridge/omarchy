#!/bin/bash
# Switch to Gaming is a System menu row and Super+Ctrl+G, both gated on the
# RC71L and the gaming session package, and both run the launch command.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')

const items = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
const row = items.find((item) => item.id === 'system.switch-gaming')
assert(row, 'System has a Switch to Gaming row')
assertEqual(row.parent, 'system', 'Switch to Gaming is under System')
assertEqual(row.label, 'Switch to Gaming', 'Switch to Gaming uses the spec label')
assertEqual(row.action, 'omarchy-launch-gaming-session', 'Switch to Gaming runs the gaming launcher')
assertEqual(row.when, 'omarchy-hw-rog-ally && omarchy-pkg-present omarchy-gaming-session', 'Switch to Gaming is hidden off the Ally gaming session')
assertDeepEqual(row.aliases, [], 'Switch to Gaming adds no aliases')

const catalog = JSON.parse(fs.readFileSync(path.join(root, 'default/i18n/en/menu.json'), 'utf8'))
assertEqual(catalog['system.switch-gaming'].label, 'Switch to Gaming', 'English menu catalog carries Switch to Gaming')
const keybindings = JSON.parse(fs.readFileSync(path.join(root, 'default/i18n/en/keybindings.json'), 'utf8'))
assertEqual(keybindings['Switch to Gaming'], 'Switch to Gaming', 'English keybindings catalog carries Switch to Gaming')
JS

when=$(node -e '
const fs = require("fs")
const path = require("path")
const menu = require(path.join(process.env.ROOT, "shell/plugins/menu/MenuModel.js"))
const items = menu.parseMenuJsonc(fs.readFileSync(path.join(process.env.ROOT, "default/omarchy/omarchy-menu.jsonc"), "utf8"))
const row = items.find((item) => item.id === "system.switch-gaming")
process.stdout.write(row.when)
')

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"
cat >"$test_dir/bin/pacman" <<'SH'
#!/bin/bash
[[ ${1:-} == -Q && ${2:-} == -- && ${3:-} == omarchy-gaming-session && ${PKG:-absent} == present ]]
SH
chmod +x "$test_dir/bin/pacman"

run_when() {
  local product=$1 board=$2 pkg=$3 vendor=${4:-ASUSTeK COMPUTER INC.}
  printf '%s\n' "$vendor" >"$test_dir/vendor"
  printf '%s\n' "$product" >"$test_dir/product"
  printf '%s\n' "$board" >"$test_dir/board"
  PATH="$test_dir/bin:$ROOT/bin:$PATH" PKG=$pkg \
    OMARCHY_DMI_SYS_VENDOR_PATH="$test_dir/vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$test_dir/product" \
    OMARCHY_DMI_BOARD_NAME_PATH="$test_dir/board" \
    bash -c "$when"
}

run_when 'ROG Ally RC71L' RC71L present &&
  pass "the menu row is shown on an RC71L with the gaming session" ||
  fail "the menu row is shown on an RC71L with the gaming session"
run_when 'ROG Ally RC71L' RC71L absent &&
  fail "the menu row is hidden on an RC71L without the gaming session" ||
  pass "the menu row is hidden on an RC71L without the gaming session"
run_when 'XPS 13' 0A1B present 'Dell Inc.' &&
  fail "the menu row is hidden on a laptop" ||
  pass "the menu row is hidden on a laptop"
run_when 'ROG Ally X RC72LA' RC72LA present &&
  fail "the menu row is hidden on Ally X" ||
  pass "the menu row is hidden on Ally X"

require_command lua
bind_for() {
  local product=$1 board=$2 pkg=$3 vendor=${4:-ASUSTeK COMPUTER INC.}
  printf '%s\n' "$vendor" >"$test_dir/vendor"
  printf '%s\n' "$product" >"$test_dir/product"
  printf '%s\n' "$board" >"$test_dir/board"
  PATH="$test_dir/bin:$ROOT/bin:$PATH" PKG=$pkg \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_DMI_SYS_VENDOR_PATH="$test_dir/vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$test_dir/product" \
    OMARCHY_DMI_BOARD_NAME_PATH="$test_dir/board" \
    /usr/bin/lua - <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path
hl = {
  bind = function(keys, command, options)
    if keys == "SUPER + CTRL + G" then
      print(command)
    end
  end,
  config = function() end,
  on = function() end,
  dsp = setmetatable({}, { __index = function(_, name)
    return function(value) return name .. ":" .. tostring(value) end
  end }),
}
require("default.hypr.helpers")
require("default.hypr.bindings.utilities")
LUA
}

[[ $(bind_for 'ROG Ally RC71L' RC71L present) == 'exec_cmd:omarchy-launch-gaming-session' ]] ||
  fail "Super+Ctrl+G runs omarchy-launch-gaming-session on an RC71L with the package"
[[ -z $(bind_for 'ROG Ally RC71L' RC71L absent) ]] ||
  fail "Super+Ctrl+G is absent without the gaming session package"
[[ -z $(bind_for 'XPS 13' 0A1B present 'Dell Inc.') ]] ||
  fail "Super+Ctrl+G is absent on a laptop"
[[ -z $(bind_for 'ROG Ally X RC72LA' RC72LA present) ]] ||
  fail "Super+Ctrl+G is absent on Ally X"
pass "Super+Ctrl+G follows the Ally gaming-session gate and launches gaming"
