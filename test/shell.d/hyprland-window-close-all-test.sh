#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
hyprctl_log="$test_tmp/hyprctl.log"
mkdir -p "$mock_bin"

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "clients" ]]; then
  default_clients='[{"address":"0xabc"},{"address":"0xdef"}]'
  printf '%s\n' "${TEST_CLIENTS:-$default_clients}"
else
  printf '%s\n' "$*" >>"$HYPRCTL_LOG"
fi
SH
chmod +x "$mock_bin/hyprctl"

PATH="$mock_bin:$PATH" HYPRCTL_LOG="$hyprctl_log" "$ROOT/bin/omarchy-hyprland-window-close-all"

expected_log="$test_tmp/expected.log"
cat >"$expected_log" <<'EOF'
--batch dispatch hl.dsp.window.close({ window = "address:0xabc" }) ; dispatch hl.dsp.window.close({ window = "address:0xdef" })
dispatch o.workspaces.focus(1)
EOF

diff -u "$expected_log" "$hyprctl_log" || fail "close-all batches window closes with the Lua dispatcher"
pass "close-all batches window closes with the Lua dispatcher"

export PATH="$mock_bin:$PATH" HYPRCTL_LOG="$hyprctl_log"
sleep 0.2 &
first_pid=$!
sleep 0.4 &
second_pid=$!
export TEST_CLIENTS="[{\"address\":\"0xabc\",\"pid\":$first_pid},{\"address\":\"0xdef\",\"pid\":$second_pid},{\"address\":\"0x123\",\"pid\":$first_pid}]"
timeout 1s "$ROOT/bin/omarchy-hyprland-window-close-all" --wait || fail "waiting succeeds"
! kill -0 "$first_pid" 2>/dev/null || fail "wait includes first application"
! kill -0 "$second_pid" 2>/dev/null || fail "wait includes last application"
pass "wait follows application exits, including multiple windows from one process"

# A desktop without clients must not start an unfiltered process wait.
TEST_CLIENTS='[]' timeout 1s "$ROOT/bin/omarchy-hyprland-window-close-all" --wait || fail "empty desktop exits immediately"
pass "empty desktop exits immediately"

TEST_CLIENTS="[{\"address\":\"0xabc\",\"pid\":$first_pid},{\"address\":\"0xdef\",\"pid\":0},{\"address\":\"0x123\"}]" timeout 1s "$ROOT/bin/omarchy-hyprland-window-close-all" --wait || fail "already exited and missing PIDs succeed"
pass "already exited and missing PIDs succeed"

require_command lua
export PATH="$mock_bin:$ROOT/bin:$PATH"
export XDG_RUNTIME_DIR=$test_tmp
export OMARCHY_DMI_SYS_VENDOR_PATH=$test_tmp/vendor
export OMARCHY_DMI_PRODUCT_NAME_PATH=$test_tmp/product
export OMARCHY_DMI_BOARD_NAME_PATH=$test_tmp/board
printf 'ASUSTeK COMPUTER INC.\n' > "$OMARCHY_DMI_SYS_VENDOR_PATH"

close_all_binding() {
  lua -E - <<'LUA'
local root = os.getenv("ROOT")
package.path = root .. "/?.lua;" .. package.path
local function noop() end
local dispatchers = setmetatable({}, { __index = function() return noop end })
hl = {
  dsp = {
    window = dispatchers, group = dispatchers, workspace = dispatchers, layout = noop, focus = noop,
    exec_cmd = function(command) return command end,
  },
  bind = function(keys, command, options)
    if keys == "CTRL + ALT + DELETE" then
      assert(not options.locked)
      print(command)
    end
  end,
}
require("default.hypr.helpers")
o.workspaces = dispatchers
require("default.hypr.bindings.tiling")
LUA
}

printf 'ROG Ally X RC72LA\n' > "$OMARCHY_DMI_PRODUCT_NAME_PATH"
printf 'RC72LA\n' > "$OMARCHY_DMI_BOARD_NAME_PATH"
binding=$(close_all_binding) || fail "the Ally X binding loads"
[[ $binding == "omarchy-hyprland-window-close-all" ]] || fail "Ally X keeps the ordinary binding"
printf 'ROG Ally RC71L\n' > "$OMARCHY_DMI_PRODUCT_NAME_PATH"
printf 'RC71L\n' > "$OMARCHY_DMI_BOARD_NAME_PATH"
binding=$(close_all_binding) || fail "the RC71L binding loads"
[[ -n $binding && $binding != *$'\n'* ]] || fail "the RC71L has one close-all binding"

cat > "$mock_bin/omarchy-menu-select" <<'SH'
#!/bin/bash
case $TEST_CLOSE_CHOICE in
  no) printf '%s\n' "$2" ;;
  yes) printf '%s\n' "$3" ;;
  dismiss) exit 1 ;;
esac
SH
chmod +x "$mock_bin/omarchy-menu-select"
unset TEST_CLIENTS
: > "$hyprctl_log"
for choice in no dismiss; do
  TEST_CLOSE_CHOICE=$choice bash -c "$binding"
  [[ ! -s $hyprctl_log ]] || fail "the RC71L hotkey leaves windows open when the prompt is not accepted"
done
TEST_CLOSE_CHOICE=yes bash -c "$binding"
diff -u "$expected_log" "$hyprctl_log" || fail "only explicit acceptance closes all windows on the RC71L"
pass "the RC71L hotkey needs a second action to close all windows"
