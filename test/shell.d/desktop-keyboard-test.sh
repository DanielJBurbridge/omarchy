#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
# Reproduce a host with wvkbd installed, even on a machine without it. The
# missing-dependency test must never discover this caller-side executable.
mkdir -p "$test_dir/host-bin"
printf '#!/bin/bash\nexit 99\n' >"$test_dir/host-bin/wvkbd-mobintl"
chmod +x "$test_dir/host-bin/wvkbd-mobintl"
PATH="$test_dir/host-bin:$PATH" python3 "$ROOT/test/helpers/desktop-keyboard-process.py" "$ROOT/bin/omarchy-toggle-desktop-keyboard"

# Exercise the actual binding and central DMI predicate: the panel shortcut
# must stay absent on a laptop, newer Ally, or machine without optional wvkbd.
require_command lua
mkdir -p "$test_dir/bin" "$test_dir/optional"
ln -s "$ROOT/bin/omarchy-hw-rog-ally" "$test_dir/bin/omarchy-hw-rog-ally"
ln -s /usr/bin/cat "$test_dir/bin/cat"
: >"$test_dir/optional/wvkbd-mobintl"
bind_log=$test_dir/binds
: >"$bind_log"

shortcut_for() {
  printf '%s\n' "${4:-ASUSTeK COMPUTER INC.}" >"$test_dir/vendor"
  printf '%s\n' "$1" >"$test_dir/product"
  printf '%s\n' "$2" >"$test_dir/board"
  PATH="$test_dir/bin${3:+:$test_dir/optional}" \
    OMARCHY_PATH="$ROOT" OMARCHY_BIND_LOG="$bind_log" \
    OMARCHY_DMI_SYS_VENDOR_PATH="$test_dir/vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$test_dir/product" OMARCHY_DMI_BOARD_NAME_PATH="$test_dir/board" \
    /usr/bin/lua - <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path
hl = {
  bind = function(keys, command, options)
    if keys == "SUPER + CTRL + X" then
      local marker = io.open(os.getenv("OMARCHY_BIND_LOG"), "a")
      marker:write(command, "\n")
      marker:close()
    end
    if keys == "SUPER + CTRL + Y" then
      assert(not options.locked, "desktop keyboard binding must not run while locked")
      print(command)
    end
  end,
  on = function() end,
  dsp = setmetatable({}, { __index = function(_, name)
    return function(value) return name .. ":" .. tostring(value) end
  end }),
}
require("default.hypr.helpers")
require("default.hypr.bindings.utilities")
LUA
}

[[ $(shortcut_for 'ROG Ally' 'RC71L' installed) == 'exec_cmd:omarchy-toggle-desktop-keyboard' ]] || fail "RC71L keyboard shortcut routes to the manual OSK"
[[ -z $(shortcut_for 'ROG Ally' 'RC71L' '') ]] || fail "keyboard shortcut needs optional wvkbd"
[[ -z $(shortcut_for 'ROG Ally X RC72LA' 'RC72LA' installed) ]] || fail "keyboard shortcut excludes Ally X"
[[ -z $(shortcut_for 'ROG Zephyrus' 'GU604' installed) ]] || fail "keyboard shortcut excludes a non-Ally ROG laptop"
[[ -z $(shortcut_for 'XPS 13' '0A1B' installed 'Dell Inc.') ]] || fail "keyboard shortcut excludes a generic laptop"
[[ $(<"$bind_log") == *omarchy.agents* && $(<"$bind_log") != *omarchy-toggle-desktop-keyboard* ]] ||
  fail "Super+Ctrl+Y does not take the Agents panel binding Super+Ctrl+X"
pass "keyboard shortcut requires RC71L and optional wvkbd, and never runs while locked"
