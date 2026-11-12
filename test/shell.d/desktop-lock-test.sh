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
# A leaked agent session must not look like a live Hyprland lock.
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY

# Spec 02 names this marker and no other.
marker=/var/lib/omarchy/handheld/k07-landed
value=/var/lib/omarchy/handheld/desktop-lock
state_dir=/var/lib/omarchy
handheld_dir=/var/lib/omarchy/handheld

work=$(mktemp -d)
stub=$work/bin
mkdir -p "$stub"
# uid 1 in the user namespace cannot traverse /home (mode 0700). The reader
# sources this copy from /tmp, which it can search.
cp "$ROOT/default/gaming/session.sh" "$work/session.sh"
cat > "$stub/omarchy-hw-rog-ally" <<'EOF'
#!/bin/bash
[[ ${LOCK_HW:-ally} == ally ]]
EOF
cat > "$stub/omarchy-pkg-present" <<'EOF'
#!/bin/bash
[[ $1 == omarchy-gaming-session && ${LOCK_PKG:-yes} == yes ]]
EOF
chmod +x "$stub/"*
export PATH="$stub:$ROOT/bin:$PATH"
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
  as_user bash -c 'source "$1"; gaming_k07_marker_state' bash "$work/session.sh"
}

user_effective() {
  as_user bash -c 'source "$1"; gaming_desktop_lock_effective' bash "$work/session.sh"
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
export sleep_log=$work/sleep
mkdir -p "$stub"
cat > "$stub/omarchy-shell" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$sleep_log"
if [[ \$1 == lock && \$2 == lock ]]; then
  printf '%s\n' lock-attempt >> "$work/desktop-actions"
  if [[ \${LOCK_FAIL:-0} == 1 ]]; then
    exit 1
  fi
  printf '%s\n' lock >> "$work/desktop-actions"
fi
if [[ \$1 == lock && \$2 == status ]]; then
  if [[ \${LOCK_FAIL:-0} == 1 ]]; then
    exit 1
  fi
  printf '%s\n' '{"secure":true}'
fi
exit 0
EOF
cat > "$stub/systemd-run" <<EOF
#!/bin/bash
printf '%s\n' "systemd-run:\$*" >> "$sleep_log"
exit 0
EOF
cat > "$stub/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
cat > "$stub/gamescope" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$stub/steam" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$stub/omarchy-hw-physical-keyboard" <<'EOF'
#!/bin/bash
exit "${LOCK_KEYBOARD:-1}"
EOF
cat > "$stub/busctl" <<'EOF'
#!/bin/bash
if [[ $1 == status && $2 == org.omarchy.Handheld.Suspend1 ]]; then
  if [[ ${LOCK_BROKER:-0} == 1 ]]; then exit 0; fi
  exit 1
fi
if [[ $1 == call && $2 == org.omarchy.Handheld.Suspend1 ]]; then
  printf '%s\n' "broker:$*" >> "$sleep_log"
  if [[ ${LOCK_BROKER:-0} == 1 ]]; then exit 0; fi
  exit 1
fi
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
cat > "$stub/omarchy-brightness-display" <<EOF
#!/bin/bash
printf '%s\n' "blank:\$*" >> "$sleep_log"
exit 0
EOF
cat > "$stub/omarchy-lock-host" <<'EOF'
#!/bin/bash
if [[ $1 == mode ]]; then
  printf '%s\n' "${LOCK_HOST_MODE:-shell}"
fi
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

sleep_status=0
run_sleep() {
  sleep_status=0
  "$@" || sleep_status=$?
}
return_runtime=$work/return-runtime
prepare_return() {
  mkdir -p "$return_runtime/omarchy-gaming-locktest"
  printf '%s\n' desktop > "$return_runtime/omarchy-gaming-locktest/active"
}
assert_returned() {
  grep -q 'default/gaming/switch.sh' "$sleep_log" || fail "$1" "$(cat "$sleep_log")"
  if grep -q -- '--confirm' "$sleep_log"; then fail "$1 passed --confirm" "$(cat "$sleep_log")"; fi
}
root_do rm -f "$marker" "$value"
: > "$sleep_log"
LOCK_HW=laptop LOCK_PKG=yes LOCK_KEYBOARD=1
run_sleep "$ROOT/bin/omarchy-system-sleep-lock"
[[ $sleep_status == 0 ]] || fail "a confirmed lock exits 0" "$sleep_status"
assert_locked "a non-handheld suspend still locks when desktop-lock is absent"
: > "$sleep_log"
write_value explicit-off
run_sleep "$ROOT/bin/omarchy-system-sleep-lock"
[[ $sleep_status == 0 ]] || fail "a non-handheld explicit-off still confirms the lock" "$sleep_status"
assert_locked "a non-handheld suspend still locks when desktop-lock is explicit-off"
pass "non-handheld suspend lock ignores desktop-lock"

LOCK_HW=ally LOCK_PKG=yes LOCK_KEYBOARD=1
root_do rm -f "$marker" "$value"
: > "$sleep_log"
run_sleep "$ROOT/bin/omarchy-system-sleep-lock"
[[ $sleep_status == 10 ]] || fail "a skipped handheld lock exits 10" "$sleep_status"
assert_unlocked "pre-K07 handheld suspend locks with no keyboard and desktop-lock off"
: > "$sleep_log"
write_value explicit-off
run_sleep "$ROOT/bin/omarchy-system-sleep-lock"
[[ $sleep_status == 10 ]] || fail "an explicit-off skip exits 10" "$sleep_status"
assert_unlocked "pre-K07 handheld explicit-off still locks on suspend without a keyboard"
: > "$sleep_log"
LOCK_KEYBOARD=0 run_sleep "$ROOT/bin/omarchy-system-sleep-lock"
[[ $sleep_status == 0 ]] || fail "a physical keyboard confirms the lock" "$sleep_status"
assert_locked "a physical keyboard still locks a pre-K07 handheld whose desktop-lock is off"
pass "pre-K07 handheld suspend locks only while a physical keyboard is attached"

write_value on
: > "$sleep_log"
status=0
prepare_return
LOCK_KEYBOARD=1 HYPRLAND_INSTANCE_SIGNATURE=fixture WAYLAND_DISPLAY=wayland-test \
  XDG_RUNTIME_DIR=$return_runtime XDG_SESSION_ID=locktest \
  "$ROOT/bin/omarchy-system-sleep-lock" || status=$?
[[ $status == 11 ]] || fail "explicit on without a keyboard cancels suspend" "$status"
assert_unlocked "explicit on without a keyboard still locks on suspend"
assert_returned "explicit on without a keyboard returns to gaming"
status=0
"$ROOT/bin/omarchy-launch-gaming-session" --confirm >/dev/null 2>&1 || status=$?
[[ $status == 2 ]] || fail "the launcher accepts --confirm" "$status"
pass "explicit on with no keyboard returns to gaming instead of locking"

root_do install -o root -g root -m 0644 /dev/null "$marker"
write_value explicit-off
: > "$sleep_log"
LOCK_KEYBOARD=1 "$ROOT/bin/omarchy-system-sleep-lock"
assert_locked "the K07 marker restores suspend lock without a physical keyboard"
pass "the K07 marker brings the ordinary suspend lock back"

# The marker is present, but this session is still the shell owner. The touch
# keyboard is not loaded until the next session latches the trusted host.
write_value on
: > "$sleep_log"
status=0
prepare_return
LOCK_KEYBOARD=1 LOCK_HOST_MODE=shell HYPRLAND_INSTANCE_SIGNATURE=fixture WAYLAND_DISPLAY=wayland-test \
  XDG_RUNTIME_DIR=$return_runtime XDG_SESSION_ID=locktest \
  "$ROOT/bin/omarchy-system-sleep-lock" || status=$?
[[ $status == 11 ]] || fail "a shell-owned session after K07 must not lock without a keyboard" "$status"
assert_unlocked "a shell-owned session after K07 still locks without a keyboard"
assert_returned "a shell-owned session after K07 did not return to gaming"
: > "$sleep_log"
status=0
LOCK_KEYBOARD=1 LOCK_HOST_MODE=host HYPRLAND_INSTANCE_SIGNATURE=fixture WAYLAND_DISPLAY=wayland-test \
  "$ROOT/bin/omarchy-system-sleep-lock" || status=$?
[[ $status == 0 ]] || fail "the trusted host after K07 should lock" "$status"
assert_locked "the trusted host supplies the lock-screen keyboard"
pass "after K07 a keyboard-less shell does not lock until the trusted host owns the session"
root_do rm -f "$marker"

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
prepare_return
LOCK_KEYBOARD=1 HYPRLAND_INSTANCE_SIGNATURE=fixture WAYLAND_DISPLAY=wayland-test \
  XDG_RUNTIME_DIR=$return_runtime XDG_SESSION_ID=locktest \
  "$ROOT/bin/omarchy-system-lock" || status=$?
[[ $status == 1 ]] || fail "explicit on idle returns to gaming" "$status"
assert_unlocked "explicit on idle still locks without a keyboard"
assert_returned "explicit on idle does not return to gaming"
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
cat > "$work/hold-socket.py" <<'PY'
import os, signal, socket, sys
path = sys.argv[1]
try:
    os.remove(path)
except FileNotFoundError:
    pass
sock = socket.socket(socket.AF_UNIX)
sock.bind(path)
sock.listen(1)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
signal.pause()
PY
cat > "$sweep/uwsm" <<EOF
#!/bin/bash
runtime=\${XDG_RUNTIME_DIR:-}
holder=''
cleanup() { [[ -n \$holder ]] && kill "\$holder" 2>/dev/null || true; }
trap cleanup EXIT
if [[ -n \$runtime ]]; then
  mkdir -p "\$runtime/hypr/fixture"
  python3 "$work/hold-socket.py" "\$runtime/wayland-1" &
  holder=\$!
fi
printf '%s\n' "uwsm:\$*" >> "$work/desktop-actions"
for _ in {1..50}; do
  grep -q '^lock-attempt$' "$work/desktop-actions" && break
  sleep 0.05
done
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
  if [[ $3 == locked || $3 == failed ]]; then
    grep -q '^uwsm:' "$actions" || fail "$2 never started Hyprland" "$(cat "$actions")"
    grep -q '^lock-attempt$' "$actions" || fail "$2 never asked the lock host" "$(cat "$actions")"
    local uwsm_line lock_line
    uwsm_line=$(grep -n '^uwsm:' "$actions" | head -n 1 | cut -d: -f1)
    lock_line=$(grep -n '^lock-attempt$' "$actions" | head -n 1 | cut -d: -f1)
    (( uwsm_line < lock_line )) || fail "$2 locked before Hyprland was up" "$(cat "$actions")"
    if [[ $3 == locked ]]; then
      grep -q '^lock$' "$actions" || fail "$2 never locked" "$(cat "$actions")"
    else
      if grep -q '^lock$' "$actions"; then fail "$2 treated a failed lock host as engaged" "$(cat "$actions")"; fi
      grep -q 'not leaving an unlocked desktop' "$log" || fail "$2 left the desktop up" "$(cat "$log" 2>/dev/null)"
    fi
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
LOCK_KEYBOARD=0 LOCK_FAIL=1 run_desktop_entry 1 "a failed lock host after Hyprland is up" failed
pass "switch to desktop never leaves a keyboard-less handheld on the lock screen before K07"

root_do rm -f "$marker" "$value"
write_value default-off
root_do env OMARCHY_PATH="$OMARCHY_PATH" "$ROOT/bin/omarchy-setup-handheld-k07"
[[ $(user_state) == absent ]] || fail "K07 setup writes the marker before a device lock test" "$(user_state)"
[[ $(head -n 1 -- "$value") == default-off ]] || fail "K07 setup turns desktop-lock on while dormant" "$(head -n 1 -- "$value")"
[[ $(user_effective) == default-off ]] || fail "a dormant handheld does not stay desktop-lock off" "$(user_effective)"
write_value explicit-off
root_do env OMARCHY_PATH="$OMARCHY_PATH" "$ROOT/bin/omarchy-setup-handheld-k07"
[[ $(head -n 1 -- "$value") == explicit-off ]] || fail "K07 setup changes an explicit off" "$(head -n 1 -- "$value")"
root_do install -o root -g root -m 0644 /dev/null "$marker"
status=0
as_user "$ROOT/bin/omarchy-rollback-handheld-k07" >/dev/null 2>"$work/rollback.err" || status=$?
[[ $status != 0 ]] || fail "a non-root user removed the K07 marker"
grep -q 'must run as root' "$work/rollback.err" || fail "rollback does not say it needs root" "$(cat "$work/rollback.err")"
[[ $(user_state) == present ]] || fail "a refused rollback deleted the marker" "$(user_state)"
root_do "$ROOT/bin/omarchy-rollback-handheld-k07"
[[ $(user_state) == absent ]] || fail "root rollback left the K07 marker" "$(user_state)"
pass "K07 stays dormant and only root can remove the marker"

host_home=$work/host-home
laptop_home=$work/laptop-home
LOCK_HW=ally HOME=$host_home "$ROOT/bin/omarchy-setup-handheld-lock-host"
host_pref=$host_home/.local/state/omarchy/lock-host-enabled
[[ -f $host_pref ]] || fail "the Ally stages the trusted lock host"
[[ $(stat -c %a -- "$host_pref") == 600 ]] || fail "the lock-host preference is not mode 0600" "$(stat -c %a -- "$host_pref")"
printf '%s\n' kept > "$host_pref"
LOCK_HW=ally HOME=$host_home "$ROOT/bin/omarchy-setup-handheld-lock-host"
[[ $(<"$host_pref") == kept ]] || fail "a second run replaces the lock-host preference"
LOCK_HW=laptop HOME=$laptop_home "$ROOT/bin/omarchy-setup-handheld-lock-host"
[[ ! -e $laptop_home/.local/state/omarchy/lock-host-enabled ]] || fail "a laptop stages the Ally lock host"
LOCK_HW=ally
HOME=$work/home
pass "the next Ally session latches the trusted lock host"

# A required lock that the shell refuses is not a confirmed surface.
cat > "$stub/omarchy-shell" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$sleep_log"
if [[ \$1 == lock && \$2 == lock ]]; then
  printf '%s\n' missing-pam
fi
exit 0
EOF
: > "$sleep_log"
LOCK_HW=laptop LOCK_PKG=yes LOCK_KEYBOARD=1 run_sleep "$ROOT/bin/omarchy-system-sleep-lock" 400
[[ $sleep_status == 1 ]] || fail "an unconfirmed lock exits 1" "$sleep_status"
pass "sleep-lock exits 1 when the lock surface is not confirmed"
cat > "$stub/omarchy-shell" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$sleep_log"
if [[ \$1 == lock && \$2 == status ]]; then
  printf '%s\n' '{"secure":true}'
fi
exit 0
EOF

# Idle on the handheld: a physical keyboard locks, none with desktop-lock on
# returns to gaming, and off blanks the outputs without locking or suspending.
: > "$sleep_log"
root_do rm -f "$marker"
write_value explicit-off
LOCK_HW=ally LOCK_PKG=yes LOCK_KEYBOARD=1 LOCK_BROKER=1 run_sleep "$ROOT/bin/omarchy-system-idle-lock"
[[ $sleep_status == 0 ]] || fail "idle with desktop-lock off exits quietly" "$sleep_status"
assert_unlocked "idle locks when desktop-lock is off and no keyboard is attached"
grep -q 'blank:off' "$sleep_log" || fail "idle with desktop-lock off does not blank" "$(cat "$sleep_log")"
if grep -q 'systemd-run:' "$sleep_log"; then fail "idle with desktop-lock off returns to gaming" "$(cat "$sleep_log")"; fi
if grep -q 'broker:' "$sleep_log"; then fail "idle with desktop-lock off calls the broker" "$(cat "$sleep_log")"; fi
: > "$sleep_log"
write_value default-off
LOCK_HW=ally LOCK_PKG=yes LOCK_KEYBOARD=1 LOCK_BROKER=1 run_sleep "$ROOT/bin/omarchy-system-idle-lock"
[[ $sleep_status == 0 ]] || fail "idle with default-off exits quietly" "$sleep_status"
grep -q 'blank:off' "$sleep_log" || fail "idle with default-off does not blank" "$(cat "$sleep_log")"
if grep -q 'systemd-run:\|broker:\|lock lock' "$sleep_log"; then fail "idle with default-off locks or suspends" "$(cat "$sleep_log")"; fi
: > "$sleep_log"
write_value on
prepare_return
LOCK_HW=ally LOCK_PKG=yes LOCK_KEYBOARD=1 LOCK_BROKER=0 \
  XDG_RUNTIME_DIR=$return_runtime XDG_SESSION_ID=locktest \
  HYPRLAND_INSTANCE_SIGNATURE=fixture WAYLAND_DISPLAY=wayland-test \
  run_sleep "$ROOT/bin/omarchy-system-idle-lock"
assert_unlocked "idle locks when desktop-lock is on and no keyboard is attached"
assert_returned "idle without a broker does not return to gaming"
: > "$sleep_log"
LOCK_HW=ally LOCK_PKG=yes LOCK_KEYBOARD=1 LOCK_BROKER=1 run_sleep "$ROOT/bin/omarchy-system-idle-lock"
grep -q 'broker:call org.omarchy.Handheld.Suspend1' "$sleep_log" || fail "idle does not call the suspend broker" "$(cat "$sleep_log")"
if grep -q 'systemd-run:' "$sleep_log"; then fail "idle calls the broker and also switches session" "$(cat "$sleep_log")"; fi
: > "$sleep_log"
LOCK_HW=ally LOCK_PKG=yes LOCK_KEYBOARD=0 LOCK_BROKER=0 run_sleep "$ROOT/bin/omarchy-system-idle-lock"
[[ $sleep_status == 0 ]] || fail "idle with a physical keyboard exits 0" "$sleep_status"
assert_locked "idle with a physical keyboard locks"
pass "handheld idle locks only while a physical keyboard is attached"

if "$ROOT/bin/omarchy-setup-gaming-session" desktop-lock off >/dev/null 2>"$work/off.err"; then
  fail "desktop-lock off without a terminal must not succeed"
fi
grep -q 'needs a terminal' "$work/off.err" || fail "desktop-lock off asks for a terminal" "$(cat "$work/off.err")"
pass "desktop-lock off refuses a passwordless background call"
