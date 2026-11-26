#!/bin/bash
# Failed gaming starts accumulate in the state directory, including an early
# exit and a supervisor killed with SIGKILL. The third one opens the Hyprland
# desktop with the on-screen keyboard and does not start Gamescope again.
# Ready, and an explicit Switch to Desktop, clear the count. A fail that
# cannot become root says why and returns non-zero.

set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$here/base-test.sh"
# shellcheck source=/dev/null
source "$here/../handheld/gaming-fixture.sh"

work=$(mktemp -d)
session_pid=
cleanup() {
  if [[ -n $session_pid ]]; then
    kill -9 -- -"$session_pid" 2>/dev/null || kill -9 -- "$session_pid" 2>/dev/null || true
    wait "$session_pid" 2>/dev/null || true
  fi
  rm -rf "$work" "${HANDHELD_RUNTIME:-}" "${HANDHELD_HOME:-}"
}
trap cleanup EXIT

refuse() {
  local -a identity=()
  if (( EUID == 0 )); then
    identity=(--reuid=65534 --regid=65534 --clear-groups)
  fi
  # This refusal must also hold on a development Ally with the real sudo grant.
  setpriv --no-new-privs "${identity[@]}" "$@"
}
if refuse "$ROOT/bin/omarchy-handheld-autologin" fail >"$work/noop-out" 2>"$work/noop-err"; then
  fail "fail without a passwordless root grant is a silent success"
fi
grep -q 'needs root' "$work/noop-err" ||
  fail "a refused fail does not say why" "$(cat "$work/noop-err" 2>/dev/null)"
pass "a fail that cannot become root is logged and returns non-zero"

handheld_prepare_gaming "$work"
export OMARCHY_HANDHELD_AUTOLOGIN_DIR=$work/run OMARCHY_SDDM_CONF_DIR=$work/sddm
cp "$ROOT/bin/omarchy-handheld-autologin" "$HANDHELD_TREE/bin/"
cp "$ROOT/default/gaming/sddm-user.sh" "$HANDHELD_TREE/default/gaming/"
sed -i "s|/usr/share/omarchy/default/gaming/session.sh|$HANDHELD_TREE/default/gaming/session.sh|" \
  "$HANDHELD_TREE/bin/omarchy-handheld-autologin"
sed -i "s|/etc/sddm.conf.d/zz-omarchy-handheld.conf|$work/sddm/zz-omarchy-handheld.conf|" \
  "$HANDHELD_TREE/bin/omarchy-session-start"
sed -i "s|exec -c /usr/bin/loginctl|exec \"$HANDHELD_STUB/loginctl\"|" \
  "$HANDHELD_TREE/bin/omarchy-session-start"
cat > "$HANDHELD_STUB/uwsm" <<'EOF'
#!/bin/bash
printf 'uwsm:%s\n' "$*" >> "$HANDHELD_ACTIONS"
if [[ ${HANDHELD_LOGIN_SERVICE:-} == sddm ]]; then
  managed_runtime=$XDG_RUNTIME_DIR/omarchy-gaming-$OMARCHY_HANDHELD_SESSION
  printf 'managed:%s:%s\n' "$OMARCHY_HANDHELD_SESSION" "$(cat "$managed_runtime/active")" >> "$HANDHELD_ACTIONS"
  if [[ ${HANDHELD_AUTH_ROUND_TRIP:-} == 1 ]]; then
    printf '%s\n' gaming > "$managed_runtime/switch"
  fi
fi
python3 - <<'PY'
import os, socket
rt = os.environ["XDG_RUNTIME_DIR"]
hypr = os.path.join(rt, "hypr", "fallback")
os.makedirs(hypr, exist_ok=True)
paths = [os.path.join(hypr, ".socket.sock"), os.path.join(rt, "wayland-0"), os.path.join(rt, "wayland-1")]
for path in paths:
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(path)
    sock.listen(1)
PY
if [[ ${HANDHELD_EXPLICIT_RETRY:-0} == 1 ]]; then
  retry_runtime=$XDG_RUNTIME_DIR/omarchy-gaming-$XDG_SESSION_ID
  if flock -n "$retry_runtime/lock" true; then
    printf '%s\n' 'Recovery desktop has no supervisor lock' >> "$HANDHELD_ACTIONS"
  fi
  "$ROOT/default/gaming/switch.sh" "$retry_runtime" || true
