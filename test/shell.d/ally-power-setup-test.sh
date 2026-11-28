#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export SETUP_FIXTURE=$work
mkdir -p "$work/"{bin,etc/systemd/system,run/systemd/system,var/lib/omarchy/handheld}
states=$work/var/lib/omarchy/handheld
receipt=$states/asus-power-handoff.state
mask=$work/etc/systemd/system/asusd.service
target=$work/etc/omarchy/handheld/omarchy-ally-power-asusd-mask.service
runtime_mask=$work/run/systemd/system/asusd.service
command=$work/bin/omarchy-setup-ally-power

# Redirect installed paths and simulate the privilege boundary. All receipt,
# symlink and flock operations below are performed by the production script.
sed \
  -e "s|=/usr/bin/omarchy-setup-ally-power|=$command|" \
  -e "s|=/var/lib/omarchy/handheld|=$states|" \
  -e "s|=/etc/systemd/system/asusd.service|=$mask|" \
  -e "s|=/etc/omarchy/handheld/|=$work/etc/omarchy/handheld/|" \
  -e "s|=/run/omarchy-ally-tdp.lock|=$work/run/omarchy-ally-tdp.lock|" \
  -e '/^  export PATH=\/usr\/bin:/d' \
  -e 's/(( EUID == 0 ))/(( ${SETUP_PRIVILEGED:-1} == 1 ))/g' \
  -e 's/(( EUID != 0 ))/(( ${SETUP_PRIVILEGED:-1} != 1 ))/g' \
  "$ROOT/bin/omarchy-setup-ally-power" > "$command"

cat > "$work/bin/omarchy-hw-rog-ally" <<'SH'
#!/bin/bash
[[ ${DMI:-ally} == ally ]]
SH

cat > "$work/bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ $1 == omarchy-gaming-session && ${SESSION_INSTALLED:-1} == 1 ]]
SH

cat > "$work/bin/omarchy-ally-tdp-apply" <<'SH'
#!/bin/bash
case $1 in
  --show)
    [[ ${FIRMWARE_AVAILABLE:-1} == 1 ]] || exit 1
    conflict=${CONFLICT_UNIT:-}
    if [[ -z $conflict && -f $SETUP_FIXTURE/asusd.service.active ]]; then
      conflict=asusd.service
    fi
    if [[ -n $conflict ]]; then
      printf 'source=ac\nwritable=0\nconflict=%s\n' "$conflict"
    else
      printf 'source=ac\nwritable=1\nconflict=\n'
    fi
    ;;
  --conflict-units) printf '%s\n' asusd.service power-profiles-daemon.service hhd.service ;;
  *) touch "$SETUP_FIXTURE/writer-called"; exit 1 ;;
esac
SH

cat > "$work/bin/systemctl" <<'SH'
#!/bin/bash
set -euo pipefail
scope=$1
shift
printf '%s\n' "$*" >> "$SETUP_FIXTURE/systemctl.log"
unit=${*: -1}
if [[ $scope == --user ]]; then
  [[ $1 == show && $unit == omarchy-ally-tdp-shim.service ]] || exit 2
  printf '%s\n' "${SHIM_STATE:-loaded}"
  exit
fi
[[ $scope == --system ]] || exit 2
case $1 in
  is-enabled)
    printf '%s\n' "${PPD_STATE:-masked}"
    exit 1
    ;;
  show)
    load=loaded active=inactive
    if [[ -e $SETUP_FIXTURE/$unit.active || $unit == "${CONFLICT_UNIT:-}" ]]; then active=active; fi
    if [[ $unit == asusd.service && ( -L $SETUP_FIXTURE/etc/systemd/system/$unit || -L $SETUP_FIXTURE/run/systemd/system/$unit ) ]]; then
      load=masked
    fi
    printf 'LoadState=%s\nActiveState=%s\n' "$load" "$active"
    ;;
  daemon-reload) [[ ${RELOAD_FAIL:-0} == 0 ]] ;;
  stop)
    [[ $unit != "${STOP_FAIL:-}" ]] || exit 1
    rm -f -- "$SETUP_FIXTURE/$unit.active"
    ;;
  start)
    [[ $unit != "${START_FAIL:-}" ]] || exit 1
    touch -- "$SETUP_FIXTURE/$unit.active"
    ;;
  *) exit 2 ;;
