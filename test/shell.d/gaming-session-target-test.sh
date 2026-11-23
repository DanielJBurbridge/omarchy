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
grep -q '^After=omarchy-gaming-session.target$' "$shim_dropin" ||
  fail "the TDP shim is ordered after the gaming session target"
if grep -q '^PartOf=' "$shim_dropin"; then
  fail "the TDP shim drop-in stops the shim with the gaming target"
fi
grep -q '^WantedBy=omarchy-gaming-session.target$' "$shim_dropin" ||
  fail "the TDP shim is wanted by the gaming session target"
shim_unit=$ROOT/default/systemd/user/omarchy-ally-tdp-shim.service
grep -q '^PartOf=graphical-session.target$' "$shim_unit" ||
  fail "the TDP shim stops with the desktop session"
if grep -q '^PartOf=omarchy-gaming-session.target$' "$shim_unit"; then
  fail "the TDP shim unit stops with the gaming target"
fi
if grep -E '^(Wants|WantedBy|RequiredBy|BindsTo)=(default\.target|graphical-session\.target)$' \
  "$unit" "$profile_unit"; then
  fail "the gaming profile is wanted by a desktop target"
fi
pkgbuild=$ROOT/packages/omarchy-gaming-session/PKGBUILD
install_script=$ROOT/packages/omarchy-gaming-session/omarchy-gaming-session.install
grep -F -q 'usr/lib/systemd/user/omarchy-gaming-session.target"' "$pkgbuild" ||
  fail "the package ships the gaming session target"
grep -F -q 'usr/lib/systemd/user/omarchy-gaming-input-profile.service"' "$pkgbuild" ||
  fail "the package ships the profile oneshot"
grep -F -q 'omarchy-gaming-session.target.wants/omarchy-gaming-input-profile.service' "$pkgbuild" ||
  fail "the package links the profile oneshot from the gaming target"
if grep -E 'default\.target\.wants|graphical-session\.target\.wants' "$pkgbuild"; then
  fail "the package links the profile oneshot from a desktop target"
fi
grep -F -q 'systemctl enable --now omarchy-inputplumber-profile.service' "$install_script" ||
  fail "the install script starts the profile service"
start_line=$(grep -n 'systemctl enable --now omarchy-inputplumber-profile.service' "$install_script" | head -1 | cut -d: -f1)
ally_line=$(grep -n '/usr/bin/omarchy-hw-rog-ally' "$install_script" | head -1 | cut -d: -f1)
if [[ -z $start_line || -z $ally_line ]] || (( ally_line >= start_line )); then
  fail "enable --now is gated on the Ally"
fi
OMARCHY_PATH=$ROOT "$ROOT/bin/omarchy-gaming-input-profile"
pass "profile load is before the bridge, and both follow the gaming session target"

# A non-login ssh command does not export OMARCHY_PATH. set -u must not abort.
assert_path_default() {
  local label=$1 note
  shift
  note=$(timeout 5 env -u OMARCHY_PATH "$@" 2>&1) || true
  [[ $note != *unbound* ]] || fail "$label aborts when OMARCHY_PATH is unset" "$note"
}
assert_path_default "omarchy-launch-gaming-session" "$ROOT/bin/omarchy-launch-gaming-session"
assert_path_default "omarchy-launch-gaming-desktop" "$ROOT/bin/omarchy-launch-gaming-desktop"
assert_path_default "omarchy-setup-gaming-session" "$ROOT/bin/omarchy-setup-gaming-session" status
assert_path_default "omarchy-session-start" "$ROOT/bin/omarchy-session-start"
steam_stub=$(mktemp -d)
printf '#!/bin/bash\nexit 0\n' >"$steam_stub/steam"
printf '#!/bin/bash\nexit 1\n' >"$steam_stub/omarchy-cmd-present"
cp "$steam_stub/omarchy-cmd-present" "$steam_stub/omarchy-pkg-present"
chmod +x "$steam_stub/steam" "$steam_stub/omarchy-cmd-present" "$steam_stub/omarchy-pkg-present"
assert_path_default "omarchy-gaming-steam" \
  env OMARCHY_GAMING_RUNTIME="${TMPDIR:-/tmp}" DISPLAY=:0 OMARCHY_GAMING_READY_TIMEOUT=1 \
  PATH="$steam_stub:/usr/bin:/bin" \
  "$ROOT/bin/omarchy-gaming-steam"
rm -rf "$steam_stub"
pass "handheld session commands default an unset OMARCHY_PATH"

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

profile_link=$HANDHELD_HOME/.config/systemd/user/omarchy-gaming-session.target.wants/omarchy-gaming-input-profile.service
[[ -L $profile_link ]] || fail "the session links the profile oneshot from the gaming target"
[[ $(readlink -- "$profile_link") == ../omarchy-gaming-input-profile.service ]] ||
  fail "the profile oneshot link points at the gaming unit" "$(readlink -- "$profile_link" 2>/dev/null)"
if [[ -e $HANDHELD_HOME/.config/systemd/user/default.target.wants/omarchy-gaming-input-profile.service ||
      -e $HANDHELD_HOME/.config/systemd/user/graphical-session.target.wants/omarchy-gaming-input-profile.service ]]; then
  fail "the session links the profile oneshot from a desktop target"
fi
pass "the session wants the profile oneshot from the gaming target only"

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
