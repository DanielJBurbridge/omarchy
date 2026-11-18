#!/bin/bash
# RC71L TDP writer: battery 20/20/25, AC 30/43/53, a bounded flock, and the
# resume unit running after wake. Nothing here touches a real Ally.

set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$here/base-test.sh"

apply=$ROOT/bin/omarchy-ally-tdp-apply
install=$ROOT/bin/omarchy-ally-tdp-install
[[ -x $apply && -x $install && -x $ROOT/bin/omarchy-ally-tdp-shim ]] || fail "the TDP commands are executable"

resume=$ROOT/default/systemd/system/omarchy-ally-tdp-resume.service
grep -q '^ExecStart=/bin/true$' "$resume" || fail "resume ExecStart writes nothing"
grep -q '^ExecStop=/usr/bin/omarchy-ally-tdp-apply --reassert$' "$resume" || fail "resume reasserts from ExecStop"
grep -q '^Before=sleep.target$' "$resume" || fail "resume is ordered before sleep"
grep -q '^WantedBy=sleep.target$' "$resume" || fail "resume is wanted by sleep"
grep -q '^RemainAfterExit=yes$' "$resume" || fail "resume stays active across sleep"
grep -q '^StopWhenUnneeded=yes$' "$resume" || fail "resume stops when sleep goes away"
grep -q 'ExecStart=.*--reassert' "$resume" && fail "resume writes on the way into sleep"
if grep -q 'PrepareForSleep\|--reassert' "$ROOT/bin/omarchy-ally-tdp-shim"; then
  fail "the shim reasserts on sleep"
fi
pass "resume reasserts after wake and the shim does not"

grep -q 'flock -w' "$apply" || fail "the writer waits with flock -w"
if grep -nE '(^|[[:space:]])flock([[:space:]]|$)' "$apply" | grep -v -- '-w'; then
  fail "the writer has a blocking flock"
fi
if grep -q 'NOPASSWD' "$apply" "$install" "$resume"; then
  fail "TDP adds a NOPASSWD sudoers rule"
fi
pass "the three stores take a bounded flock"

migration=$ROOT/migrations/1794842519.sh
[[ $(stat -c %a -- "$migration") == 644 ]] || fail "the migration is mode 0644"
[[ $(head -1 "$migration") != '#!'* ]] || fail "the migration has a shebang"
grep -q 'omarchy-hw-rog-ally' "$migration" || fail "the migration is gated on the Ally"
grep -q 'omarchy-pkg-present omarchy-gaming-session' "$migration" || fail "the session install is gated on the gaming package"
grep -q 'exit 1' "$migration" || fail "a failed install exits zero"
grep -q 'omarchy-ally-tdp-install" hardware' "$ROOT/install/hardware/asus/ally-tdp.sh" || fail "the hardware leaf installs the units"
grep -q 'omarchy-pkg-present omarchy-gaming-session' "$ROOT/install/hardware/asus/ally-tdp.sh" || fail "the leaf gates the session on the gaming package"
# shellcheck disable=SC2016
grep -q 'run_logged "$OMARCHY_INSTALL/hardware/asus/ally-tdp.sh"' "$ROOT/install/hardware/all.sh" || fail "hardware setup runs the Ally TDP leaf"
pass "the leaf and the migration install TDP on an Ally"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/supply/ADP1" "$work/supply/BAT1"

cat >"$work/bin/omarchy-hw-rog-ally" <<'EOF'
#!/bin/bash
if [[ ${HW:-ally} == ally ]]; then
  exit 0
fi
exit 1
EOF
cat >"$work/bin/logger" <<'EOF'
#!/bin/bash
if [[ $* == *"SPPT write failed"* ]]; then
  if [[ -n ${TEST_UNPLUG_ON_WRITE_FAILURE:-} ]]; then
    printf '0\n' >"$TEST_UNPLUG_ON_WRITE_FAILURE"
  elif [[ -n ${TEST_FPPT_CHANGE_ON_WRITE_FAILURE:-} ]]; then
    printf '52\n' >"$TEST_FPPT_CHANGE_ON_WRITE_FAILURE"
  fi
fi
exit 0
EOF
cat >"$work/bin/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"${SYSTEMCTL_LOG:?}"
if [[ ${SYSTEMCTL_FAIL:-0} == 1 ]]; then
  exit 1
fi
if [[ $1 == is-active ]]; then
  exit 3
fi
exit 0
EOF
cat >"$work/bin/udevadm" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$work/bin/busctl" <<'EOF'
#!/bin/bash
if [[ ${1:-} == --user ]]; then
  exec /usr/bin/busctl "$@"
