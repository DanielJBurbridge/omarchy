#!/bin/bash
# Steam's saved-token logon was starting before Wi-Fi was fully up, and
# closing the sign-in screen was recorded as Switch to Desktop. The wrapper
# waits for NetworkManager. unknown connectivity does not wait. The first
# desktop request before the ready marker relaunches Gaming; the second opens
# the desktop. Ready clears that count.

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
    kill -- -"$session_pid" 2>/dev/null || kill "$session_pid" 2>/dev/null || true
    wait "$session_pid" 2>/dev/null || true
  fi
  rm -rf "$work" "${HANDHELD_RUNTIME:-}" "${HANDHELD_HOME:-}"
}
trap cleanup EXIT

home=$work/home
runtime=$work/runtime
state_dir=$home/.local/state/omarchy/gaming-session
stub=$work/stub
mkdir -p "$state_dir" "$runtime" "$stub"
chmod 700 "$runtime"

cat > "$stub/steam" <<'EOF'
#!/bin/bash
printf 'steam:%s\n' "$*" >> "$WAIT_LOG"
exit 0
EOF
cat > "$stub/nm-online" <<'EOF'
#!/bin/bash
printf 'nm-online:%s\n' "$*" >> "$WAIT_LOG"
sleep 0.2
exit 1
EOF
cat > "$stub/nmcli" <<'EOF'
#!/bin/bash
printf 'nmcli:%s\n' "$*" >> "$WAIT_LOG"
printf 'full\n'
exit 0
EOF
chmod +x "$stub/steam" "$stub/nm-online" "$stub/nmcli"

run_wrapper() {
  local timeout=$1
  : > "$work/wait.log"
  : > "$state_dir/fallback.log"
  rm -f "$state_dir/fallback.log"
  env \
    HOME="$home" \
    XDG_STATE_HOME="$home/.local/state" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_GAMING_RUNTIME="$runtime" \
    OMARCHY_GAMING_NETWORK_TIMEOUT="$timeout" \
    DISPLAY=:9 \
    WAIT_LOG="$work/wait.log" \
    PATH="$stub:$ROOT/bin:/usr/bin:/bin" \
    "$ROOT/bin/omarchy-gaming-steam" >"$work/wrap-out" 2>"$work/wrap-err"
}

wrap_detail() {
  echo '--- wait log ---'
  cat "$work/wait.log" 2>/dev/null || true
  echo '--- fallback ---'
  cat "$state_dir/fallback.log" 2>/dev/null || true
  echo '--- stderr ---'
  cat "$work/wrap-err" 2>/dev/null || true
}

run_wrapper 30 || fail "Steam did not launch after the connectivity timeout" "$(wrap_detail)"
grep -q 'nm-online:-q -t 30' "$work/wait.log" || fail "the connectivity wait did not call nm-online -q -t 30" "$(wrap_detail)"
grep -q 'steam:-steamos3 -steampal -steamdeck -gamepadui' "$work/wait.log" ||
  fail "the connectivity timeout did not launch Steam" "$(wrap_detail)"
online_line=$(grep -n '^nm-online:' "$work/wait.log" | head -1 | cut -d: -f1)
steam_line=$(grep -n '^steam:' "$work/wait.log" | head -1 | cut -d: -f1)
if [[ -z $online_line || -z $steam_line ]] || (( online_line >= steam_line )); then
  fail "Steam launched before the connectivity wait returned" "$(wrap_detail)"
fi
[[ $(cat "$state_dir/fallback.log" 2>/dev/null) == 'network connectivity wait timed out after 30s; launching Steam anyway.' ]] ||
  fail "the connectivity timeout did not log one line" "$(wrap_detail)"
pass "a connectivity timeout still launches Steam and logs one line"

cat > "$stub/nm-online" <<'EOF'
#!/bin/bash
printf 'nm-online:%s\n' "$*" >> "$WAIT_LOG"
exit 0
EOF
cat > "$stub/nmcli" <<'EOF'
#!/bin/bash
printf 'nmcli\n' >> "$WAIT_LOG"
printf 'none\n'
exit 0
EOF
chmod +x "$stub/nm-online" "$stub/nmcli"
run_wrapper 2 || fail "Steam did not launch when connectivity stayed short of full" "$(wrap_detail)"
nmcli_calls=$(grep -c '^nmcli$' "$work/wait.log" || true)
(( nmcli_calls >= 1 )) || fail "a site-only link did not ask nmcli for full" "$(wrap_detail)"
grep -q 'steam:-steamos3 -steampal -steamdeck -gamepadui' "$work/wait.log" ||
  fail "Steam did not launch when connectivity stayed short of full" "$(wrap_detail)"
