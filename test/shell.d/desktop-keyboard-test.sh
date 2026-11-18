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
# A PATH decoy must not satisfy the bind. The config calls the predicate by
# its path under OMARCHY_PATH, which is the real detector.
cat >"$test_dir/bin/omarchy-hw-rog-ally" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$test_dir/bin/omarchy-hw-rog-ally"
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
local panel = { name = "eDP-1", transform = 0 }
local external = { name = "DP-1", transform = 0 }
local layout_changed
local events = {}
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
  config = function(value)
    local vk = value.input and value.input.virtualkeyboard
    if vk and vk.release_pressed_on_close then
      local marker = io.open(os.getenv("OMARCHY_BIND_LOG"), "a")
      marker:write("release_pressed_on_close\n")
      marker:close()
    end
  end,
  get_monitors = function() return { panel, external } end,
  on = function(name, handler)
    if name == "monitor.layout_changed" then layout_changed = handler end
  end,
  dispatch = function(event) table.insert(events, event) end,
  dsp = setmetatable({}, { __index = function(_, name)
    return function(value) return name .. ":" .. tostring(value) end
  end }),
}
require("default.hypr.helpers")
require("default.hypr.bindings.utilities")
if layout_changed then
  local marker = io.open(os.getenv("OMARCHY_BIND_LOG"), "a")
  marker:write("monitor_layout_changed\n")
  marker:close()

  layout_changed()
  external.transform = 2
  layout_changed()
  assert(#events == 0, "stable and external displays do not refresh the handheld transform")

  panel.transform = 2
  layout_changed()
  layout_changed()
  panel.transform = 1
  layout_changed()
  assert(#events == 2 and events[1] == "event:omarchy-monitor-transform:eDP-1" and events[2] == events[1],
    "each internal rotation invalidates the cached transform once")
end
LUA
}

before_release=$(grep -c release_pressed_on_close "$bind_log" || true)
[[ $(shortcut_for 'ROG Ally' 'RC71L' installed) == 'exec_cmd:omarchy-toggle-desktop-keyboard' ]] || fail "RC71L keyboard shortcut routes to the manual OSK"
[[ $(grep -c '^monitor_layout_changed$' "$bind_log") == 1 ]] || fail "RC71L with wvkbd subscribes to native monitor changes"
after_release=$(grep -c release_pressed_on_close "$bind_log" || true)
(( after_release == before_release + 1 )) || fail "RC71L releases virtual-keyboard keys when the client dies"
[[ -z $(shortcut_for 'ROG Ally' 'RC71L' '') ]] || fail "keyboard shortcut needs optional wvkbd"
before_release=$(grep -c release_pressed_on_close "$bind_log" || true)
[[ -z $(shortcut_for 'ROG Ally X RC72LA' 'RC72LA' installed) ]] || fail "keyboard shortcut excludes Ally X"
after_release=$(grep -c release_pressed_on_close "$bind_log" || true)
(( after_release == before_release )) || fail "Ally X does not change virtual-keyboard key release"
[[ -z $(shortcut_for 'ROG Zephyrus' 'GU604' installed) ]] || fail "keyboard shortcut excludes a non-Ally ROG laptop"
before_release=$(grep -c release_pressed_on_close "$bind_log" || true)
[[ -z $(shortcut_for 'XPS 13' '0A1B' installed 'Dell Inc.') ]] || fail "keyboard shortcut excludes a generic laptop"
after_release=$(grep -c release_pressed_on_close "$bind_log" || true)
(( after_release == before_release )) || fail "a generic laptop does not change virtual-keyboard key release"
[[ $(grep -c '^monitor_layout_changed$' "$bind_log") == 1 ]] || fail "the monitor listener excludes PCs and devices without optional wvkbd"
[[ $(<"$bind_log") == *omarchy.agents* && $(<"$bind_log") != *omarchy-toggle-desktop-keyboard* ]] ||
  fail "Super+Ctrl+Y does not take the Agents panel binding Super+Ctrl+X"
pass "keyboard shortcut requires RC71L and optional wvkbd, and never runs while locked"
pass "native internal-display transform events require RC71L and optional wvkbd"