fi
exit 0
EOF
cat >"$work/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
cat >"$work/bin/omarchy-pkg-present" <<'EOF'
#!/bin/bash
[[ $1 == omarchy-gaming-session && ${GAMING:-0} == 1 ]]
EOF
cat >"$work/bin/omarchy-shell" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$work/bin/omarchy-powerprofiles-list" <<'EOF'
#!/bin/bash
printf '%s\n' performance balanced power-saver
EOF
cat >"$work/bin/powerprofilesctl" <<'EOF'
#!/bin/bash
if [[ $1 == set ]]; then
  printf '%s\n' "$2" >>"${POWERPROFILES_LOG:?}"
fi
EOF
chmod +x "$work/bin/"*

armoury=$work/armoury
state=$work/state
run=$work/run
lock=$work/tdp.lock

write_attr() {
  local name=$1 min=$2 def=$3 max=$4 cur=$5
  local dir=$armoury/$name
  mkdir -p "$dir"
  printf '%s\n' "$min" >"$dir/min_value"
  printf '%s\n' "$def" >"$dir/default_value"
  printf '%s\n' "$max" >"$dir/max_value"
  printf '%s\n' "$cur" >"$dir/current_value"
}

ac_table() {
  write_attr ppt_pl1_spl 7 30 30 30
  write_attr ppt_pl2_sppt 15 43 43 43
  write_attr ppt_pl3_fppt 15 53 53 53
  printf '%s\n' Mains >"$work/supply/ADP1/type"
  printf '%s\n' 1 >"$work/supply/ADP1/online"
  printf '%s\n' Battery >"$work/supply/BAT1/type"
  printf '%s\n' 1 >"$work/supply/BAT1/online"
}

battery_table() {
  write_attr ppt_pl1_spl 7 15 25 15
  write_attr ppt_pl2_sppt 15 20 30 20
  write_attr ppt_pl3_fppt 15 25 35 25
  printf '%s\n' Mains >"$work/supply/ADP1/type"
  printf '%s\n' 0 >"$work/supply/ADP1/online"
  printf '%s\n' Battery >"$work/supply/BAT1/type"
  printf '%s\n' 1 >"$work/supply/BAT1/online"
}

reset_state() {
  rm -rf "$state" "$run" "$lock"
  mkdir -p "$state"
}

tuple() {
  printf '%s/%s/%s' \
    "$(<"$armoury/ppt_pl1_spl/current_value")" \
    "$(<"$armoury/ppt_pl2_sppt/current_value")" \
    "$(<"$armoury/ppt_pl3_fppt/current_value")"
}

run_apply() {
  HW=${HW:-ally} \
    OMARCHY_ALLY_TDP_FIXTURE=1 \
    OMARCHY_ALLY_TDP_ARMOURY=$armoury \
    OMARCHY_ALLY_TDP_POWER=$work/supply \
    OMARCHY_ALLY_TDP_STATE=$state \
    OMARCHY_ALLY_TDP_RUN=$run \
    OMARCHY_ALLY_TDP_LOCK=$lock \
    OMARCHY_ALLY_TDP_BOOT_ID=boot \
    PATH="$work/bin:$PATH" \
    "$apply" "$@"
}

stored() {
  if [[ -f $state/request ]]; then
    cat "$state/request"
  fi
}

reset_state
battery_table
run_apply --set 25 >/dev/null
[[ $(tuple) == 20/20/25 ]] || fail "battery --set 25 applies 20/20/25" "$(tuple)"
[[ $(stored) == 25 ]] || fail "battery --set 25 stores 25" "$(stored)"
reset_state
battery_table
run_apply --set 20 >/dev/null
[[ $(tuple) == 20/20/25 ]] || fail "battery --set 20 applies 20/20/25" "$(tuple)"
[[ $(stored) == 20 ]] || fail "battery --set 20 stores 20"
pass "battery 20 and 25 apply 20/20/25"

reset_state
ac_table
run_apply --set 30 >/dev/null
[[ $(tuple) == 30/43/53 ]] || fail "AC --set 30 applies 30/43/53" "$(tuple)"
[[ $(stored) == 30 ]] || fail "AC --set 30 stores 30"
battery_table
run_apply --reassert >/dev/null
[[ $(tuple) == 20/20/25 ]] || fail "unplug applies 20/20/25" "$(tuple)"
[[ $(stored) == 30 ]] || fail "unplug keeps the stored 30" "$(stored)"
ac_table
run_apply --reassert >/dev/null
[[ $(tuple) == 30/43/53 ]] || fail "replug restores 30/43/53" "$(tuple)"
[[ $(stored) == 30 ]] || fail "replug keeps the stored 30"
pass "unplug clamps a stored 30 and replug restores it"

