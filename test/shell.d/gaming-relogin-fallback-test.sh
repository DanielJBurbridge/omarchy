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
  if (( EUID == 0 )); then
    setpriv --reuid=65534 --regid=65534 --clear-groups "$@"
  else
    "$@"
  fi
}
if refuse "$ROOT/bin/omarchy-handheld-autologin" fail >"$work/noop-out" 2>"$work/noop-err"; then
  fail "fail without a passwordless root grant is a silent success"
fi
grep -q 'needs root' "$work/noop-err" ||
  fail "a refused fail does not say why" "$(cat "$work/noop-err" 2>/dev/null)"
pass "a fail that cannot become root is logged and returns non-zero"

handheld_prepare_gaming "$work"
cat > "$HANDHELD_STUB/uwsm" <<'EOF'
#!/bin/bash
printf 'uwsm:%s\n' "$*" >> "$HANDHELD_ACTIONS"
python3 - <<'PY'
import os, socket
rt = os.environ["XDG_RUNTIME_DIR"]
hypr = os.path.join(rt, "hypr", "fallback")
os.makedirs(hypr, exist_ok=True)
paths = [os.path.join(hypr, ".socket.sock"), os.path.join(rt, "wayland-1")]
for path in paths:
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(path)
    sock.listen(1)
PY
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
exit 0
EOF
chmod +x "$HANDHELD_STUB/uwsm" "$HANDHELD_STUB/omarchy-toggle-desktop-keyboard" \
  "$HANDHELD_STUB/omarchy-inputplumber-profile"
handheld_gaming_env

state=$HANDHELD_HOME/.local/state/omarchy/gaming-session
failures=$state/start-failures
latch='Gaming failed repeatedly; desktop selected until an explicit gaming choice.'

reset_case() {
  rm -rf "$HANDHELD_HOME/.local/state"
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
grep -q '^profile:load osk$' "$HANDHELD_LOG" ||
  fail "the fail limit does not load the on-screen keyboard profile" "$(detail "$work/limit-err")"
grep -q '^osk:show:fallback:wayland-1$' "$HANDHELD_LOG" ||
  fail "the fail limit does not show the on-screen keyboard" "$(detail "$work/limit-err")"
[[ $(cat "$state/recovery" 2>/dev/null) == "$latch" ]] ||
  fail "the fail limit does not record its recovery latch" "$(detail "$work/limit-err")"
: > "$HANDHELD_LOG"
run_session "$work/again-err" relogin
[[ $(cat "$failures" 2>/dev/null) == 3 ]] ||
  fail "a later fallback counts as another failure" "$(detail "$work/again-err")"
if grep -q '^gamescope$' "$HANDHELD_LOG"; then
  fail "a later fallback starts Gamescope" "$(detail "$work/again-err")"
fi
[[ $(cat "$state/recovery" 2>/dev/null) == "$latch" ]] ||
  fail "a later fallback drops the recovery latch" "$(detail "$work/again-err")"
pass "three early exits open the desktop with the on-screen keyboard and do not loop"

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

# desktop-lock on, no physical keyboard. The fail-limit path must not open an
# unlocked Hyprland. It logs, pins Relogin off, and exits to the greeter.
# The lock file is root-owned; a user-owned copy is not the setting.
reset_case
cat > "$HANDHELD_STUB/steam" <<'EOF'
#!/bin/bash
printf 'steam\n' >> "$HANDHELD_ACTIONS"
exit 1
EOF
cat > "$HANDHELD_STUB/omarchy-hw-physical-keyboard" <<'EOF'
#!/bin/bash
exit 1
EOF
cat > "$HANDHELD_STUB/omarchy-pkg-present" <<'EOF'
#!/bin/bash
exit 0
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
mkdir -p "$state" "$work/sddm" "$work/run"
printf '2\n' > "$failures"
: > "$HANDHELD_LOG"
export SUDO_USER=ally AUTOLOGIN_FAKE_HOME=$HANDHELD_HOME
export OMARCHY_HANDHELD_AUTOLOGIN_DIR=$work/run OMARCHY_SDDM_CONF_DIR=$work/sddm
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
setsid timeout 12 "$HANDHELD_TREE/bin/omarchy-session-start" relogin >"$work/lock-out" 2>"$work/lock-err"
printf '%s\n' "\$?" > "$work/lock-status"
EOF
if (( EUID == 0 )); then
  bash "$work/lock-case.sh" || true
else
  unshare --user --map-root-user --map-auto bash "$work/lock-case.sh" || true
fi
lock_status=$(cat "$work/lock-status" 2>/dev/null || true)
lock_detail=$(
  echo "status=$lock_status"
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
[[ -n $lock_status && $lock_status != 0 && $lock_status != 124 ]] ||
  fail "a locked fail-limit desktop does not exit to the greeter" "$lock_detail"
if grep -q '^uwsm:' "$HANDHELD_LOG"; then
  fail "desktop-lock on with no keyboard starts an unlocked Hyprland" "$lock_detail"
fi
if grep -q '^osk:' "$HANDHELD_LOG"; then
  fail "the refused fail-limit desktop starts the on-screen keyboard" "$lock_detail"
fi
if grep -q '^gamescope$' "$HANDHELD_LOG"; then
  fail "the refused fail-limit desktop starts Gamescope" "$lock_detail"
fi
grep -q 'not starting the fail-limit desktop' "$state/session.log" ||
  fail "the refused fail-limit desktop does not say the lock stopped it" "$lock_detail"
grep -q '^Relogin=false$' "$work/sddm/zz-omarchy-handheld.conf" ||
  fail "the refused fail-limit desktop does not pin Relogin off" "$lock_detail"
[[ -f $work/run/stop ]] || fail "the refused fail-limit desktop does not write the autologin stop"
[[ ! -e $work/run/actions ]] || ! grep -q 'sddm-restart' "$work/run/actions" ||
  fail "pinning Relogin off restarts SDDM" "$(cat "$work/run/actions" 2>/dev/null)"
unset SUDO_USER AUTOLOGIN_FAKE_HOME OMARCHY_HANDHELD_AUTOLOGIN_DIR OMARCHY_SDDM_CONF_DIR
pass "desktop-lock on with no keyboard leaves the greeter instead of an unlocked desktop"
