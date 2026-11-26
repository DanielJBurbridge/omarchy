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

bridge_dropin=$ROOT/default/systemd/user/omarchy-rog-ally-input.service.d/10-gaming-session.conf
shim_dropin=$ROOT/default/systemd/user/omarchy-ally-tdp-shim.service.d/10-gaming-session.conf
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
pkgbuild=$ROOT/packages/omarchy-gaming-session/PKGBUILD
install_script=$ROOT/packages/omarchy-gaming-session/omarchy-gaming-session.install
grep -F -q 'usr/lib/systemd/user/omarchy-gaming-session.target"' "$pkgbuild" ||
  fail "the package ships the gaming session target"
if grep -E 'default\.target\.wants|graphical-session\.target\.wants' "$pkgbuild"; then
  fail "the package links gaming units from a desktop target"
fi
grep -F -q 'systemctl start omarchy-inputplumber-profile.service' "$install_script" ||
  fail "the install script starts the profile service"
start_line=$(grep -n 'systemctl start omarchy-inputplumber-profile.service' "$install_script" | head -1 | cut -d: -f1)
ally_line=$(grep -n '/usr/bin/omarchy-hw-rog-ally' "$install_script" | head -1 | cut -d: -f1)
if [[ -z $start_line || -z $ally_line ]] || (( ally_line >= start_line )); then
  fail "profile service startup is gated on the Ally"
fi
pass "the bridge and TDP shim are wanted by the gaming session target"

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
vendor_units=$work/vendor/systemd/user
sed -i "s|/usr/lib/systemd/user/|$vendor_units/|" "$HANDHELD_TREE/bin/omarchy-session-start"
# Exercise the pre-K07 passwordless path with no marker or lock policy.
sed -i -e "s|^gaming_k07_marker=.*|gaming_k07_marker=$work/k07-absent|" \
  -e "s|^gaming_desktop_lock_file=.*|gaming_desktop_lock_file=$work/desktop-lock-absent|" \
  "$HANDHELD_TREE/default/gaming/session.sh"
cat > "$HANDHELD_STUB/omarchy-pkg-present" <<'EOF'
#!/bin/bash
[[ $* == omarchy-gaming-session ]]
EOF
cat > "$HANDHELD_STUB/omarchy-hw-physical-keyboard" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$HANDHELD_STUB/busctl" <<'EOF'
#!/bin/bash
if [[ $* == '--timeout=3s --auto-start=no call org.omarchy.InputPlumberProfile /org/omarchy/InputPlumberProfile org.omarchy.InputPlumberProfile Load s '* ]]; then
  printf 'profile:%s:%s\n' "${@: -1}" "$XDG_SESSION_ID" >> "$HANDHELD_ACTIONS"
  exit "${PROFILE_LOAD_STATUS:-0}"
fi
exit 1
EOF
cat > "$HANDHELD_STUB/steam" <<'EOF'
#!/bin/bash
if [[ $* == '-ifrunning -shutdown' ]]; then
  printf 'steam:shutdown:%s\n' "$DISPLAY" >> "$HANDHELD_ACTIONS"
  touch "$OMARCHY_GAMING_RUNTIME/test-steam-shutdown"
  exit 0
fi
printf 'steam:%s\n' "$*" >> "$HANDHELD_ACTIONS"
timeout 2 bash -c 'printf "started\n" > "$1"' _ "$OMARCHY_GAMING_RUNTIME/ready" || exit 1
last=$XDG_STATE_HOME/omarchy/gaming-session/last
for _ in {1..80}; do
  [[ $(cat "$last" 2>/dev/null) == "gaming" ]] && break
  sleep 0.05
done
steamos-session-select plasma
if [[ ${WAIT_FOR_STEAM_SHUTDOWN:-0} == 1 ]]; then
  while [[ ! -f $OMARCHY_GAMING_RUNTIME/test-steam-shutdown ]]; do
    sleep 0.05
  done
  if [[ ${STEAM_IGNORES_SHUTDOWN:-0} == 1 ]]; then
    sleep 30
  fi
  printf 'steam:clean-exit\n' >> "$HANDHELD_ACTIONS"
