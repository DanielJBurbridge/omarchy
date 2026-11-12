#!/bin/bash

set -euo pipefail

# CI has no passwordless sudo. A user namespace supplies a uid 0 that can
# create the directories and a second uid that sees them the way the desktop
# user does. This machine's sudo -n path stays the default.
if [[ ${DESKTOP_LOCK_NS:-} != 1 ]] && { [[ ${DESKTOP_LOCK_FORCE_NS:-} == 1 ]] || ! sudo -n true 2>/dev/null; }; then
  exec unshare --user --map-auto --map-root-user --mount --propagation private \
    env DESKTOP_LOCK_NS=1 bash "$0"
fi

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
source "$ROOT/default/gaming/session.sh"

# Spec 02 names this marker and no other.
marker=/var/lib/omarchy/handheld/k07-landed
value=/var/lib/omarchy/handheld/desktop-lock
state_dir=/var/lib/omarchy
handheld_dir=/var/lib/omarchy/handheld

work=$(mktemp -d)
stub=$work/bin
mkdir -p "$stub"
cat > "$stub/omarchy-hw-rog-ally" <<'EOF'
#!/bin/bash
[[ ${LOCK_HW:-ally} == ally ]]
EOF
cat > "$stub/omarchy-pkg-present" <<'EOF'
#!/bin/bash
[[ $1 == omarchy-gaming-session && ${LOCK_PKG:-yes} == yes ]]
EOF
chmod +x "$stub/"*
export PATH="$stub:$PATH"
export HOME=$work/home
export LOCK_HW=ally LOCK_PKG=yes
mkdir -p "$HOME/.local/state/omarchy"
chmod -R a+rX "$work"

if [[ ${DESKTOP_LOCK_NS:-} == 1 ]]; then
  mount -t tmpfs tmpfs /var/lib
fi

root_do() {
  if [[ $EUID == 0 ]]; then
    "$@"
  else
    sudo -n "$@"
  fi
}

as_user() {
  if [[ ${DESKTOP_LOCK_NS:-} == 1 && $EUID == 0 ]]; then
    setpriv --reuid=1 --regid=1 --clear-groups "$@"
  else
    "$@"
  fi
}

user_state() {
  as_user bash -c 'source "$1"; gaming_k07_marker_state' bash "$ROOT/default/gaming/session.sh"
}

user_effective() {
  as_user bash -c 'source "$1"; gaming_desktop_lock_effective' bash "$ROOT/default/gaming/session.sh"
}

restore_tree() {
  root_do "$ROOT/bin/omarchy-setup-handheld-dirs" >/dev/null 2>&1 || true
  root_do rm -f "$marker" "$value"
  rm -rf "$work"
}
trap restore_tree EXIT