fi
exit 0
EOF
cat > "$HANDHELD_STUB/omarchy-toggle-desktop-keyboard" <<'EOF'
#!/bin/bash
printf 'osk:%s:%s:%s\n' "$*" "${HYPRLAND_INSTANCE_SIGNATURE:-}" "${WAYLAND_DISPLAY:-}" >> "$HANDHELD_ACTIONS"
exit 0
EOF
cat > "$HANDHELD_STUB/omarchy-inputplumber-profile" <<'EOF'
#!/bin/bash
printf 'profile:%s\n' "$*" >> "$HANDHELD_ACTIONS"
exit 1
EOF
cat > "$HANDHELD_STUB/hyprctl" <<'EOF'
#!/bin/bash
[[ $* == "instances -j" ]] || exit 1
printf '%s\n' '[{"instance":"unrelated","wl_socket":"wayland-0"},{"instance":"fallback","wl_socket":"wayland-1"}]'
EOF
cat > "$HANDHELD_STUB/omarchy-pkg-present" <<'EOF'
#!/bin/bash
[[ $* == omarchy-gaming-session ]]
EOF
cat > "$HANDHELD_STUB/busctl" <<'EOF'
#!/bin/bash
[[ $* == '--timeout=3s --auto-start=no call org.omarchy.InputPlumberProfile /org/omarchy/InputPlumberProfile org.omarchy.InputPlumberProfile Load s '* ]] || exit 1
printf 'broker:%s\n' "${@: -1}" >> "$HANDHELD_ACTIONS"
if [[ ${@: -1} == "osk" ]]; then
  exit "${HANDHELD_OSK_BROKER_STATUS:-0}"
fi
EOF
chmod +x "$HANDHELD_STUB/uwsm" "$HANDHELD_STUB/omarchy-toggle-desktop-keyboard" \
  "$HANDHELD_STUB/omarchy-inputplumber-profile" "$HANDHELD_STUB/omarchy-pkg-present" \
  "$HANDHELD_STUB/busctl" "$HANDHELD_STUB/hyprctl"
handheld_gaming_env

state=$HANDHELD_HOME/.local/state/omarchy/gaming-session
failures=$state/start-failures
latch='Gaming failed repeatedly; desktop selected until an explicit gaming choice.'

reset_case() {
  rm -rf "$HANDHELD_HOME/.local/state" "$work/run" "$work/sddm"
  : > "$HANDHELD_LOG"
  rm -f "$HANDHELD_SCOPE_PID"
}

detail() {
  echo '--- actions ---'
  cat "$HANDHELD_LOG" 2>/dev/null || true
  echo '--- stderr ---'
  cat "$1" 2>/dev/null || true
  echo '--- failures ---'
  cat "$failures" 2>/dev/null || true
  echo '--- recovery ---'
  cat "$state/recovery" 2>/dev/null || true
}

run_session() {
  local err=$1
  shift
  rm -rf "$HANDHELD_RUNTIME/hypr"
  rm -f "$HANDHELD_RUNTIME"/wayland-*
  setsid timeout 12 "$HANDHELD_TREE/bin/omarchy-session-start" "$@" >"$work/out" 2>"$err" &
  session_pid=$!
  wait "$session_pid" || true
  session_pid=
}

# shellcheck source=/dev/null
source "$ROOT/default/gaming/session.sh"
mkdir -p "$state"
printf '%s\n' "$latch" > "$state/recovery"
[[ $(gaming_entry_selection relogin) == desktop ]] ||
  fail "Relogin ignores the fail-limit latch"
[[ $(cat "$state/recovery") == "$latch" ]] || fail "Relogin deletes the fail-limit latch"
printf 'failed\n' > "$state/recovery"
[[ $(gaming_entry_selection relogin) == gaming ]] ||
  fail "Relogin treats an ordinary recovery latch as the fail limit"
pass "Relogin honours only the fail-limit latch"

reset_case
cat > "$HANDHELD_STUB/steam" <<'EOF'
#!/bin/bash
printf 'steam\n' >> "$HANDHELD_ACTIONS"
exit 1
EOF
chmod +x "$HANDHELD_STUB/steam"
run_session "$work/early-err" relogin
[[ $(cat "$failures" 2>/dev/null) == 2 ]] ||
  fail "an early exit and its retry count as two failed starts" "$(detail "$work/early-err")"
