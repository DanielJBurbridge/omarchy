#!/bin/bash
# Switch to Desktop must lock before Hyprland. The release-tip supervisor
# starts uwsm with no lock after gaming returns, including after a gamescope
# suspend where nothing was locked. Left failing for dev-blue.

set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$here/../shell.d/base-test.sh"
source "$here/gaming-fixture.sh"

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

handheld_prepare_gaming "$work"
cat > "$HANDHELD_STUB/steam" <<'EOF'
#!/bin/bash
printf 'steam:%s\n' "$*" >> "$HANDHELD_ACTIONS"
steamos-session-select plasma
printf 'select:%s\n' "$?" >> "$HANDHELD_ACTIONS"
exit 0
EOF
chmod +x "$HANDHELD_STUB/steam"

handheld_gaming_env
setsid timeout 8 "$HANDHELD_TREE/bin/omarchy-session-start" gaming >"$work/out" 2>"$work/err" &
session_pid=$!
wait "$session_pid" || true
status=$?
session_pid=

log=$HANDHELD_HOME/.local/state/omarchy/gaming-session/session.log
detail=$(
  printf 'status:%s\n' "$status"
  echo '--- actions ---'
  cat "$HANDHELD_LOG"
  echo '--- session log ---'
  cat "$log" 2>/dev/null || true
  echo '--- stderr ---'
  cat "$work/err"
)

grep -F 'Requested return to desktop.' "$log" >/dev/null 2>&1 || fail "Switch to Desktop reaches the gaming return path" "$detail"
grep -q '^uwsm:' "$HANDHELD_LOG" || fail "Switch to Desktop starts Hyprland" "$detail"

uwsm_line=$(grep -n '^uwsm:' "$HANDHELD_LOG" | head -1 | cut -d: -f1)
lock_line=$(grep -n -E '^(lock|sleep-lock):' "$HANDHELD_LOG" | head -1 | cut -d: -f1 || true)
if [[ -n $lock_line ]] && (( lock_line < uwsm_line )); then
  pass "Switch to Desktop locks the session before Hyprland"
  exit 0
fi
fail "Switch to Desktop locks the session before Hyprland" "$detail"
