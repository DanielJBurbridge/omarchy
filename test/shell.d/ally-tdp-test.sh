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
export SYSTEMCTL_LOG=$work/systemctl.log

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
if [[ $1 == --root=* && ${!#} == power-profiles-daemon.service ]]; then
  root=${1#--root=}
  shift
  unit=power-profiles-daemon.service
  persistent=$root/etc/systemd/system
  runtime=$root/run/systemd/system
  case $1 in
    is-enabled)
      if [[ -L $persistent/$unit ]]; then
        echo masked
        exit 1
      elif [[ -L $runtime/$unit ]]; then
        echo masked-runtime
        exit 1
      elif [[ -L $persistent/multi-user.target.wants/$unit ]]; then
        echo enabled
      elif [[ -L $runtime/multi-user.target.wants/$unit ]]; then
        echo enabled-runtime
      else
        echo disabled
        exit 1
      fi
      ;;
    show)
      if [[ -e $root/ppd-active ]]; then echo active; else echo inactive; fi
      ;;
    start)
      [[ ${PPD_FAIL:-} != start && ! -L $persistent/$unit && ! -L $runtime/$unit ]] || exit 1
      touch "$root/ppd-active"
      ;;
    stop)
      [[ ${PPD_FAIL:-} != stop ]] || exit 1
      rm -f -- "$root/ppd-active"
      ;;
    mask)
      ln -sT -- /dev/null "$persistent/$unit"
      ;;
    unmask)
      rm -f -- "$persistent/$unit" "$runtime/$unit"
      ;;
    enable)
      mkdir -p "$persistent/multi-user.target.wants"
      ln -sTf -- "/usr/lib/systemd/system/$unit" "$persistent/multi-user.target.wants/$unit"
      ;;
    disable)
      rm -f -- "$persistent/multi-user.target.wants/$unit" "$runtime/multi-user.target.wants/$unit"
      ;;
  esac
  exit
fi
if [[ $1 == is-active ]]; then
  shift
  result=3
  for unit in "$@"; do
    if [[ $unit == "${OMARCHY_ALLY_TDP_CONFLICT:-}" || ( $unit == "asusd.service" && -e ${TEST_OWNER_STARTED:-} ) ]]; then
      echo active
      result=0
    else
      echo inactive
    fi
  done
  exit "$result"