[[ $(cat "$state_dir/fallback.log" 2>/dev/null) == 'network connectivity wait timed out after 2s; launching Steam anyway.' ]] ||
  fail "a site-only link was treated as full connectivity" "$(wrap_detail)"
pass "nm-online success still waits until connectivity is full"

cat > "$stub/nmcli" <<'EOF'
#!/bin/bash
printf 'nmcli\n' >> "$WAIT_LOG"
printf 'unknown\n'
exit 0
EOF
cat > "$stub/timeout" <<'EOF'
#!/bin/bash
printf 'timeout:%s\n' "$*" >> "$WAIT_LOG"
exec /usr/bin/timeout "$@"
EOF
chmod +x "$stub/nmcli" "$stub/timeout"
run_wrapper 5 || fail "Steam did not launch when connectivity was unknown" "$(wrap_detail)"
nmcli_calls=$(grep -c '^nmcli$' "$work/wait.log" || true)
(( nmcli_calls == 1 )) || fail "unknown connectivity was polled instead of treated as online" "$(wrap_detail)"
grep -q '^timeout:2 nmcli networking connectivity$' "$work/wait.log" ||
  fail "the connectivity read was not capped with timeout" "$(wrap_detail)"
grep -q 'steam:-steamos3 -steampal -steamdeck -gamepadui' "$work/wait.log" ||
  fail "Steam did not launch when connectivity was unknown" "$(wrap_detail)"
[[ ! -e $state_dir/fallback.log ]] ||
  fail "unknown connectivity waited out the budget" "$(wrap_detail)"
pass "unknown connectivity launches Steam without waiting"

handheld_prepare_gaming "$work/session"
cat > "$HANDHELD_STUB/steam" <<'EOF'
#!/bin/bash
launches=$(grep -c '^steam$' "$HANDHELD_ACTIONS" 2>/dev/null || true)
printf 'steam\n' >> "$HANDHELD_ACTIONS"
if [[ $launches == 0 ]]; then
  steamos-session-select plasma
  exit 0
fi
printf 'relaunch\n' >> "$HANDHELD_ACTIONS"
while [[ ! -f $HANDHELD_RELEASE ]]; do
  sleep 0.05
done
timeout 2 bash -c 'printf "started\n" > "$1"' _ "$OMARCHY_GAMING_RUNTIME/ready" || true
last=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/gaming-session/last
for _ in $(seq 1 80); do
  [[ $(cat "$last" 2>/dev/null || true) == gaming ]] && break
  sleep 0.05
done
steamos-session-select plasma
exit 0
EOF
chmod +x "$HANDHELD_STUB/steam"
handheld_gaming_env
export OMARCHY_GAMING_READY_TIMEOUT=30
export HANDHELD_RELEASE=$work/session/release

state=$HANDHELD_HOME/.local/state/omarchy/gaming-session
detail() {
  echo '--- actions ---'
  cat "$HANDHELD_LOG" 2>/dev/null || true
  echo '--- last ---'
  cat "$state/last" 2>/dev/null || true
  echo '--- next ---'
  cat "$state/next" 2>/dev/null || true
  echo '--- fallback ---'
  cat "$state/fallback.log" 2>/dev/null || true
  echo '--- early-returns ---'
  cat "$state/early-returns" 2>/dev/null || true
  echo '--- session log ---'
  cat "$state/session.log" 2>/dev/null || true
  echo '--- stderr ---'
  cat "$work/session-err" 2>/dev/null || true
  echo '--- cap stderr ---'
  cat "$work/cap-err" 2>/dev/null || true
}

setsid timeout 12 "$HANDHELD_TREE/bin/omarchy-session-start" gaming >"$work/session-out" 2>"$work/session-err" &
session_pid=$!
spins=0
while (( spins < 80 )); do
  grep -q '^relaunch$' "$HANDHELD_LOG" && break
  sleep 0.05
  spins=$((spins + 1))
