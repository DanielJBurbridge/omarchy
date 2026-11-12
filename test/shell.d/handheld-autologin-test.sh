#!/bin/bash
# Handheld SDDM autologin, Relogin forcing gaming, and the root-owned 60s stop.

set -uo pipefail

# The counter is root-owned. A user namespace supplies uid 0 to create it and
# uid 1 to prove the desktop user cannot write it.
if [[ ${AUTOLOGIN_NS:-} != 1 ]]; then
  exec unshare --user --map-auto --map-root-user --mount --propagation private \
    env AUTOLOGIN_NS=1 bash "$0"
fi

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$here/base-test.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/run" "$work/sddm" "$work/state" "$work/home"
cat > "$work/bin/omarchy-hw-rog-ally" <<'EOF'
#!/bin/bash
[[ ${HW:-ally} == ally ]]
EOF
cat > "$work/bin/omarchy-pkg-present" <<'EOF'
#!/bin/bash
[[ $1 == omarchy-gaming-session && ${PKG:-present} == present ]]
EOF
cat > "$work/bin/omarchy-display-rog-ally" <<'EOF'
#!/bin/bash
[[ $1 == docked && ${DOCKED:-0} == 1 ]]
EOF
chmod +x "$work/bin/"* "$ROOT/bin/omarchy-handheld-autologin"

as_user() {
  setpriv --reuid=1 --regid=1 --clear-groups "$@"
}

run_guard() {
  HW=${HW:-ally} PKG=${PKG:-present} \
    OMARCHY_HANDHELD_AUTOLOGIN_DIR=$work/run \
    OMARCHY_SDDM_CONF_DIR=$work/sddm \
    PATH="$work/bin:$PATH" \
    "$ROOT/bin/omarchy-handheld-autologin" "$@"
}

assert_root_file() {
  local path=$1 owner mode
  owner=$(stat -c '%u:%g' -- "$path")
  mode=$(stat -c %a -- "$path")
  [[ $owner == 0:0 && $mode == 644 ]] || fail "$path is root-owned mode 0644" "owner=$owner mode=$mode"
  (( (8#$mode & 8#022) == 0 )) || fail "$path is writable by group or other" "$mode"
  as_user test ! -w "$path" || fail "$path is writable by the desktop user"
}

dropin=$work/sddm/zz-omarchy-handheld.conf
run_guard apply
grep -q '^Session=omarchy-handheld.desktop$' "$dropin" || fail "autologin selects the gaming session" "$(cat "$dropin")"
grep -q '^Relogin=true$' "$dropin" || fail "handheld autologin sets Relogin=true" "$(cat "$dropin")"
grep -q 'objectName: "greeterKeyboard"' "$ROOT/default/sddm/omarchy/Main.qml" ||
  fail "the greeter has an on-screen keyboard"
pass "handheld drop-in autologins into gaming with Relogin=true"

export XDG_STATE_HOME=$work/state HOME=$work/home PATH="$work/bin:$PATH"
# shellcheck source=/dev/null
source "$ROOT/default/gaming/session.sh"
mkdir -p "$gaming_state"
printf 'desktop\n' > "$gaming_state/preference"
printf 'failed\n' > "$gaming_state/recovery"
export DOCKED=1
[[ $(gaming_selection) == desktop ]] || fail "a recovery latch and a dock still select the desktop"
[[ $(gaming_entry_selection relogin) == gaming ]] || fail "Relogin stays on gaming through a latch and a dock"
[[ -f $gaming_state/recovery ]] || fail "Relogin leaves the recovery latch in place"
rm -f "$gaming_state/recovery"
printf 'auto\n' > "$gaming_state/preference"
[[ $(gaming_selection) == desktop ]] || fail "docked auto selects the desktop"
[[ $(gaming_entry_selection relogin) == gaming ]] || fail "Relogin ignores dock auto-switch"
export DOCKED=0
[[ $(gaming_selection) == gaming ]] || fail "undocked auto stays on gaming"
grep -q 'omarchy-session-start relogin' "$ROOT/bin/omarchy-handheld-autologin" ||
  fail "the autologin session uses the Relogin entry"
pass "Relogin forces gaming and ignores the recovery latch and dock auto-switch"

user_dir=$work/user-run
mkdir -p "$user_dir"
chown 1:1 "$user_dir"
as_user env OMARCHY_HANDHELD_AUTOLOGIN_DIR=$user_dir OMARCHY_AUTOLOGIN_NOW=1 \
  "$ROOT/bin/omarchy-handheld-autologin" fail
[[ ! -e $user_dir/failures && ! -e $user_dir/stop ]] || fail "a desktop user does not create the counter"

OMARCHY_AUTOLOGIN_NOW=1000 run_guard fail
assert_root_file "$work/run/failures"
dir_owner=$(stat -c '%u:%g:%a' -- "$work/run")
[[ $dir_owner == 0:0:755 ]] || fail "the counter directory is root-owned mode 0755" "$dir_owner"
as_user test ! -w "$work/run" || fail "the counter directory is writable by the desktop user"
run_guard reset
[[ ! -s $work/run/failures ]] || fail "the ready signal truncates the failure counter" "$(cat "$work/run/failures")"
assert_root_file "$work/run/failures"
[[ ! -f $work/run/stop ]] || fail "a healthy session does not stop autologin"
grep -q '^Relogin=true$' "$dropin" || fail "terminate-session still returns to gaming"
grep -q '^Exec=omarchy-handheld-autologin$' "$ROOT/default/gaming/wayland-sessions/omarchy-handheld.desktop" ||
  fail "the handheld session entry starts the gaming autologin"
pass "the counter is root-owned and a healthy session returns to gaming"

OMARCHY_AUTOLOGIN_NOW=2000 run_guard fail
OMARCHY_AUTOLOGIN_NOW=2020 run_guard fail
OMARCHY_AUTOLOGIN_NOW=2040 run_guard fail
[[ $(cat "$work/run/failures") == $'2000\n2020\n2040' ]] ||
  fail "three timestamps inside 60s are stored" "$(cat "$work/run/failures")"
[[ -f $work/run/stop ]] || fail "the third failure within 60s writes the stop file"
assert_root_file "$work/run/stop"
grep -q '^Relogin=false$' "$dropin" || fail "the stop file turns autologin off" "$(cat "$dropin")"
grep -q '^sddm-restart$' "$work/run/actions" || fail "tripping restarts the greeter"
pass "three failure timestamps within 60s stop autologin"

rm -f "$work/run/stop" "$work/run/failures" "$work/run/actions"
OMARCHY_AUTOLOGIN_NOW=3000 run_guard fail
OMARCHY_AUTOLOGIN_NOW=3010 run_guard fail
OMARCHY_AUTOLOGIN_NOW=3080 run_guard fail
[[ $(cat "$work/run/failures") == 3080 ]] || fail "timestamps older than 60s are pruned" "$(cat "$work/run/failures")"
[[ ! -f $work/run/stop ]] || fail "a pruned window does not trip"
OMARCHY_AUTOLOGIN_NOW=3100 run_guard fail
OMARCHY_AUTOLOGIN_NOW=3120 run_guard fail
[[ -f $work/run/stop ]] || fail "the third timestamp still inside the window trips"
pass "failures older than 60s are pruned and the third one left trips"

printf 'stale\n' > "$dropin"
HW=laptop run_guard apply
[[ ! -e $dropin ]] || fail "a laptop loses the handheld drop-in" "$(cat "$dropin")"
HW=ally PKG=absent run_guard apply
[[ ! -e $dropin ]] || fail "removing the gaming package removes autologin"
pass "laptops and a removed variant get no autologin drop-in"
