#!/bin/bash

set -euo pipefail

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

restore_tree() {
  sudo "$ROOT/bin/omarchy-setup-handheld-dirs" >/dev/null 2>&1 || true
  sudo rm -f "$marker" "$value"
  rm -rf "$work"
}
trap restore_tree EXIT

assert_dir() {
  local dir=$1 owner mode
  owner=$(stat -c %u -- "$dir")
  mode=$(stat -c %a -- "$dir")
  [[ $owner == 0 && $mode == 755 ]] || fail "$dir is root-owned mode 0755" "owner=$owner mode=$mode"
  [[ ! -w $dir ]] || fail "$dir is not writable by the desktop user"
  (( (8#$mode & 8#022) == 0 )) || fail "$dir is not writable by group or other" "$mode"
}

# A too-tight directory is what locked the Ally out before K07. The creator
# has to open it to 0755, root-owned, without making it writable.
sudo mkdir -p "$state_dir"
sudo chmod 0700 "$state_dir"
sudo "$ROOT/bin/omarchy-setup-handheld-dirs"
assert_dir "$state_dir"
assert_dir "$handheld_dir"
pass "install creates /var/lib/omarchy root-owned and not writable"

sudo rm -f "$marker"
[[ $(gaming_k07_marker_state) == absent ]] || fail "a missing marker in a 0755 directory is absent"
LOCK_HW=ally LOCK_PKG=yes
[[ $(gaming_desktop_lock_effective) == default-off ]] || fail "pre-K07 handheld desktop-lock is off when the marker is absent" "$(gaming_desktop_lock_effective)"
pass "pre-K07 absence is visible to the desktop user and desktop-lock is off"

sudo chmod 0700 "$state_dir"
[[ $(gaming_k07_marker_state) == present ]] || fail "an unreadable /var/lib/omarchy counts as the marker being present" "$(gaming_k07_marker_state)"
[[ $(gaming_desktop_lock_effective) == on ]] || fail "an unreadable marker turns desktop-lock on" "$(gaming_desktop_lock_effective)"
pass "an unreadable state directory fails closed to desktop-lock on"
sudo "$ROOT/bin/omarchy-setup-handheld-dirs"

sudo rm -rf "$handheld_dir"
echo 'not-a-directory' | sudo tee "$handheld_dir" >/dev/null
[[ $(gaming_k07_marker_state) == present ]] || fail "a stat error other than ENOENT counts as present" "$(LC_ALL=C stat -c %u -- "$marker" 2>&1 || true)"
pass "a non-ENOENT marker error fails closed"
sudo rm -f "$handheld_dir"
sudo "$ROOT/bin/omarchy-setup-handheld-dirs"

printf '%s\n' explicit-off > "$HOME/.local/state/omarchy/desktop-lock"
[[ $(gaming_desktop_lock_effective) == default-off ]] || fail "a user-writable copy cannot store explicit-off" "$(gaming_desktop_lock_effective)"
pass "a user-writable desktop-lock copy is ignored"

sudo install -o root -g root -m 0644 /dev/null "$marker"
[[ $(gaming_desktop_lock_effective) == on ]] || fail "post-K07 a missing value is on" "$(gaming_desktop_lock_effective)"
printf '%s\n' 'not-a-value' | sudo tee "$value" >/dev/null
sudo chown root:root "$value"
sudo chmod 0644 "$value"
[[ $(gaming_desktop_lock_effective) == on ]] || fail "post-K07 a corrupt value is on" "$(gaming_desktop_lock_effective)"
printf '%s\n' explicit-off | sudo tee "$value" >/dev/null
sudo chown root:root "$value"
sudo chmod 0644 "$value"
[[ $(gaming_desktop_lock_effective) == explicit-off ]] || fail "post-K07 explicit-off stays off" "$(gaming_desktop_lock_effective)"
printf '%s\n' off > "$HOME/.local/state/omarchy/desktop-lock"
[[ $(gaming_desktop_lock_effective) == explicit-off ]] || fail "a user off does not replace a root value"
printf '%s\n' on | sudo tee "$value" >/dev/null
sudo chown root:root "$value"
sudo chmod 0644 "$value"
[[ $(gaming_desktop_lock_effective) == on ]] || fail "root on wins over a user off" "$(gaming_desktop_lock_effective)"
sudo chmod 0666 "$value"
[[ $(gaming_desktop_lock_effective) == on ]] || fail "a group-writable value is ignored after K07" "$(gaming_desktop_lock_effective)"
pass "post-K07 missing and corrupt lock, and only explicit-off stays off"

sudo rm -f "$marker" "$value"
LOCK_HW=laptop
[[ $(gaming_desktop_lock_effective) == on ]] || fail "a laptop with the package stays on" "$(gaming_desktop_lock_effective)"
LOCK_HW=ally
LOCK_PKG=no
[[ $(gaming_desktop_lock_effective) == on ]] || fail "an Ally without the session package stays on" "$(gaming_desktop_lock_effective)"
LOCK_PKG=yes
pass "desktop-lock stays on unless the machine is the handheld pair"

# Sleep and idle do not read desktop-lock. Explicit-off skips only the extra
# session lock; suspend still asks the shell to lock.
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
: > "$sleep_log"
sudo rm -f "$value"
"$ROOT/bin/omarchy-system-sleep-lock"
grep -q 'lock lock' "$sleep_log" || fail "sleep lock still requests a lock when desktop-lock is absent" "$(cat "$sleep_log")"
: > "$sleep_log"
printf '%s\n' explicit-off | sudo tee "$value" >/dev/null
sudo chown root:root "$value"
sudo chmod 0644 "$value"
sudo rm -f "$marker"
LOCK_HW=ally LOCK_PKG=yes
[[ $(gaming_desktop_lock_effective) == explicit-off ]] || fail "explicit-off skips the session lock" "$(gaming_desktop_lock_effective)"
"$ROOT/bin/omarchy-system-sleep-lock"
grep -q 'lock lock' "$sleep_log" || fail "explicit-off still lets sleep lock request a lock" "$(cat "$sleep_log")"
idle_home=$work/idle-home
mkdir -p "$idle_home"
HOME=$idle_home "$ROOT/bin/omarchy-toggle-idle" status | grep -q '"enabled":false' || fail "idle lock stays allowed when desktop-lock is absent"
pass "sleep and idle lock stay on when the session lock is skipped"

if "$ROOT/bin/omarchy-setup-gaming-session" desktop-lock off >/dev/null 2>"$work/off.err"; then
  fail "desktop-lock off without a terminal must not succeed"
fi
grep -q 'needs a terminal' "$work/off.err" || fail "desktop-lock off asks for a terminal" "$(cat "$work/off.err")"
pass "desktop-lock off refuses a passwordless background call"