done
grep -q '^relaunch$' "$HANDHELD_LOG" ||
  fail "a desktop request before Steam was ready did not relaunch Gaming" "$(detail)"
[[ $(cat "$state/early-returns" 2>/dev/null || true) == 1 ]] ||
  fail "the first pre-ready desktop request did not count as one" "$(detail)"
choice=$(cat "$state/last" 2>/dev/null || true)
[[ $choice != desktop ]] ||
  fail "a desktop request before Steam was ready wrote last=desktop" "$(detail)"
[[ ! -e $state/next ]] ||
  fail "a desktop request before Steam was ready wrote next=desktop" "$(detail)"
grep -q 'relaunching the gaming session' "$state/fallback.log" ||
  fail "a pre-ready desktop request was not logged" "$(detail)"
if [[ -f $state/session.log ]] && grep -F 'Requested return to desktop.' "$state/session.log" >/dev/null; then
  fail "a pre-ready desktop request was logged as Switch to Desktop" "$(detail)"
fi
touch "$HANDHELD_RELEASE"
wait "$session_pid" || true
session_pid=
[[ $(cat "$state/last" 2>/dev/null) == desktop ]] ||
  fail "Switch to Desktop after Steam was ready did not write last=desktop" "$(detail)"
grep -F 'Requested return to desktop.' "$state/session.log" >/dev/null ||
  fail "Switch to Desktop after Steam was ready did not reach the return path" "$(detail)"
grep -q '^uwsm:' "$HANDHELD_LOG" ||
  fail "Switch to Desktop after Steam was ready did not start Hyprland" "$(detail)"
[[ ! -e $state/early-returns ]] ||
  fail "Steam becoming ready did not clear the early-return count" "$(detail)"
pass "a desktop request before Steam is ready relaunches Gaming, and one after ready still returns"

: > "$HANDHELD_LOG"
rm -f "$state/fallback.log" "$state/last" "$state/next" "$state/early-returns" "$state/session.log"
cat > "$HANDHELD_STUB/steam" <<'EOF'
#!/bin/bash
printf 'steam\n' >> "$HANDHELD_ACTIONS"
steamos-session-select plasma
exit 0
EOF
cat > "$HANDHELD_STUB/omarchy-notification-send" <<'EOF'
#!/bin/bash
printf 'notify:%s\n' "$*" >> "$HANDHELD_ACTIONS"
exit 0
EOF
chmod +x "$HANDHELD_STUB/steam" "$HANDHELD_STUB/omarchy-notification-send"
setsid timeout 12 "$HANDHELD_TREE/bin/omarchy-session-start" gaming >"$work/cap-out" 2>"$work/cap-err" &
session_pid=$!
wait "$session_pid" || true
session_pid=
steam_n=$(grep -c '^steam$' "$HANDHELD_LOG" || true)
(( steam_n == 2 )) ||
  fail "the second pre-ready desktop request did not stop relaunching" "$(detail)"
[[ $(cat "$state/last" 2>/dev/null) == desktop ]] ||
  fail "the second pre-ready desktop request did not write last=desktop" "$(detail)"
[[ $(cat "$state/early-returns" 2>/dev/null || true) == 2 ]] ||
  fail "the second pre-ready desktop request was not counted" "$(detail)"
grep -q 'relaunching the gaming session' "$state/fallback.log" ||
  fail "the first pre-ready desktop request did not relaunch" "$(detail)"
grep -q 'Steam was not ready' "$state/fallback.log" ||
  fail "the second pre-ready desktop request did not say Steam was not ready" "$(detail)"
grep -q '^notify:Steam was not ready Opening the desktop.$' "$HANDHELD_LOG" ||
  fail "the second pre-ready desktop request did not notify" "$(detail)"
grep -F 'Requested return to desktop.' "$state/session.log" >/dev/null ||
  fail "the second pre-ready desktop request did not reach the return path" "$(detail)"
grep -q '^uwsm:' "$HANDHELD_LOG" ||
  fail "the second pre-ready desktop request did not start Hyprland" "$(detail)"
pass "the second pre-ready desktop request opens the desktop"
