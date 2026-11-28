#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
# Apple Silicon: a battery not called BAT*, power_now signed by direction, and
# the thresholds and cycle count only under the native path.
mkdir -p "$tmp_dir/power/macsmc-battery" "$tmp_dir/power/hidpp_battery_0"
printf '%s\n' '-10800000' >"$tmp_dir/power/macsmc-battery/power_now"
printf '75\n' >"$tmp_dir/power/macsmc-battery/charge_control_start_threshold"
printf '80\n' >"$tmp_dir/power/macsmc-battery/charge_control_end_threshold"
printf '212\n' >"$tmp_dir/power/macsmc-battery/cycle_count"
printf '999\n' >"$tmp_dir/power/hidpp_battery_0/cycle_count"
cat >"$tmp_dir/bin/upower" <<'STUB'
#!/bin/bash

# A wireless mouse enumerates first, as a battery_ device that is not a power
# supply; the machine's own battery follows it.
if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/line_power_macsmc_ac"
  echo "/org/freedesktop/UPower/devices/battery_hidpp_battery_0"
  echo "/org/freedesktop/UPower/devices/battery_${OMARCHY_TEST_NATIVE_PATH//-/_}"
  exit 0
fi

if [[ $1 == "-i" && $2 == */battery_hidpp_battery_0 ]]; then
  cat <<'INFO'
  native-path:          hidpp_battery_0
  model:                Wireless Mouse
  power supply:         no
  state:                discharging
  percentage:           5%
INFO
  exit 0
fi

if [[ $1 == "-i" ]]; then
  cat <<'INFO'
  native-path:          macsmc-battery
  power supply:         yes
  state:                discharging
  energy:               28.3 Wh
  energy-full:          56.7 Wh
  energy-rate:          7.3 W
  time to empty:        2.5 hours
  percentage:           51%
INFO
  exit 0
fi

exit 1
STUB
chmod +x "$tmp_dir/bin/upower"

