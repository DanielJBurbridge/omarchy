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
trap 'rm -rf "$work" ${user_bin:-}' EXIT
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
    PATH="$work/bin:$ROOT/bin:$PATH" \
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

export XDG_STATE_HOME=$work/state HOME=$work/home PATH="$work/bin:$ROOT/bin:$PATH"
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

# next=desktop is the session user's one-shot, mode 0600. Relogin consumes
# that value once even when the recovery latch and a dock are set, then the
# following Relogin is gaming again. A different next value stays put.
gaming_state_init
printf 'failed\n' > "$gaming_state/recovery"
gaming_save next desktop
next_mode=$(stat -c %a -- "$gaming_state/next")
next_owner=$(stat -c %u -- "$gaming_state/next")
[[ $next_mode == 600 && $next_owner == "$(id -u)" ]] ||
  fail "next=desktop is the session user's mode 0600 file" "mode=$next_mode owner=$next_owner"
export DOCKED=1
[[ $(gaming_entry_selection relogin) == desktop ]] ||
  fail "Relogin consumes next=desktop once through a latch and a dock"
[[ ! -e $gaming_state/next ]] || fail "consuming next=desktop deletes the one-shot"
[[ -f $gaming_state/recovery ]] || fail "consuming next=desktop leaves the recovery latch"
[[ $(gaming_entry_selection relogin) == gaming ]] || fail "the next Relogin returns to gaming"
printf 'gaming\n' > "$gaming_state/next"
[[ $(gaming_entry_selection relogin) == gaming ]] || fail "Relogin ignores a next value other than desktop"
[[ $(cat "$gaming_state/next") == gaming ]] || fail "Relogin leaves a non-desktop one-shot in place"
rm -f "$gaming_state/next"
printf 'stop\n' > "$work/run/stop"
[[ $(gaming_entry_selection relogin) == gaming ]] ||
  fail "Relogin without next=desktop stays on gaming while autologin is stopped"
[[ -f $work/run/stop ]] || fail "the one-shot path does not delete the autologin stop file"
grep -q '^Relogin=true$' "$dropin" || fail "consuming the one-shot does not change Relogin" "$(cat "$dropin")"
rm -f "$work/run/stop"
pass "Relogin consumes next=desktop once and otherwise stays on gaming"

user_dir=$work/user-run
mkdir -p "$user_dir"
chown 1:1 "$user_dir"
# The checkout can be mode 0700, so uid 1 cannot exec the script there. The
# copy is what the desktop user runs, and a refused fail still has to say why.
user_bin=$(mktemp -d)
chmod 755 "$user_bin"
cp "$ROOT/bin/omarchy-handheld-autologin" "$user_bin/omarchy-handheld-autologin"
chmod 755 "$user_bin/omarchy-handheld-autologin"
if as_user env OMARCHY_HANDHELD_AUTOLOGIN_DIR="$user_dir" OMARCHY_AUTOLOGIN_NOW=1 \
  "$user_bin/omarchy-handheld-autologin" fail >"$work/user-out" 2>"$work/user-err"; then
  fail "a desktop user fail without root is a silent success"
fi
grep -q 'needs root' "$work/user-err" || fail "a refused fail does not say why" "$(cat "$work/user-err" 2>/dev/null)"
rm -rf "$user_bin"
[[ ! -e $user_dir/failures && ! -e $user_dir/stop ]] || fail "a desktop user does not create the counter"

OMARCHY_AUTOLOGIN_NOW=1000 run_guard fail
[[ ! -e $work/run/actions ]] || ! grep -q 'inputplumber-profile:load' "$work/run/actions" ||
  fail "one failure does not load a profile" "$(cat "$work/run/actions" 2>/dev/null)"
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
grep -q '^Relogin=false$' "$dropin" || fail "a crash-loop stop sets Relogin=false" "$(cat "$dropin")"
grep -qx 'sddm-restart' "$work/run/actions" || fail "a crash-loop stop restarts the greeter" "$(cat "$work/run/actions")"
restart_line=$(grep -n '^sddm-restart$' "$work/run/actions" | head -1 | cut -d: -f1)
pointer_line=$(grep -n '^inputplumber-profile:load pointer$' "$work/run/actions" | head -1 | cut -d: -f1)
[[ -n $pointer_line && $restart_line -lt $pointer_line ]] ||
  fail "a crash-loop stop loads the pointer profile after the greeter restart" "$(cat "$work/run/actions")"
grep -Eq 'inputplumber-profile:load (desktop|gaming|osk|gamepad)' "$work/run/actions" &&
  fail "a crash-loop stop does not load a session profile" "$(cat "$work/run/actions")"