[[ $(cat "$state/recovery" 2>/dev/null) == 'Steam or Gamescope exited; desktop selected until an explicit gaming choice.' ]] ||
  fail "two failed starts still use the ordinary recovery latch" "$(detail "$work/early-err")"
grep -q '^gamescope$' "$HANDHELD_LOG" || fail "the first failed starts do not run Gamescope" "$(detail "$work/early-err")"
: > "$HANDHELD_LOG"
run_session "$work/limit-err" relogin
[[ $(cat "$failures" 2>/dev/null) == 3 ]] ||
  fail "the third failed start is the fail limit" "$(detail "$work/limit-err")"
if grep -q '^gamescope$' "$HANDHELD_LOG"; then
  fail "the fail limit still starts Gamescope" "$(detail "$work/limit-err")"
fi
grep -q '^uwsm:start -g -1 -e -D Hyprland hyprland.desktop$' "$HANDHELD_LOG" ||
  fail "the fail limit does not start the Hyprland desktop" "$(detail "$work/limit-err")"
mapfile -t profile_actions < <(grep -E '^(broker:|uwsm:|profile:)' "$HANDHELD_LOG")
if [[ ${profile_actions[0]:-} != "broker:osk" || ${profile_actions[1]:-} != uwsm:* ||
      ${profile_actions[2]:-} != "broker:pointer" ]] || grep -q '^profile:' "$HANDHELD_LOG"; then
  fail "recovery loads the OSK profile through the broker before Hyprland and restores the greeter pointer afterward" "$(detail "$work/limit-err")"
fi
grep -q '^osk:show:fallback:wayland-1$' "$HANDHELD_LOG" ||
  fail "recovery shows the keyboard on its own compositor rather than an unrelated Wayland display" "$(detail "$work/limit-err")"
[[ $(cat "$state/recovery" 2>/dev/null) == "$latch" ]] ||
  fail "the fail limit does not record its recovery latch" "$(detail "$work/limit-err")"
: > "$HANDHELD_LOG"
HANDHELD_OSK_BROKER_STATUS=1 run_session "$work/again-err" relogin
[[ $(cat "$failures" 2>/dev/null) == 3 ]] ||
  fail "a later fallback counts as another failure" "$(detail "$work/again-err")"
if grep -q '^gamescope$' "$HANDHELD_LOG"; then
  fail "a later fallback starts Gamescope" "$(detail "$work/again-err")"
fi
[[ $(cat "$state/recovery" 2>/dev/null) == "$latch" ]] ||
  fail "a later fallback drops the recovery latch" "$(detail "$work/again-err")"
grep -q '^broker:osk$' "$HANDHELD_LOG" && ! grep -q '^broker:pointer$' "$HANDHELD_LOG" &&
  grep -q '^osk:show:fallback:wayland-1$' "$HANDHELD_LOG" ||
  fail "a denied profile switch leaves the recovery touch keyboard available and does not overwrite the previous profile" "$(detail "$work/again-err")"
pass "three early exits open the desktop with the on-screen keyboard and do not loop"

mkdir -p "$work/retry-stop"
printf 'stop\n' > "$work/retry-stop/stop"
cat > "$HANDHELD_STUB/omarchy-system" <<'EOF'
#!/bin/bash
printf 'system:%s\n' "$*" >> "$HANDHELD_ACTIONS"
[[ $* == 'logout --execute' ]]
EOF
chmod +x "$HANDHELD_STUB/omarchy-system"
: > "$HANDHELD_LOG"
HANDHELD_EXPLICIT_RETRY=1 OMARCHY_HANDHELD_AUTOLOGIN_DIR=$work/retry-stop run_session "$work/retry-err" relogin
[[ $(grep -c '^system:logout --execute$' "$HANDHELD_LOG") == 1 &&
   $(grep -c '^gamescope$' "$HANDHELD_LOG") == 1 &&
   $(grep -c '^uwsm:' "$HANDHELD_LOG") == 2 ]] ||
  fail "one explicit Switch to Gaming from recovery launches once and falls back on failure" "$(detail "$work/retry-err")"
if grep -q '^Recovery desktop has no supervisor lock$' "$HANDHELD_LOG"; then
  fail "the recovery desktop must hold the supervisor lock" "$(detail "$work/retry-err")"