shell_output=$(OMARCHY_TEST_NATIVE_PATH=macsmc-battery OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'percentage\t51%' <<<"$shell_output" >/dev/null || fail "battery status reports the machine's battery, not the mouse's"
grep -Fx $'state\tdischarging' <<<"$shell_output" >/dev/null || fail "battery status reports state"
grep -Fx $'rate\t10.8W' <<<"$shell_output" >/dev/null || fail "battery status reports live sysfs power rate"
grep -Fx $'size\t56Wh' <<<"$shell_output" >/dev/null || fail "battery status reports full capacity"
grep -Fx $'time\t2h 37m' <<<"$shell_output" >/dev/null || fail "battery status works the time left out from the draw it shows"
grep -Fx $'cycles\t212' <<<"$shell_output" >/dev/null || fail "battery status reports native-path cycle count"
grep -Fx $'threshold\t75-80%' <<<"$shell_output" >/dev/null || fail "battery status reports native-path charge thresholds"
line_output=$(OMARCHY_TEST_NATIVE_PATH=macsmc-battery OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status")
[[ $line_output == *$' '"10.8W"$' / '"56Wh" ]] || fail "a draw signed negative still shows in the status line" "$line_output"

# The BAT* name the script used to key on is one of many; CMB0 is another.
mkdir -p "$tmp_dir/power/CMB0"
printf '7300000\n' >"$tmp_dir/power/CMB0/power_now"
sed -i 's/native-path:          macsmc-battery/native-path:          CMB0/' "$tmp_dir/bin/upower"
generic_output=$(OMARCHY_TEST_NATIVE_PATH=CMB0 OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'rate\t7.3W' <<<"$generic_output" >/dev/null || fail "battery status accepts arbitrary UPower battery paths"
grep -Fx $'time\t3h 53m' <<<"$generic_output" >/dev/null || fail "battery status time left follows the live draw"
if grep -q $'^cycles\t' <<<"$generic_output"; then
  fail "a battery without a cycle count leaves out the mouse's count" "$generic_output"
fi
pass "battery status supports Apple Silicon and arbitrary native battery paths"

# Firmware that doesn't know the present rate leaves current_now in place but
# gives nothing on read; UPower's rate, from the falling charge, stands.
rm "$tmp_dir/power/CMB0/power_now"
: >"$tmp_dir/power/CMB0/current_now"
printf '12900000\n' >"$tmp_dir/power/CMB0/voltage_now"
unknown_rate_output=$(OMARCHY_TEST_NATIVE_PATH=CMB0 OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'rate\t7.3W' <<<"$unknown_rate_output" >/dev/null || fail "an unreadable current_now leaves UPower's rate in place" "$unknown_rate_output"
pass "battery status keeps UPower's rate when the battery has no live reading"

# An 80% hold threshold doesn't trip while the battery is still below it.
hold_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir" "$hold_dir"' EXIT

mkdir -p "$hold_dir/bin" "$hold_dir/power/BAT0" "$hold_dir/power/ac"
printf 'Mains\n' >"$hold_dir/power/ac/type"
printf '1\n' >"$hold_dir/power/ac/online"
printf '80\n' >"$hold_dir/power/BAT0/charge_control_end_threshold"
cat >"$hold_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  exit 0
fi

if [[ $1 == "-i" ]]; then
  cat <<'INFO'
  native-path:          BAT0
  power supply:         yes
  state:                charging
  energy-full:          69.6 Wh
  energy-rate:          0.1 W
  time to full:         0.2 hours
  percentage:           79.5%
  charge-end-threshold: 80%
INFO
  exit 0
fi

exit 1
STUB
chmod +x "$hold_dir/bin/upower"

hold_output=$(OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'state\tcharging' <<<"$hold_output" >/dev/null || fail "a hold below its threshold is still charging"
pass "battery status doesn't trip a hold early"

# Once the battery reaches the threshold, idle charging is holding.
sed -i 's/percentage:           79.5%/percentage:           80.0%/' "$hold_dir/bin/upower"
held_output=$(OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'percentage\t80%' <<<"$held_output" >/dev/null || fail "threshold percentage still displays as 80%"
grep -Fx $'state\tholding' <<<"$held_output" >/dev/null || fail "idle charging at the threshold is holding"
pass "battery status reports holding once the raw percentage reaches the threshold"

# Charging counts up to the charge limit, not to a full battery.
printf '27800000\n' >"$hold_dir/power/BAT0/power_now"
sed -i 's/percentage:           80.0%/percentage:           40.0%/; s/energy-full:          69.6 Wh/energy:               27.84 Wh\n  energy-full:          69.6 Wh/' "$hold_dir/bin/upower"
charging_output=$(OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'time\t1h' <<<"$charging_output" >/dev/null || fail "time to full counts up to the charge limit" "$charging_output"
pass "battery status times charging to the charge limit"

# UPower can still describe its configured 75–80% range when that policy is
# disabled. BAT0 exposes only the effective firmware end threshold.
sed -i '/charge-end-threshold: 80%/a\  charge-start-threshold: 75%\n  charge-threshold-supported: yes' "$hold_dir/bin/upower"
printf '100\n' >"$hold_dir/power/BAT0/charge_control_end_threshold"
disabled_output=$(OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'time\t1h 30m' <<<"$disabled_output" >/dev/null || fail "a disabled charge limit counts up to 100%" "$disabled_output"
if grep -q $'^threshold\t' <<<"$disabled_output"; then
  fail "a configured but disabled charge limit is not reported" "$disabled_output"
fi
printf '65\n' >"$hold_dir/power/BAT0/charge_control_end_threshold"
manual_output=$(OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'threshold\t65%' <<<"$manual_output" >/dev/null || fail "the actual firmware limit is reported without a stale start threshold" "$manual_output"
grep -Fx $'time\t38m' <<<"$manual_output" >/dev/null || fail "charging time follows the actual firmware limit" "$manual_output"
printf '80\n' >"$hold_dir/power/BAT0/charge_control_end_threshold"
sed -i '/charge-start-threshold: 75%/d; /charge-threshold-supported: yes/d' "$hold_dir/bin/upower"
pass "battery status follows the effective firmware threshold when UPower has a different configuration"

# UPower's own estimate stands in when the draw is too small to divide by...
printf '100000\n' >"$hold_dir/power/BAT0/power_now"
idle_output=$(OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'time\t12m' <<<"$idle_output" >/dev/null || fail "a negligible draw falls back to UPower's time" "$idle_output"

# ...and when the energy reading is missing.
printf '27800000\n' >"$hold_dir/power/BAT0/power_now"
sed -i '/energy:               27.84 Wh/d' "$hold_dir/bin/upower"
unread_output=$(OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'time\t12m' <<<"$unread_output" >/dev/null || fail "a missing energy reading falls back to UPower's time" "$unread_output"
pass "battery status falls back to UPower's time when it cannot work it out"

# Another battery's charge limit does not shorten this one's time to full.
sed -i 's/energy-full:          69.6 Wh/energy:               27.84 Wh\n  energy-full:          69.6 Wh/' "$hold_dir/bin/upower"
rm "$hold_dir/power/BAT0/charge_control_end_threshold"
sed -i '/charge-end-threshold: 80%/d' "$hold_dir/bin/upower"
mkdir -p "$hold_dir/power/BAT1"
printf '55\n' >"$hold_dir/power/BAT1/charge_control_start_threshold"
printf '60\n' >"$hold_dir/power/BAT1/charge_control_end_threshold"
printf '420\n' >"$hold_dir/power/BAT1/cycle_count"
unlimited_output=$(OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'time\t1h 30m' <<<"$unlimited_output" >/dev/null || fail "time to full ignores another battery's charge limit" "$unlimited_output"
pass "battery status times charging to its own battery's limit"

# The status line and its durations follow the Omarchy language.
echo "da" >"$tmp_dir/language"
danish_output=$(OMARCHY_LANGUAGE_FILE="$tmp_dir/language" OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status")
[[ $danish_output == "Batteri 40%  ·  1 t 30 min til fuld  ·  "* ]] || fail "battery status reads in the Omarchy language" "$danish_output"
danish_time=$(OMARCHY_LANGUAGE_FILE="$tmp_dir/language" OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'time\t1 t 30 min' <<<"$danish_time" >/dev/null || fail "battery status durations follow the Omarchy language" "$danish_time"
pass "battery status reads in the Omarchy language"

# A pending battery on AC can only be holding at its own charge limit.
sed -i 's/state:                charging/state:                pending-charge/; /time to full:/d' "$hold_dir/bin/upower"
printf '0\n' >"$hold_dir/power/BAT0/power_now"
pending_output=$(OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'percentage\t40%' <<<"$pending_output" >/dev/null || fail "battery status reports BAT0's percentage" "$pending_output"
grep -Fx $'state\tpending-charge' <<<"$pending_output" >/dev/null || fail "BAT1's limit does not make BAT0 report holding" "$pending_output"
if grep -Eq $'^(threshold|cycles)\t' <<<"$pending_output"; then
  fail "battery status omits the other battery's thresholds and cycle count" "$pending_output"
fi

# A UPower end threshold without a start belongs to BAT0 alone.
sed -i '/percentage:/a\  charge-end-threshold: 80%' "$hold_dir/bin/upower"
upower_limit_output=$(OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'threshold\t80%' <<<"$upower_limit_output" >/dev/null || fail "BAT0's UPower threshold does not borrow BAT1's start threshold" "$upower_limit_output"

# When UPower has no thresholds, use the matched battery's sysfs readings.
sed -i '/charge-end-threshold: 80%/d' "$hold_dir/bin/upower"
printf '35\n' >"$hold_dir/power/BAT0/charge_control_start_threshold"
printf '40\n' >"$hold_dir/power/BAT0/charge_control_end_threshold"
printf '123\n' >"$hold_dir/power/BAT0/cycle_count"
matched_output=$(OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'state\tholding' <<<"$matched_output" >/dev/null || fail "BAT0 holds at its own sysfs limit" "$matched_output"
grep -Fx $'threshold\t35-40%' <<<"$matched_output" >/dev/null || fail "battery status reports BAT0's sysfs thresholds" "$matched_output"
grep -Fx $'cycles\t123' <<<"$matched_output" >/dev/null || fail "battery status reports BAT0's sysfs cycle count" "$matched_output"
rm "$hold_dir/power/BAT0/"{charge_control_start_threshold,charge_control_end_threshold,cycle_count}
pass "battery status uses thresholds and cycle count from the selected battery"

# A full battery says so, with no time to count and no 0W draw.
cat >"$hold_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  exit 0
fi

if [[ $1 == "-i" ]]; then
  cat <<'INFO'
  native-path:          BAT0
  power supply:         yes
  state:                fully-charged
  energy:               53.2 Wh
  energy-full:          53.2 Wh
  energy-rate:          0 W
  percentage:           100%
INFO
  exit 0
fi

exit 1
STUB
printf '0\n' >"$hold_dir/power/BAT0/power_now"
full_output=$(OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status")
[[ $full_output == "Battery 100%  ·  Fully charged  ·  53Wh" ]] || fail "a full battery shows no time or draw" "$full_output"

# A load bigger than the adapter drains a battery still reading 100%.
sed -i 's/state:                fully-charged/state:                discharging/' "$hold_dir/bin/upower"
printf '10000000\n' >"$hold_dir/power/BAT0/power_now"
draining_output=$(OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status")
[[ $draining_output == "Battery 100%  ·  5h 19m left  ·  "*"10W"*"53Wh" ]] || fail "a battery draining on AC at 100% is not fully charged" "$draining_output"
sed -i 's/state:                discharging/state:                fully-charged/' "$hold_dir/bin/upower"

# A battery with no time estimate and no capacity reading leaves both out.
sed -i 's/state:                fully-charged/state:                discharging/; s/percentage:           100%/percentage:           60%/; /energy/d' "$hold_dir/bin/upower"
printf '0\n' >"$hold_dir/power/ac/online"
printf '9000000\n' >"$hold_dir/power/BAT0/power_now"
sparse_output=$(OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status")
[[ $sparse_output == "Battery 60%  ·  "$' '"9W" ]] || fail "missing readings drop out of the status line" "$sparse_output"
pass "battery status leaves out readings it doesn't have"

# A charge limit request belongs to the present system battery. The fixture
# lists a controller, the aggregate display device and an absent battery first.
charge_limit=$ROOT/bin/omarchy-battery-charge-limit
export OMARCHY_TEST_CHARGE_STATE="$tmp_dir/charge-state"
export OMARCHY_TEST_CHARGE_WRITES="$tmp_dir/charge-writes"
export OMARCHY_TEST_CHARGE_NOTICE="$tmp_dir/charge-notice"
export OMARCHY_TEST_ASUSD_STATE_FILE="$tmp_dir/asusd-state"
printf 'false\n' >"$OMARCHY_TEST_CHARGE_STATE"
: >"$OMARCHY_TEST_CHARGE_WRITES"

cat >"$tmp_dir/bin/omarchy-hw-rog-ally" <<'STUB'
#!/bin/bash
[[ ${OMARCHY_TEST_HARDWARE:-ally} == "ally" ]]
STUB
cat >"$tmp_dir/bin/systemctl" <<'STUB'
#!/bin/bash
[[ $* == "--system show --property=ActiveState --value asusd.service" ]] || exit 2
[[ ${OMARCHY_TEST_ASUSD_QUERY:-ok} == "ok" ]] || exit 1
if [[ -f $OMARCHY_TEST_ASUSD_STATE_FILE ]]; then
  cat "$OMARCHY_TEST_ASUSD_STATE_FILE"
else
  printf '%s\n' "${OMARCHY_TEST_ASUSD_STATE:-inactive}"
fi
STUB
cat >"$tmp_dir/bin/omarchy-menu-select" <<'STUB'
#!/bin/bash
case ${OMARCHY_TEST_CHARGE_PICK:-cancel} in
  apply) printf '%s\n' "$3" ;;
  back) printf '%s\n' "$2" ;;
  reclaim)
    printf 'activating\n' >"$OMARCHY_TEST_ASUSD_STATE_FILE"
    printf '%s\n' "$3"
    ;;
  cancel) exit 1 ;;
esac
STUB
cat >"$tmp_dir/bin/omarchy-notification-send" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >"$OMARCHY_TEST_CHARGE_NOTICE"
STUB
cat >"$tmp_dir/bin/busctl" <<'STUB'
#!/bin/bash
[[ $1 == "--system" && $2 == "--auto-start=no" ]] || exit 2
shift 2
if [[ $1 == "--json=short" ]]; then
  shift
fi
[[ $2 == "org.freedesktop.UPower" ]] || exit 2

case "$1:$5" in
  call:EnumerateDevices)
    cat <<'JSON'
{"type":"ao","data":[[
  "/org/freedesktop/UPower/devices/battery_gamepad",
  "/org/freedesktop/UPower/devices/DisplayDevice",
  "/org/freedesktop/UPower/devices/battery_BAT1",
  "/org/freedesktop/UPower/devices/battery_BAT0"
]]}
JSON
    ;;
  call:GetAll)
    [[ $4 == "org.freedesktop.DBus.Properties" && $6 == "s" && $7 == "org.freedesktop.UPower.Device" ]] || exit 2
    supply=true
    present=true
    settings=2
    case "${3##*/}" in
      battery_gamepad) supply=false ;;
      battery_BAT1) present=${OMARCHY_TEST_SECOND_BATTERY:-false} ;;
      battery_BAT0) settings=${OMARCHY_TEST_THRESHOLD_SETTINGS:-2} ;;
    esac
    cat <<JSON
{"type":"a{sv}","data":[{
  "Type":{"type":"u","data":2},
  "PowerSupply":{"type":"b","data":$supply},
  "IsPresent":{"type":"b","data":$present},
  "ChargeThresholdSupported":{"type":"b","data":true},
  "ChargeThresholdSettingsSupported":{"type":"u","data":$settings},
  "ChargeEndThreshold":{"type":"u","data":80},
  "ChargeThresholdEnabled":{"type":"b","data":$(<"$OMARCHY_TEST_CHARGE_STATE")}
}]}
JSON
    ;;
  call:EnableChargeThreshold)
    printf '%s %s\n' "$3" "$7" >>"$OMARCHY_TEST_CHARGE_WRITES"
    [[ $4 == "org.freedesktop.UPower.Device" && $6 == "b" ]] || exit 2
    printf '%s\n' "$7" >"$OMARCHY_TEST_CHARGE_STATE"
    ;;
  get-property:ChargeThresholdEnabled)
    [[ $4 == "org.freedesktop.UPower.Device" ]] || exit 2
    printf 'b %s\n' "$(<"$OMARCHY_TEST_CHARGE_STATE")"
    ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$tmp_dir/bin/"{busctl,omarchy-hw-rog-ally,systemctl,omarchy-menu-select,omarchy-notification-send}

run_charge_limit() {
  OMARCHY_PATH="$ROOT" OMARCHY_LANGUAGE_FILE="$tmp_dir/absent-language" \
    PATH="$tmp_dir/bin:$ROOT/bin:$PATH" "$charge_limit" "$@"
}

charge_status=$(run_charge_limit status)
[[ $charge_status == "UPower charge limit is off (80% configured)." && ! -s $OMARCHY_TEST_CHARGE_WRITES ]] ||
  fail "charge limit status distinguishes disabled from the configured ceiling and changes nothing" "$charge_status"

charge_on=$(run_charge_limit on)
charge_off=$(run_charge_limit off)
[[ $charge_on == "UPower charge limit is on (80%)." && $charge_off == "$charge_status" ]] ||
  fail "charge limit commands report the confirmed state"
mapfile -t charge_writes <"$OMARCHY_TEST_CHARGE_WRITES"
[[ ${#charge_writes[@]} == 2 &&
  ${charge_writes[0]} == "/org/freedesktop/UPower/devices/battery_BAT0 true" &&
  ${charge_writes[1]} == "/org/freedesktop/UPower/devices/battery_BAT0 false" ]] ||
  fail "charge limit changes only the present system battery"
pass "charge limit status, on and off act on the real system battery"

: >"$OMARCHY_TEST_CHARGE_WRITES"
if OMARCHY_TEST_HARDWARE=laptop run_charge_limit on ||
  OMARCHY_TEST_SECOND_BATTERY=true run_charge_limit on ||
  OMARCHY_TEST_THRESHOLD_SETTINGS=4 run_charge_limit on; then
  fail "charge limit requires an RC71L and one present system battery with a supported ceiling"
fi
[[ ! -s $OMARCHY_TEST_CHARGE_WRITES ]] || fail "refused charge limit requests never call UPower's setter"
pass "charge limit refuses other hardware, ambiguous batteries and unsupported ceilings"

active_status=$(OMARCHY_TEST_ASUSD_STATE=active run_charge_limit status)
if OMARCHY_TEST_ASUSD_STATE=active run_charge_limit on >"$tmp_dir/charge-error" 2>&1; then
  fail "charge limit refuses to write while asusd owns the setting"
fi
[[ $active_status == "$charge_status" && ! -s $OMARCHY_TEST_CHARGE_WRITES ]] ||
  fail "asusd does not block read-only status and no UPower setter runs"
grep -Fq asusd "$tmp_dir/charge-error" || fail "the refusal identifies the competing daemon"
pass "charge limit status remains available while asusd manages the ceiling"

run_charge_limit choose
OMARCHY_TEST_CHARGE_PICK=back run_charge_limit choose
[[ ! -s $OMARCHY_TEST_CHARGE_WRITES ]] || fail "cancelling or going back never changes charging"
OMARCHY_TEST_CHARGE_PICK=apply run_charge_limit choose
[[ $(run_charge_limit status) == "UPower charge limit is on (80%)." ]] ||
  fail "the desktop chooser enables the configured ceiling"
[[ $(<"$OMARCHY_TEST_CHARGE_NOTICE") == $'Battery charge limit\n80% charge limit is on' ]] ||
  fail "the chooser reports UPower's confirmed charging limit"

: >"$OMARCHY_TEST_CHARGE_WRITES"
if OMARCHY_TEST_CHARGE_PICK=reclaim run_charge_limit choose >"$tmp_dir/charge-error" 2>&1 ||
  OMARCHY_TEST_ASUSD_QUERY=failed run_charge_limit off >"$tmp_dir/charge-error" 2>&1; then
  fail "a charge limit request requires known idle ASUS charging ownership"
fi
[[ ! -s $OMARCHY_TEST_CHARGE_WRITES ]] ||
  fail "charging ownership changing while the picker is open blocks the UPower write"
pass "the fixed charge limit chooser applies only a confirmed selection while ASUS charging is idle"