esac
SH

cat > "$work/bin/omarchy-i18n" <<'SH'
#!/bin/bash
printf '%s\n' "$1"
SH

cat > "$work/bin/omarchy-menu-select" <<'SH'
#!/bin/bash
printf '%s\n' "$@" > "$SETUP_FIXTURE/menu.log"
case ${MENU_RESULT:-cancel} in
  cancel) exit 1 ;;
  use) printf 'allyPower.useOmarchy\tallyPower.useOmarchyHint\n' ;;
esac
SH

cat > "$work/bin/pkexec" <<'SH'
#!/bin/bash
printf '%s\n' "$@" > "$SETUP_FIXTURE/auth.log"
SETUP_PRIVILEGED=1 "$@"
SH

cat > "$work/bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$@" > "$SETUP_FIXTURE/notification.log"
SH

chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH"

check_gaming_status() {
  local expected=$1 result
  shift
  result=$(env SETUP_PRIVILEGED=0 "$@" "$command" gaming-status </dev/null) ||
    fail "the Gaming power status failed for $expected"
  [[ $result == "$expected" ]] ||
    fail "the Gaming power status should report $expected" "$result"
}

check_gaming_status unavailable SESSION_INSTALLED=0
check_gaming_status backend
touch "$states/power-profiles-daemon.state"
check_gaming_status backend SHIM_STATE=not-found
check_gaming_status firmware FIRMWARE_AVAILABLE=0
check_gaming_status conflict CONFLICT_UNIT=hhd.service
check_gaming_status ready
touch "$work/asusd.service.active"
check_gaming_status asus
[[ ! -e $work/auth.log && ! -e $work/writer-called && ! -e $receipt && ! -L $mask && -f $work/asusd.service.active ]] ||
  fail 'reporting Gaming power status changed state or requested administration'
if rg -q '^(start|stop|restart|enable|disable|daemon-reload)( |$)' "$work/systemctl.log"; then
  fail 'reporting Gaming power status changed a systemd unit'
fi
pass 'Gaming power status distinguishes provisioning, firmware and active power owners without changing them'

touch "$states/power-profiles-daemon.state" "$work/asusd.service.active" "$work/asus-shutdown.service.active"
if DMI=laptop "$command" use-omarchy; then fail 'a non-Ally received the ASUS power handoff'; fi
if SESSION_INSTALLED=0 "$command" use-omarchy; then fail 'the handoff ran before gaming setup'; fi
if PPD_STATE=masked-runtime "$command" use-omarchy; then fail 'a temporary PPD mask allowed a persistent handoff'; fi
if FIRMWARE_AVAILABLE=0 "$command" use-omarchy; then fail 'the handoff ran without the firmware interface'; fi
if CONFLICT_UNIT=hhd.service "$command" use-omarchy; then fail 'the handoff ran with another known active owner'; fi
[[ ! -e $receipt && ! -L $mask && -f $work/asusd.service.active ]] ||
  fail 'a denied handoff still touched ASUS state'
pass 'the handoff checks the model, installed backend, firmware and competing owners'

SETUP_PRIVILEGED=0 "$command" </dev/null
[[ ! -e $work/auth.log && ! -e $receipt ]] || fail 'opening or cancelling the picker requests administration'
exec 8>"$work/run/omarchy-ally-tdp.lock"
flock -x 8
if result=$(timeout 1s "$command" use-omarchy 8>&-); then
  fail 'the handoff ran while the writer held its lock' "$result"
else
  (( $? == 124 )) || fail 'the handoff did not wait on the writer lock'
fi
flock -u 8
exec 8>&-
[[ ! -e $receipt && ! -L $mask ]] || fail 'waiting on the writer lock changed ownership'
pass 'opening the picker is read-only and ownership changes wait for the TDP writer'