fi
[[ $(cat "$work/retry-stop/stop") == stop && $(cat "$state/recovery") == "$latch" &&
   ! -e $HANDHELD_RUNTIME/omarchy-gaming-$XDG_SESSION_ID/active &&
   ! -e $HANDHELD_RUNTIME/omarchy-gaming-$XDG_SESSION_ID/switch ]] ||
  fail "a failed retry preserves both stops without leaving an active switch request" "$(detail "$work/retry-err")"
pass "recovery desktop accepts one explicit retry while the autologin stop stays in effect"

reset_case
mkdir -p "$state"
printf '1\n' > "$failures"
cat > "$HANDHELD_STUB/steam" <<'EOF'
#!/bin/bash
printf 'steam\n' >> "$HANDHELD_ACTIONS"
timeout 2 bash -c 'printf "started\n" > "$1"' _ "$OMARCHY_GAMING_RUNTIME/ready" || true
last=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/gaming-session/last
for _ in $(seq 1 80); do
  [[ -f $last ]] && break
  sleep 0.05
done
steamos-session-select plasma
exit 0
EOF
chmod +x "$HANDHELD_STUB/steam"
run_session "$work/return-err" relogin
[[ ! -e $failures ]] ||
  fail "an explicit Switch to Desktop leaves the failure count" "$(detail "$work/return-err")"
grep -q 'cleared the gaming start failures' "$state/fallback.log" ||
  fail "an explicit Switch to Desktop does not clear the failure count" "$(detail "$work/return-err")"
pass "an explicit Switch to Desktop clears the failure count"

reset_case
mkdir -p "$state"
printf '1\n' > "$failures"
cat > "$HANDHELD_TREE/bin/omarchy-gaming-steam" <<'EOF'
#!/bin/bash
printf 'started\n' > "$OMARCHY_GAMING_RUNTIME/ready"
steam "$@"
status=$?
printf '%s\n' "$status" > "$OMARCHY_GAMING_RUNTIME/steam-exit"
exit "$status"
EOF
chmod +x "$HANDHELD_TREE/bin/omarchy-gaming-steam"
cat > "$HANDHELD_STUB/steam" <<'EOF'
#!/bin/bash
printf 'steam\n' >> "$HANDHELD_ACTIONS"
exit 0
EOF
chmod +x "$HANDHELD_STUB/steam"
run_session "$work/ready-err" relogin
[[ ! -e $failures ]] ||
  fail "a ready session leaves the failure count" "$(detail "$work/ready-err")"
grep -q 'cleared the gaming start failures' "$state/fallback.log" ||
  fail "a ready session does not clear the failure count" "$(detail "$work/ready-err")"
pass "a ready session clears the failure count"

reset_case
cp "$ROOT/bin/omarchy-gaming-steam" "$HANDHELD_TREE/bin/omarchy-gaming-steam"
chmod +x "$HANDHELD_TREE/bin/omarchy-gaming-steam"
cat > "$HANDHELD_STUB/steam" <<'EOF'
#!/bin/bash
printf 'steam\n' >> "$HANDHELD_ACTIONS"
sleep 30
EOF
chmod +x "$HANDHELD_STUB/steam"
kill_supervisor() {
  local want=$1 spins=0 got='' scope=''
  setsid "$HANDHELD_TREE/bin/omarchy-session-start" relogin >"$work/kill-out" 2>"$work/kill-err" &
  session_pid=$!
  while (( spins < 40 )); do
    got=$(cat "$failures" 2>/dev/null || true)
    [[ $got == "$want" ]] && break
    sleep 0.05
    spins=$((spins + 1))
  done
  kill -9 -- -"$session_pid" 2>/dev/null || kill -9 -- "$session_pid" 2>/dev/null || true
  wait "$session_pid" 2>/dev/null || true
  session_pid=
  if [[ -f $HANDHELD_SCOPE_PID ]]; then
    scope=$(cat "$HANDHELD_SCOPE_PID")
    kill -9 -- -"$scope" 2>/dev/null || kill -9 -- "$scope" 2>/dev/null || true
    wait "$scope" 2>/dev/null || true
  fi
}
kill_supervisor 1
[[ $(cat "$failures" 2>/dev/null) == 1 ]] ||
  fail "a SIGKILL before the exit trap does not count" "$(detail "$work/kill-err")"