reset_state
ac_table
printf 'USB\n' >"$work/supply/ADP1/type"
printf 'Device\n' >"$work/supply/ADP1/scope"
run_apply --set 30 >/dev/null
[[ $(tuple) == 20/20/25 ]] || fail "an online USB peripheral does not raise the power limit" "$(tuple)"
printf 'System\n' >"$work/supply/ADP1/scope"
run_apply --reassert >/dev/null
[[ $(tuple) == 30/43/53 ]] || fail "an online system USB supply uses the AC limit" "$(tuple)"
printf '0\n' >"$work/supply/ADP1/online"
run_apply --reassert >/dev/null
[[ $(tuple) == 20/20/25 ]] || fail "an offline USB supply uses the battery limit" "$(tuple)"
rm "$work/supply/ADP1/scope"
pass "USB raises the limit only while it supplies system power"

reset_state
battery_table
run_apply --set 5 >/dev/null
[[ $(tuple) == 7/15/15 ]] || fail "--set 5 writes the SPL floor" "$(tuple)"
[[ $(stored) == 5 ]] || fail "--set 5 stores 5"
before=$(tuple)
if run_apply --set 015 >/dev/null 2>"$work/err"; then
  fail "015 is accepted"
fi
if run_apply --set +15 >/dev/null 2>>"$work/err"; then
  fail "+15 is accepted"
fi
if run_apply --set 15.5 >/dev/null 2>>"$work/err"; then
  fail "15.5 is accepted"
fi
if run_apply --set 1e1 >/dev/null 2>>"$work/err"; then
  fail "1e1 is accepted"
fi
[[ $(tuple) == "$before" ]] || fail "a bad watt string writes" "$(tuple)"
pass "a non-canonical watt writes nothing and --set 5 clamps up"

reset_state
battery_table
write_attr ppt_pl1_spl 7 15 25 9
write_attr ppt_pl2_sppt 40 40 50 40
write_attr ppt_pl3_fppt 15 25 35 25
if run_apply --set 15 >/dev/null 2>"$work/err"; then
  fail "a tuple that breaks order is written"
fi
[[ $(tuple) == 9/40/25 ]] || fail "a rejected plan still writes" "$(tuple)"
pass "a tuple that breaks order writes nothing"

reset_state
ac_table
run_apply --set 30 >/dev/null
sppt_file=$armoury/ppt_pl2_sppt/current_value
chmod 0444 "$sppt_file"
if run_apply --set 12 >/dev/null 2>"$work/err"; then
  fail "a failed SPPT write reports success"
fi
[[ $(tuple) == 30/43/53 ]] || fail "a failed SPPT write restores the earlier SPL write" "$(tuple)"
[[ $(stored) == 30 ]] || fail "a failed TDP write changes the saved request" "$(stored)"

fppt_file=$armoury/ppt_pl3_fppt/current_value
if TEST_FPPT_CHANGE_ON_WRITE_FAILURE="$fppt_file" run_apply --set 12 >/dev/null 2>"$work/err"; then
  fail "a failed SPPT write reports success after the firmware changes FPPT"
fi
[[ $(tuple) == 30/43/52 ]] || fail "rollback preserves an FPPT value it did not write" "$(tuple)"
grep -q 'TDP rollback incomplete.*30,43,52' "$work/err" ||
  fail "the remaining mismatch after rollback is not logged" "$(cat "$work/err")"
printf '53\n' >"$fppt_file"

if TEST_UNPLUG_ON_WRITE_FAILURE="$work/supply/ADP1/online" run_apply --set 12 >/dev/null 2>"$work/err"; then
  fail "a failed SPPT write during unplug reports success"
fi
chmod 0644 "$sppt_file"
[[ $(<"$work/supply/ADP1/online") == 0 ]] || fail "unplug fixture did not switch the power source"
[[ $(tuple) == 12/43/53 ]] || fail "rollback replays the AC setting after unplug" "$(tuple)"
[[ $(stored) == 30 ]] || fail "a failed write during unplug changes the saved request" "$(stored)"
grep -q 'power source changed.*rollback skipped' "$work/err" ||
  fail "skipping rollback when the power source changes is not logged" "$(cat "$work/err")"
pass "a partial write rolls back only on the original power source"

reset_state
ac_table
write_attr ppt_pl1_spl 7 30 30 1
write_attr ppt_pl2_sppt 15 43 43 1
write_attr ppt_pl3_fppt 15 53 53 1
flock "$lock" -c 'sleep 30' &
holder=$!
held=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ! flock -w 0 "$lock" true; then
    held=1
    break
  fi
  sleep 0.05