ln -s /dev/null "$runtime_mask"
if "$command" use-omarchy; then fail 'an existing runtime mask was adopted'; fi
[[ -L $runtime_mask && ! -L $mask && ! -e $receipt ]] || fail 'the existing runtime mask was not preserved'
rm -- "$runtime_mask"
ln -s /dev/null "$mask"
if "$command" use-omarchy; then fail 'an existing persistent mask was adopted'; fi
"$command" restore-asus
[[ $(readlink -- "$mask") == /dev/null && ! -e $receipt ]] || fail 'restore touched a mask it did not create'
rm -- "$mask"
pass 'pre-existing systemd masks remain under their original ownership'

if RELOAD_FAIL=1 "$command" use-omarchy; then fail 'an unsuccessful daemon reload completed the handoff'; fi
[[ $(<"$receipt") == '1 1' && -f $work/asusd.service.active && -f $work/asus-shutdown.service.active ]] ||
  fail 'an unsuccessful daemon reload lost the original service states'
if STOP_FAIL=asusd.service "$command" use-omarchy; then fail 'an incomplete stop was reported as a completed handoff'; fi
[[ $(<"$receipt") == '1 1' && $(readlink -- "$mask") == "$target" && -f $work/asusd.service.active ]] ||
  fail 'the interrupted claim lost its rollback state'
MENU_RESULT=use SETUP_PRIVILEGED=0 "$command" </dev/null
[[ $(<"$work/auth.log") == "$command"$'\n'use-omarchy ]] || fail 'the graphical picker did not request regular administration'
[[ $(<"$receipt") == '1 1' && ! -e $work/asusd.service.active && ! -e $work/asus-shutdown.service.active ]] ||
  fail 'retry did not finish the handoff or rewrote original service states'
[[ $(readlink -- "$mask") == "$target" && $(readlink -- "$target") == /dev/null ]] ||
  fail 'the handoff did not create an identifiable persistent mask'
[[ ! -e $work/writer-called ]] || fail 'changing ownership directly wrote a new TDP limit'
pass 'the picker completes a partially applied handoff without replacing the initial receipt'

if START_FAIL=asus-shutdown.service "$command" restore-asus; then fail 'an incomplete restore was reported as successful'; fi
[[ -f $receipt && ! -L $mask && -f $work/asusd.service.active && ! -e $work/asus-shutdown.service.active ]] ||
  fail 'restore lost the receipt before both services were restored'
"$command" restore-asus
[[ ! -e $receipt && ! -L $mask && ! -L $target && -f $work/asusd.service.active && -f $work/asus-shutdown.service.active ]] ||
  fail 'retry did not restore both originally active ASUS units'
pass 'a partial undo keeps its receipt until both active ASUS services are restored'

rm -- "$work/asusd.service.active" "$work/asus-shutdown.service.active"
"$command" use-omarchy
rm -- "$target"
ln -s /etc/replacement.service "$target"
if "$command" restore-asus; then fail 'restore accepted an externally replaced mask target'; fi
[[ $(readlink -- "$mask") == "$target" && $(readlink -- "$target") == /etc/replacement.service && -f $receipt ]] ||
  fail 'restore removed a modified mask chain or its receipt'
rm -- "$target"
ln -s /dev/null "$target"
rm -- "$mask"
ln -s /dev/null "$mask"
if "$command" restore-asus; then fail 'restore treated an externally replaced mask as its own'; fi
[[ $(readlink -- "$mask") == /dev/null && -f $receipt ]] || fail 'restore removed a replacement mask or its receipt'
rm -- "$mask"
rm -- "$work/run/omarchy-ally-tdp.lock.updated"
mkdir "$work/run/omarchy-ally-tdp.lock.updated"
"$command" restore-asus
[[ ! -e $receipt && ! -e $work/asusd.service.active && ! -e $work/asus-shutdown.service.active ]] ||
  fail 'restore started an originally inactive ASUS unit'
pass 'undo leaves independently changed masks and originally inactive services alone'
