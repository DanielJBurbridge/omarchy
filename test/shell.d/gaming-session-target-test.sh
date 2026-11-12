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

profile_unit=$ROOT/default/systemd/user/omarchy-gaming-input-profile.service
bridge_dropin=$ROOT/default/systemd/user/omarchy-rog-ally-input.service.d/10-gaming-session.conf
shim_dropin=$ROOT/default/systemd/user/omarchy-ally-tdp-shim.service.d/10-gaming-session.conf
grep -q '^Wants=omarchy-gaming-input-profile.service$' "$unit" ||
  fail "the gaming session target wants the profile load"
grep -q '^Before=omarchy-rog-ally-input.service$' "$profile_unit" ||
  fail "the profile load is ordered before the gaming bridge"
grep -q '^PartOf=omarchy-gaming-session.target$' "$profile_unit" ||
  fail "the profile load is part of the gaming session target"
grep -q '^WantedBy=omarchy-gaming-session.target$' "$profile_unit" ||
  fail "the profile load is wanted by the gaming session target"
grep -q '^After=omarchy-gaming-input-profile.service$' "$bridge_dropin" ||
  fail "the bridge unit is After= the profile load"
grep -q '^PartOf=omarchy-gaming-session.target$' "$bridge_dropin" ||
  fail "the bridge unit is part of the gaming session target"
grep -q '^WantedBy=omarchy-gaming-session.target$' "$bridge_dropin" ||
  fail "the bridge unit is wanted by the gaming session target"
grep -q '^PartOf=omarchy-gaming-session.target$' "$shim_dropin" ||
  fail "the TDP shim is part of the gaming session target"
grep -q '^WantedBy=omarchy-gaming-session.target$' "$shim_dropin" ||
  fail "the TDP shim is wanted by the gaming session target"
OMARCHY_PATH=$ROOT "$ROOT/bin/omarchy-gaming-input-profile"
pass "profile load is before the bridge, and both follow the gaming session target"

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

bridge_line=$(grep -n 'systemctl:--user start omarchy-rog-ally-input.service' "$HANDHELD_LOG" | head -1 | cut -d: -f1)
shim_line=$(grep -n 'systemctl:--user restart omarchy-ally-tdp-shim.service' "$HANDHELD_LOG" | head -1 | cut -d: -f1)
if [[ -z $bridge_line || -z $start_line || -z $gamescope_line ]] || (( bridge_line <= start_line || bridge_line >= gamescope_line )); then
  fail "the bridge starts after the session target and before Gamescope" "$detail"
fi
if [[ -z $shim_line ]] || (( shim_line <= start_line || shim_line >= gamescope_line )); then
  fail "an installed TDP shim is restarted before Gamescope" "$detail"
fi
pass "bridge starts after the profile target and the installed TDP shim is restarted"

# The fixture systemctl answers every cat. This one reports #33's unit absent.
cat > "$HANDHELD_STUB/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >> "$HANDHELD_ACTIONS"
if [[ $* == *'cat omarchy-ally-tdp-shim.service'* || $* == *'cat omarchy-rog-ally-input.service'* ]]; then
  exit 1
fi
if [[ $* == *stop* && -f ${HANDHELD_SCOPE_PID:-} ]]; then
  scope_pid=$(cat "$HANDHELD_SCOPE_PID")
  kill -- -"$scope_pid" 2>/dev/null || kill "$scope_pid" 2>/dev/null || true
fi
exit 0
EOF
chmod +x "$HANDHELD_STUB/systemctl"
: > "$HANDHELD_LOG"
setsid timeout 8 "$HANDHELD_TREE/bin/omarchy-session-start" gaming >"$work/absent-out" 2>"$work/absent-err" &
session_pid=$!
wait "$session_pid" || true
session_pid=
absent=$(cat "$HANDHELD_LOG")
if grep -q 'restart omarchy-ally-tdp-shim.service' <<<"$absent"; then
  fail "a missing TDP shim is not restarted" "$absent"
fi
grep -q 'start omarchy-rog-ally-input.service' <<<"$absent" &&
  fail "a missing bridge unit is not started" "$absent"
grep -q '^gamescope$' <<<"$absent" || fail "a missing TDP shim still starts Gamescope" "$absent"
pass "a missing TDP shim and bridge are skipped and Gamescope still starts"

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