done
[[ $held == 1 ]] || fail "the test could not hold the lock"
started=$SECONDS
if OMARCHY_ALLY_TDP_LOCK_WAIT=1 run_apply --set 15 >"$work/out" 2>"$work/err"; then
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true
  fail "a busy lock still writes"
fi
elapsed=$(( SECONDS - started ))
kill "$holder" 2>/dev/null || true
wait "$holder" 2>/dev/null || true
(( elapsed < 4 )) || fail "flock -w did not give up" "waited ${elapsed}s"
grep -q 'timed out' "$work/err" || fail "a lock timeout is not logged" "$(cat "$work/err")"
[[ $(tuple) == 1/1/1 ]] || fail "a lock timeout still writes" "$(tuple)"
pass "a busy lock logs, exits non-zero, and writes nothing"

reset_state
ac_table
cat >"$work/bin/flock" <<'EOF'
#!/bin/bash
printf '0\n' > "$TEST_AC_ONLINE"
exec /usr/bin/flock "$@"
EOF
chmod +x "$work/bin/flock"
TEST_AC_ONLINE="$work/supply/ADP1/online" run_apply --set 30 >"$work/out"
rm "$work/bin/flock"
grep -q '^source=battery$' "$work/out" || fail "TDP uses the power source after acquiring the lock" "$(cat "$work/out")"
[[ $(tuple) == 20/20/25 ]] || fail "an unplug while waiting for the lock applies battery caps" "$(tuple)"
pass "an unplug while waiting for the lock applies battery caps"

reset_state
battery_table
if HW=laptop run_apply --set 15 >/dev/null 2>"$work/err"; then
  fail "a laptop can set TDP"
fi
[[ $(tuple) == 15/20/25 ]] || fail "a laptop writes the attributes" "$(tuple)"
HW=ally
rm -f "$armoury/ppt_pl3_fppt/current_value"
if run_apply --show >/dev/null 2>"$work/err"; then
  fail "a missing attribute still shows"
fi
pass "a laptop and a missing attribute write nothing"

reset_state
ac_table
run_apply --set 30 >/dev/null
battery_table
if OMARCHY_ALLY_TDP_CONFLICT=asusd.service run_apply --set 18 >/dev/null 2>"$work/err"; then
  fail "asusd does not block --set"
fi
if OMARCHY_ALLY_TDP_CONFLICT=asusd.service run_apply --snapshot >/dev/null 2>"$work/err"; then
  fail "asusd does not block --snapshot"
fi
OMARCHY_ALLY_TDP_CONFLICT=asusd.service run_apply --reassert >/dev/null 2>"$work/err" ||
  fail "background reapply must defer to the active owner without failing" "$(cat "$work/err")"
[[ $(tuple) == 15/20/25 && $(stored) == 30 ]] ||
  fail "a conflict changes firmware limits or the stored request" "$(tuple), $(stored)"
pass "an active asusd blocks explicit requests and background reapply defers without writing"

reset_state
battery_table
show=$(run_apply --show)
grep -q '^source=battery$' <<<"$show" || fail "--show does not name the source" "$show"
grep -q '^max=20$' <<<"$show" || fail "--show max is not the battery cap" "$show"
grep -q '^writable=1$' <<<"$show" || fail "--show is not writable" "$show"
pass "--show reports the battery window"

dest=$work/dest
SYSTEMCTL_LOG=$work/systemctl.log
export SYSTEMCTL_LOG
: >"$SYSTEMCTL_LOG"
HW=laptop OMARCHY_PATH=$ROOT OMARCHY_ALLY_TDP_FIXTURE=1 OMARCHY_ALLY_TDP_DEST=$dest \
  PATH="$work/bin:$PATH" bash -euo pipefail "$migration"
[[ ! -e $dest/etc/udev/rules.d/99-omarchy-ally-tdp.rules ]] || fail "a laptop migration installs udev"
[[ ! -e $dest/usr/share/polkit-1/actions/org.omarchy.ally.set-tdp.policy ]] || fail "a laptop migration installs the TDP policy"
[[ ! -e $dest/etc/polkit-1/rules.d/50-omarchy-ally-set-tdp.rules ]] || fail "a laptop migration installs the TDP rule"
pass "a laptop migration does nothing"

