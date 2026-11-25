#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

dmi="$test_tmp/dmi"
mkdir -p "$dmi" "$dmi/lid" "$dmi/input"
: >"$dmi/sys_vendor"
: >"$dmi/product_name"
: >"$dmi/board_name"
printf '3\n' >"$dmi/chassis_type"

write_dmi() {
  printf '%s\n' "$1" >"$dmi/sys_vendor"
  printf '%s\n' "$2" >"$dmi/product_name"
  printf '%s\n' "$3" >"$dmi/board_name"
}

run_ally() {
  OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    "$ROOT/bin/omarchy-hw-rog-ally"
}

# --- DMI: original Ally, not Ally X or a later board ---

vendor="ASUSTeK COMPUTER INC."

# Leave the board empty so only the product-name branch can match these cases.
write_dmi "$vendor" "ROG Ally RC71L" ""
run_ally || fail "product ROG Ally RC71L is the original Ally"
pass "product ROG Ally RC71L is the original Ally"

write_dmi "$vendor" "ROG Ally RC71L_RC71L" ""
run_ally || fail "product ROG Ally RC71L_RC71L is the original Ally"
pass "product ROG Ally RC71L_RC71L is the original Ally"

write_dmi "$vendor" "ROG Ally RC71L_Action" ""
run_ally || fail "product ROG Ally RC71L_Action is the original Ally"
pass "product ROG Ally RC71L_Action is the original Ally"

write_dmi "$vendor" "ROG Ally" "RC71L"
run_ally || fail "board RC71L is the original Ally when the product string is short"
pass "board RC71L is the original Ally when the product string is short"

write_dmi "$vendor" "ROG Ally X RC72LA" "RC72LA"
if run_ally; then
  fail "Ally X product ROG Ally X RC72LA is not the original Ally"
fi
pass "Ally X product ROG Ally X RC72LA is not the original Ally"

write_dmi "$vendor" "ROG Ally X RC72LA_RC72LA" "RC72LA"
if run_ally; then
  fail "Ally X product ROG Ally X RC72LA_RC72LA is not the original Ally"
fi
pass "Ally X product ROG Ally X RC72LA_RC72LA is not the original Ally"

write_dmi "$vendor" "ROG Xbox Ally RC73YA" "RC73YA"
if run_ally; then
  fail "Xbox Ally RC73YA is not the original Ally"
fi
pass "Xbox Ally RC73YA is not the original Ally"

write_dmi "ASUS" "ROG Ally RC71L_RC71L" "RC71L"
if run_ally; then
  fail "a short ASUS vendor string is not the original Ally"
fi
pass "a short ASUS vendor string is not the original Ally"

write_dmi "LENOVO" "ROG Ally RC71L" "RC71L"
if run_ally; then
  fail "another vendor with an Ally product string is not the original Ally"
fi
pass "another vendor with an Ally product string is not the original Ally"

write_dmi "$vendor" "ROG Strix G16" "GU605CX"
if run_ally; then
  fail "a ROG laptop is not the original Ally"
fi
pass "a ROG laptop is not the original Ally"

OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/missing-vendor" \
  OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/missing-product" \
  OMARCHY_DMI_BOARD_NAME_PATH="$dmi/missing-board" \
  "$ROOT/bin/omarchy-hw-rog-ally" && fail "missing DMI is not the original Ally"
pass "missing DMI is not the original Ally"

