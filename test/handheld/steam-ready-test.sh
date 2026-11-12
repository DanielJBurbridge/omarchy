#!/bin/bash
# The ready fifo is written before Steam is spawned, so the 60s "did
# Gamescope start Steam" check passes immediately. A Steam that never
# becomes usable is then waited on with no desktop fallback. Left failing
# for dev-blue.

set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$here/../shell.d/base-test.sh"
source "$here/gaming-fixture.sh"

work=$(mktemp -d)
child_pid=
cleanup() {
  if [[ -n $child_pid ]]; then
    kill -- -"$child_pid" 2>/dev/null || kill "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
  fi
  rm -rf "$work" "${HANDHELD_RUNTIME:-}" "${HANDHELD_HOME:-}"
}
trap cleanup EXIT

handheld_prepare_gaming "$work"
runtime=$HANDHELD_RUNTIME/omarchy-gaming-redteam
mkdir -p "$runtime"
mkfifo -m 600 "$runtime/ready"

cat > "$HANDHELD_STUB/steam" <<'EOF'
#!/bin/bash
printf 'steam\n' >> "$HANDHELD_ACTIONS"
printf 'started\n' > "$HANDHELD_STEAM_AT"
exit 0
EOF
chmod +x "$HANDHELD_STUB/steam"

handheld_gaming_env
export OMARCHY_GAMING_RUNTIME=$runtime
export DISPLAY=:77
export HANDHELD_STEAM_AT=$work/steam-at
setsid timeout 5 "$HANDHELD_TREE/bin/omarchy-gaming-steam" >"$work/order-out" 2>"$work/order-err" &
child_pid=$!
sleep 0.4
steam_before_reader=0
[[ -f $work/steam-at ]] && steam_before_reader=1
# Unblock a ready write that still sits ahead of Steam, then stop the wrapper.
exec 3<>"$runtime/ready" || true
read -r -t 1 ready_event <&3 || ready_event=
exec 3<&- || true
kill -- -"$child_pid" 2>/dev/null || true
wait "$child_pid" 2>/dev/null || true
child_pid=

order_detail=$(
  printf 'steam-before-reader:%s\nready-event:%s\n' "$steam_before_reader" "$ready_event"
  echo '--- stderr ---'
  cat "$work/order-err"
)

# A hung Steam child must not leave the supervisor waiting forever once the
# ready check has already passed. Steam here never selects the desktop.
cat > "$HANDHELD_STUB/steam" <<'EOF'
#!/bin/bash
printf 'steam:%s\n' "$*" >> "$HANDHELD_ACTIONS"
printf 'hung\n' > "$HANDHELD_STEAM_AT"
sleep 30
EOF
chmod +x "$HANDHELD_STUB/steam"
: > "$HANDHELD_LOG"
rm -f "$work/steam-at"
handheld_gaming_env
export HANDHELD_STEAM_AT=$work/steam-at
setsid timeout 12 "$HANDHELD_TREE/bin/omarchy-session-start" gaming >"$work/hang-out" 2>"$work/hang-err" &
child_pid=$!
hung=0
for _ in $(seq 1 50); do
  [[ -f $work/steam-at ]] && hung=1 && break
  sleep 0.1
done
if (( hung )); then
  sleep 3
fi
desktop=0
grep -q '^uwsm:' "$HANDHELD_LOG" && desktop=1
kill -- -"$child_pid" 2>/dev/null || true
wait "$child_pid" 2>/dev/null || true
child_pid=

hang_detail=$(
  printf 'steam-started:%s\ndesktop:%s\n' "$hung" "$desktop"
  echo '--- actions ---'
  cat "$HANDHELD_LOG"
  echo '--- stderr ---'
  cat "$work/hang-err"
)

problems=
if (( ! steam_before_reader )); then
  problems+="ready is published before Steam starts. $order_detail"$'\n'
fi
if (( ! hung )); then
  problems+="hung-Steam fixture never started Steam. $hang_detail"$'\n'
elif (( ! desktop )); then
  problems+="Steam hung without Switch to Desktop, and the session did not return to Hyprland. $hang_detail"$'\n'
fi
if [[ -z $problems ]]; then
  pass "Steam ready follows a live Steam child and a hung child returns to the desktop"
  exit 0
fi
fail "Steam ready follows a live Steam child and a hung child returns to the desktop" "$problems"