rm -rf "$dest"
mkdir -p "$dest"
: >"$SYSTEMCTL_LOG"
SYSTEMCTL_FAIL=1 HW=ally OMARCHY_PATH=$ROOT OMARCHY_ALLY_TDP_FIXTURE=1 OMARCHY_ALLY_TDP_DEST=$dest \
  PATH="$work/bin:$PATH" bash -euo pipefail "$migration" >"$work/migrate.out" 2>"$work/migrate.err" &&
  fail "a failed install exits zero"
grep -q 'Ally TDP hardware install failed' "$work/migrate.err" || fail "a failed install is silent" "$(cat "$work/migrate.err")"
pass "a failed install exits non-zero"

unset SYSTEMCTL_FAIL
rm -rf "$dest"
mkdir -p "$dest"
: >"$SYSTEMCTL_LOG"
mkdir -p "$dest/etc/sddm.conf.d" "$dest/usr/share/polkit-1/actions"
printf 'User=ally\n' >"$dest/etc/sddm.conf.d/omarchy-handheld-user.conf"
cp "$ROOT/default/polkit/org.omarchy.ally.set-tdp.policy" \
  "$dest/usr/share/polkit-1/actions/org.omarchy.ally.set-tdp.policy"
HW=ally GAMING=0 OMARCHY_PATH=$ROOT OMARCHY_ALLY_TDP_FIXTURE=1 OMARCHY_ALLY_TDP_DEST=$dest \
  PATH="$work/bin:$PATH" bash -euo pipefail "$migration"
[[ -f $dest/etc/systemd/system/omarchy-ally-tdp-resume.service ]] || fail "hardware install skips the resume unit"
[[ -f $dest/etc/udev/rules.d/99-omarchy-ally-tdp.rules ]] || fail "hardware install skips udev"
[[ ! -e $dest/etc/systemd/user/omarchy-ally-tdp-shim.service ]] || fail "hardware install adds the shim without the gaming session"
grep -q 'mask power-profiles-daemon' "$SYSTEMCTL_LOG" && fail "hardware install masks power-profiles-daemon"
hardware_rule=$(cat "$dest/etc/polkit-1/rules.d/50-omarchy-ally-set-tdp.rules")
grep -q 'return polkit.Result.NO;' <<<"$hardware_rule" || fail "a desktop-only Ally does not return NO"
grep -q 'polkit.Result.YES' <<<"$hardware_rule" && fail "a desktop-only Ally authorizes a user" "$hardware_rule"
grep -q 'subject.user == "ally"' <<<"$hardware_rule" && fail "hardware install grants the handheld user"
pass "hardware install leaves the gaming session alone and denies TDP"

printf '// existing policy\n' >"$dest/etc/polkit-1/rules.d/50-omarchy-ally-set-tdp.rules"
: >"$SYSTEMCTL_LOG"
HW=ally OMARCHY_PATH=$ROOT OMARCHY_ALLY_TDP_FIXTURE=1 OMARCHY_ALLY_TDP_DEST=$dest \
  PATH="$work/bin:$PATH" "$install" power-source
grep -q 'enable omarchy-ally-tdp-source.path$' "$SYSTEMCTL_LOG" ||
  fail "refreshing the source units enables the watcher"
[[ $(cat "$dest/etc/polkit-1/rules.d/50-omarchy-ally-set-tdp.rules") == "// existing policy" ]] ||
  fail "refreshing the source units preserves the installed policy"
pass "a power-source refresh enables the watcher without changing permissions"

rm -rf "$dest"
mkdir -p "$dest/etc/sddm.conf.d"
printf 'User=sddm\n' >"$dest/etc/sddm.conf.d/omarchy-handheld-user.conf"
chmod 644 "$dest/etc/sddm.conf.d/omarchy-handheld-user.conf"
: >"$SYSTEMCTL_LOG"
HW=ally GAMING=1 OMARCHY_PATH=$ROOT OMARCHY_ALLY_TDP_FIXTURE=1 OMARCHY_ALLY_TDP_DEST=$dest \
  PATH="$work/bin:$PATH" "$install" session
[[ -f $dest/etc/systemd/user/omarchy-ally-tdp-shim.service ]] || fail "session install skips the shim"
grep -q 'enable omarchy-ally-tdp-source.path$' "$SYSTEMCTL_LOG" ||
  fail "session install without hardware setup leaves power changes unwatched"
grep -q 'enable omarchy-ally-tdp-resume.service$' "$SYSTEMCTL_LOG" ||
  fail "session install without hardware setup leaves resume unwatched"
[[ -f $dest/usr/share/dbus-1/services/com.steampowered.SteamOSManager1.service ]] || fail "session install skips activation"
grep -q 'SystemdService=omarchy-ally-tdp-shim.service' \
  "$dest/usr/share/dbus-1/services/com.steampowered.SteamOSManager1.service" ||
  fail "activation still names steamos-manager"