# An installed but dormant asusd must stay dormant even on an explicit colour request.
write_dmi "$vendor" "ROG Ally RC71L" "RC71L"
services="$test_tmp/data/dbus-1/services"
mkdir -p "$services"
cat >"$services/xyz.ljones.Asusd.service" <<EOF
[D-BUS Service]
Name=xyz.ljones.Asusd
Exec=/usr/bin/touch $test_tmp/activated
EOF
if message=$(XDG_DATA_HOME="$test_tmp/data" OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
  OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
  PATH="$ROOT/bin:$PATH" dbus-run-session -- bash -c '
    export DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS
    omarchy games lighting colour 135793
  ' 2>&1); then
  fail "lighting accepted a colour without an ASUS owner"
fi
[[ ! -e $test_tmp/activated ]] || fail "lighting activated the dormant ASUS owner"
[[ $message == *"asusd is not running"* || $message == *"Alternate joystick-ring driver active"* ]] ||
  fail "lighting did not explain the unavailable stock owner" "$message"
pass "a ring colour request leaves a dormant ASUS owner alone"

OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
  OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" PATH="$ROOT/bin:$PATH" \
  python3 "$ROOT/test/helpers/ally-lighting.py" "$ROOT" "$test_tmp"
pass "ring writes require matching live and saved settings across RON field orders"

# --- asusctl is the laptop package, and the Ally leaf only speaks on RC71L ---

stub="$test_tmp/bin"
mkdir -p "$stub"
pkg_log="$test_tmp/packages"
: >"$pkg_log"

cat >"$stub/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$PKG_LOG"
SH
chmod +x "$stub/omarchy-pkg-add"

cat >"$stub/omarchy-hw-asus-rog" <<'SH'
#!/bin/bash
exit "${FAKE_ASUS_ROG:-1}"
SH
chmod +x "$stub/omarchy-hw-asus-rog"

cat >"$stub/omarchy-hw-rog-ally" <<'SH'
#!/bin/bash
exit "${FAKE_ROG_ALLY:-1}"
SH
chmod +x "$stub/omarchy-hw-rog-ally"

source_install() {
  local script="$1"
  PKG_LOG="$pkg_log" FAKE_ASUS_ROG="${2:-1}" FAKE_ROG_ALLY="${3:-1}" \
    PATH="$stub:$PATH" \
    bash -eE -c 'source "$1"' bash "$script" </dev/null
}

: >"$pkg_log"
source_install "$ROOT/install/hardware/asus-rog.sh" 0 1
[[ $(cat "$pkg_log") == "asusctl" ]] || fail "a ROG laptop still installs asusctl" "$(cat "$pkg_log")"
pass "a ROG laptop still installs asusctl"

: >"$pkg_log"
source_install "$ROOT/install/hardware/asus-rog.sh" 0 0
[[ ! -s $pkg_log ]] || fail "the original Ally does not install asusctl" "$(cat "$pkg_log")"
pass "the original Ally does not install asusctl"

: >"$pkg_log"
source_install "$ROOT/install/hardware/asus-rog.sh" 1 1
[[ ! -s $pkg_log ]] || fail "a non-ROG machine does not install asusctl" "$(cat "$pkg_log")"
pass "a non-ROG machine does not install asusctl"

power_stub="$test_tmp/power-stub"
mkdir -p "$power_stub"
cat >"$power_stub/omarchy-install-rog-ally-powerbutton" <<'SH'
#!/bin/bash
printf '%s\n' "install-powerbutton" >>"$PKG_LOG"
exit "${FAKE_POWER_INSTALL:-0}"
SH
cat >"$power_stub/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ $1 == omarchy-gaming-session && ${FAKE_GAMING_SESSION:-0} == 1 ]]
SH
chmod +x "$power_stub/omarchy-install-rog-ally-powerbutton" "$power_stub/omarchy-pkg-present"

run_ally_leaf() {
  OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    PKG_LOG="$pkg_log" FAKE_POWER_INSTALL="${1:-0}" FAKE_GAMING_SESSION="${2:-0}" \
    PATH="$power_stub:$ROOT/bin:$PATH" \
    bash -eE -c 'source "$1"' bash "$ROOT/install/hardware/asus/rog-ally.sh" </dev/null
}

: >"$pkg_log"
note=$(
  write_dmi "$vendor" "ROG Ally RC71L_RC71L" "RC71L"
  run_ally_leaf 0 0
)
[[ $note == *"RC71L"* && $note == *"asusctl"* ]] || fail "the Ally hardware leaf names the machine and the skipped package" "$note"
[[ ! -s $pkg_log ]] || fail "the Ally hardware leaf does not install the power button without the gaming session" "$(<"$pkg_log")"
pass "the Ally hardware leaf names the machine and skips the power button without the gaming session"

: >"$pkg_log"
note=$(
  write_dmi "$vendor" "ROG Ally RC71L_RC71L" "RC71L"
  run_ally_leaf 0 1
)
[[ $(<"$pkg_log") == "install-powerbutton" ]] || fail "the Ally hardware leaf installs the power-button companion with the gaming session" "$(<"$pkg_log")"
pass "the Ally hardware leaf installs the power-button companion with the gaming session"

: >"$pkg_log"
note=$(
  write_dmi "$vendor" "ROG Ally X RC72LA_RC72LA" "RC72LA"
  run_ally_leaf
)
[[ -z $note ]] || fail "the Ally hardware leaf is silent on an Ally X" "$note"
[[ ! -s $pkg_log ]] || fail "an Ally X does not install the power-button companion" "$(<"$pkg_log")"
pass "the Ally hardware leaf is silent on an Ally X"

: >"$pkg_log"
write_dmi "$vendor" "ROG Ally" "RC71L"
if ! err=$(run_ally_leaf 1 1 2>&1 >/dev/null); then
  fail "a failed companion install does not abort the Ally hardware leaf"
fi
[[ $err == *"omarchy-setup-gaming-session"* ]] || fail "a failed companion install names the command to re-run" "$err"
pass "a failed companion install does not stall the rest of hardware setup"

# Laptop audio quirks must not run on the Ally. sudo is stubbed so a body that
# does run cannot touch the machine.
cat >"$stub/sudo" <<'SH'
#!/bin/bash
printf '%s\n' "sudo $*" >>"$PKG_LOG"
exit 1
SH
chmod +x "$stub/sudo"

# Keep the laptop-path mixer test off the host's sound cards.
cat >"$stub/aplay" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub/aplay"

home="$test_tmp/home"
mkdir -p "$home"
mixer="$home/.config/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf"

: >"$pkg_log"
FAKE_ASUS_ROG=0 FAKE_ROG_ALLY=0 PKG_LOG="$pkg_log" \
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$stub:$PATH" \
  bash -eE -c 'source "$1"' bash "$ROOT/install/user/hardware/asus/fix-audio-mixer.sh" </dev/null
[[ ! -e $mixer ]] || fail "the Ally does not get the ROG laptop soft mixer"
[[ ! -s $pkg_log ]] || fail "the Ally audio leaf does not call sudo" "$(cat "$pkg_log")"
pass "the Ally does not get the ROG laptop soft mixer"

: >"$pkg_log"
FAKE_ASUS_ROG=0 FAKE_ROG_ALLY=0 PKG_LOG="$pkg_log" \
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$stub:$PATH" \
  bash -eE -c 'source "$1"' bash "$ROOT/install/user/hardware/asus/fix-mic.sh" </dev/null
[[ ! -s $pkg_log ]] || fail "the Ally mic leaf does not call sudo" "$(cat "$pkg_log")"
pass "the Ally does not get the ROG laptop mic boost change"

: >"$pkg_log"
FAKE_ASUS_ROG=0 FAKE_ROG_ALLY=1 PKG_LOG="$pkg_log" \
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$stub:$PATH" \
  bash -eE -c 'source "$1"' bash "$ROOT/install/user/hardware/asus/fix-audio-mixer.sh" </dev/null
[[ -f $mixer ]] || fail "a ROG laptop still gets the soft mixer"
pass "a ROG laptop still gets the soft mixer"

# Append to test/shell.d/hw-rog-ally-test.sh from PR #18022.
# Regression: a detector/installer integration error must not erase an Ally
# user's saved audio routes or replace their mixer on repeated finalisation.
# Reuse the suite's scratch DMI and home, but run the REAL Ally predicate.

real_predicate="$test_tmp/real-predicate"
mkdir -p "$real_predicate"
ln -s "$ROOT/bin/omarchy-hw-rog-ally" "$real_predicate/omarchy-hw-rog-ally"
cat >"$stub/amixer" <<'SH'
#!/bin/bash
printf 'amixer %s\n' "$*" >>"$PKG_LOG"
exit 1
SH
chmod +x "$stub/amixer"

route="$home/.local/state/wireplumber/default-routes"
mkdir -p "$(dirname "$route")" "$(dirname "$mixer")"
printf 'user-selected audio route\n' >"$route"
printf '# user-owned mixer\n' >"$mixer"
cp "$route" "$test_tmp/expected-routes"
cp "$mixer" "$test_tmp/expected-mixer"

for identity in product board; do
  if [[ $identity == "product" ]]; then
    write_dmi "$vendor" "ROG Ally RC71L_RC71L" ""
  else
    write_dmi "$vendor" "ROG Ally" "RC71L"
  fi
  for attempt in first repeated; do
    : >"$pkg_log"
    for leaf in hardware/asus-rog.sh user/hardware/asus/fix-audio-mixer.sh user/hardware/asus/fix-mic.sh; do
      OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
        OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
        OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
        FAKE_ASUS_ROG=0 PKG_LOG="$pkg_log" HOME="$home" OMARCHY_PATH="$ROOT" \
        PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
        bash -eE -c 'source "$1"' bash "$ROOT/install/$leaf" </dev/null
    done
    cmp -s "$route" "$test_tmp/expected-routes" ||
      fail "Ally $identity identity preserves audio routes on $attempt finalisation"
    cmp -s "$mixer" "$test_tmp/expected-mixer" ||
      fail "Ally $identity identity preserves a custom mixer on $attempt finalisation"
    [[ ! -s $pkg_log ]] ||
      fail "Ally $identity identity skips laptop packages and privileged audio writes" "$(cat "$pkg_log")"
  done
done
pass "real Ally detection preserves existing audio state on repeated hardware/user setup"

# A negative control keeps this from passing just because setup never runs.
write_dmi "$vendor" "ROG Strix G16" "GU605CX"
: >"$pkg_log"
OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
  OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
  OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
  FAKE_ASUS_ROG=0 PKG_LOG="$pkg_log" \
  PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
  bash -eE -c 'source "$1"' bash "$ROOT/install/hardware/asus-rog.sh" </dev/null
[[ $(cat "$pkg_log") == "asusctl" ]] || fail "real Ally detector leaves ROG laptop setup active"
pass "real Ally detector leaves ROG laptop setup active"

# Exercise the first-login invitation independently of an installed Steam client.
cat >"$stub/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ $1 == "omarchy-setup-gaming" && ${OMARCHY_TEST_GAMING_SETUP:-0} == "1" ]]
SH
cat >"$stub/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$PKG_LOG"
SH
chmod +x "$stub/omarchy-cmd-present" "$stub/omarchy-notification-send"

run_gaming_invitation() {
  OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    HOME="$test_tmp/invitation-$1" OMARCHY_PATH="$ROOT" PKG_LOG="$pkg_log" \
    OMARCHY_TEST_GAMING_SETUP="$2" PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
    bash "$ROOT/install/user/first-run/setup-rog-ally.hook"
}

: >"$pkg_log"
write_dmi "$vendor" "ROG Strix G16" "GU605CX"
run_gaming_invitation other 0
[[ ! -s $pkg_log && ! -e "$test_tmp/invitation-other/.local/state/omarchy/done/rog-ally-gaming-invitation" ]] ||
  fail "other hardware receives no Ally invitation or marker"
write_dmi "$vendor" "ROG Ally RC71L_RC71L" "RC71L"
run_gaming_invitation fallback 0
run_gaming_invitation fallback 0
[[ $(wc -l <"$pkg_log") == "1" && $(<"$pkg_log") == *"--exec omarchy-menu summon install.gaming" ]] ||
  fail "the Ally invites once using the existing installer menu when Gaming Setup is absent"
: >"$pkg_log"
run_gaming_invitation guided 1
[[ $(<"$pkg_log") == *"--exec omarchy-setup-gaming" ]] ||
  fail "the Ally invitation uses Gaming Setup when available"
pass "first-login invitation is hardware-gated, once-only and independently usable"

# The Suspend row and power button must share the same lock decision on an
# RC71L. The existing sleep-lock suite exercises secure-lock IPC.
power_omarchy="$test_tmp/power-omarchy"
mkdir -p "$power_omarchy/bin" "$test_tmp/runtime"
cat >"$power_omarchy/bin/omarchy-system-sleep-lock" <<'SH'
#!/bin/bash
echo lock >>"$PKG_LOG"
exit "${FAKE_LOCK_RESULT:-0}"
SH
cat >"$stub/omarchy-menu" <<'SH'
#!/bin/bash
echo "menu $*" >>"$PKG_LOG"
SH
cat >"$stub/systemctl" <<'SH'
#!/bin/bash
echo "systemctl $*" >>"$PKG_LOG"
SH
cat >"$stub/hyprctl" <<'SH'
#!/bin/bash
[[ $* == "locked" ]] || exit 2
printf '%s\n' "${FAKE_COMPOSITOR_LOCKED:-false}"
exit "${FAKE_HYPRCTL_RESULT:-0}"
SH
cat >"$stub/omarchy-sleep-disabled" <<'SH'
#!/bin/bash
exit "${FAKE_SLEEP_DISABLED:-1}"
SH
cat >"$stub/omarchy-toggle-enabled" <<'SH'
#!/bin/bash
[[ $1 == "suspend-off" ]] && exit "${FAKE_SUSPEND_OFF:-1}"
exit 1
SH
chmod +x "$power_omarchy/bin/omarchy-system-sleep-lock" "$stub/omarchy-menu" \
  "$stub/systemctl" "$stub/hyprctl" "$stub/omarchy-sleep-disabled" "$stub/omarchy-toggle-enabled"

run_desktop_action() {
  OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    XDG_RUNTIME_DIR="$test_tmp/runtime" OMARCHY_PATH="$power_omarchy" \
    PKG_LOG="$pkg_log" PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
    "$@"
}

run_power_button() {
  run_desktop_action omarchy-system-power-button
}

menu_suspend=$(run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const items = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
process.stdout.write(items.find(item => item.id === 'system.suspend').action)
JS
)

run_menu_suspend() {
  run_desktop_action bash -c "$menu_suspend"
}

for product in "ROG Strix G16" "ROG Ally X RC72LA"; do
  write_dmi "$vendor" "$product" ""
  : >"$pkg_log"
  run_power_button
  [[ $(<"$pkg_log") == "menu toggle system" ]] || fail "power button preserves $product power menu"
  : >"$pkg_log"
  FAKE_LOCK_RESULT=1 run_menu_suspend
  [[ $(<"$pkg_log") == "systemctl suspend" ]] || fail "the Suspend row keeps the existing $product behavior"
done
pass "non-RC71L power buttons and Suspend rows retain their existing behavior"

write_dmi "$vendor" "ROG Ally" "RC71L"
for entry in run_power_button run_menu_suspend; do
  : >"$pkg_log"
  "$entry"
  [[ $(<"$pkg_log") == $'lock\nsystemctl suspend' ]] || fail "$entry must lock the RC71L before requesting suspend"

  : >"$pkg_log"
  if FAKE_LOCK_RESULT=1 "$entry"; then
    fail "a failed lock must cancel $entry"
  fi
  [[ $(<"$pkg_log") == "lock" ]] || fail "a failed lock never reaches systemctl"
done
pass "the RC71L Suspend row and power button both cancel suspend when the desktop lock fails"

: >"$pkg_log"
FAKE_COMPOSITOR_LOCKED=true run_power_button
FAKE_COMPOSITOR_LOCKED=unknown run_power_button
FAKE_HYPRCTL_RESULT=1 run_power_button
[[ ! -s $pkg_log ]] || fail "an RC71L power press requires a confirmed unlocked compositor"
pass "the RC71L power button leaves locked and unreadable compositor states alone"

: >"$pkg_log"
FAKE_COMPOSITOR_LOCKED=true run_menu_suspend
[[ $(<"$pkg_log") == $'lock\nsystemctl suspend' ]] || fail "the Suspend row still follows its lock-before-sleep policy"
pass "the RC71L Suspend row retains explicit lock-before-sleep behavior"

: >"$pkg_log"
FAKE_SLEEP_DISABLED=0 run_power_button
FAKE_SUSPEND_OFF=0 run_power_button
[[ $(<"$pkg_log") == $'menu toggle system\nmenu toggle system' ]] || fail "sleep-disabled settings prevent button suspend"
pass "RC71L honours disabled suspend settings"

: >"$pkg_log"
FAKE_SLEEP_DISABLED=0 run_menu_suspend
FAKE_SUSPEND_OFF=0 run_menu_suspend
[[ ! -s $pkg_log ]] || fail "a stale Suspend row cannot request sleep while disabled"
pass "the RC71L Suspend row rechecks availability before requesting sleep"

(
  flock 9
  run_power_button
  run_menu_suspend
) 9>"$test_tmp/runtime/omarchy-power-button.lock"
[[ ! -s $pkg_log ]] || fail "both entries observe the shared power-button lock"
pass "overlapping menu and power-button requests cannot race the desktop lock"

# A gaming daemon on the desktop would handle the same press a second time.
# Run the real launch guard with the real DMI predicate and a recording daemon.
cat >"$stub/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ $1 == "steamos-powerbuttond" && ${FAKE_POWERBUTTON_INSTALLED:-1} == "1" ]]
SH
cat >"$stub/steamos-powerbuttond" <<'SH'
#!/bin/bash
echo daemon >>"$PKG_LOG"
SH
chmod +x "$stub/omarchy-cmd-present" "$stub/steamos-powerbuttond"

run_gaming_button() {
  OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    XDG_RUNTIME_DIR="$test_tmp/runtime" XDG_CURRENT_DESKTOP="${TEST_DESKTOP:-gamescope}" \
    DISPLAY="${TEST_DISPLAY-:7}" HYPRLAND_INSTANCE_SIGNATURE="${TEST_HYPRLAND:-}" \
    PKG_LOG="$pkg_log" PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-launch-gaming-powerbutton"
}

: >"$pkg_log"
write_dmi "$vendor" "ROG Ally X RC72LA" "RC72LA"
if run_gaming_button; then fail "Ally X cannot start the RC71L handler"; fi
write_dmi "$vendor" "ROG Ally" "RC71L"
if TEST_DESKTOP=Hyprland run_gaming_button; then fail "desktop cannot start gaming handler"; fi
if TEST_HYPRLAND=active run_gaming_button; then fail "active Hyprland cannot start gaming handler"; fi
if TEST_DISPLAY= run_gaming_button; then fail "handler must wait for Gamescope DISPLAY"; fi
if FAKE_POWERBUTTON_INSTALLED=0 run_gaming_button; then fail "missing companion is explicit"; fi
[[ ! -s $pkg_log ]] || fail "refused launches never reach the daemon"
pass "gaming handler rejects unsupported hardware, desktop and missing prerequisites"

run_gaming_button
[[ $(<"$pkg_log") == "daemon" ]] || fail "Gamescope RC71L starts upstream daemon"
: >"$pkg_log"
(
  flock 9
  run_gaming_button
) 9>"$test_tmp/runtime/omarchy-power-button.lock"
[[ ! -s $pkg_log ]] || fail "a second button handler cannot start"
pass "gaming handler starts once and shares exclusion with desktop handler"

# A substring match for 0x74 would also tag an ordinary keyboard carrying
# only KEY_ZOOM (0x174). Query a real isolated hwdb, never the host database.
hwdb_root="$test_tmp/hwdb"
mkdir -p "$hwdb_root/usr/lib/udev/hwdb.d"
cp "$ROOT/default/rog-ally/powerbutton/70-omarchy-rog-ally-power-button.hwdb" "$hwdb_root/usr/lib/udev/hwdb.d/"
systemd-hwdb --root="$hwdb_root" --strict update
for keys in "74," "71,74,8F,"; do
  tagged=$(systemd-hwdb --root="$hwdb_root" query "id-input:modalias:input:b0019v0000p0001e0000-e0,1,k${keys}ramlsfw")
  [[ $tagged == "OMARCHY_POWER_BUTTON=1" ]] || fail "hwdb finds KEY_POWER in its capability list"
done
tagged=$(systemd-hwdb --root="$hwdb_root" query "id-input:modalias:input:b0019v0000p0001e0000-e0,1,k174,ramlsfw")
[[ -z $tagged ]] || fail "hwdb must not grant power-button access to KEY_ZOOM"
pass "hwdb matches KEY_POWER tokens without tagging unrelated keyboard capabilities"

# The keyboard setup must accept the same board-only identity as hardware setup.
# Stop at the missing reviewed package so this never installs or configures it.
cat >"$stub/pacman" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$stub/pacman"
write_dmi "$vendor" "ROG Ally" "RC71L"
if note=$(OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
  OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
  OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
  HOME="$home" PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-setup-rog-ally-keyboard" --configure-reviewed-package 2>&1); then
  fail "keyboard setup stops before configuring a missing reviewed package"
fi
[[ $note == *"Install the reviewed wvkbd"* ]] || fail "keyboard setup accepts the short Ally product with RC71L board" "$note"
pass "keyboard setup accepts the short Ally product with RC71L board"

reject_keyboard_setup() {
  local label=$1
  if note=$(OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    HOME="$home" PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-setup-rog-ally-keyboard" --configure-reviewed-package 2>&1); then
    fail "$label"
  fi
  [[ $note == *"This optional setup is for ASUS ROG Ally RC71L."* ]] || fail "$label" "$note"
}

write_dmi "$vendor" "ROG Strix G16" "GU605CX"
reject_keyboard_setup "keyboard setup rejects a non-Ally ROG laptop"
write_dmi "Dell Inc." "XPS 13" "0A1B"
reject_keyboard_setup "keyboard setup rejects a generic laptop"
write_dmi "$vendor" "ROG Ally X RC72LA_RC72LA" "RC72LA"
reject_keyboard_setup "keyboard setup rejects Ally X"
write_dmi "$vendor" "ROG Xbox Ally RC73YA" "RC73YA"
reject_keyboard_setup "keyboard setup rejects Xbox Ally"
write_dmi "$vendor" "ROG Xbox Ally X RC73XA" "RC73XA"
reject_keyboard_setup "keyboard setup rejects Xbox Ally X"
if note=$(OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/missing-vendor" \
  OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/missing-product" \
  OMARCHY_DMI_BOARD_NAME_PATH="$dmi/missing-board" \
  HOME="$home" PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-setup-rog-ally-keyboard" --configure-reviewed-package 2>&1); then
  fail "keyboard setup rejects missing DMI"
fi
[[ $note == *"This optional setup is for ASUS ROG Ally RC71L."* ]] || fail "keyboard setup rejects missing DMI" "$note"
pass "keyboard setup stays closed on a ROG laptop, a generic laptop, Ally X, Xbox Ally and missing DMI"

# A present reviewed package and a running shell still place the bar widget
# only after omarchy-hw-rog-ally accepts the machine.
cat >"$stub/pacman" <<'SH'
#!/bin/bash
[[ $1 == -Q && $2 == wvkbd ]] || exit 1
printf 'wvkbd 0.21-1\n'
SH
cat >"$stub/wvkbd-mobintl" <<'SH'
#!/bin/bash
printf '%s\n' '--non-exclusive --wayland-layer'
SH
cat >"$stub/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ $1 == wvkbd-mobintl ]]
SH
cat >"$stub/omarchy-shell" <<'SH'
#!/bin/bash
printf 'shell %s\n' "$*" >>"$PKG_LOG"
if [[ $1 == shell && $2 == ping ]]; then
  [[ ${OMARCHY_TEST_SHELL_UP:-0} == 1 ]]
  exit
fi
if [[ $1 == -q && $2 == shell && $3 == ping ]]; then
  [[ ${OMARCHY_TEST_SHELL_UP:-0} == 1 ]]
  exit
fi
exit 0
SH
cat >"$stub/omarchy-bar" <<'SH'
#!/bin/bash
printf 'bar %s\n' "$*" >>"$PKG_LOG"
[[ ${OMARCHY_TEST_BAR_FAIL:-0} == 1 ]] && exit 1
exit 0
SH
chmod +x "$stub/pacman" "$stub/wvkbd-mobintl" "$stub/omarchy-cmd-present" "$stub/omarchy-shell" "$stub/omarchy-bar"
mkdir -p "$home/.local/share/applications"
touch "$home/.local/share/applications/omarchy-desktop-keyboard.desktop"

run_keyboard_setup() {
  : >"$pkg_log"
  OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    HOME="$home" OMARCHY_PATH="$ROOT" PKG_LOG="$pkg_log" \
    OMARCHY_TEST_SHELL_UP="$1" OMARCHY_TEST_BAR_FAIL="${2:-0}" \
    WAYLAND_DISPLAY=wayland-test \
    PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-setup-rog-ally-keyboard" --configure-reviewed-package
}

write_dmi "$vendor" "ROG Ally" "RC71L"
if ! note=$(run_keyboard_setup 1 2>&1); then
  fail "keyboard setup places the bar widget on RC71L" "$note"
fi
[[ $note == *"Tap Keyboard in the bar"* ]] || fail "keyboard setup places the bar widget on RC71L" "$note"
[[ $(<"$pkg_log") == *"bar put omarchy.desktop-keyboard --section right"* ]] ||
  fail "keyboard setup places the bar widget on RC71L" "$(<"$pkg_log")"

reject_widget() {
  local label=$1
  if note=$(run_keyboard_setup 1 2>&1); then
    fail "$label"
  fi
  [[ $note == *"This optional setup is for ASUS ROG Ally RC71L."* && $(<"$pkg_log") != *'bar put'* ]] ||
    fail "$label" "$note $(<"$pkg_log")"
}

write_dmi "$vendor" "ROG Strix G16" "GU605CX"
reject_widget "keyboard setup does not place the widget on a ROG laptop"
write_dmi "Dell Inc." "XPS 13" "0A1B"
reject_widget "keyboard setup does not place the widget on a generic laptop"
write_dmi "$vendor" "ROG Ally X RC72LA_RC72LA" "RC72LA"
reject_widget "keyboard setup does not place the widget on Ally X"
write_dmi "$vendor" "ROG Xbox Ally RC73YA" "RC73YA"
reject_widget "keyboard setup does not place the widget on Xbox Ally"
write_dmi "$vendor" "ROG Xbox Ally X RC73XA" "RC73XA"
reject_widget "keyboard setup does not place the widget on Xbox Ally X"
: >"$pkg_log"
if note=$(OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/missing-vendor" \
  OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/missing-product" \
  OMARCHY_DMI_BOARD_NAME_PATH="$dmi/missing-board" \
  HOME="$home" OMARCHY_PATH="$ROOT" PKG_LOG="$pkg_log" \
  OMARCHY_TEST_SHELL_UP=1 WAYLAND_DISPLAY=wayland-test \
  PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-setup-rog-ally-keyboard" --configure-reviewed-package 2>&1); then
  fail "keyboard setup does not place the widget when DMI is missing"
fi
[[ $note == *"This optional setup is for ASUS ROG Ally RC71L."* && $(<"$pkg_log") != *'bar put'* ]] ||
  fail "keyboard setup does not place the widget when DMI is missing" "$note $(<"$pkg_log")"
pass "bar widget is placed only for RC71L"

write_dmi "$vendor" "ROG Ally" "RC71L"
if ! note=$(run_keyboard_setup 1 1 2>&1); then
  fail "a failed bar placement still finishes a successful keyboard install" "$note"
fi
[[ $note == *"rerun this setup in the desktop"* && $note != *"Tap Keyboard in the bar"* ]] ||
  fail "a failed bar placement still finishes a successful keyboard install" "$note"
pass "bar placement failure does not fail keyboard setup"

config="$home/.config/omarchy/shell.json"
mkdir -p "$(dirname "$config")" "$home/.local/share/applications"
cp "$ROOT/default/omarchy/applications/Desktop Keyboard.desktop" \
  "$home/.local/share/applications/omarchy-desktop-keyboard.desktop"
printf '%s\n' '{"version":1,"bar":{"layout":{"right":["omarchy.clock",{"id":"omarchy.desktop-keyboard"}]}},"plugins":[{"id":"omarchy.desktop-keyboard"}]}' >"$config"
cp "$config" "$test_tmp/shell-before.json"
if ! note=$(HOME="$home" OMARCHY_PATH="$ROOT" \
  PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-setup-rog-ally-keyboard" --remove 2>&1); then
  fail "keyboard setup removes the bar button" "$note"
fi
[[ ! -e $home/.local/share/applications/omarchy-desktop-keyboard.desktop ]] ||
  fail "keyboard setup removes the launcher it created"
[[ $note == *"next time the shell runs"* ]] ||
  fail "a stopped shell tells the user to drop the button later" "$note"
cmp -s "$config" "$test_tmp/shell-before.json" ||
  fail "a stopped shell rewrites shell.json" "$(<"$config")"
printf '%s\n' 'custom launcher' >"$home/.local/share/applications/omarchy-desktop-keyboard.desktop"
HOME="$home" OMARCHY_PATH="$ROOT" PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-setup-rog-ally-keyboard" --remove >/dev/null
[[ $(<"$home/.local/share/applications/omarchy-desktop-keyboard.desktop") == 'custom launcher' ]] ||
  fail "keyboard setup keeps a launcher it did not create"
pass "removing the keyboard leaves shell.json alone when the shell is down"

cp "$config" "$test_tmp/shell-before.json"
cat >"$stub/omarchy-plugin-disable" <<'SH'
#!/bin/bash
printf 'plugin-disable %s\n' "$*" >>"$PKG_LOG"
exit 0
SH
chmod +x "$stub/omarchy-plugin-disable"
: >"$pkg_log"
if ! note=$(HOME="$home" OMARCHY_PATH="$ROOT" PKG_LOG="$pkg_log" \
  OMARCHY_TEST_SHELL_UP=1 WAYLAND_DISPLAY=wayland-test \
  PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-setup-rog-ally-keyboard" --remove 2>&1); then
  fail "keyboard setup removes the button through the shell" "$note"
fi
[[ $note == *"Desktop Keyboard was removed from the bar."* ]] ||
  fail "keyboard setup removes the button through the shell" "$note"
[[ $(<"$pkg_log") == *"plugin-disable omarchy.desktop-keyboard"* ]] ||
  fail "keyboard setup does not call omarchy-plugin-disable" "$(<"$pkg_log")"
cmp -s "$config" "$test_tmp/shell-before.json" ||
  fail "a running shell still rewrites shell.json from setup" "$(<"$config")"
rm -f "$stub/omarchy-plugin-disable"
pass "a running shell drops the button through omarchy-plugin-disable"

write_dmi "Dell Inc." "XPS 13" "0A1B"
cp "$config" "$test_tmp/shell-before.json"
if note=$(run_keyboard_setup 0 2>&1); then
  fail "a non-RC71L setup with the shell down still configures the keyboard"
fi
[[ $note == *"This optional setup is for ASUS ROG Ally RC71L."* && $note == *"next time the shell runs"* ]] ||
  fail "a non-RC71L setup with the shell down names the later drop" "$note"
cmp -s "$config" "$test_tmp/shell-before.json" ||
  fail "a non-RC71L setup with the shell down rewrites shell.json" "$(<"$config")"
pass "a non-RC71L setup leaves shell.json alone when the shell is down"

rm -f "$home/.local/share/applications/omarchy-desktop-keyboard.desktop"
printf '%s\n' '{"version":1,"bar":{"layout":{"right":["omarchy.clock"]}}}' >"$config"
cp "$config" "$test_tmp/shell-before.json"
if ! note=$(HOME="$home" OMARCHY_PATH="$ROOT" \
  PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-setup-rog-ally-keyboard" --remove 2>&1); then
  fail "removing the keyboard with nothing installed exits 0" "$note"
fi
[[ $note != *"next time the shell runs"* && $note != *"Keyboard button"* ]] ||
  fail "a stopped shell stays quiet when the button was never added" "$note"
cmp -s "$config" "$test_tmp/shell-before.json" ||
  fail "a quiet removal rewrites shell.json" "$(<"$config")"
if note=$(run_keyboard_setup 0 2>&1); then
  fail "a non-RC71L setup with no button still configures the keyboard"
fi
[[ $note == *"This optional setup is for ASUS ROG Ally RC71L."* && $note != *"Keyboard button"* && $note != *"next time the shell runs"* ]] ||
  fail "a non-RC71L setup stays quiet when the button was never added" "$note"
cmp -s "$config" "$test_tmp/shell-before.json" ||
  fail "a quiet non-RC71L setup rewrites shell.json" "$(<"$config")"
pass "a stopped shell stays quiet when the Keyboard button was never added"

printf '%s\n' '{"version":1,"bar":{"layout":{"right":["omarchy.desktop-keyboard"]}}}' >"$config"
cp "$config" "$test_tmp/shell-before.json"
if ! note=$(HOME="$home" OMARCHY_PATH="$ROOT" \
  PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-setup-rog-ally-keyboard" --remove 2>&1); then
  fail "a layout button with the shell down exits 0" "$note"
fi
[[ $note == *"next time the shell runs"* ]] ||
  fail "a stopped shell names the button that is still in the layout" "$note"
cmp -s "$config" "$test_tmp/shell-before.json" ||
  fail "naming the layout button rewrites shell.json" "$(<"$config")"
printf '%s\n' '{"version":1}' >"$config"
cp "$ROOT/default/omarchy/applications/Desktop Keyboard.desktop" \
  "$home/.local/share/applications/omarchy-desktop-keyboard.desktop"
cp "$config" "$test_tmp/shell-before.json"
if ! note=$(HOME="$home" OMARCHY_PATH="$ROOT" \
  PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-setup-rog-ally-keyboard" --remove 2>&1); then
  fail "a setup launcher with the shell down exits 0" "$note"
fi
[[ $note == *"Removed the Desktop Keyboard launcher created by this setup."* && $note == *"next time the shell runs"* ]] ||
  fail "a stopped shell names the button when this setup's launcher was installed" "$note"
[[ ! -e $home/.local/share/applications/omarchy-desktop-keyboard.desktop ]] ||
  fail "a setup launcher is still removed when the layout has no button"
cmp -s "$config" "$test_tmp/shell-before.json" ||
  fail "removing the setup launcher rewrites shell.json" "$(<"$config")"
pass "a stopped shell names the button only when it is installed"

xdg_config="$test_tmp/xdg-config"
rm -f "$home/.local/share/applications/omarchy-desktop-keyboard.desktop"
printf '%s\n' '{"version":1}' >"$config"
mkdir -p "$xdg_config/omarchy"
xdg_shell="$xdg_config/omarchy/shell.json"
printf '%s\n' '{"version":1,"bar":{"layout":{"right":["omarchy.desktop-keyboard"]}}}' >"$xdg_shell"
cp "$xdg_shell" "$test_tmp/xdg-shell-before.json"
cp "$config" "$test_tmp/home-shell-before.json"
if ! note=$(HOME="$home" XDG_CONFIG_HOME="$xdg_config" OMARCHY_PATH="$ROOT" \
  PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-setup-rog-ally-keyboard" --remove 2>&1); then
  fail "a custom XDG_CONFIG_HOME with the shell down exits 0" "$note"
fi
[[ $note == *"next time the shell runs"* ]] ||
  fail "a stopped shell reads the Keyboard button from XDG_CONFIG_HOME" "$note"
cmp -s "$xdg_shell" "$test_tmp/xdg-shell-before.json" ||
  fail "a custom XDG_CONFIG_HOME shell.json is rewritten" "$(<"$xdg_shell")"
cmp -s "$config" "$test_tmp/home-shell-before.json" ||
  fail "the default config is rewritten when XDG_CONFIG_HOME is set" "$(<"$config")"
pass "a stopped shell reads shell.json from XDG_CONFIG_HOME"

# A laptop that has wvkbd, or the setup command, still gets neither keyboard row.
# Dropping the RC71L check from the install row makes this fail.
menu_log=$test_tmp/gaming-menu
cat >"$stub/omarchy-menu-select" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$MENU_LOG"
exit 1
SH
cat >"$stub/omarchy-cmd-present" <<'SH'
#!/bin/bash
case $1 in
  omarchy-toggle-desktop-keyboard) [[ ${HAS_TOGGLE:-0} == 1 ]] ;;
  wvkbd-mobintl) [[ ${HAS_WVKBD:-0} == 1 ]] ;;
  omarchy-setup-rog-ally-keyboard) [[ ${HAS_SETUP:-0} == 1 ]] ;;
  *) exit 1 ;;
esac
SH
chmod +x "$stub/omarchy-menu-select" "$stub/omarchy-cmd-present"
toggle_label=$(OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-i18n" gaming.desktopKeyboard)
install_label=$(OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-i18n" gaming.installKeyboard)

run_gaming_menu() {
  : >"$menu_log"
  HOME="$home" OMARCHY_PATH="$ROOT" MENU_LOG="$menu_log" \
    OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    HAS_TOGGLE="$1" HAS_WVKBD="$2" HAS_SETUP="$3" \
    PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-setup-gaming" >/dev/null
}

write_dmi "Dell Inc." "XPS 13" "0A1B"
run_gaming_menu 1 1 1
[[ $(<"$menu_log") != *"$toggle_label"* && $(<"$menu_log") != *"$install_label"* ]] ||
  fail "a laptop with wvkbd gets no desktop keyboard row" "$(<"$menu_log")"
write_dmi "$vendor" "ROG Ally" "RC71L"
run_gaming_menu 0 0 1
[[ $(<"$menu_log") == *"$install_label"* && $(<"$menu_log") != *"$toggle_label"* ]] ||
  fail "RC71L offers keyboard setup when wvkbd is absent" "$(<"$menu_log")"
run_gaming_menu 1 1 1
[[ $(<"$menu_log") == *"$toggle_label"* && $(<"$menu_log") != *"$install_label"* ]] ||
  fail "RC71L with wvkbd offers the keyboard toggle" "$(<"$menu_log")"
pass "gaming keyboard rows stay on RC71L"

# The companion is built from the in-tree recipe and installed with pacman -U.
# Stubs replace makepkg, pacman and udev so this never compiles or tags the host.
build_stub="$test_tmp/power-build"
mkdir -p "$build_stub"
cat >"$build_stub/makepkg" <<'SH'
#!/bin/bash
printf 'makepkg %s\n' "$*" >>"$PKG_LOG"
printf 'git-speed %s %s\n' "${GIT_HTTP_LOW_SPEED_LIMIT:-missing}" "${GIT_HTTP_LOW_SPEED_TIME:-missing}" >>"$PKG_LOG"
pwd >"$PKG_LOG.workdir"
cmp -s PKGBUILD "$OMARCHY_PATH/default/rog-ally/powerbutton/PKGBUILD" || exit 1
cmp -s 70-omarchy-rog-ally-power-button.hwdb "$OMARCHY_PATH/default/rog-ally/powerbutton/70-omarchy-rog-ally-power-button.hwdb" || exit 1
cmp -s 70-omarchy-rog-ally-power-button.rules "$OMARCHY_PATH/default/rog-ally/powerbutton/70-omarchy-rog-ally-power-button.rules" || exit 1
: >omarchy-rog-ally-powerbutton-4.2-1-x86_64.pkg.tar.zst
SH
cat >"$build_stub/pacman" <<'SH'
#!/bin/bash
if [[ $1 == -Q ]]; then
  name=${!#}
  [[ $name == omarchy-gaming-session && ${FAKE_GAMING_SESSION:-0} == 1 ]] && exit 0
  [[ $name == omarchy-rog-ally-powerbutton && ${FAKE_POWER_PKG:-0} == 1 ]] && exit 0
  [[ -n ${FAKE_CONFLICT:-} && $name == "$FAKE_CONFLICT" ]] && exit 0
  exit 1
fi
printf 'pacman %s\n' "$*" >>"$PKG_LOG"
SH
cat >"$build_stub/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$PKG_LOG"
"$@"
SH
cat >"$build_stub/systemd-hwdb" <<'SH'
#!/bin/bash
printf 'systemd-hwdb %s\n' "$*" >>"$PKG_LOG"
SH
cat >"$build_stub/udevadm" <<'SH'
#!/bin/bash
printf 'udevadm %s\n' "$*" >>"$PKG_LOG"
SH
cat >"$build_stub/yay" <<'SH'
#!/bin/bash
printf 'yay %s\n' "$*" >>"$PKG_LOG"
exit 99
SH
cat >"$build_stub/timeout" <<'SH'
#!/bin/bash
printf 'timeout %s\n' "$1" >>"$PKG_LOG"
[[ $1 =~ ^[0-9]+$ ]] || exit 1
(( $1 > 0 && $1 <= 120 )) || exit 1
shift
exec "$@"
SH
chmod +x "$build_stub"/*

power_migration=$ROOT/migrations/1795075200.sh
[[ -x $ROOT/bin/omarchy-install-rog-ally-powerbutton ]] || fail "the power-button installer is executable"
[[ $(stat -c %a -- "$power_migration") == 644 ]] || fail "the power-button migration is mode 0644"
[[ $(head -1 "$power_migration") != '#!'* ]] || fail "the power-button migration has no shebang"
grep -q 'pkexec\|NOPASSWD' "$power_migration" && fail "the power-button migration uses pkexec or NOPASSWD"
grep -q 'pkexec\|NOPASSWD' "$ROOT/bin/omarchy-install-rog-ally-powerbutton" && fail "the power-button installer uses pkexec or NOPASSWD"
pass "the power-button migration is a non-executable repair without a sudoers grant"

run_power_install() {
  OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    OMARCHY_PATH="$ROOT" PKG_LOG="$pkg_log" \
    FAKE_POWER_PKG="${FAKE_POWER_PKG:-0}" FAKE_CONFLICT="${FAKE_CONFLICT:-}" \
    FAKE_GAMING_SESSION="${FAKE_GAMING_SESSION:-0}" \
    PATH="$build_stub:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-install-rog-ally-powerbutton"
}

udev_refreshed() {
  [[ $(<"$pkg_log") == *"sudo systemd-hwdb update"* ]] || return 1
  [[ $(<"$pkg_log") == *"sudo udevadm control --reload"* ]] || return 1
  [[ $(<"$pkg_log") == *"sudo udevadm trigger --subsystem-match=input"* ]] || return 1
}

write_dmi "Dell Inc." "XPS 13" "0A1B"
: >"$pkg_log"
run_power_install
[[ ! -s $pkg_log ]] || fail "a laptop does not build the RC71L power-button companion" "$(<"$pkg_log")"
write_dmi "$vendor" "ROG Ally X RC72LA" "RC72LA"
run_power_install
[[ ! -s $pkg_log ]] || fail "Ally X does not build the RC71L power-button companion" "$(<"$pkg_log")"
pass "the power-button installer stays closed off the original Ally"

write_dmi "$vendor" "ROG Ally" "RC71L"
: >"$pkg_log"
FAKE_GAMING_SESSION=0 run_power_install
[[ ! -s $pkg_log ]] || fail "the installer does nothing without the gaming session" "$(<"$pkg_log")"
pass "the power-button installer does nothing without the gaming session"

write_dmi "$vendor" "ROG Ally" "RC71L"
: >"$pkg_log"
power_unset=$(env -u OMARCHY_PATH \
  OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
  OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
  OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
  PKG_LOG="$pkg_log" \
  FAKE_GAMING_SESSION=1 \
  PATH="$build_stub:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-install-rog-ally-powerbutton" 2>&1) || true
[[ $power_unset != *unbound* ]] ||
  fail "the power-button installer aborts when OMARCHY_PATH is unset" "$power_unset"
pass "the power-button installer defaults an unset OMARCHY_PATH"

for conflict in steamos-powerbuttond steam-powerbuttond steam-powerbuttond-git; do
  : >"$pkg_log"
  if note=$(FAKE_GAMING_SESSION=1 FAKE_CONFLICT="$conflict" run_power_install 2>&1); then
    fail "an installed $conflict is refused"
  fi
  [[ $note == *"$conflict"* ]] || fail "the refusal names $conflict" "$note"
  [[ $(<"$pkg_log") != *makepkg* && $(<"$pkg_log") != *"pacman -U"* && $(<"$pkg_log") != *yay* ]] ||
    fail "a conflicting handler is not replaced" "$(<"$pkg_log")"
done
pass "an already installed Steam power daemon is left in place"

: >"$pkg_log"
FAKE_GAMING_SESSION=1 FAKE_POWER_PKG=1 run_power_install
udev_refreshed || fail "an installed companion still reloads the input tags" "$(<"$pkg_log")"
[[ $(<"$pkg_log") != *makepkg* && $(<"$pkg_log") != *"pacman -U"* ]] ||
  fail "an installed companion is not built again" "$(<"$pkg_log")"
pass "an installed companion only reloads udev"

: >"$pkg_log"
rm -f "$pkg_log.workdir"
FAKE_GAMING_SESSION=1 FAKE_POWER_PKG=0 FAKE_CONFLICT='' run_power_install
[[ $(<"$pkg_log") == *'timeout 90'* ]] || fail "the build is capped before the display manager" "$(<"$pkg_log")"
[[ $(<"$pkg_log") == *'git-speed 1000 30'* ]] || fail "a stalled clone aborts" "$(<"$pkg_log")"
[[ $(<"$pkg_log") == *makepkg* ]] || fail "a missing companion is built" "$(<"$pkg_log")"
[[ $(<"$pkg_log") == *"pacman -U --noconfirm --"* && $(<"$pkg_log") == *"omarchy-rog-ally-powerbutton-"*".pkg.tar.zst"* ]] ||
  fail "the built package is installed with pacman -U" "$(<"$pkg_log")"
udev_refreshed || fail "a new companion reloads the input tags" "$(<"$pkg_log")"
[[ $(<"$pkg_log") != *yay* && $(<"$pkg_log") != *steamos-powerbuttond* ]] ||
  fail "the installer does not take the AUR or CachyOS package" "$(<"$pkg_log")"
[[ -f $pkg_log.workdir && ! -d $(<"$pkg_log.workdir") ]] || fail "the build directory is removed"
[[ -z $(find "$ROOT/default/rog-ally/powerbutton" -name '*.pkg.tar.*' -print -quit) ]] ||
  fail "the recipe directory is not the build directory"
pass "the missing companion is built from the in-tree recipe and installed locally"

run_power_migration() {
  OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    OMARCHY_PATH="$ROOT" HOME="$power_home" \
    PKG_LOG="$pkg_log" FAKE_POWER_INSTALL="${FAKE_POWER_INSTALL:-0}" \
    FAKE_GAMING_SESSION="${FAKE_GAMING_SESSION:-0}" \
    FAKE_POWER_PKG="${FAKE_POWER_PKG:-0}" FAKE_CONFLICT="${FAKE_CONFLICT:-}" \
    PATH="$1:$ROOT/bin:$PATH" \
    bash -euo pipefail "$power_migration"
}

power_home="$test_tmp/power-home"
mkdir -p "$power_home"
power_marker="$power_home/.local/state/omarchy/migrations/1795075200.sh"

grep -q '1794843321' "$power_migration" || fail "1795075200 does not name the catch-up"
grep -q 'omarchy-setup-gaming-session' "$power_migration" || fail "1795075200 does not name the retry"
grep -q 'omarchy-install-rog-ally-powerbutton' "$power_migration" && fail "1795075200 calls the installer"
: >"$pkg_log"
write_dmi "$vendor" "ROG Ally RC71L_RC71L" "RC71L"
FAKE_GAMING_SESSION=1 FAKE_POWER_INSTALL=0 run_power_migration "$power_stub" >/dev/null
[[ ! -s $pkg_log ]] || fail "1795075200 installs the companion on an RC71L" "$(<"$pkg_log")"
: >"$pkg_log"
write_dmi "Dell Inc." "XPS 13" "0A1B"
FAKE_GAMING_SESSION=1 FAKE_POWER_INSTALL=1 run_power_migration "$power_stub" >/dev/null
[[ ! -s $pkg_log ]] || fail "1795075200 installs the companion off the Ally" "$(<"$pkg_log")"
[[ ! -e $power_marker ]] || fail "1795075200 writes its own marker"
pass "1795075200 is a no-op and names 1794843321"

greeter_migration=$ROOT/migrations/1794830400.sh
[[ $(basename "$greeter_migration") == 1794830400.sh ]] || fail "the greeter migration stamp changed"
[[ $(stat -c %a -- "$greeter_migration") == 644 ]] || fail "the greeter migration is mode 0644"
run_greeter_migration() {
  OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    PKG_LOG="$pkg_log" \
    PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
    bash -euo pipefail "$greeter_migration" >/dev/null
}
: >"$pkg_log"
write_dmi "Dell Inc." "XPS 13" "0A1B"
run_greeter_migration
[[ ! -s $pkg_log ]] || fail "qt6-virtualkeyboard is installed off the Ally" "$(<"$pkg_log")"
: >"$pkg_log"
write_dmi "$vendor" "ROG Ally" "RC71L"
run_greeter_migration
[[ $(<"$pkg_log") == qt6-virtualkeyboard ]] || fail "the Ally catch-up does not install qt6-virtualkeyboard" "$(<"$pkg_log")"
pass "the greeter keyboard package is installed only on the Ally"

# Status and invalid options must not install anything or create session state.
# An explicit retry works even when the fresh-install marker already exists.
setup_home="$test_tmp/setup-home"
mkdir -p "$setup_home"
run_power_setup() {
  local power_install=$1 gaming_session=$2
  shift 2
  OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    OMARCHY_PATH="$ROOT" HOME="$setup_home" XDG_STATE_HOME="$setup_home/.local/state" \
    PKG_LOG="$pkg_log" FAKE_POWER_INSTALL="$power_install" FAKE_GAMING_SESSION="$gaming_session" \
    PATH="$power_stub:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-setup-gaming-session" "$@"
}
: >"$pkg_log"
write_dmi "$vendor" "ROG Ally" "RC71L"
run_power_setup 0 1 >/dev/null
run_power_setup 0 1 status >/dev/null
if run_power_setup 0 1 default unknown >/dev/null 2>&1; then
  fail "gaming setup rejects an invalid session preference"
fi
[[ ! -s $pkg_log ]] || fail "status and invalid preferences do not install the power button" "$(<"$pkg_log")"
[[ ! -e $setup_home/.local/state/omarchy/gaming-session ]] ||
  fail "status and invalid preferences do not create session state"
pass "status and invalid preferences leave power-button packages and session state alone"

if run_power_setup 0 0 install-power-button >/dev/null 2>&1; then
  fail "an explicit install without the gaming session reports failure"
fi
[[ ! -s $pkg_log ]] || fail "setup does not install the power button without the gaming session" "$(<"$pkg_log")"
pass "the explicit power-button install requires the gaming session"

: >"$pkg_log"
mkdir -p "$setup_home/.local/state/omarchy/migrations"
marked="$setup_home/.local/state/omarchy/migrations/1795075200.sh"
touch "$marked"
marked_stamp=$(stat -c %Y -- "$marked")
if setup_err=$(run_power_setup 1 1 install-power-button 2>&1 >/dev/null); then
  fail "a failed power-button build reports success" "$setup_err"
fi
if setup_err2=$(run_power_setup 1 1 install-power-button 2>&1 >/dev/null); then
  fail "a second failed power-button build reports success" "$setup_err2"
fi
[[ $setup_err == *"omarchy-setup-gaming-session install-power-button"* &&
  $setup_err2 == *"omarchy-setup-gaming-session install-power-button"* ]] ||
  fail "a failed build does not warn" "$setup_err"
[[ $(grep -c install-powerbutton "$pkg_log") == 2 ]] ||
  fail "a pre-marked migration or a failed build skips the next setup" "$(<"$pkg_log")"
[[ $(stat -c %Y -- "$marked") == "$marked_stamp" ]] || fail "setup rewrites the migration marker"
[[ ! -e $setup_home/.local/state/omarchy/rog-ally-powerbutton ]] ||
  fail "a failed build records a power-button success"
pass "a failed build is not marked done and setup retries it"

# udev applies every ATTRS match to one parent. This walks a udevadm info -a
# chain and accepts a rule only when one parent satisfies all of its ATTRS keys.
attrs_block_matches() {
  local i val alt pat
  local -a alts=()
  for i in "${!keys[@]}"; do
    [[ $1 =~ ATTRS\{${keys[$i]}\}==\"([^\"]*)\" ]] || return 1
    val=${BASH_REMATCH[1]}
    IFS='|' read -ra alts <<< "${pats[$i]}"
    alt=0
    for pat in "${alts[@]}"; do
      # udev match text is a glob. "*PNP0C0C*" must stay unquoted.
      # shellcheck disable=SC2053
      if [[ $val == $pat ]]; then
        alt=1
        break
      fi
    done
    (( alt == 1 )) || return 1
  done
  return 0
}

attrs_same_parent() {
  local fixture=$2 rest=$1
  local -a keys=() pats=()
  while [[ $rest =~ ATTRS\{([A-Za-z0-9_]+)\}==\"([^\"]*)\" ]]; do
    keys+=("${BASH_REMATCH[1]}")
    pats+=("${BASH_REMATCH[2]}")
    rest=${rest#*"ATTRS{${BASH_REMATCH[1]}}==\"${BASH_REMATCH[2]}\""}
  done
  (( ${#keys[@]} > 0 )) || return 1
  local block='' line
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == 'looking at '* && -n $block ]]; then
      attrs_block_matches "$block" && return 0
      block=''
    fi
    block+=$line$'\n'
  done <<< "$fixture"
  [[ -n $block ]] && attrs_block_matches "$block"
}

# Parent chains in `udevadm info -a` shape. name and phys are on the input
# device. The ACPI modalias is on the grandparent, so a rule that requires
# both can never match.
pnp_chain='looking at device /devices/LNXSYSTM:00/PNP0C0C:00/input/input3/event3:
    KERNEL=="event3"
    SUBSYSTEM=="input"
looking at parent device /devices/LNXSYSTM:00/PNP0C0C:00/input/input3:
    KERNELS=="input3"
    SUBSYSTEMS=="input"
    ATTRS{name}=="Power Button"
    ATTRS{phys}=="PNP0C0C/button/input0"
    ATTRS{modalias}=="input:b0019v0000p0001e0000-e0,1,k74,ramlsfw"
looking at parent device /devices/LNXSYSTM:00/PNP0C0C:00:
    KERNELS=="PNP0C0C:00"
    SUBSYSTEMS=="acpi"
    DRIVERS=="button"
    ATTRS{hid}=="PNP0C0C"
    ATTRS{modalias}=="acpi:PNP0C0C:"
'
lnx_chain='looking at device /devices/LNXSYSTM:00/LNXPWRBN:00/input/input4/event4:
    KERNEL=="event4"
    SUBSYSTEM=="input"
looking at parent device /devices/LNXSYSTM:00/LNXPWRBN:00/input/input4:
    KERNELS=="input4"
    SUBSYSTEMS=="input"
    ATTRS{name}=="Power Button"
    ATTRS{phys}=="LNXPWRBN/button/input0"
    ATTRS{modalias}=="input:b0019v0000p0001e0000-e0,1,k74,ramlsfw"
looking at parent device /devices/LNXSYSTM:00/LNXPWRBN:00:
    KERNELS=="LNXPWRBN:00"
    SUBSYSTEMS=="acpi"
    DRIVERS=="button"
    ATTRS{hid}=="LNXPWRBN"
    ATTRS{modalias}=="acpi:LNXPWRBN:"
'
keyboard_chain='looking at device /devices/platform/i8042/serio0/input/input0/event0:
    KERNEL=="event0"
    SUBSYSTEM=="input"
looking at parent device /devices/platform/i8042/serio0/input/input0:
    KERNELS=="input0"
    SUBSYSTEMS=="input"
    ATTRS{name}=="AT Translated Set 2 keyboard"
    ATTRS{phys}=="isa0060/serio0/input0"
    ATTRS{modalias}=="input:b0011v0001p0001eab83-e0,1,4,11,14,k71,72,73,74,75,ramlsfw"
looking at parent device /devices/platform/i8042/serio0:
    KERNELS=="serio0"
    SUBSYSTEMS=="serio"
    DRIVERS=="atkbd"
'
sleep_chain='looking at parent device /devices/LNXSYSTM:00/PNP0C0E:00/input/input5:
    ATTRS{name}=="Sleep Button"
    ATTRS{phys}=="PNP0C0E/button/input0"
    ATTRS{modalias}=="input:b0019v0000p0003e0000-e0,1,k8e,ramlsfw"
looking at parent device /devices/LNXSYSTM:00/PNP0C0E:00:
    ATTRS{hid}=="PNP0C0E"
    ATTRS{modalias}=="acpi:PNP0C0E:"
'
mixed_parent='ATTRS{name}=="Power Button", ATTRS{modalias}=="*PNP0C0C*"'
if attrs_same_parent "$mixed_parent" "$pnp_chain"; then
  fail "a rule that mixes the input name with the ACPI modalias was accepted"
fi
if attrs_same_parent 'ATTRS{name}=="Power Button", ATTRS{modalias}=="*LNXPWRBN*"' "$lnx_chain"; then
  fail "a rule that mixes the input name with the ACPI modalias was accepted"
fi

rules=$ROOT/default/rog-ally/powerbutton/70-omarchy-rog-ally-power-button.rules
uaccess_count=0
pnp_rule=''
lnx_rule=''
while IFS= read -r line; do
  [[ $line == *'TAG+="uaccess"'* ]] || continue
  uaccess_count=$((uaccess_count + 1))
  [[ $line == *'ATTRS{name}=="Power Button"'* && $line == *'ATTRS{phys}=='* ]] ||
    fail "uaccess is not limited to the input device name and phys" "$line"
  if [[ $line == *'PNP0C0C/button/input0'* ]]; then
    pnp_rule=$line
  elif [[ $line == *'LNXPWRBN/button/input0'* ]]; then
    lnx_rule=$line
  else
    fail "uaccess phys is not the ACPI power-button input" "$line"
  fi
done <"$rules"
(( uaccess_count == 2 )) || fail "the power-button rule no longer grants uaccess" "$uaccess_count"
attrs_same_parent "$pnp_rule" "$pnp_chain" || fail "the PNP0C0C power button is not granted uaccess"
attrs_same_parent "$lnx_rule" "$lnx_chain" || fail "the LNXPWRBN power button is not granted uaccess"
if attrs_same_parent "$pnp_rule" "$lnx_chain" || attrs_same_parent "$lnx_rule" "$pnp_chain"; then
  fail "a power-button rule matches the other ACPI id"
fi
for line in "$pnp_rule" "$lnx_rule"; do
  if attrs_same_parent "$line" "$keyboard_chain"; then
    fail "a KEY_POWER keyboard is granted uaccess" "$line"
  fi
  if attrs_same_parent "$line" "$sleep_chain"; then
    fail "the sleep button is granted uaccess" "$line"
  fi
done
pass "the power-button uaccess rule matches one parent of the ACPI power button"

# A packaged /usr/share/omarchy is only what omarchy-pkgs package() copies
# there. Pinned from omacom/omarchy-pkgs master on 16 Nov 2026, not from
# docs/file-layout.md.
#
# pkgbuilds/omarchy-dev/PKGBUILD (_commit 7c8e05925391188d6e95e581dc51c12fb2facd48)
# and pkgbuilds/omarchy/PKGBUILD (_commit a948d8a6871f446b335258c827648ac5f4e9428b)
# copy install, themes, icons when that directory exists, migrations, shell
# and version. They do not copy default/, config/, share/ or packaging/.
#
# pkgbuilds/omarchy-settings-dev/PKGBUILD (same 7c8e059 pin) and
# pkgbuilds/omarchy-settings/PKGBUILD (same a948d8a pin) copy config/. to
# /usr/share/omarchy/config/, applications/. to /usr/share/omarchy/applications/
# (then remove applications/icons), default/. to /usr/share/omarchy/default/,
# and logo.txt, logo.svg, icon.txt and icon.png into /usr/share/omarchy/.
copy_packaged_omarchy() {
  local dest=$1
  local name brand
  local -a omarchy_dirs=(install themes migrations shell)

  mkdir -p "$dest"
  if [[ -d $ROOT/icons ]]; then
    omarchy_dirs+=(icons)
  fi
  for name in "${omarchy_dirs[@]}"; do
    [[ -d $ROOT/$name ]] || fail "omarchy package() names a missing tree" "$name"
    cp -a "$ROOT/$name" "$dest/$name"
  done
  [[ -f $ROOT/version ]] || fail "omarchy package() names a missing version file"
  cp -a "$ROOT/version" "$dest/version"

  for name in config applications default; do
    [[ -d $ROOT/$name ]] || fail "omarchy-settings package() names a missing tree" "$name"
    mkdir -p "$dest/$name"
    cp -a "$ROOT/$name/." "$dest/$name/"
  done
  rm -rf "$dest/applications/icons"
  for brand in logo.txt logo.svg icon.txt icon.png; do
    [[ -f $ROOT/$brand ]] || fail "omarchy-settings package() names a missing brand file" "$brand"
    cp -a "$ROOT/$brand" "$dest/$brand"
  done
}

packaged=$test_tmp/packaged-omarchy
copy_packaged_omarchy "$packaged"
[[ -f $packaged/default/rog-ally/powerbutton/PKGBUILD ]] || fail "the packaged tree omits the recipe settings copies with default/"
[[ ! -e $packaged/packaging ]] || fail "the packaged tree contains packaging/"
[[ ! -e $packaged/share ]] || fail "the packaged tree contains share/"

packaged_stub=$test_tmp/packaged-stub
mkdir -p "$packaged_stub"
cat >"$packaged_stub/makepkg" <<'SH'
#!/bin/bash
printf 'makepkg %s\n' "$*" >>"$PKG_LOG"
recipe=$OMARCHY_PATH/default/rog-ally/powerbutton
[[ -f PKGBUILD ]] || exit 1
cmp -s PKGBUILD "$recipe/PKGBUILD" || exit 1
cmp -s 70-omarchy-rog-ally-power-button.hwdb "$recipe/70-omarchy-rog-ally-power-button.hwdb" || exit 1
cmp -s 70-omarchy-rog-ally-power-button.rules "$recipe/70-omarchy-rog-ally-power-button.rules" || exit 1
: >omarchy-rog-ally-powerbutton-4.2-1-x86_64.pkg.tar.zst
SH
cat >"$packaged_stub/pacman" <<'SH'
#!/bin/bash
if [[ $1 == -Q ]]; then
  [[ ${!#} == omarchy-gaming-session ]]
  exit $?
fi
printf 'pacman %s\n' "$*" >>"$PKG_LOG"
SH
cat >"$packaged_stub/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$PKG_LOG"
"$@"
SH
cat >"$packaged_stub/systemd-hwdb" <<'SH'
#!/bin/bash
printf 'systemd-hwdb %s\n' "$*" >>"$PKG_LOG"
SH
cat >"$packaged_stub/udevadm" <<'SH'
#!/bin/bash
printf 'udevadm %s\n' "$*" >>"$PKG_LOG"
SH
cat >"$packaged_stub/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ $1 == omarchy-gaming-session ]]
SH
chmod +x "$packaged_stub"/*

write_dmi "$vendor" "ROG Ally" "RC71L"
: >"$pkg_log"
set +e
packaged_note=$(
  OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    OMARCHY_PATH="$packaged" PKG_LOG="$pkg_log" \
    PATH="$packaged_stub:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-install-rog-ally-powerbutton" 2>&1
)
packaged_status=$?
set -e
[[ $packaged_status -eq 0 ]] || fail "a packaged tree does not install the companion" "$packaged_note"
[[ $packaged_note != *'Missing the RC71L power-button recipe'* ]] ||
  fail "a packaged tree is missing the recipe" "$packaged_note"
[[ $(<"$pkg_log") == *makepkg* && $(<"$pkg_log") == *"pacman -U --noconfirm --"* ]] ||
  fail "a packaged tree does not build and install the recipe" "$(<"$pkg_log")"
[[ ! -e $packaged/packaging ]] || fail "the packaged tree grew a packaging directory"
pass "a packaged tree ships the power-button recipe"

# 1795075200 is a no-op. 1794843321 is the catch-up for an existing user.
# A fresh install pre-marks that later migration too.
rerun=
for candidate in "$ROOT"/migrations/*.sh; do
  [[ $(basename "$candidate") == 1795075200.sh ]] && continue
  if grep -q 'omarchy-rog-ally-powerbutton' "$candidate"; then
    rerun=$candidate
  fi
done
[[ -n $rerun && -f $rerun ]] || fail "the power-button rerun migration is present"
[[ $(stat -c %a -- "$rerun") == 644 ]] || fail "the rerun migration is mode 0644"
[[ $(head -1 "$rerun") != '#!'* ]] || fail "the rerun migration has no shebang"
grep -q 'pkexec\|NOPASSWD' "$rerun" && fail "the rerun migration uses pkexec or NOPASSWD"

rerun_stub=$test_tmp/rerun-stub
mkdir -p "$rerun_stub"
cat >"$rerun_stub/omarchy-install-rog-ally-powerbutton" <<'SH'
#!/bin/bash
printf '%s\n' install-powerbutton >>"$PKG_LOG"
exit "${FAKE_POWER_INSTALL:-0}"
SH
cat >"$rerun_stub/omarchy-pkg-present" <<'SH'
#!/bin/bash
case $1 in
  omarchy-gaming-session) [[ ${FAKE_GAMING_SESSION:-0} == 1 ]] ;;
  omarchy-rog-ally-powerbutton) [[ ${FAKE_POWER_PKG:-0} == 1 ]] ;;
  *) exit 1 ;;
esac
SH
chmod +x "$rerun_stub"/*

run_rerun() {
  OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    OMARCHY_PATH="$ROOT" PKG_LOG="$pkg_log" \
    FAKE_POWER_INSTALL="${FAKE_POWER_INSTALL:-0}" \
    FAKE_GAMING_SESSION="${FAKE_GAMING_SESSION:-0}" \
    FAKE_POWER_PKG="${FAKE_POWER_PKG:-0}" \
    PATH="$rerun_stub:$ROOT/bin:$PATH" \
    bash -euo pipefail "$rerun" >/dev/null
}

: >"$pkg_log"
write_dmi "Dell Inc." "XPS 13" "0A1B"
run_rerun
[[ ! -s $pkg_log ]] || fail "the rerun migration does nothing off the original Ally" "$(<"$pkg_log")"
write_dmi "$vendor" "ROG Ally" "RC71L"
FAKE_GAMING_SESSION=0 run_rerun
[[ ! -s $pkg_log ]] || fail "the rerun migration does nothing without the gaming session" "$(<"$pkg_log")"
FAKE_GAMING_SESSION=1 FAKE_POWER_PKG=1 run_rerun
[[ ! -s $pkg_log ]] || fail "the rerun migration skips an installed companion" "$(<"$pkg_log")"
pass "the rerun migration stays closed without an RC71L gaming session that lacks the companion"

: >"$pkg_log"
FAKE_GAMING_SESSION=1 FAKE_POWER_PKG=0 FAKE_POWER_INSTALL=0 run_rerun
[[ $(<"$pkg_log") == install-powerbutton ]] || fail "the rerun migration installs a missing companion" "$(<"$pkg_log")"
: >"$pkg_log"
if rerun_note=$(FAKE_GAMING_SESSION=1 FAKE_POWER_PKG=0 FAKE_POWER_INSTALL=1 run_rerun 2>&1 >/dev/null); then
  :
else
  fail "a failed rerun halts the migration"
fi
[[ $rerun_note == *omarchy-setup-gaming-session* ]] || fail "a failed rerun names the online retry" "$rerun_note"
[[ $(<"$pkg_log") == install-powerbutton ]] || fail "a failed rerun did not call the installer" "$(<"$pkg_log")"
pass "the rerun migration installs a missing companion and soft-fails a failed build"
