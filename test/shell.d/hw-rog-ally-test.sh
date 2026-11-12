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

note=$(
  write_dmi "$vendor" "ROG Ally RC71L_RC71L" "RC71L"
  OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    PATH="$ROOT/bin:$PATH" \
    bash -eE -c 'source "$1"' bash "$ROOT/install/hardware/asus/rog-ally.sh" </dev/null
)
[[ $note == *"RC71L"* && $note == *"asusctl"* ]] || fail "the Ally hardware leaf names the machine and the skipped package" "$note"
pass "the Ally hardware leaf names the machine and the skipped package"

note=$(
  write_dmi "$vendor" "ROG Ally X RC72LA_RC72LA" "RC72LA"
  OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    PATH="$ROOT/bin:$PATH" \
    bash -eE -c 'source "$1"' bash "$ROOT/install/hardware/asus/rog-ally.sh" </dev/null
)
[[ -z $note ]] || fail "the Ally hardware leaf is silent on an Ally X" "$note"
pass "the Ally hardware leaf is silent on an Ally X"

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

# Power-button routing must never suspend a desktop whose lock failed, or
# replace the ordinary laptop/desktop power menu. The existing sleep-lock
# suite exercises secure-lock IPC; this exercises the caller's decision.
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
  "$stub/systemctl" "$stub/omarchy-sleep-disabled" "$stub/omarchy-toggle-enabled"

run_power_button() {
  OMARCHY_DMI_SYS_VENDOR_PATH="$dmi/sys_vendor" \
    OMARCHY_DMI_PRODUCT_NAME_PATH="$dmi/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$dmi/board_name" \
    XDG_RUNTIME_DIR="$test_tmp/runtime" OMARCHY_PATH="$power_omarchy" \
    PKG_LOG="$pkg_log" PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-system-power-button"
}

for product in "ROG Strix G16" "ROG Ally X RC72LA"; do
  write_dmi "$vendor" "$product" ""
  : >"$pkg_log"
  run_power_button
  [[ $(<"$pkg_log") == "menu toggle system" ]] || fail "power button preserves $product power menu"
done
pass "non-RC71L power buttons retain the existing system menu"

write_dmi "$vendor" "ROG Ally" "RC71L"
: >"$pkg_log"
run_power_button
[[ $(<"$pkg_log") == $'lock\nsystemctl suspend' ]] || fail "RC71L locks before requesting suspend"
pass "RC71L power button locks before requesting suspend"

: >"$pkg_log"
if FAKE_LOCK_RESULT=1 run_power_button; then
  fail "a failed lock cancels the power-button suspend"
fi
[[ $(<"$pkg_log") == "lock" ]] || fail "a failed lock never reaches systemctl"
pass "failed desktop lock cancels suspend"

: >"$pkg_log"
FAKE_SLEEP_DISABLED=0 run_power_button
FAKE_SUSPEND_OFF=0 run_power_button
[[ $(<"$pkg_log") == $'menu toggle system\nmenu toggle system' ]] || fail "sleep-disabled settings prevent button suspend"
pass "RC71L honours disabled suspend settings"

: >"$pkg_log"
(
  flock 9
  run_power_button
) 9>"$test_tmp/runtime/omarchy-power-button.lock"
[[ ! -s $pkg_log ]] || fail "overlapping power-button events are ignored"
pass "overlapping power-button events cannot race the desktop lock"

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
cp "$ROOT/packaging/rog-ally-powerbutton/70-omarchy-rog-ally-power-button.hwdb" "$hwdb_root/usr/lib/udev/hwdb.d/"
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
if ! note=$(HOME="$home" OMARCHY_PATH="$ROOT" \
  PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-setup-rog-ally-keyboard" --remove 2>&1); then
  fail "keyboard setup removes the bar button" "$note"
fi
[[ ! -e $home/.local/share/applications/omarchy-desktop-keyboard.desktop ]] ||
  fail "keyboard setup removes the launcher it created"
[[ $(<"$config") != *omarchy.desktop-keyboard* && $(<"$config") == *omarchy.clock* ]] ||
  fail "keyboard setup removes only the keyboard widget" "$(<"$config")"
printf '%s\n' 'custom launcher' >"$home/.local/share/applications/omarchy-desktop-keyboard.desktop"
HOME="$home" OMARCHY_PATH="$ROOT" PATH="$real_predicate:$stub:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-setup-rog-ally-keyboard" --remove >/dev/null
[[ $(<"$home/.local/share/applications/omarchy-desktop-keyboard.desktop") == 'custom launcher' ]] ||
  fail "keyboard setup keeps a launcher it did not create"
pass "removing the keyboard drops the button and only the launcher this setup created"

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