grep -q 'mask power-profiles-daemon' "$SYSTEMCTL_LOG" || fail "session install does not mask power-profiles-daemon"
rule=$(cat "$dest/etc/polkit-1/rules.d/50-omarchy-ally-set-tdp.rules")
grep -q 'subject.user == "sddm"' <<<"$rule" || fail "the rule does not refuse sddm"
grep -q 'polkit.Result.NO' <<<"$rule" || fail "the rule does not return NO"
grep -q 'polkit.Result.YES' <<<"$rule" && fail "sddm becomes the YES user"
grep -q 'wheel' <<<"$rule" && fail "the rule grants wheel"
[[ -f $dest/usr/share/polkit-1/actions/org.omarchy.ally.set-tdp.policy ]] || fail "session install skips the policy"
PATH="$work/bin:$PATH" HW=ally GAMING=1 OMARCHY_PATH=$ROOT OMARCHY_ALLY_TDP_FIXTURE=1 OMARCHY_ALLY_TDP_DEST=$dest \
  "$install" remove-session
removed=$(cat "$dest/etc/polkit-1/rules.d/50-omarchy-ally-set-tdp.rules")
grep -q 'polkit.Result.YES' <<<"$removed" && fail "removing the session leaves YES"
grep -q 'return polkit.Result.NO;' <<<"$removed" || fail "removing the session drops the deny rule"
[[ -f $dest/usr/share/polkit-1/actions/org.omarchy.ally.set-tdp.policy ]] || fail "removing the session drops the hardware policy"
pass "the gaming session sets up power reapply, masks power-profiles-daemon and refuses sddm"

HW=ally OMARCHY_PATH=$ROOT OMARCHY_ALLY_TDP_FIXTURE=1 OMARCHY_ALLY_TDP_DEST=$dest \
  PATH="$work/bin:$PATH" "$install" remove
[[ ! -e $dest/etc/systemd/system/omarchy-ally-tdp-source.path && ! -e $dest/etc/systemd/system/omarchy-ally-tdp-resume.service ]] ||
  fail "full TDP removal leaves reapply units installed"
pass "full TDP removal clears the reapply units"

yes_dest=$work/yes-dest
rm -rf "$yes_dest"
# shellcheck disable=SC2016
if unshare --user --map-root-user --mount --propagation private bash -c '
  set -euo pipefail
  dest=$1
  root=$2
  stub=$3
  mkdir -p "$dest/etc/sddm.conf.d"
  printf "User=ally\n" >"$dest/etc/sddm.conf.d/omarchy-handheld-user.conf"
  chown 0:0 "$dest/etc/sddm.conf.d/omarchy-handheld-user.conf"
  chmod 644 "$dest/etc/sddm.conf.d/omarchy-handheld-user.conf"
  export HW=ally GAMING=1 OMARCHY_PATH=$root
  export OMARCHY_ALLY_TDP_FIXTURE=1 OMARCHY_ALLY_TDP_DEST=$dest
  export SYSTEMCTL_LOG=$dest/systemctl.log
  : >"$SYSTEMCTL_LOG"
  PATH=$stub "$root/bin/omarchy-ally-tdp-install" hardware
  wide=$(cat "$dest/etc/polkit-1/rules.d/50-omarchy-ally-set-tdp.rules")
  grep -q "polkit.Result.YES" <<<"$wide" && exit 1
  grep -q "return polkit.Result.NO;" <<<"$wide"
  PATH=$stub bash "$root/migrations/1794842519.sh"
  rule=$(cat "$dest/etc/polkit-1/rules.d/50-omarchy-ally-set-tdp.rules")
  grep -q "subject.user == \"ally\"" <<<"$rule"
  grep -q "polkit.Result.YES" <<<"$rule"
  grep -q "subject.user == \"sddm\"" <<<"$rule"
  grep -q "return polkit.Result.NO;" <<<"$rule"
  grep -F -q "%s" <<<"$rule"
  grep -F -q "\\n" <<<"$rule"
  if grep -q "@USER@" <<<"$rule"; then
    exit 1
  fi
' bash "$yes_dest" "$ROOT" "$work/bin:$PATH"; then
  pass "only the recorded handheld user is YES"
else
  fail "the recorded handheld user is not YES"
fi

