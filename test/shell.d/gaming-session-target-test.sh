#!/bin/bash
# The gamescope session pulls omarchy-gaming-session.target in when it
# starts and stops that target before the desktop session starts.

set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$here/base-test.sh"
source "$here/../handheld/gaming-fixture.sh"

unit=$ROOT/default/systemd/user/omarchy-gaming-session.target
name=$(basename "$unit")
[[ $name == omarchy-gaming-session.target ]] || fail "gaming session unit has the expected name" "$name"
[[ -f $unit ]] || fail "gaming session unit is shipped with the other user units"
grep -q '^Description=Omarchy handheld gaming session$' "$unit" ||
  fail "gaming session unit describes the handheld session"
if grep -q '^\[Service\]' "$unit"; then
  fail "gaming session unit is a plain target"
fi
pass "omarchy-gaming-session.target is a plain user target"

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
exit 0
EOF
chmod +x "$HANDHELD_STUB/steam"
handheld_gaming_env
setsid timeout 8 "$HANDHELD_TREE/bin/omarchy-session-start" gaming >"$work/out" 2>"$work/err" &
session_pid=$!
wait "$session_pid" || true
session_pid=

start_line=$(grep -n 'systemctl:--user start omarchy-gaming-session.target' "$HANDHELD_LOG" | head -1 | cut -d: -f1)
stop_line=$(grep -n 'systemctl:--user stop omarchy-gaming-session.target' "$HANDHELD_LOG" | head -1 | cut -d: -f1)
gamescope_line=$(grep -n '^gamescope$' "$HANDHELD_LOG" | head -1 | cut -d: -f1)
desktop_line=$(grep -n '^uwsm:' "$HANDHELD_LOG" | head -1 | cut -d: -f1)
detail=$(
  echo '--- actions ---'
  cat "$HANDHELD_LOG"
  echo '--- stderr ---'
  cat "$work/err"
)
if [[ -z $start_line || -z $gamescope_line ]] || (( start_line >= gamescope_line )); then
  fail "gamescope session start pulls in omarchy-gaming-session.target" "$detail"
fi
if [[ -z $stop_line || -z $desktop_line ]] || (( stop_line <= gamescope_line || stop_line >= desktop_line )); then
  fail "switching to the desktop stops omarchy-gaming-session.target first" "$detail"
fi
pass "gamescope start pulls in the target and the desktop switch stops it"

# A machine that is not the handheld never enters the gaming supervisor.
printf 'Dell Inc.\n' > "$work/dmi/sys_vendor"
printf 'XPS 13\n' > "$work/dmi/product_name"
printf '0A1B\n' > "$work/dmi/board_name"
: > "$HANDHELD_LOG"
setsid timeout 8 "$HANDHELD_TREE/bin/omarchy-session-start" preferred >"$work/laptop-out" 2>"$work/laptop-err" &
session_pid=$!
wait "$session_pid" || true
session_pid=
if grep -q 'omarchy-gaming-session.target' "$HANDHELD_LOG"; then
  fail "a non-handheld session does not pull in the gaming target" "$(cat "$HANDHELD_LOG")"
fi
grep -q '^uwsm:' "$HANDHELD_LOG" || fail "a non-handheld session still starts the desktop" "$(cat "$HANDHELD_LOG")"
pass "the gaming session target stays on the handheld path"