assert_dir() {
  local dir=$1 owner mode
  owner=$(stat -c %u -- "$dir")
  mode=$(stat -c %a -- "$dir")
  [[ $owner == 0 && $mode == 755 ]] || fail "$dir is root-owned mode 0755" "owner=$owner mode=$mode"
  as_user test ! -w "$dir" || fail "$dir is not writable by the desktop user"
  (( (8#$mode & 8#022) == 0 )) || fail "$dir is not writable by group or other" "$mode"
}

# A too-tight directory is what locked the Ally out before K07. The creator
# has to open it to 0755, root-owned, without making it writable.
root_do mkdir -p "$state_dir"
root_do chmod 0700 "$state_dir"
root_do "$ROOT/bin/omarchy-setup-handheld-dirs"
assert_dir "$state_dir"
assert_dir "$handheld_dir"
pass "install creates /var/lib/omarchy root-owned and not writable"

root_do rm -f "$marker"
[[ $(user_state) == absent ]] || fail "a missing marker in a 0755 directory is absent"
LOCK_HW=ally LOCK_PKG=yes
[[ $(user_effective) == default-off ]] || fail "pre-K07 handheld desktop-lock is off when the marker is absent" "$(user_effective)"
pass "pre-K07 absence is visible to the desktop user and desktop-lock is off"

root_do chmod 0700 "$state_dir"
[[ $(user_state) == present ]] || fail "an unreadable /var/lib/omarchy counts as the marker being present" "$(user_state)"
[[ $(user_effective) == on ]] || fail "an unreadable marker turns desktop-lock on" "$(user_effective)"
pass "an unreadable state directory fails closed to desktop-lock on"
root_do "$ROOT/bin/omarchy-setup-handheld-dirs"

root_do rm -rf "$handheld_dir"
echo 'not-a-directory' | root_do tee "$handheld_dir" >/dev/null
[[ $(user_state) == present ]] || fail "a stat error other than ENOENT counts as present" "$(LC_ALL=C stat -c %u -- "$marker" 2>&1 || true)"
pass "a non-ENOENT marker error fails closed"
root_do rm -f "$handheld_dir"
root_do "$ROOT/bin/omarchy-setup-handheld-dirs"

printf '%s\n' explicit-off > "$HOME/.local/state/omarchy/desktop-lock"
[[ $(user_effective) == default-off ]] || fail "a user-writable copy cannot store explicit-off" "$(user_effective)"
pass "a user-writable desktop-lock copy is ignored"

root_do install -o root -g root -m 0644 /dev/null "$marker"
[[ $(user_effective) == on ]] || fail "post-K07 a missing value is on" "$(user_effective)"
printf '%s\n' 'not-a-value' | root_do tee "$value" >/dev/null
root_do chown root:root "$value"
root_do chmod 0644 "$value"
[[ $(user_effective) == on ]] || fail "post-K07 a corrupt value is on" "$(user_effective)"
printf '%s\n' explicit-off | root_do tee "$value" >/dev/null
root_do chown root:root "$value"
root_do chmod 0644 "$value"
[[ $(user_effective) == explicit-off ]] || fail "post-K07 explicit-off stays off" "$(user_effective)"
printf '%s\n' off > "$HOME/.local/state/omarchy/desktop-lock"
[[ $(user_effective) == explicit-off ]] || fail "a user off does not replace a root value"
printf '%s\n' on | root_do tee "$value" >/dev/null
root_do chown root:root "$value"
root_do chmod 0644 "$value"
[[ $(user_effective) == on ]] || fail "root on wins over a user off" "$(user_effective)"
root_do chmod 0666 "$value"
[[ $(user_effective) == on ]] || fail "a group-writable value is ignored after K07" "$(user_effective)"
pass "post-K07 missing and corrupt lock, and only explicit-off stays off"

root_do rm -f "$marker" "$value"
LOCK_HW=laptop
[[ $(user_effective) == on ]] || fail "a laptop with the package stays on" "$(user_effective)"
LOCK_HW=ally
LOCK_PKG=no
[[ $(user_effective) == on ]] || fail "an Ally without the session package stays on" "$(user_effective)"
LOCK_PKG=yes
pass "desktop-lock stays on unless the machine is the handheld pair"

# The Ally's N-KEY controller interface is a udev keyboard and must not count.
source "$ROOT/default/gaming/keyboard.sh"
nkey=$'ID_INPUT_KEYBOARD=1\nID_VENDOR_ID=0b05\nID_MODEL_ID=1abe\nNAME="N-KEY Device"\nDEVPATH=/devices/pci0000:00/usb1/1-3/1-3:1.0/input/input4/event4'
gaming_device_is_physical_keyboard "$nkey" && fail "the Ally N-KEY keyboard interface counts as a physical keyboard"
virtual_keys=$'ID_INPUT_KEYBOARD=1\nNAME="py-evdev-uinput"\nDEVPATH=/devices/virtual/input/input9/event9'
gaming_device_is_physical_keyboard "$virtual_keys" && fail "a virtual uinput keyboard counts as a physical keyboard"
usb_keys=$'ID_INPUT_KEYBOARD=1\nID_VENDOR_ID=046d\nID_MODEL_ID=c31c\nID_BUS=usb\nNAME="Logitech USB Keyboard"\nDEVPATH=/devices/pci0000:00/usb2/2-1/2-1:1.0/input/input8/event8'
gaming_device_is_physical_keyboard "$usb_keys" || fail "a USB keyboard counts as a physical keyboard"
kb=$work/kb
mkdir -p "$kb/event0" "$kb/event1" "$kb/bin"
printf '%s\n' "$nkey" > "$kb/event0/props"
printf '%s\n' "$virtual_keys" > "$kb/event1/props"
cat > "$kb/bin/udevadm" <<'EOF'
#!/bin/bash
event=${!#}
cat "$event/props"
EOF
chmod +x "$kb/bin/udevadm"
(PATH="$kb/bin:$PATH" gaming_physical_keyboard_in "$kb") && fail "only the Ally interface and a virtual keyboard means no physical keyboard"
mkdir -p "$kb/event2"
printf '%s\n' "$usb_keys" > "$kb/event2/props"
(PATH="$kb/bin:$PATH" gaming_physical_keyboard_in "$kb") || fail "a USB keyboard beside the Ally interface counts"
pass "the Ally's internal keyboard interface is not a physical keyboard"

# Before K07, the handheld locks on suspend only with a physical keyboard.
# Other machines still lock when desktop-lock is off. That is the case-4
# override, and it stops once the K07 marker is present.
sleep_log=$work/sleep
mkdir -p "$stub"
cat > "$stub/omarchy-shell" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$sleep_log"
if [[ \$1 == lock && \$2 == status ]]; then
  printf '%s\n' '{"secure":true}'
fi
exit 0
EOF
cat > "$stub/omarchy-launch-gaming-session" <<EOF
#!/bin/bash
printf '%s\n' "launch:\$*" >> "$sleep_log"
exit 0
EOF
cat > "$stub/omarchy-hw-physical-keyboard" <<'EOF'
#!/bin/bash
exit "${LOCK_KEYBOARD:-1}"
EOF
cat > "$stub/busctl" <<'EOF'
#!/bin/bash
printf '%s\n' 't 15000000'
EOF
cat > "$stub/omarchy-hyprland-monitor-clamshell" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$stub/omarchy-notification-send" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$stub/"*
export LOCK_KEYBOARD=1
write_value() {
  printf '%s\n' "$1" | root_do tee "$value" >/dev/null
  root_do chown root:root "$value"
  root_do chmod 0644 "$value"
}
assert_locked() {
  grep -q 'lock lock' "$sleep_log" || fail "$1" "$(cat "$sleep_log")"
}
assert_unlocked() {
  if grep -q 'lock lock' "$sleep_log"; then
    fail "$1" "$(cat "$sleep_log")"
  fi
}

root_do rm -f "$marker" "$value"
: > "$sleep_log"
LOCK_HW=laptop LOCK_PKG=yes LOCK_KEYBOARD=1
"$ROOT/bin/omarchy-system-sleep-lock"
assert_locked "a non-handheld suspend still locks when desktop-lock is absent"
: > "$sleep_log"
write_value explicit-off
"$ROOT/bin/omarchy-system-sleep-lock"
assert_locked "a non-handheld suspend still locks when desktop-lock is explicit-off"
pass "non-handheld suspend lock ignores desktop-lock"

LOCK_HW=ally LOCK_PKG=yes LOCK_KEYBOARD=1
root_do rm -f "$marker" "$value"
: > "$sleep_log"
"$ROOT/bin/omarchy-system-sleep-lock"
assert_unlocked "pre-K07 handheld suspend locks with no keyboard and desktop-lock off"
: > "$sleep_log"
write_value explicit-off
"$ROOT/bin/omarchy-system-sleep-lock"
assert_unlocked "pre-K07 handheld explicit-off still locks on suspend without a keyboard"
: > "$sleep_log"
LOCK_KEYBOARD=0 "$ROOT/bin/omarchy-system-sleep-lock"
assert_locked "a physical keyboard still locks a pre-K07 handheld whose desktop-lock is off"
pass "pre-K07 handheld suspend locks only while a physical keyboard is attached"

write_value on
: > "$sleep_log"
status=0
LOCK_KEYBOARD=1 HYPRLAND_INSTANCE_SIGNATURE=fixture WAYLAND_DISPLAY=wayland-test \
  "$ROOT/bin/omarchy-system-sleep-lock" || status=$?
[[ $status == 1 ]] || fail "explicit on without a keyboard cancels suspend" "$status"
assert_unlocked "explicit on without a keyboard still locks on suspend"
grep -q 'launch:--confirm' "$sleep_log" || fail "explicit on without a keyboard returns to gaming" "$(cat "$sleep_log")"
pass "explicit on with no keyboard returns to gaming instead of locking"

root_do install -o root -g root -m 0644 /dev/null "$marker"
write_value explicit-off
: > "$sleep_log"
LOCK_KEYBOARD=1 "$ROOT/bin/omarchy-system-sleep-lock"
assert_locked "the K07 marker restores suspend lock without a physical keyboard"
root_do rm -f "$marker"
pass "the K07 marker brings the ordinary suspend lock back"

: > "$sleep_log"
root_do rm -f "$value"
printf '%s\n' 'boolean false' | LOCK_KEYBOARD=1 "$ROOT/bin/omarchy-system-sleep-monitor" --consume
assert_unlocked "resume locks a keyboard-less handheld before K07"
printf '%s\n' 'boolean false' | LOCK_KEYBOARD=0 "$ROOT/bin/omarchy-system-sleep-monitor" --consume
assert_unlocked "resume adds a second lock when a keyboard is attached"
printf '%s\n' 'boolean true' | LOCK_KEYBOARD=1 "$ROOT/bin/omarchy-system-sleep-monitor" --consume
assert_unlocked "the before-sleep path locks a keyboard-less handheld before K07"
pass "resume and before-sleep do not lock a keyboard-less handheld before K07"

: > "$sleep_log"
root_do rm -f "$value"
LOCK_KEYBOARD=1 "$ROOT/bin/omarchy-system-lock"
assert_unlocked "idle locks a keyboard-less handheld before K07"
: > "$sleep_log"
status=0
write_value on
LOCK_KEYBOARD=1 HYPRLAND_INSTANCE_SIGNATURE=fixture WAYLAND_DISPLAY=wayland-test \
  "$ROOT/bin/omarchy-system-lock" || status=$?
[[ $status == 1 ]] || fail "explicit on idle returns to gaming" "$status"
assert_unlocked "explicit on idle still locks without a keyboard"
grep -q 'launch:--confirm' "$sleep_log" || fail "explicit on idle does not return to gaming" "$(cat "$sleep_log")"
: > "$sleep_log"
LOCK_KEYBOARD=0 "$ROOT/bin/omarchy-system-lock"
assert_locked "a physical keyboard lets idle and the lock hotkey lock"
pass "idle, lid, and the lock hotkey share the keyboard gate"

sweep=$work/sweep
mkdir -p "$sweep"
cat > "$sweep/omarchy-cmd-present" <<'EOF'
#!/bin/bash
case $1 in
  gamescope | steam) exit 1 ;;
esac
command -v "$1" >/dev/null
EOF
cat > "$sweep/uwsm" <<EOF
#!/bin/bash
printf '%s\n' "uwsm:\$*" >> "$work/desktop-actions"
exit 0
EOF
cat > "$sweep/omarchy-system-lock" <<EOF
#!/bin/bash
printf '%s\n' lock >> "$work/desktop-actions"
exit 0
EOF
chmod +x "$sweep/"*
sed 's|source /usr/share/omarchy/default/bash/env-bootstrap|:|' "$ROOT/bin/omarchy-session-start" > "$work/session-start"
chmod +x "$work/session-start"
run_desktop_entry() {
  local expect=$1
  local status=0
  local log actions=$work/desktop-actions
  : > "$actions"
  rm -rf "$HOME/.local/state" "$work/runtime"
  mkdir -p "$HOME/.local/state/omarchy/gaming-session" "$work/runtime"
  printf '%s\n' desktop > "$HOME/.local/state/omarchy/gaming-session/preference"
  XDG_RUNTIME_DIR=$work/runtime XDG_SESSION_ID=locktest OMARCHY_GAMING_RETRY_GAP=0 \
    PATH="$sweep:$stub:$PATH" \
    "$work/session-start" preferred || status=$?
  [[ $status == "$expect" ]] || fail "switch to desktop exited $expect" "$status"
  log=$HOME/.local/state/omarchy/gaming-session/session.log
  if [[ $3 == locked ]]; then
    grep -q '^lock$' "$actions" || fail "$2 never locked" "$(cat "$actions")"
    grep -q '^uwsm:' "$actions" || fail "$2 never started the desktop" "$(cat "$actions")"
  elif [[ $3 == desktop ]]; then
    if grep -q '^lock$' "$actions"; then fail "$2 locked" "$(cat "$actions")"; fi
    grep -q '^uwsm:' "$actions" || fail "$2 never started the desktop" "$(cat "$actions")"
  else
    if grep -q '^lock$' "$actions" || grep -q '^uwsm:' "$actions"; then
      fail "$2 started a desktop or a lock" "$(cat "$actions")"
    fi
    grep -q 'returning to gaming' "$log" || fail "$2 did not return to gaming" "$(cat "$log" 2>/dev/null)"
  fi
}
root_do rm -f "$marker"
write_value on
LOCK_HW=ally LOCK_PKG=yes LOCK_KEYBOARD=1
run_desktop_entry 1 "switch to desktop with explicit on and no keyboard" return
root_do rm -f "$value"
run_desktop_entry 0 "switch to desktop with default-off and no keyboard" desktop
write_value on
LOCK_KEYBOARD=0 run_desktop_entry 0 "switch to desktop with a keyboard and explicit on" locked
pass "switch to desktop never leaves a keyboard-less handheld on the lock screen before K07"

if "$ROOT/bin/omarchy-setup-gaming-session" desktop-lock off >/dev/null 2>"$work/off.err"; then
  fail "desktop-lock off without a terminal must not succeed"
fi
grep -q 'needs a terminal' "$work/off.err" || fail "desktop-lock off asks for a terminal" "$(cat "$work/off.err")"
pass "desktop-lock off refuses a passwordless background call"