marker=$work/ppd-state
printf 'enabled\n' >"$marker"
POWERPROFILES_LOG=$work/profiles
: >"$POWERPROFILES_LOG"
export POWERPROFILES_LOG
profile_env=(
  HW=ally
  OMARCHY_ALLY_TDP_PPD_RECORD=$marker
  OMARCHY_ALLY_TDP_FIXTURE=1
  OMARCHY_ALLY_TDP_ARMOURY=$armoury
  OMARCHY_ALLY_TDP_POWER=$work/supply
  OMARCHY_ALLY_TDP_STATE=$state
  OMARCHY_ALLY_TDP_RUN=$run
  OMARCHY_ALLY_TDP_LOCK=$lock
  OMARCHY_ALLY_TDP_BOOT_ID=boot
  OMARCHY_POWERPROFILES_STATE_DIR=$work/profiles-state
  PATH="$work/bin:$ROOT/bin:$PATH"
)
set_profile() {
  env "${profile_env[@]}" "$ROOT/bin/omarchy-powerprofiles-set" "$@"
}
reset_state
battery_table
mkdir -p "$work/profiles-state"
printf 'balanced\n' >"$work/profiles-state/battery"
if OMARCHY_ALLY_TDP_CONFLICT=asusd.service set_profile battery performance; then
  fail "a refused TDP write still reports success"
fi
[[ $(<"$work/profiles-state/battery") == balanced ]] || fail "a refused profile is recorded" "$(<"$work/profiles-state/battery")"
[[ $(tuple) == 15/20/25 ]] || fail "a refused profile still writes" "$(tuple)"
unset OMARCHY_ALLY_TDP_CONFLICT
set_profile battery performance
[[ ! -s $POWERPROFILES_LOG ]] || fail "a masked daemon still calls powerprofilesctl" "$(cat "$POWERPROFILES_LOG")"
[[ $(tuple) == 20/20/25 ]] || fail "battery performance does not clamp to 20/20/25" "$(tuple)"
[[ $(stored) == 30 ]] || fail "battery performance does not request the AC policy" "$(stored)"
[[ $(<"$work/profiles-state/battery") == performance ]] || fail "battery performance is not recorded"
set_profile battery power-saver
[[ $(tuple) == 7/15/15 ]] || fail "battery power-saver does not apply the live floor" "$(tuple)"
[[ $(stored) == 7 ]] || fail "battery power-saver does not store the floor" "$(stored)"
[[ $(<"$work/profiles-state/battery") == power-saver ]] || fail "battery power-saver is not recorded"
ac_table
set_profile ac balanced
[[ $(tuple) == 20/29/35 ]] || fail "AC balanced does not apply the battery policy" "$(tuple)"
[[ $(stored) == 20 ]] || fail "AC balanced does not store the battery policy" "$(stored)"
[[ $(<"$work/profiles-state/ac") == balanced ]] || fail "AC balanced is not recorded"
set_profile ac performance
[[ $(tuple) == 30/43/53 ]] || fail "AC performance does not apply 30/43/53" "$(tuple)"
[[ $(stored) == 30 ]] || fail "AC performance does not store 30" "$(stored)"
[[ $(<"$work/profiles-state/ac") == performance ]] || fail "AC performance is not recorded"
pass "a masked profile switch applies the mapped TDP and records only that"

python3 -m py_compile "$ROOT/bin/omarchy-ally-tdp-shim"
if grep -q 'current_value' "$ROOT/bin/omarchy-ally-tdp-shim"; then
  fail "the shim writes sysfs"
fi
grep -q 'pkexec' "$ROOT/bin/omarchy-ally-tdp-shim" || fail "the shim does not pkexec the writer"
python3 - <<PY
from pathlib import Path
import re
root = Path("$ROOT")
pattern = re.compile(r"<interface name=\"com.steampowered.SteamOSManager1.TdpLimit1\">.*</interface>", re.S)
xml = (root / "default/ally-tdp/com.steampowered.SteamOSManager1.TdpLimit1.xml").read_text()
notice = (root / "default/ally-tdp/NOTICE.steamos-manager").read_text()
if pattern.search(xml) is None or "MIT" not in notice:
    raise SystemExit(1)
if (root / "packaging").exists():
    raise SystemExit(1)
PY
pass "the shim compiles and the vendored interface is the default tree"