fi
exit 0
EOF
chmod +x "$HANDHELD_STUB/steam" "$HANDHELD_STUB/busctl" "$HANDHELD_STUB/omarchy-pkg-present" \
  "$HANDHELD_STUB/omarchy-hw-physical-keyboard"
handheld_gaming_env
export XDG_CONFIG_HOME=$work/config
export OMARCHY_HANDHELD_AUTOLOGIN_DIR=$work/run OMARCHY_SDDM_CONF_DIR=$work/sddm
unset XKB_DEFAULT_LAYOUT XKB_DEFAULT_VARIANT
run_session() {
  local entry=$1 status=0
  : > "$HANDHELD_LOG"
  setsid timeout 8 "$HANDHELD_TREE/bin/omarchy-session-start" "$entry" >"$work/out" 2>"$work/err" &
  session_pid=$!
  wait "$session_pid" || status=$?
  session_pid=
  (( status == 0 )) ||
    fail "the $entry supervisor exits cleanly" "$(printf 'status=%s\n' "$status"; cat "$HANDHELD_LOG" "$work/err")"
}
assert_gamescope_keyboard() {
  local expected=$1 description=$2
  grep -Fxq "gamescope-keyboard:$expected" "$HANDHELD_LOG" ||
    fail "$description" "$(cat "$HANDHELD_LOG" "$work/err")"
  pass "$description"
}
export OMARCHY_DRM_PATH=$work/drm
mkdir -p "$OMARCHY_DRM_PATH/"{card0-eDP-1,card0-DP-1}
printf 'connected\n' >"$OMARCHY_DRM_PATH/card0-eDP-1/status"
printf 'connected\n' >"$OMARCHY_DRM_PATH/card0-DP-1/status"
head -c 128 /dev/zero >"$OMARCHY_DRM_PATH/card0-DP-1/edid"
omarchy-gaming-output DP-1 || fail "a connected external output can be preferred"
mkdir -p "$XDG_CONFIG_HOME/omarchy" "$HANDHELD_TREE/etc"
keyboard_selection=$XDG_CONFIG_HOME/omarchy/keyboard-layouts
vconsole=$HANDHELD_TREE/etc/vconsole.conf
printf 'XKBLAYOUT=gb\n' > "$vconsole"
printf 'XKBLAYOUT=de,us\nXKBVARIANT=nodeadkeys,dvorak\n' > "$keyboard_selection"
WAIT_FOR_STEAM_SHUTDOWN=1 run_session gaming
assert_gamescope_keyboard '[de] [nodeadkeys]' "Gamescope uses the leading saved layout and its paired variant"
grep -Fxq 'uwsm-keyboard:[<unset>] [<unset>]' "$HANDHELD_LOG" ||
  fail "the saved layout is scoped to Gamescope" "$(cat "$HANDHELD_LOG")"
pass "the saved layout stays out of the desktop environment"
grep -Fxq 'gamescope-output:DP-1,eDP-1' "$HANDHELD_LOG" ||
  fail "the launcher passes the paired output priority to Gamescope" "$(cat "$HANDHELD_LOG")"
user_units=$XDG_CONFIG_HOME/systemd/user
cmp -s "$unit" "$user_units/$name" ||
  fail "the runtime still supplies the target for an older gaming-session package"

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

mapfile -t shutdown_actions < <(grep -E '^(steam:shutdown:|steam:clean-exit$|gamescope-child-exit:|systemctl:--user stop omarchy-gamescope-)' "$HANDHELD_LOG")
[[ ${shutdown_actions[0]:-} == steam:shutdown::77 && ${shutdown_actions[1]:-} == steam:clean-exit &&
  ${shutdown_actions[2]:-} == gamescope-child-exit:0 && ${shutdown_actions[3]:-} == 'systemctl:--user stop omarchy-gamescope-redteam.scope' ]] ||
  fail "Switch to Desktop lets Steam exit through its own display before the scope receives TERM" "$detail"
pass "the explicit desktop return lets Steam and Gamescope exit in order"