fi
if [[ $1 == is-enabled && $2 == power-profiles-daemon.service && ${PPD_MASKED:-0} == "1" ]]; then
  printf 'masked\n'
  exit 1
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
if [[ ${!#} == "ListNames" ]]; then
  printf 'as 2 "org.freedesktop.DBus" "%s"\n' "${PPD_OWNER:-:1.0}"
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
cat >"$work/bin/powerprofilesctl" <<'EOF'
#!/bin/bash
if [[ ${PPD_MASKED:-0} == "1" && -z ${PPD_OWNER:-} ]]; then
  printf 'masked daemon: %s\n' "$*" >>"${POWERPROFILES_LOG:?}"
  exit 1
fi
if [[ $1 == list ]]; then
  printf '  performance:\n* balanced:\n  power-saver:\n'
fi
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
    head -n 1 "$state/request"
  fi
}

ac_table
boot_cache=$work/boot-run/omarchy-ally-tdp/boot
mkdir -p "$boot_cache/unknown/ac" "$work/boot-sys/class/firmware-attributes/asus-armoury"
ln -s "$armoury" "$work/boot-sys/class/firmware-attributes/asus-armoury/attributes"
ln -s "$work/supply" "$work/boot-sys/class/power_supply"
printf '15\n' >"$boot_cache/unknown/ac/ppt_pl1_spl.max_value"
# Exercise the production path in a rootless namespace with an old cache.
show=$(PATH="$work/bin:$PATH" OMARCHY_ALLY_TDP_FIXTURE=1 OMARCHY_ALLY_TDP_BOOT_ID=unknown \
  unshare --user --map-root-user --mount --propagation private bash -euc '
    mount --bind "$1/boot-sys" /sys
    mount --bind "$1/boot-run" /run
    mount -t tmpfs tmpfs /var/lib
    "$2" --snapshot
  ' bash "$work" "$apply")
grep -Fxq 'max=30' <<<"$show" && [[ -f $boot_cache/$(</proc/sys/kernel/random/boot_id)/ac/ppt_pl1_spl.max_value ]] ||
  fail "the current boot must snapshot its own AC ceiling" "$show"
pass "the current boot ignores an earlier TDP snapshot"

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
write_attr ppt_pl1_spl 7 25 25 25
printf 'unavailable\n' >"$armoury/ppt_pl3_fppt/min_value"
if run_apply --set 30 >/dev/null 2>"$work/err"; then fail "a partial firmware read succeeded"; fi
[[ $(tuple) == 25/43/53 && -z $(stored) ]] || fail "a failed capture changed the limits or saved request"
ac_table
# An older release could already have left its SPL ceiling behind.
mkdir -p "$run/boot/boot/ac"
printf '25\n' >"$run/boot/boot/ac/ppt_pl1_spl.max_value"
show=$(run_apply --show)
grep -Fxq 'max=30' <<<"$show" || fail "a partial AC snapshot caps the Steam slider" "$show"
run_apply --set 30 >/dev/null
[[ $(tuple) == 30/43/53 ]] || fail "a partial previous snapshot caps the next AC request" "$(tuple)"
pass "an incomplete capture is ignored and a steady AC request recovers"

reset_state
ac_table
cat >"$work/unplug-at-read" <<'EOF'
read() {
  if [[ /dev/stdin -ef $OMARCHY_ALLY_TDP_ARMOURY/ppt_pl2_sppt/default_value ]]; then
    printf '0\n' >"$OMARCHY_ALLY_TDP_POWER/ADP1/online"
  fi
  builtin read "$@"
}
EOF
if BASH_ENV="$work/unplug-at-read" run_apply --snapshot >/dev/null 2>"$work/err"; then
  fail "an AC snapshot was published across unplug"
fi
[[ $(<"$work/supply/ADP1/online") == 0 && ! -d $run/boot/boot/ac ]] ||
  fail "the charger changed but left a published AC snapshot"
pass "an unplug during collection discards the AC snapshot"

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

# asusd can start while a Steam request is waiting for another firmware writer.
cat >"$work/bin/flock" <<'EOF'
#!/bin/bash
: >"$TEST_OWNER_STARTED"
exec /usr/bin/flock "$@"
EOF
chmod +x "$work/bin/flock"
if TEST_OWNER_STARTED="$work/asusd-started" run_apply --set 18 >/dev/null 2>"$work/err"; then
  fail "a queued request wrote after asusd took ownership"
fi
rm "$work/bin/flock"
[[ $(tuple) == 15/20/25 && $(stored) == 30 ]] || fail "the queued request changed the previous limits"
grep -Fq 'asusd.service' "$work/err" || fail "the queued request reports the conflicting owner"
pass "a queued request respects a new power owner"

show=$(SYSTEMCTL_FAIL=1 run_apply --show)
grep -Fxq 'writable=0' <<<"$show" && grep -Fxq 'conflict=unknown' <<<"$show" ||
  fail "a systemd query failure leaves the firmware read-only" "$show"

reset_state
battery_table
show=$(run_apply --show)
grep -q '^source=battery$' <<<"$show" || fail "--show does not name the source" "$show"
grep -q '^max=20$' <<<"$show" || fail "--show max is not the battery cap" "$show"
grep -q '^writable=1$' <<<"$show" || fail "--show is not writable" "$show"
pass "--show reports the battery window"

dest=$work/dest
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
[[ ! -L $dest/etc/systemd/system/power-profiles-daemon.service ]] || fail "hardware install masks power-profiles-daemon"
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
[[ -L $dest/etc/systemd/system/power-profiles-daemon.service ]] || fail "session install does not mask power-profiles-daemon"
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

# Exercise the installer's live PPD activity decisions with the same scratch
# root and systemctl stub. All other fixture-mode guards stay in effect.
# shellcheck disable=SC2016
sed '/^ppd_activity() {$/,+1 s/if \[\[ -n \$prefix \]\]; then/if false; then/' "$install" >"$work/install-ppd"
run_ppd_install() {
  HW=ally GAMING=1 OMARCHY_PATH=$ROOT OMARCHY_ALLY_TDP_FIXTURE=1 OMARCHY_ALLY_TDP_DEST=$dest \
    PATH="$work/bin:$PATH" bash "$work/install-ppd" "$@"
}

ppd=power-profiles-daemon.service
ppd_mask=$dest/etc/systemd/system/$ppd
ppd_runtime_mask=$dest/run/systemd/system/$ppd
ppd_enabled=$dest/etc/systemd/system/multi-user.target.wants/$ppd
ppd_runtime_enabled=$dest/run/systemd/system/multi-user.target.wants/$ppd
ppd_receipt=$dest/var/lib/omarchy/handheld/power-profiles-daemon.state
ppd_active=$dest/ppd-active
mkdir -p "${ppd_runtime_enabled%/*}"
ln -s "/usr/lib/systemd/system/$ppd" "$ppd_runtime_enabled"
run_ppd_install session
run_ppd_install remove-session
[[ -L $ppd_runtime_enabled && ! -L $ppd_enabled && ! -e $ppd_active && ! -L $ppd_mask ]] ||
  fail "rollback changes runtime enablement or starts an initially inactive PPD"
pass "an inactive runtime-enabled daemon stays inactive and runtime-enabled"

rm -- "$ppd_runtime_enabled"
touch "$ppd_active"
if PPD_FAIL=stop run_ppd_install session; then
  fail "the handoff reports success after PPD failed to stop"
fi
[[ -L $ppd_mask && -e $ppd_receipt && -e $ppd_active ]] || fail "a failed stop loses the PPD handoff"
run_ppd_install session
run_ppd_install session
[[ ! -e $ppd_active ]] || fail "an installation retry leaves PPD active"
if PPD_FAIL=start run_ppd_install remove-session; then
  fail "rollback reports success after PPD failed to start"
fi
[[ ! -L $ppd_mask && -e $ppd_receipt ]] || fail "a failed restart loses the PPD receipt"
run_ppd_install remove-session
[[ -e $ppd_active && ! -e $ppd_receipt && ! -L $ppd_enabled && ! -L $ppd_runtime_enabled ]] ||
  fail "rollback does not recover an initially active disabled PPD after retry"
pass "interrupted handoff and rollback restore an active disabled daemon on retry"

for admin_mask in "$ppd_mask" "$ppd_runtime_mask"; do
  ln -s /dev/null "$admin_mask"
  run_ppd_install session
  run_ppd_install remove-session
  [[ $(readlink -- "$admin_mask") == /dev/null && -e $ppd_active && ! -e $ppd_receipt ]] ||
    fail "handoff or rollback changes a pre-existing administrator mask or its active daemon"
  rm -- "$admin_mask"
done
run_ppd_install session
ln -sTf -- /dev/null "$ppd_mask"
if run_ppd_install remove-session; then
  fail "rollback reports success while a replacement mask prevents restoring PPD"
fi
[[ $(readlink -- "$ppd_mask") == /dev/null && -e $ppd_receipt ]] ||
  fail "rollback removes the administrator's replacement mask or discards the retry receipt"
rm -- "$ppd_mask"
run_ppd_install remove-session
pass "existing administrator masks and replacement masks survive the handoff"

rm -- "$ppd_active"
ln -s "/usr/lib/systemd/system/$ppd" "$ppd_runtime_enabled"
ln -s /dev/null "$ppd_mask"
printf 'enabled-runtime\n' >"$ppd_receipt"
run_ppd_install remove-session
[[ ! -L $ppd_mask && ! -e $ppd_receipt && ! -e $ppd_active && -L $ppd_runtime_enabled && ! -L $ppd_enabled ]] ||
  fail "legacy rollback does not remove its persistent mask while preserving runtime enablement"
ln -s /dev/null "$ppd_runtime_mask"
ln -s /dev/null "$ppd_mask"
printf 'masked-runtime\n' >"$ppd_receipt"
run_ppd_install remove-session
[[ $(readlink -- "$ppd_runtime_mask") == /dev/null && ! -L $ppd_mask && ! -e $ppd_receipt ]] ||
  fail "legacy rollback does not distinguish its added mask from a pre-existing runtime mask"
ln -s /dev/null "$ppd_mask"
printf 'masked\n' >"$ppd_receipt"
run_ppd_install remove-session
[[ $(readlink -- "$ppd_mask") == /dev/null && ! -e $ppd_receipt ]] ||
  fail "legacy rollback removes a pre-existing persistent mask"
pass "legacy receipts preserve enablement and any originally recorded mask"

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
  PPD_MASKED=1
  "OMARCHY_PATH=$ROOT"
  "OMARCHY_ALLY_TDP_PPD_RECORD=$marker"
  OMARCHY_ALLY_TDP_FIXTURE=1
  "OMARCHY_ALLY_TDP_ARMOURY=$armoury"
  "OMARCHY_ALLY_TDP_POWER=$work/supply"
  "OMARCHY_ALLY_TDP_STATE=$state"
  "OMARCHY_ALLY_TDP_RUN=$run"
  "OMARCHY_ALLY_TDP_LOCK=$lock"
  OMARCHY_ALLY_TDP_BOOT_ID=boot
  "OMARCHY_POWERPROFILES_STATE_DIR=$work/profiles-state"
  PATH="$work/bin:$ROOT/bin:$PATH"
)
set_profile() {
  env "${profile_env[@]}" "$ROOT/bin/omarchy-powerprofiles-set" "$@"
}
list_profiles() {
  env "${profile_env[@]}" "$ROOT/bin/omarchy-powerprofiles-list" --active-state
}
reset_state
battery_table
no_active_presets=$'power-saver\t0\nbalanced\t0\nperformance\t0'
[[ $(list_profiles) == "$no_active_presets" && ! -e $lock && ! -e $run && ! -e $state/request ]] ||
  fail "a masked profile query lists available presets without creating a request or snapshot"
# The same managed system opens an ordinary panel on a dock. A previously
# visible preset cannot reach the handheld writer after the output changes.
regular=$(env "${profile_env[@]}" "$ROOT/bin/omarchy-powerprofiles-list" --ppd-only --active-state) ||
  fail "the regular power panel cannot refresh when PPD is masked"
[[ -z $regular ]] || fail "the regular power panel exposes Ally firmware presets"
before=$(tuple)
if set_profile --ppd-only ac performance || [[ $(tuple) != "$before" || -e $state/request || -s $POWERPROFILES_LOG ]]; then
  fail "a stale regular panel action changes a power profile on the managed Ally"
fi
pass "regular panels omit handheld presets and cannot apply one on the managed Ally"

mkdir -p "$work/profiles-state"
printf 'balanced\n' >"$work/profiles-state/battery"
[[ -z $(OMARCHY_ALLY_TDP_CONFLICT=asusd.service list_profiles) ]] ||
  fail "an active ASUS owner leaves no Omarchy presets available"
if OMARCHY_ALLY_TDP_CONFLICT=asusd.service set_profile battery performance; then
  fail "a refused TDP write still reports success"
fi
[[ $(<"$work/profiles-state/battery") == balanced ]] || fail "a refused profile is recorded" "$(<"$work/profiles-state/battery")"
[[ $(tuple) == 15/20/25 ]] || fail "a refused profile still writes" "$(tuple)"
unset OMARCHY_ALLY_TDP_CONFLICT
set_profile battery performance || fail "the real profile list must make presets discoverable with PPD masked"
[[ ! -s $POWERPROFILES_LOG ]] || fail "a masked daemon still calls powerprofilesctl" "$(cat "$POWERPROFILES_LOG")"
[[ $(tuple) == 20/20/25 ]] || fail "battery performance does not clamp to 20/20/25" "$(tuple)"
[[ $(stored) == 30 ]] || fail "battery performance does not request the AC policy" "$(stored)"
[[ $(<"$work/profiles-state/battery") == performance ]] || fail "battery performance is not recorded"
[[ $(list_profiles) == $'power-saver\t0\nbalanced\t0\nperformance\t1' ]] ||
  fail "the saved performance request stays selected at the battery cap"
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
printf '29\n' >"$armoury/ppt_pl1_spl/current_value"
[[ $(list_profiles) == "$no_active_presets" ]] || fail "a firmware mismatch clears the preset's active state"
run_apply --set 18 >/dev/null
[[ $(list_profiles) == "$no_active_presets" ]] || fail "a custom TDP request leaves presets unselected"
rm "$work/profiles-state/ac" "$work/profiles-state/battery"
before_startup=$(tuple)
env "${profile_env[@]}" "$ROOT/bin/omarchy-powerprofiles-init"
[[ $(stored) == 18 && $(tuple) == "$before_startup" ]] ||
  fail "desktop startup preserves a custom Gaming Mode request" "$(stored), $(tuple)"

printf 'balanced\n' >"$work/profiles-state/battery"
printf 'performance\n' >"$work/profiles-state/ac"
battery_table
run_apply --reassert >/dev/null
set_profile battery
[[ $(stored) == 18 && $(tuple) == 18/20/25 ]] ||
  fail "unplug preserves a custom request despite an older battery preference" "$(stored), $(tuple)"
ac_table
set_profile ac
run_apply --reassert >/dev/null
[[ $(stored) == 18 && $(tuple) == "$before_startup" ]] ||
  fail "replug preserves a custom request despite an older AC preference" "$(stored), $(tuple)"

run_apply --set 30 >/dev/null
battery_table
set_profile battery
run_apply --reassert >/dev/null
[[ $(stored) == 30 && $(tuple) == 20/20/25 ]] ||
  fail "desktop battery refresh clamps the applied limit without replacing the saved AC request" "$(stored), $(tuple)"
ac_table
run_apply --reassert >/dev/null
set_profile ac
[[ $(stored) == 30 && $(tuple) == 30/43/53 ]] ||
  fail "desktop AC refresh restores the saved limit" "$(stored), $(tuple)"

rm "$armoury/ppt_pl3_fppt/current_value"
[[ -z $(list_profiles) ]] || fail "missing firmware attributes leave no Omarchy presets available"
pass "masked profile queries and writes share the live TDP backend and report honest active state"

for owner in org.freedesktop.UPower.PowerProfiles net.hadess.PowerProfiles; do
  regular=$(env "${profile_env[@]}" PPD_OWNER="$owner" "$ROOT/bin/omarchy-powerprofiles-list" --ppd-only --active-state)
  [[ $regular == *$'balanced\t1'* ]] || fail "the regular panel omits the running $owner provider"
  PPD_OWNER="$owner" set_profile --ppd-only ac power-saver
  [[ $(tail -n 1 "$POWERPROFILES_LOG") == "power-saver" && $(stored) == 30 ]] ||
    fail "the regular panel fails to select the live provider independently of the TDP request"
done
: >"$POWERPROFILES_LOG"
pass "a running PPD-compatible provider survives a masked service on external displays"

env "${profile_env[@]}" PPD_MASKED=0 "$ROOT/bin/omarchy-powerprofiles-set" ac balanced
[[ $(<"$POWERPROFILES_LOG") == balanced && $(stored) == 30 ]] ||
  fail "a stale record cannot route an unmasked daemon's profiles to the TDP writer"
pass "an unmasked Power Profiles Daemon still handles presets with an old record present"

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

ac_table
reset_state
if env HW=ally OMARCHY_ALLY_TDP_NO_PKEXEC=1 OMARCHY_ALLY_TDP_FIXTURE=1 \
  OMARCHY_ALLY_TDP_ARMOURY="$armoury" OMARCHY_ALLY_TDP_POWER="$work/supply" \
  OMARCHY_ALLY_TDP_STATE="$state" OMARCHY_ALLY_TDP_RUN="$run" \
  OMARCHY_ALLY_TDP_LOCK="$lock" OMARCHY_ALLY_TDP_BOOT_ID=boot PATH="$work/bin:$PATH" \
  dbus-run-session -- python3 "$ROOT/test/helpers/ally-tdp-shim.py"; then
  [[ $(tuple) == 20/20/25 ]] || fail "a reassert without a request writes to firmware" "$(tuple)"
  [[ -z $(stored) ]] || fail "a reassert without a request persists a setting" "$(stored)"
  pass "clients discover the TDP shim and receive external reassert updates"
else
  fail "a client could not discover the shim or receive external TDP changes"
fi