cat >"$work/shim-session.sh" <<EOF
#!/bin/bash
set -euo pipefail
export HW=ally
export OMARCHY_PATH=$ROOT
export OMARCHY_ALLY_TDP_NO_PKEXEC=1
export OMARCHY_ALLY_TDP_APPLY=$apply
export OMARCHY_ALLY_TDP_FIXTURE=1
export OMARCHY_ALLY_TDP_ARMOURY=$armoury
export OMARCHY_ALLY_TDP_POWER=$work/supply
export OMARCHY_ALLY_TDP_STATE=$state
export OMARCHY_ALLY_TDP_RUN=$run
export OMARCHY_ALLY_TDP_LOCK=$lock
export OMARCHY_ALLY_TDP_BOOT_ID=boot
export PATH=$work/bin:\$PATH
"\$ROOT/bin/omarchy-ally-tdp-shim" &
pid=\$!
trap 'kill "\$pid" 2>/dev/null || true; wait "\$pid" 2>/dev/null || true' EXIT
ready=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if busctl --user status com.steampowered.SteamOSManager1 >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.2
done
[[ \$ready == 1 ]]
model=\$(busctl --user get-property com.steampowered.SteamOSManager1 /com/steampowered/SteamOSManager1 com.steampowered.SteamOSManager1.Manager2 DeviceModel)
[[ \$model == *rog_ally* && \$model == *RC71L* ]]
bus=com.steampowered.SteamOSManager1
object=/com/steampowered/SteamOSManager1
interface=\$bus.TdpLimit1
python3 - <<'PY'
import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio

bus = "com.steampowered.SteamOSManager1"
path = "/com/steampowered/SteamOSManager1"
manager = Gio.DBusObjectManagerClient.new_for_bus_sync(
    Gio.BusType.SESSION, Gio.DBusObjectManagerClientFlags.DO_NOT_AUTO_START, bus, "/",
)
tdp = manager.get_interface(path, bus + ".TdpLimit1")
assert tdp is not None, "Steam discovery could not find TdpLimit1"
for name, value in {"TdpLimit": 30, "TdpLimitMin": 7, "TdpLimitMax": 30}.items():
    prop = tdp.get_cached_property(name)
    assert prop is not None and prop.get_uint32() == value, name
gpu = manager.get_interface(path, bus + ".GpuPerformanceLevel1")
assert gpu.get_cached_property("ManualGpuClock") is None
PY
busctl --user set-property "\$bus" "\$object" "\$interface" TdpLimit u 30
[[ \$(busctl --user get-property "\$bus" "\$object" "\$interface" TdpLimitMax) == "u 30" ]]
expect_tdp_update() {
  local limit=\$1
  for _ in {1..50}; do
    if grep -q "PropertiesChanged.*TdpLimitMax.*uint32 \$limit" "$work/tdp-signals"; then return 0; fi
    sleep 0.1
  done
  printf 'No TDP update to %s: %s\\n' "\$limit" "\$(cat "$work/tdp-signals")" >&2
  return 1
}
stdbuf -oL gdbus monitor --session --dest "\$bus" --object-path "\$object" > "$work/tdp-signals" &
monitor=\$!
trap 'kill "\$monitor" "\$pid" 2>/dev/null || true; wait "\$monitor" "\$pid" 2>/dev/null || true' EXIT
for _ in {1..50}; do
  if grep -q 'is owned by' "$work/tdp-signals"; then break; fi
  sleep 0.1
done
grep -q 'is owned by' "$work/tdp-signals"
printf '0\\n' > "\$OMARCHY_ALLY_TDP_POWER/ADP1/online"
"\$OMARCHY_ALLY_TDP_APPLY" --reassert >/dev/null
expect_tdp_update 20
[[ \$(busctl --user get-property "\$bus" "\$object" "\$interface" TdpLimit) == "u 20" ]]
[[ \$(busctl --user get-property "\$bus" "\$object" "\$interface" TdpLimitMax) == "u 20" ]]
[[ \$(<"\$OMARCHY_ALLY_TDP_STATE/request") == 30 ]]

# With no saved setting, a power change still updates the slider bounds.
rm "\$OMARCHY_ALLY_TDP_STATE/request"
printf '1\\n' > "\$OMARCHY_ALLY_TDP_POWER/ADP1/online"
"\$OMARCHY_ALLY_TDP_APPLY" --reassert >/dev/null
expect_tdp_update 30
[[ \$(busctl --user get-property "\$bus" "\$object" "\$interface" TdpLimitMax) == "u 30" ]]
EOF
chmod +x "$work/shim-session.sh"
ac_table
reset_state
if dbus-run-session -- bash "$work/shim-session.sh"; then
  [[ $(tuple) == 20/20/25 ]] || fail "a reassert without a request writes to firmware" "$(tuple)"
  [[ -z $(stored) ]] || fail "a reassert without a request persists a setting" "$(stored)"
  pass "clients discover the TDP shim and receive external reassert updates"
else
  fail "a client could not discover the shim or receive external TDP changes"
fi