kill_supervisor 2
[[ $(cat "$failures" 2>/dev/null) == 2 ]] ||
  fail "a second SIGKILL does not count" "$(detail "$work/kill-err")"
: > "$HANDHELD_LOG"
run_session "$work/killed-limit-err" relogin
[[ $(cat "$failures" 2>/dev/null) == 3 ]] ||
  fail "the start after two SIGKILLs is not the fail limit" "$(detail "$work/killed-limit-err")"
if grep -q '^gamescope$' "$HANDHELD_LOG"; then
  fail "the fail limit after SIGKILL still starts Gamescope" "$(detail "$work/killed-limit-err")"
fi
grep -q '^osk:show:fallback:wayland-1$' "$HANDHELD_LOG" ||
  fail "the fail limit after SIGKILL does not show the on-screen keyboard" "$(detail "$work/killed-limit-err")"
pass "a SIGKILLed supervisor counts, and the third start is the desktop"

# A required lock cannot be secured before Hyprland exists, even with a
# physical keyboard. The fail-limit path pins Relogin off and exits.
# The lock file is root-owned; a user-owned copy is not the setting.
cat > "$HANDHELD_STUB/steam" <<'EOF'
#!/bin/bash
printf 'steam\n' >> "$HANDHELD_ACTIONS"
exit 1
EOF
cat > "$HANDHELD_STUB/omarchy-hw-physical-keyboard" <<'EOF'
#!/bin/bash
exit "$HANDHELD_KEYBOARD_STATUS"
EOF
cat > "$HANDHELD_STUB/omarchy-pkg-present" <<'EOF'
#!/bin/bash
[[ $* == omarchy-gaming-session ]]
EOF
cat > "$HANDHELD_STUB/getent" <<'EOF'
#!/bin/bash
if [[ $1 == passwd ]]; then
  printf 'ally:x:1000:1000:ally:%s:/bin/bash\n' "$AUTOLOGIN_FAKE_HOME"
  exit 0
fi
exit 1
EOF
chmod +x "$HANDHELD_STUB/steam" "$HANDHELD_STUB/omarchy-hw-physical-keyboard" \
  "$HANDHELD_STUB/omarchy-pkg-present" "$HANDHELD_STUB/getent"
sed -i "s|^gaming_desktop_lock_file=.*|gaming_desktop_lock_file=$work/desktop-lock|" \
  "$HANDHELD_TREE/default/gaming/session.sh"
sed -i "s|^gaming_k07_marker=.*|gaming_k07_marker=$work/k07-absent|" \
  "$HANDHELD_TREE/default/gaming/session.sh"
export SUDO_USER=ally AUTOLOGIN_FAKE_HOME=$HANDHELD_HOME
cat > "$work/lock-case.sh" <<EOF
#!/bin/bash
set -uo pipefail
printf 'on\n' > "$work/desktop-lock"
chmod 644 "$work/desktop-lock"
owner=\$(stat -c %u -- "$work/desktop-lock")
if [[ \$owner != 0 ]]; then
  printf 'lock owner %s\n' "\$owner" > "$work/lock-err"
  exit 99
