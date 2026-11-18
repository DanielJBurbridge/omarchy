#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

script=$ROOT/docs/handheld/research/tools/ally-press-test.sh

bash -n "$script" || fail "ally press test has valid syntax"
pass "ally press test has valid syntax"

grep -F 'Press the LEFT back paddle (M2)' "$script" >/dev/null || fail "the left back paddle is M2"
grep -F 'Press the RIGHT back paddle (M1)' "$script" >/dev/null || fail "the right back paddle is M1"
grep -F 'LEFT back paddle (M1)' "$script" >/dev/null && fail "the left back paddle is not labelled M1"
grep -F 'RIGHT back paddle (M2)' "$script" >/dev/null && fail "the right back paddle is not labelled M2"
pass "paddle prompts name M2 on the left and M1 on the right"

grep -F 'inputplumber.service' "$script" >/dev/null || fail "the press test names inputplumber.service"
grep -F 'systemctl stop' "$script" >/dev/null || fail "the press test stops inputplumber"
grep -F 'systemctl start' "$script" >/dev/null || fail "the press test starts inputplumber"
grep -F 'IP_WAS_ACTIVE' "$script" >/dev/null || fail "the press test restarts inputplumber only when it was active"
grep -F 'IP_RESTORED' "$script" >/dev/null || fail "the press test restore runs once"
grep -F 'trap restore_capture EXIT' "$script" >/dev/null || fail "the press test restores inputplumber on EXIT"
grep -F "trap 'restore_capture; exit 130' INT" "$script" >/dev/null || fail "the press test restores inputplumber on INT"
grep -F "trap 'restore_capture; exit 143' TERM" "$script" >/dev/null || fail "the press test restores inputplumber on TERM"
grep -F "trap 'restore_capture; exit 129' HUP" "$script" >/dev/null || fail "the press test restores inputplumber on HUP"
pass "the press test restores inputplumber from an idempotent trap"

# Run the capture against a copy of the recorded RC71L USB layout. Include
# an identical Xbox controller behind a hub and interleave unrelated events.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
usb=$work/usb
mkdir -p "$work"/{bin,input,home} "$usb"/{usb5,5-3}
for pad in 5-2 5-4.2; do
  mkdir -p "$usb/$pad" "$usb/$pad:1.0/input/input0"
  printf '045e\n' > "$usb/$pad/idVendor"
  printf '028e\n' > "$usb/$pad/idProduct"
  ln -s /sys/bus/usb/drivers/xpad "$usb/$pad:1.0/driver"
done
mkdir "$usb/5-2:1.0/input/input0/event11" "$usb/5-4.2:1.0/input/input0/event5"
printf '0b05\n' > "$usb/5-3/idVendor"
printf '1abe\n' > "$usb/5-3/idProduct"
ln -s /dev/null "$work/input/event11"
ln -s /dev/null "$work/input/event5"
sed -e "s|/sys/bus/usb/devices|$usb|g" -e "s|/dev/input/|$work/input/|g" "$script" > "$work/capture"
cat > "$work/bin/boundary" <<'EOF'
#!/bin/bash
case ${0##*/} in
  sudo) if [[ $1 == "-v" || $1 == "-n" ]]; then exit 0; fi; exec "$@" ;;
  systemctl) echo "${1}" >> "$HOME/service" ;;
  omarchy-hw-rog-ally) exit 0 ;;
  pacman) [[ $1 == "-Q" ]] ;;
  evtest)
    [[ $* == "--grab ${HOME%/home}/input/event11" ]] || exit 1
    code=307
    if [[ -f $HOME/first ]]; then code=308; fi
    touch "$HOME/first"
    echo "Event: time 42.000000, type 3 (EV_ABS), code 0 (ABS_X), value 1"
    for value in 1 0; do
      echo "Event: time 42.000000, type 1 (EV_KEY), code $code (BTN), value $value"
    done ;;
esac
EOF
chmod +x "$work/bin/boundary"
for cmd in sudo systemctl omarchy-hw-rog-ally pacman evtest; do ln -s boundary "$work/bin/$cmd"; done
run_capture() {
  env HOME="$work/home" PATH="$work/bin:$PATH" bash "$work/capture" --face-buttons-only
}
run_capture <<< $'\n' > "$work/log" 2>&1 || fail "capture selects the built-in xpad" "$(cat "$work/log")"
out=("$work/home"/ally-press-test/*)
for face in X Y; do
  code=307
  if [[ $face == "Y" ]]; then code=308; fi
  [[ $(awk '{print $8, $NF}' "${out[0]}/$face.txt") == "$code 1"$'\n'"$code 0" ]] ||
    fail "only $face press and release are saved" "$(cat "${out[0]}/$face.txt")"
done
[[ $(cat "$work/home/service") == $'is-active\nstop\nstart' ]] || fail "capture restores the active daemon"
mkfifo "$work/prompt"
exec {prompt}<>"$work/prompt"
: > "$work/home/service"
env HOME="$work/home" PATH="$work/bin:$PATH" bash "$work/capture" --face-buttons-only <&"$prompt" > "$work/hup" 2>&1 &
pid=$!
for _ in {1..100}; do
  grep -q '^Embedded xpad:' "$work/hup" && break
  sleep 0.05
done
kill -HUP "$pid"
status=0
wait "$pid" || status=$?
exec {prompt}>&-
(( status == 129 )) && [[ $(cat "$work/home/service") == $'is-active\nstop\nstart' ]] ||
  fail "losing SSH at the prompt restores the daemon once"
rm -r "$usb/5-2:1.0"
if run_capture <<< $'\n' > "$work/log" 2>&1; then fail "an external pad cannot stand in for the embedded pad"; fi
grep -q 'Could not identify one embedded RC71L xpad' "$work/log" || fail "capture rejects the external pad before reading events"
[[ $(tail -n 1 "$work/home/service") == "start" ]] || fail "failure to find the embedded pad restores the daemon"
pass "X and Y capture is limited to the embedded xpad and restores InputPlumber"