run_guard apply
grep -q '^Relogin=false$' "$dropin" || fail "apply keeps Relogin=false while the stop file exists" "$(cat "$dropin")"
cat > "$work/bin/omarchy-session-start" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$work/run/session-args"
exit 0
EOF
chmod +x "$work/bin/omarchy-session-start"
rm -f "$work/run/session-args"
restarts_before=$(grep -c '^sddm-restart$' "$work/run/actions")
run_guard session || fail "a stopped session does not start the desktop supervisor"
run_guard session || fail "a second stopped session does not start the desktop supervisor"
[[ $(grep -c '^relogin$' "$work/run/session-args") == 2 ]] ||
  fail "a stopped session starts the desktop supervisor once per entry" "$(cat "$work/run/session-args" 2>/dev/null)"
restarts_after=$(grep -c '^sddm-restart$' "$work/run/actions")
[[ $restarts_before == "$restarts_after" ]] ||
  fail "opening the desktop after stop restarts SDDM again" "$(cat "$work/run/actions")"
grep -q '^Relogin=false$' "$dropin" || fail "the greeter restart leaves Relogin=false" "$(cat "$dropin")"
pass "three failure timestamps within 60s pin Relogin off and the next session is the desktop"

user_conf=$work/sddm/omarchy-handheld-user.conf
printf '[Autologin]\nUser=daniel\n' > "$user_conf"
kept_user=$(cat "$user_conf")
run_guard install-user othername
[[ $(cat "$user_conf") == "$kept_user" ]] || fail "install-user does not replace an existing User=" "$(cat "$user_conf")"
run_guard apply
[[ $(cat "$user_conf") == "$kept_user" ]] || fail "apply rewrites the installer User= file" "$(cat "$user_conf")"
grep -q '^User=' "$dropin" && fail "apply writes User= into the session drop-in" "$(cat "$dropin")"
rm -f "$user_conf"
run_guard install-user daniel
grep -q '^User=daniel$' "$user_conf" || fail "install-user writes User= on its own" "$(cat "$user_conf")"
grep -q '^Session=' "$user_conf" && fail "the User= file also sets Session" "$(cat "$user_conf")"
assert_root_file "$user_conf"
if run_guard install-user '../daniel'; then
  fail "install-user accepts a path"
fi
printf '[General]\nUser=other\n' > "$user_conf"
run_guard install-user daniel
grep -q '^\[Autologin\]$' "$user_conf" || fail "a User= outside [Autologin] is rewritten into the section" "$(cat "$user_conf")"
grep -q '^User=daniel$' "$user_conf" || fail "a misplaced User= is replaced" "$(cat "$user_conf")"
printf '[Autologin]\n# User=ghost\nUser=\n' > "$user_conf"
run_guard install-user daniel
grep -q '^User=daniel$' "$user_conf" || fail "a comment or an empty User= counts" "$(cat "$user_conf")"
rm -f "$user_conf"
HW=laptop run_guard install-user daniel
[[ ! -e $user_conf ]] || fail "a laptop install-user writes User=" "$(cat "$user_conf" 2>/dev/null)"
HW=ally PKG=absent run_guard install-user daniel
[[ ! -e $user_conf ]] || fail "install-user writes User= without the gaming session package"
pass "User= stays in its own file and apply never writes it"

rm -f "$user_conf"
env -i PATH="$work/bin:$ROOT/bin:/usr/bin:/bin" HW=ally PKG=present \
  OMARCHY_SDDM_CONF_DIR="$work/sddm" \
  OMARCHY_HANDHELD_AUTOLOGIN_DIR="$work/run" \
  "$ROOT/bin/omarchy-handheld-autologin" install-user daniel
grep -q '^User=daniel$' "$user_conf" || fail "install-user under env -i writes User=" "$(cat "$user_conf" 2>/dev/null)"
pass "install-user does not need the caller's OMARCHY_PATH"

rm -f "$user_conf"
printf '[General]\nUser=other\n[Autologin]\nUser=daniel\n' > "$work/sddm/autologin.conf"
PATH="$work/bin:$ROOT/bin:$PATH" HW=ally PKG=present \
  OMARCHY_SDDM_CONF_DIR=$work/sddm OMARCHY_SDDM_STATE=$work/missing-state \
  "$ROOT/default/gaming/sddm-user.sh" install-recorded