fi
rm -rf "$HANDHELD_RUNTIME/hypr"
rm -f "$HANDHELD_RUNTIME"/wayland-*
setsid timeout 12 "$HANDHELD_TREE/bin/omarchy-session-start" "\$@" >"$work/lock-out" 2>"$work/lock-err"
printf '%s\n' "\$?" > "$work/lock-status"
EOF
run_locked_session() {
  if (( EUID == 0 )); then
    bash "$work/lock-case.sh" "${1:-relogin}"
  else
    unshare --user --map-root-user bash "$work/lock-case.sh" "${1:-relogin}"
  fi
}
for keyboard_status in 1 0; do
  reset_case
  rm -f "$work/lock-status"
  mkdir -p "$state" "$work/sddm" "$work/run"
  printf '2\n' > "$failures"
  export HANDHELD_KEYBOARD_STATUS=$keyboard_status
  run_locked_session || true
  lock_status=$(cat "$work/lock-status" 2>/dev/null || true)
  lock_detail=$(
    echo "keyboard-status=$keyboard_status status=$lock_status"
    echo '--- actions ---'
    cat "$HANDHELD_LOG" 2>/dev/null || true
    echo '--- session ---'
    cat "$state/session.log" 2>/dev/null || true
    echo '--- stderr ---'
    cat "$work/lock-err" 2>/dev/null || true
    echo '--- drop-in ---'
    cat "$work/sddm/zz-omarchy-handheld.conf" 2>/dev/null || true
  )
  [[ $lock_status == 99 ]] && fail "the desktop-lock file is not root-owned" "$lock_detail"
  [[ $lock_status == 0 ]] ||
    fail "a locked fail-limit desktop does not exit to the greeter" "$lock_detail"
  if grep -Eq '^(uwsm:|osk:|lock:|broker:|gamescope$)' "$HANDHELD_LOG"; then
    fail "a required lock must not open or try to lock a new desktop from the supervisor" "$lock_detail"
  fi
  grep -q 'not starting the fail-limit desktop' "$state/session.log" ||
    fail "the refused fail-limit desktop does not say the lock stopped it" "$lock_detail"
  grep -q '^Relogin=false$' "$work/sddm/zz-omarchy-handheld.conf" ||
    fail "the refused fail-limit desktop does not pin Relogin off" "$lock_detail"
  [[ -f $work/run/stop ]] || fail "the refused fail-limit desktop does not write the autologin stop"
  [[ ! -e $work/run/actions ]] || ! grep -q 'sddm-restart' "$work/run/actions" ||
    fail "pinning Relogin off restarts SDDM" "$(cat "$work/run/actions" 2>/dev/null)"
done
pass "a required lock returns to the greeter with or without a keyboard"

reset_case
rm -f "$work/lock-status"
mkdir -p "$state" "$work/sddm" "$work/run"
run_locked_session
[[ $(cat "$work/lock-status") == 0 && -s $state/recovery && ! -e $state/next ]] ||
  fail "a failed Gaming launch hands the locked desktop back to SDDM" "$(detail "$work/lock-err")"
grep -qx 'Relogin=false' "$work/sddm/zz-omarchy-handheld.conf" && ! grep -q '^uwsm:' "$HANDHELD_LOG" ||
  fail "a failed Gaming launch requires sign-in before Hyprland" "$(detail "$work/lock-err")"
pass "failed Gaming launches return to protected sign-in"

handheld_late_desktop_return
reset_case
rm -f "$work/lock-status"
mkdir -p "$state" "$work/sddm" "$work/run"
run_locked_session
[[ $(cat "$work/lock-status") == 0 ]] || fail "the requested sign-in handoff exits cleanly" "$(detail "$work/lock-err")"
[[ $(grep -c '^gamescope$' "$HANDHELD_LOG") == 2 ]] || fail "the first pre-ready request relaunches Gaming" "$(detail "$work/lock-err")"
! grep -q '^uwsm:' "$HANDHELD_LOG" || fail "an autologin never starts Hyprland when desktop sign-in is required"
grep -qx 'Relogin=false' "$work/sddm/zz-omarchy-handheld.conf" || fail "SDDM will show sign-in on the next display"
grep -qx 'broker:pointer' "$HANDHELD_LOG" || fail "the greeter gets the pointer profile before sign-out"
grep -Fxq 'steam:shutdown' "$HANDHELD_LOG" && grep -Fxq 'gamescope-child-exit:0' "$HANDHELD_LOG" ||
  fail "a late sign-in request closes Steam gracefully" "$(detail "$work/lock-err")"
[[ ! -e $state/next && ! -e $state/recovery && ! -e $failures && ! -e $work/run/stop ]] ||
  fail "sign-in leaves no passwordless desktop request or crash count" "$(detail "$work/lock-err")"
[[ ! -e $work/run/actions ]] || fail "the sign-in handoff uses the existing SDDM daemon" "$(cat "$work/run/actions")"
pass "the second return after a ready timeout prepares SDDM sign-in without opening Hyprland"

cat > "$HANDHELD_STUB/steam" <<'EOF'
#!/bin/bash
printf 'steam\n' >> "$HANDHELD_ACTIONS"
steamos-session-select plasma
EOF
reset_case
rm -f "$work/lock-status"
mkdir -p "$state" "$work/sddm" "$work/run"
run_locked_session
[[ $(cat "$work/lock-status") == 0 && $(grep -cx gamescope "$HANDHELD_LOG") == 2 ]] ||
  fail "the second pre-ready return exits to sign-in after one retry" "$(detail "$work/lock-err")"
