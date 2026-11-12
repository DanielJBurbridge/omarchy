#!/bin/bash

# Device check for a virtual keyboard killed mid-key. CI has no Hyprland
# session and no wvkbd, so this skips there. On a desktop it requires the
# shipped config to have already enabled release_pressed_on_close, holds
# Backspace, then Shift, through the same virtual-keyboard protocol wvkbd
# uses, SIGKILLs that client and wvkbd, and checks the key does not stay down.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

if ! compositor_reachable; then
  skip "no Wayland compositor; skipping virtual keyboard release on SIGKILL"
  exit 0
fi

for cmd in wvkbd-mobintl wtype hyprctl foot python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    skip "virtual keyboard release test needs $cmd"
    exit 0
  fi
done

option=$(hyprctl getoption input:virtualkeyboard:release_pressed_on_close 2>/dev/null || true)
[[ -n $option ]] || {
  skip "Hyprland has no virtualkeyboard release option; skipping SIGKILL key release"
  exit 0
}
# The shipped RC71L config turns this on. Setting it here would hide a revert.
[[ $option == *'int: 1'* || $option == *'= 1'* || $option == *'= true'* ]] ||
  fail "shipped config left input:virtualkeyboard:release_pressed_on_close off" "$option"

# A stuck key repeats only after input:repeat_delay. Watch longer than that
# delay, and at least a second, so the old 0.4s glance cannot miss it.
repeat_delay_ms=600
repeat=$(hyprctl getoption input:repeat_delay 2>/dev/null || true)
if [[ $repeat =~ int:[[:space:]]*([0-9]+) ]]; then
  repeat_delay_ms=${BASH_REMATCH[1]}
elif [[ $repeat =~ =[[:space:]]*([0-9]+) ]]; then
  repeat_delay_ms=${BASH_REMATCH[1]}
fi
settle_ms=$(( repeat_delay_ms + 400 ))
if (( settle_ms < 1000 )); then
  settle_ms=1000
fi

work=$(mktemp -d)
record=$work/keys
: >"$record"
cat >"$work/record.py" <<'PY'
import os
import sys

fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
while True:
    data = os.read(0, 64)
    if not data:
        break
    os.write(fd, data)
PY
cat >"$work/record.sh" <<SH
#!/bin/bash
stty raw -echo
exec python3 "$work/record.py" "$record"
SH
chmod +x "$work/record.sh"

foot_pid=''
wtype_pid=''
keyboard_pid=''

cleanup() {
  if [[ -n $wtype_pid ]]; then
    kill -9 "$wtype_pid" 2>/dev/null || true
  fi
  if [[ -n $keyboard_pid ]]; then
    kill -9 "$keyboard_pid" 2>/dev/null || true
  fi
  if [[ -n $foot_pid ]]; then
    kill "$foot_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

foot --app-id omarchy-keyboard-release -e "$work/record.sh" >/dev/null 2>&1 &
foot_pid=$!

found=false
for _ in {1..50}; do
  if hyprctl clients -j 2>/dev/null | python3 -c 'import json,sys
clients=json.load(sys.stdin)
pid=int(sys.argv[1])
raise SystemExit(0 if any(c.get("pid")==pid for c in clients) else 1)' "$foot_pid"; then
    found=true
    break
  fi
  sleep 0.05
done
$found || fail "the release recorder window did not appear"

hyprctl dispatch focuswindow "pid:$foot_pid" >/dev/null

# Show wvkbd so the SIGKILL hits the desktop keyboard, not only the holder.
WAYLAND_DISPLAY=${WAYLAND_DISPLAY} "$ROOT/bin/omarchy-toggle-desktop-keyboard" show >/dev/null 2>&1 || true
session=${WAYLAND_DISPLAY##*/}
state="${XDG_RUNTIME_DIR:-/run/user/$UID}/omarchy-desktop-keyboard-$session/process"
if [[ -f $state ]]; then
  read -r keyboard_pid _ _ <"$state" || true
fi

# Hold a key, wait until the recorder sees it, then kill the holder and wvkbd.
hold_key() {
  local name=$1 needle=${2-}
  wtype -P "$name" -s 20000 >/dev/null 2>&1 &
  wtype_pid=$!
  local seen=false
  local i
  for (( i = 0; i < 40; i++ )); do
    if [[ -n $needle ]]; then
      if python3 -c 'import pathlib,sys
text=pathlib.Path(sys.argv[1]).read_bytes()
raise SystemExit(0 if sys.argv[2].encode() in text else 1)' "$record" "$needle"; then
        seen=true
        break
      fi
    elif kill -0 "$wtype_pid" 2>/dev/null; then
      # Shift produces no character. Give the press time to land, and
      # require the holder to still be alive so the key is down.
      if (( i >= 4 )); then
        seen=true
        break
      fi
    else
      break
    fi
    sleep 0.05
  done
  $seen || fail "held $name never reached the recorder"
  local size again
  size=$(wc -c <"$record" | tr -d ' ')
  kill -9 "$wtype_pid" 2>/dev/null || true
  wait "$wtype_pid" 2>/dev/null || true
  wtype_pid=''
  if [[ -n $keyboard_pid ]]; then
    kill -9 "$keyboard_pid" 2>/dev/null || true
    keyboard_pid=''
  fi
  sleep "$(printf '%d.%03d' $(( settle_ms / 1000 )) $(( settle_ms % 1000 )))"
  again=$(wc -c <"$record" | tr -d ' ')
  (( again == size )) || fail "$name stayed down after SIGKILL" "grew from $size to $again"
}

: >"$record"
hold_key BackSpace $'\177'
: >"$record"
hold_key Shift_L
# An empty needle matches immediately. Type a letter after Shift dies and
# require it to stay lowercase, which a latched Shift would change.
wtype a >/dev/null
typed=false
for _ in {1..40}; do
  if [[ $(<"$record") == *a* && $(<"$record") != *A* ]]; then
    typed=true
    break
  fi
  sleep 0.05
done
$typed || fail "Shift stayed latched after SIGKILL" "$(<"$record")"

pass "SIGKILL of a virtual keyboard releases a held key and a latched Shift"