grep -q '^User=daniel$' "$user_conf" || fail "install-recorded reads [Autologin] User=" "$(cat "$user_conf" 2>/dev/null)"
kept_user=$(cat "$user_conf")
printf '[Autologin]\nUser=other\n' > "$work/sddm/autologin.conf"
PATH="$work/bin:$ROOT/bin:$PATH" HW=ally PKG=present \
  OMARCHY_SDDM_CONF_DIR=$work/sddm \
  "$ROOT/default/gaming/sddm-user.sh" install-recorded
[[ $(cat "$user_conf") == "$kept_user" ]] || fail "install-recorded replaces a counted User=" "$(cat "$user_conf")"
rm -f "$user_conf" "$work/sddm/autologin.conf"
printf '[Last]\nSession=omarchy.desktop\nUser=daniel\n' > "$work/state.conf"
PATH="$work/bin:$ROOT/bin:$PATH" HW=ally PKG=present \
  OMARCHY_SDDM_CONF_DIR=$work/sddm OMARCHY_SDDM_STATE=$work/state.conf \
  "$ROOT/default/gaming/sddm-user.sh" install-recorded
grep -q '^User=daniel$' "$user_conf" || fail "install-recorded reads SDDM [Last] User= after autologin.conf is gone" "$(cat "$user_conf" 2>/dev/null)"
rm -f "$user_conf"
printf '[Autologin]\nUser=other\n' > "$work/state.conf"
PATH="$work/bin:$ROOT/bin:$PATH" HW=ally PKG=present \
  OMARCHY_SDDM_CONF_DIR=$work/sddm OMARCHY_SDDM_STATE=$work/state.conf \
  "$ROOT/default/gaming/sddm-user.sh" install-recorded
[[ ! -e $user_conf ]] || fail "a User= outside [Last] in the SDDM state is used" "$(cat "$user_conf")"
pass "the recorded installer user is copied and never guessed"

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

rm -f "$work/sddm/"*
printf '[Autologin]\nUser=daniel\n' > "$user_conf"
printf '[Autologin]\nSession=omarchy-handheld.desktop\nRelogin=true\n' > "$dropin"
HW=laptop run_guard apply
[[ ! -e $dropin && ! -e $user_conf ]] || fail "a laptop apply leaves a handheld SDDM file"
grep -Rqs 'User=' "$work/sddm" && fail "a laptop apply leaves User= under sddm.conf.d"
printf '[Autologin]\nUser=daniel\n' > "$user_conf"
printf '[Autologin]\nSession=omarchy-handheld.desktop\nRelogin=true\n' > "$dropin"
HW=ally PKG=absent run_guard apply
[[ ! -e $dropin && ! -e $user_conf ]] || fail "removing the gaming package leaves a handheld SDDM file"
grep -Rqs 'User=' "$work/sddm" && fail "removing the gaming package leaves User= under sddm.conf.d"
# shellcheck source=/dev/null
source "$ROOT/packages/omarchy-gaming-session/omarchy-gaming-session.install"
printf '[Autologin]\nUser=daniel\nSession=omarchy.desktop\n' > "$user_conf"
printf '[Autologin]\nUser=keep\nSession=omarchy.desktop\n' > "$work/sddm/autologin.conf"
PATH=/usr/bin:/bin OMARCHY_SDDM_CONF_DIR=$work/sddm post_remove
[[ ! -e $user_conf ]] || fail "post_remove leaves omarchy-handheld-user.conf"
grep -q '^User=keep$' "$work/sddm/autologin.conf" || fail "post_remove deletes autologin.conf"
printf '[Autologin]\nUser=daniel\n' > "$user_conf"
PATH=/usr/bin:/bin OMARCHY_SDDM_CONF_DIR=$work/sddm pre_remove
[[ ! -e $user_conf ]] || fail "pre_remove leaves omarchy-handheld-user.conf"
grep -q '^User=keep$' "$work/sddm/autologin.conf" || fail "pre_remove deletes autologin.conf"
pass "laptops and a removed package leave no handheld User="

# sudo strips the environment, so fail reads the default state home of
# SUDO_USER. A count already at the limit pins Relogin off without restarting
# SDDM: the session is about to open the desktop.
fake_home=$work/fake-home
mkdir -p "$fake_home/.local/state/omarchy/gaming-session"
printf '3\n' > "$fake_home/.local/state/omarchy/gaming-session/start-failures"
cat > "$work/bin/getent" <<'EOF'
#!/bin/bash
if [[ $1 == passwd ]]; then
  printf 'ally:x:1000:1000:ally:%s:/bin/bash\n' "$AUTOLOGIN_FAKE_HOME"
  exit 0