grep -qx 'Relogin=false' "$work/sddm/zz-omarchy-handheld.conf" &&
  grep -Fxq 'broker:pointer' "$HANDHELD_LOG" && ! grep -q '^uwsm:' "$HANDHELD_LOG" ||
  fail "the capped return restores the greeter pointer and requires authentication" "$(detail "$work/lock-err")"
[[ ! -e $state/next && ! -e $state/recovery ]] ||
  fail "the capped return writes no passwordless desktop request" "$(detail "$work/lock-err")"
pass "two pre-ready desktop requests hand the locked desktop back to SDDM"

reset_case
rm -f "$work/lock-status"
mkdir -p "$state" "$work/sddm" "$work/run"
ln -s "$work/refused-dropin" "$work/sddm/zz-omarchy-handheld.conf"
run_locked_session
[[ $(cat "$work/lock-status") == 1 ]] || fail "a refused SDDM update exits with failure" "$(detail "$work/lock-err")"
grep -q 'Could not prepare desktop sign-in' "$state/session.log" || fail "the refused handoff is logged"
! grep -Eq '^(uwsm:|broker:pointer)' "$HANDHELD_LOG" || fail "a refused handoff keeps the desktop closed"
[[ ! -e $state/next && ! -e $work/refused-dropin ]] || fail "a refused handoff writes no unauthenticated desktop request"
pass "a refused SDDM update leaves the desktop closed"

cat > "$HANDHELD_STUB/loginctl" <<'EOF'
#!/bin/bash
[[ $1 == --no-pager && $2 == show-session && $3 == self ]] || exit 2
printf '%s\n' 'Id=authenticated' 'Active=yes' 'Class=user' 'Remote=no' 'Seat=seat0' \
  "Service=$HANDHELD_LOGIN_SERVICE" 'Type=wayland' "User=$UID"
EOF
chmod +x "$HANDHELD_STUB/loginctl"
export XDG_SESSION_ID=stale OMARCHY_HANDHELD_SESSION=unrelated

reset_case
HANDHELD_LOGIN_SERVICE=sddm-autologin run_locked_session authenticated-desktop
[[ $(cat "$work/lock-status") == 1 && ! -s $HANDHELD_LOG ]] || fail "autologin cannot use the authenticated desktop entry"
pass "the managed desktop checks the caller's own PAM service"

reset_case
mkdir -p "$state" "$work/run"
printf '%s\n' 3 > "$failures"
printf '%s\n' stop > "$work/run/stop"
HANDHELD_LOGIN_SERVICE=sddm run_locked_session authenticated-desktop
[[ $(cat "$work/lock-status") == 0 ]] || fail "PAM sign-in starts the managed desktop even after a gaming failure" "$(detail "$work/lock-err")"
grep -Fxq 'managed:authenticated:desktop' "$HANDHELD_LOG" || fail "the desktop uses the current logind session id"
grep -Fxq 'broker:desktop' "$HANDHELD_LOG" || fail "PAM sign-in loads the desktop input profile"
grep -Fxq 'broker:pointer' "$HANDHELD_LOG" || fail "sign-out restores the greeter profile"
[[ $(cat "$failures") == 3 && -f $work/run/stop && ! -f $work/run/failures ]] || fail "desktop-only login leaves gaming failure accounting alone"
pass "password sign-in starts the managed desktop with controller input"

handheld_late_desktop_return
reset_case
mkdir -p "$state"
HANDHELD_LOGIN_SERVICE=sddm HANDHELD_AUTH_ROUND_TRIP=1 run_locked_session authenticated-desktop
[[ $(cat "$work/lock-status") == 0 ]] || fail "the authenticated desktop can switch to Gaming and request sign-in" "$(detail "$work/lock-err")"
[[ $(grep -c '^uwsm:' "$HANDHELD_LOG") == 1 && $(grep -c '^gamescope$' "$HANDHELD_LOG") == 2 ]] ||
  fail "going back to Desktop after Gaming needs a fresh sign-in" "$(detail "$work/lock-err")"
grep -Fxq 'Relogin=false' "$work/sddm/zz-omarchy-handheld.conf" || fail "after Gaming the desktop request reaches the greeter"
pass "the authenticated desktop can switch to Gaming and requires sign-in on return"