mapfile -t profile_actions < <(grep -n '^profile:' "$HANDHELD_LOG")
(( ${#profile_actions[@]} == 4 )) &&
  [[ ${profile_actions[0]#*:} == 'profile:gaming:redteam' && ${profile_actions[1]#*:} == 'profile:pointer:redteam' &&
  ${profile_actions[2]#*:} == 'profile:desktop:redteam' && ${profile_actions[3]#*:} == 'profile:pointer:redteam' ]] ||
  fail "the active login loads each session profile and restores the pointer on teardown" "$detail"
if (( ${profile_actions[0]%%:*} >= start_line || ${profile_actions[1]%%:*} <= stop_line ||
  ${profile_actions[1]%%:*} >= ${profile_actions[2]%%:*} || ${profile_actions[2]%%:*} >= desktop_line ||
  ${profile_actions[3]%%:*} <= desktop_line )); then
  fail "the controller watches bracket Gaming and Desktop in the active login" "$detail"
fi
pass "the managed session switches the controller mapping between Gaming, Desktop and the greeter"

bridge_line=$(grep -n 'systemctl:--user start omarchy-rog-ally-input.service' "$HANDHELD_LOG" | head -1 | cut -d: -f1)
shim_line=$(grep -n 'systemctl:--user restart omarchy-ally-tdp-shim.service' "$HANDHELD_LOG" | head -1 | cut -d: -f1)
if [[ -z $bridge_line || -z $start_line || -z $gamescope_line ]] || (( bridge_line <= start_line || bridge_line >= gamescope_line )); then
  fail "the bridge starts after the session target and before Gamescope" "$detail"
fi
if [[ -z $shim_line ]] || (( shim_line <= start_line || shim_line >= gamescope_line )); then
  fail "an installed TDP shim is restarted before Gamescope" "$detail"
fi
pass "bridge starts after the profile target and the installed TDP shim is restarted"

rm -f "$XDG_RUNTIME_DIR/omarchy-gaming-$XDG_SESSION_ID/test-steam-shutdown"
printf 'XKBLAYOUT=de,us\nXKBVARIANT=,dvorak\n' > "$keyboard_selection"
WAIT_FOR_STEAM_SHUTDOWN=1 STEAM_IGNORES_SHUTDOWN=1 run_session gaming
assert_gamescope_keyboard '[de] [<unset>]' "Gamescope keeps the default variant when the next layout has one"
grep -Fxq 'steam:shutdown::77' "$HANDHELD_LOG" &&
  grep -Fxq 'systemctl:--user stop omarchy-gamescope-redteam.scope' "$HANDHELD_LOG" &&
  ! grep -q '^systemctl:--user kill ' "$HANDHELD_LOG" &&
  grep -q '^uwsm:' "$HANDHELD_LOG" && ! grep -Fxq 'steam:clean-exit' "$HANDHELD_LOG" ||
  fail "an unresponsive Steam client still falls back to bounded scope teardown" "$(cat "$HANDHELD_LOG")"
pass "a stuck Steam shutdown does not prevent the desktop return"

rm -f "$XDG_RUNTIME_DIR/omarchy-gaming-$XDG_SESSION_ID/test-steam-shutdown"
rm "$keyboard_selection"
cat > "$vconsole" <<'EOF'
KEYMAP=fr
 XKBLAYOUT = "fr,us" # Installed layout
XKBVARIANT='bepo,dvorak'
EOF
WAIT_FOR_STEAM_SHUTDOWN=1 GAMESCOPE_STAYS_AFTER_STEAM=1 run_session gaming
assert_gamescope_keyboard '[fr] [bepo]' "Gamescope falls back to the installed layout and variant"
mapfile -t stuck_actions < <(grep -E '^(gamescope-child-exit:|systemctl:--user (kill|stop omarchy-gamescope-)|uwsm:)' "$HANDHELD_LOG")
[[ ${stuck_actions[0]:-} == gamescope-child-exit:0 &&
  ${stuck_actions[1]:-} == 'systemctl:--user kill --kill-whom=all --signal=KILL omarchy-gamescope-redteam.scope' &&
  ${stuck_actions[2]:-} == 'systemctl:--user stop omarchy-gamescope-redteam.scope' && ${stuck_actions[3]:-} == uwsm:* ]] ||
  fail "a compositor that stays up after a clean Steam exit is killed by exact scope before desktop starts" "$(cat "$HANDHELD_LOG")"
pass "confirmed Steam exit lets recovery bypass the compositor's stop timeout"

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
printf '\n# User override\n' >> "$user_units/$name"
cp "$user_units/$name" "$work/user-target"
XKB_DEFAULT_LAYOUT=gb PROFILE_LOAD_STATUS=1 run_session gaming
assert_gamescope_keyboard '[gb] [<unset>]' "an inherited layout keeps its own default variant"
cmp -s "$work/user-target" "$user_units/$name" ||
  fail "the legacy unit setup preserves a user's existing target"
absent=$(cat "$HANDHELD_LOG")
if grep -q 'restart omarchy-ally-tdp-shim.service' <<<"$absent"; then
  fail "a missing TDP shim is not restarted" "$absent"
fi
grep -q 'start omarchy-rog-ally-input.service' <<<"$absent" &&
  fail "a missing bridge unit is not started" "$absent"
grep -q '^gamescope$' <<<"$absent" || fail "a missing TDP shim still starts Gamescope" "$absent"
if ! grep -q '^profile:gaming:redteam$' <<<"$absent" || grep -q '^profile:pointer:' <<<"$absent"; then
  fail "a refused gaming profile still starts Gamescope and leaves the controller's native map available" "$absent"
fi
pass "a missing TDP shim and bridge are skipped and Gamescope still starts"

mkdir -p "$vendor_units"
cp "$unit" "$vendor_units/$name"
rm "$user_units/omarchy-rog-ally-input.service.d/10-gaming-session.conf"
printf 'KEYMAP=us\n' > "$vconsole"
run_session gaming
assert_gamescope_keyboard '[<unset>] [<unset>]' "Gamescope keeps its defaults without an XKB selection"
grep -q '^gamescope$' "$HANDHELD_LOG" || fail "the installed gaming package still starts Gamescope"
[[ ! -e $user_units/omarchy-rog-ally-input.service.d/10-gaming-session.conf ]] ||
  fail "the installed gaming package does not recreate per-user units"
cmp -s "$work/user-target" "$user_units/$name" ||
  fail "the installed gaming package leaves the user's override in place"
pass "the gaming-session package supplies units without rewriting user configuration"

printf 'XKBLAYOUT=de\nXKBVARIANT=nodeadkeys\n' > "$keyboard_selection"
XKB_DEFAULT_VARIANT=dvorak run_session gaming
assert_gamescope_keyboard '[<unset>] [dvorak]' "a variant-only override keeps its implicit layout"

printf 'desktop\n' > "$XDG_STATE_HOME/omarchy/gaming-session/preference"
run_session preferred
if ! grep -q '^profile:desktop:redteam$' "$HANDHELD_LOG" || grep -q '^gamescope$' "$HANDHELD_LOG"; then
  fail "a managed login straight into Desktop requests the profile without Gamescope" "$(cat "$HANDHELD_LOG")"
fi
PROFILE_LOAD_STATUS=1 run_session preferred
if ! grep -q '^profile:desktop:redteam$' "$HANDHELD_LOG" || ! grep -q '^uwsm:' "$HANDHELD_LOG" ||
  grep -q '^profile:pointer:' "$HANDHELD_LOG"; then
  fail "a refused profile load leaves the desktop available and does not restore another profile" "$(cat "$HANDHELD_LOG")"
fi
pass "a managed Desktop login requests controller mode and can continue if refused"

sed -i -e '/\/usr\/bin\/loginctl/s/exec -c /exec /' \
  -e "s|/usr/bin/loginctl|$HANDHELD_STUB/loginctl|" \
  -e "s|/proc/\$pid/environ|$work/compositor-environ|" "$HANDHELD_TREE/bin/omarchy-session-start"
printf 'OMARCHY_HANDHELD_SESSION=old-desktop\0' > "$work/compositor-environ"
cat > "$HANDHELD_STUB/loginctl" <<'EOF'
#!/bin/bash
case $3 in
  self) printf '%s\n' "Id=$XDG_SESSION_ID" Active=yes "State=${CURRENT_LOGIN_STATE:-active}" Service=sddm-autologin ;;
  old-desktop) printf '%s\n' Id=old-desktop Active=no Service=sddm "State=$OLD_LOGIN_STATE" ;;
  *) exit 1 ;;
esac
printf '%s\n' Class=user Remote=no Seat=seat0 Type=wayland "User=$UID"
EOF
cat > "$HANDHELD_STUB/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >> "$HANDHELD_ACTIONS"
if [[ $* == '--user show wayland-wm@hyprland.desktop.service '* ]]; then
  printf '%s\n' ActiveState=active MainPID=1234 InvocationID=0123456789abcdef0123456789abcdef
fi
EOF
chmod +x "$HANDHELD_STUB/loginctl"
OLD_LOGIN_STATE=closing run_session preferred
mapfile -t desktop_actions < <(grep -E '^(systemctl:--user stop wayland-wm@|uwsm:)' "$HANDHELD_LOG")
[[ ${desktop_actions[0]:-} == 'systemctl:--user stop wayland-wm@hyprland.desktop.service' &&
  ${desktop_actions[1]:-} == uwsm:* ]] ||
  fail "a new local login retires the compositor from the closed PAM session before starting Hyprland" "$(cat "$HANDHELD_LOG")"
pass "a closed managed login releases Hyprland before the next desktop starts"

OLD_LOGIN_STATE=active run_session preferred
grep -q '^uwsm:' "$HANDHELD_LOG" && ! grep -q 'systemctl:--user stop wayland-wm@' "$HANDHELD_LOG" ||
  fail "a live managed login must keep its compositor" "$(cat "$HANDHELD_LOG")"
CURRENT_LOGIN_STATE=closing OLD_LOGIN_STATE=closing run_session preferred
grep -q '^uwsm:' "$HANDHELD_LOG" && ! grep -q 'systemctl:--user stop wayland-wm@' "$HANDHELD_LOG" ||
  fail "a closing login cannot retire another login's compositor" "$(cat "$HANDHELD_LOG")"
printf 'OTHER_VARIABLE=first-line\nOMARCHY_HANDHELD_SESSION=old-desktop\0' > "$work/compositor-environ"
OLD_LOGIN_STATE=closing run_session preferred
grep -q '^uwsm:' "$HANDHELD_LOG" && ! grep -q 'systemctl:--user stop wayland-wm@' "$HANDHELD_LOG" ||
  fail "a compositor without a managed login ID must be left alone" "$(cat "$HANDHELD_LOG")"
pass "live and unmanaged desktop sessions keep their Hyprland service"

# A machine that is not the handheld never enters the gaming supervisor.
printf 'Dell Inc.\n' > "$work/dmi/sys_vendor"
printf 'XPS 13\n' > "$work/dmi/product_name"
printf '0A1B\n' > "$work/dmi/board_name"
run_session preferred
if grep -Eq 'omarchy-gaming-session.target|^profile:' "$HANDHELD_LOG"; then
  fail "a non-handheld session does not pull in the gaming target or change controller profiles" "$(cat "$HANDHELD_LOG")"
fi
grep -q '^uwsm:' "$HANDHELD_LOG" || fail "a non-handheld session still starts the desktop" "$(cat "$HANDHELD_LOG")"
pass "the gaming session target stays on the handheld path"

if ! dbus-run-session -- python3 "$here/../handheld/input-profile-watch-test.py" \
  "$ROOT/default/gaming/input-profile-watch.py" > "$work/profile-watch.log" 2>&1; then
  fail "managed profiles recover when InputPlumber and the Ally composite reappear" "$(cat "$work/profile-watch.log")"
fi
pass "managed profiles recover when InputPlumber and the Ally composite reappear"