fi
exit 1
EOF
chmod +x "$work/bin/getent"
rm -f "$work/run/stop" "$work/run/failures" "$work/run/actions"
export SUDO_USER=ally AUTOLOGIN_FAKE_HOME=$fake_home
OMARCHY_AUTOLOGIN_NOW=9000 run_guard fail
unset SUDO_USER AUTOLOGIN_FAKE_HOME
rm -f "$work/bin/getent"
[[ -f $work/run/stop ]] || fail "a persisted count of 3 writes the stop file"
grep -q '^Relogin=false$' "$dropin" || fail "a persisted count of 3 sets Relogin=false" "$(cat "$dropin")"
[[ ! -e $work/run/actions ]] || fail "a persisted count of 3 does not restart SDDM" "$(cat "$work/run/actions" 2>/dev/null)"
pass "a persisted count of 3 pins Relogin off without restarting SDDM"

rm -f "$work/run/stop" "$work/run/failures" "$work/run/actions"
OMARCHY_AUTOLOGIN_NOW=4000 HW=laptop run_guard fail
OMARCHY_AUTOLOGIN_NOW=4010 HW=laptop run_guard fail
OMARCHY_AUTOLOGIN_NOW=4020 HW=laptop run_guard fail
[[ -f $work/run/stop ]] || fail "three failures off the handheld variant still record the stop"
if [[ -f $work/run/actions ]] && grep -q 'sddm-restart\|inputplumber-profile' "$work/run/actions"; then
  fail "a fail off the handheld variant restarts sddm" "$(cat "$work/run/actions")"
fi
pass "a fail off the handheld variant does not restart sddm"

grant=$ROOT/packages/omarchy-gaming-session/omarchy-handheld-autologin
pkgbuild=$ROOT/packages/omarchy-gaming-session/PKGBUILD
[[ -f $grant ]] || fail "the gaming-session package is missing the autologin grant"
[[ ! -e $ROOT/etc/sudoers.d/omarchy-handheld-autologin ]] || fail "the base tree still ships the autologin grant"
grep -q 'install -Dm440 "$srcdir/omarchy-handheld-autologin"' "$pkgbuild" ||
  fail "the package does not install the grant at mode 0440"
grep -q 'install -dm750 "$pkgdir/etc/sudoers.d"' "$pkgbuild" ||
  fail "the package does not create sudoers.d at mode 0750"
grep -q '"$pkgdir/etc/sudoers.d/omarchy-handheld-autologin"' "$pkgbuild" ||
  fail "the package does not install the grant into sudoers.d"
grep -q "iproute2" "$pkgbuild" || fail "the gaming session package does not depend on iproute2"
if grep -q 'SKIP' "$pkgbuild"; then
  fail "the gaming session package skips a source checksum"
fi
(
  cd "$ROOT/packages/omarchy-gaming-session"
  # makepkg sets startdir to this directory, then keeps only the basename.
  startdir=$PWD
  # shellcheck disable=SC1091
  source ./PKGBUILD
  (( ${#source[@]} == ${#sha256sums[@]} )) || exit 1
  for i in "${!source[@]}"; do
    [[ ${source[$i]} != */* ]] || exit 1
    [[ -f ${source[$i]} ]] || exit 1
    sum=$(sha256sum "${source[$i]}" | awk '{print $1}')
    [[ ${sha256sums[$i]} == "$sum" ]] || exit 1
  done
  for rel in \
    default/gaming/wayland-sessions/omarchy-gamescope.desktop \
    default/gaming/wayland-sessions/omarchy-handheld.desktop \
    'default/gaming/applications/Omarchy Gaming.desktop' \
    default/gaming/steamos-update \
    default/gaming/sddm-user.sh \
    LICENSE
  do
    grep -F -q "\$_repo/$rel" PKGBUILD || exit 1
    [[ -f $_repo/$rel ]] || exit 1
  done
) || fail "a gaming session source is not beside the PKGBUILD, or a checkout file it installs is missing"
grant_rule=$(grep -vE '^[[:space:]]*(#|$)' "$grant")
[[ $grant_rule == '%wheel ALL=(root) NOPASSWD: /usr/bin/omarchy-handheld-autologin fail, /usr/bin/omarchy-handheld-autologin reset, /usr/bin/omarchy-handheld-autologin apply' ]] ||
  fail "the package grant is not the three autologin verbs" "$grant_rule"
if command -v visudo >/dev/null; then
  visudo -cf "$grant" >/dev/null || fail "the package grant does not parse"
  pass "the autologin grant ships in the gaming-session package and parses"
else
  pass "the autologin grant ships in the gaming-session package"
  skip "visudo is not installed; skipping the autologin grant parse check"
fi
