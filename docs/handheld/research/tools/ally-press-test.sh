#!/bin/bash
# Device-only research tool for the test Ally. Not part of the product.
# ROG Ally RC71L button press test (Omarchy Handheld research). Run ON the Ally: bash ~/ally-press-test.sh
# Captures evtest (N-KEY kbd/if02, WMI hotkeys, Xbox pad) + raw hidraw for each prompted button.
# OQ-2 (CC long: F20 vs Ctrl+Alt+Del), OQ-3 (long-press threshold), OQ-8 (volume rocker) covered.
# Grabs the N-KEY/WMI devices during each capture so presses don't trigger desktop actions.
# Remove afterwards: rm -r ~/ally-press-test.sh ~/ally-press-test ; sudo pacman -Rns evtest
set -u
OUT=~/ally-press-test/$(date +%Y%m%d-%H%M%S); mkdir -p "$OUT"
LOG=~/omarchy-handheld-deploy.log
SECS=${SECS:-5}

echo "Needs sudo once (evtest reads /dev/input as root)."; sudo -v || exit 1
( while true; do sudo -n -v; sleep 50; done ) & KEEP=$!; trap 'kill $KEEP 2>/dev/null' EXIT

{ date -Is; pacman -Q omarchy-dev 2>/dev/null; uname -r; cat /sys/class/dmi/id/bios_version; } > "$OUT/state.txt"
if ! command -v evtest >/dev/null; then
  echo "$(date -Is) press-test: installing evtest (pacman -S evtest). State: $(pacman -Q omarchy-dev 2>/dev/null), kernel $(uname -r). Remove: sudo pacman -Rns evtest" >> "$LOG"
  sudo pacman -S --needed --noconfirm evtest || exit 1
fi

# Resolve devices by name (event numbers change between boots)
dev() { awk -v pat="$1" -v want="$2" 'BEGIN{RS=""} $0 ~ pat && (want=="" || $0 ~ want) { if (match($0,/event[0-9]+/)) print "/dev/input/" substr($0,RSTART,RLENGTH) }' /proc/bus/input/devices; }
PAD=$(dev 'X-Box 360 pad' '' | head -1)
WMI=$(dev 'Asus WMI hotkeys' '' | head -1)
NKEY=$(dev 'N-KEY Device' '' )   # all three N-KEY interfaces
HIDRAW=$(for h in /sys/class/hidraw/hidraw*; do grep -q '0B05:00001ABE' "$h/device/uevent" 2>/dev/null && [[ $(readlink -f "$h/device") == *:1.2/* ]] && echo /dev/$(basename "$h"); done | head -1)
echo "pad=$PAD wmi=$WMI nkey=$(echo $NKEY) hidraw=$HIDRAW" | tee "$OUT/devices.txt"
cat /proc/bus/input/devices > "$OUT/proc-input-devices.txt"

STEPS=(
 "armoury_short|Tap the Armoury Crate button (right of screen, lower) once"
 "armoury_long|HOLD the Armoury Crate button ~2 seconds, then release"
 "cc_short|Tap the Command Centre button (left of screen, lower) once"
 "cc_long|HOLD the Command Centre button ~2 seconds, then release"
 "cc_hold_0.5s|HOLD Command Centre about HALF a second, then release (count 'one-and')"
 "cc_hold_1s|HOLD Command Centre about ONE second, then release"
 "armoury_hold_0.5s|HOLD Armoury Crate about HALF a second, then release"
 "armoury_hold_1s|HOLD Armoury Crate about ONE second, then release"
 "vol_up|Press VOLUME UP twice"
 "vol_down|Press VOLUME DOWN twice"
 "paddle_left|Press the LEFT back paddle (M1) twice"
 "paddle_right|Press the RIGHT back paddle (M2) twice"
 "paddle_left_plus_A|Hold LEFT paddle, press A, release both"
 "paddle_right_plus_A|Hold RIGHT paddle, press A, release both"
 "armoury_plus_A|Hold Armoury Crate, press A, release both"
 "cc_plus_A|Hold Command Centre, press A, release both"
 "idle|Press NOTHING (baseline / catches stray 0xa2 reports)"
)
n=0; total=${#STEPS[@]}
for s in "${STEPS[@]}"; do
  n=$((n+1)); id=${s%%|*}; msg=${s#*|}
  echo; read -rp "[$n/$total] $msg. Press Enter, then do it within ${SECS}s (s=skip): " a
  [[ $a == s ]] && continue
  pids=()
  for d in $NKEY $WMI; do sudo timeout "$SECS" stdbuf -oL evtest --grab "$d" > "$OUT/$id.$(basename $d).txt" 2>&1 & pids+=($!); done
  [[ -n $PAD ]] && { sudo timeout "$SECS" stdbuf -oL evtest "$PAD" > "$OUT/$id.pad.txt" 2>&1 & pids+=($!); }
  [[ -n $HIDRAW ]] && { sudo timeout "$SECS" stdbuf -oL od -An -tx1 -w64 -v "$HIDRAW" > "$OUT/$id.hidraw.txt" 2>&1 & pids+=($!); }
  journalctl -k -f -n0 --no-pager > "$OUT/$id.dmesg.txt" 2>&1 & jp=$!
  echo "  recording..."; wait "${pids[@]}" 2>/dev/null; kill $jp 2>/dev/null
  ev=$(cat "$OUT/$id".*.txt 2>/dev/null | grep -E 'type 1 \(EV_KEY\).*value 1' | sed -E 's/.*code [0-9]+ \(([A-Z0-9_]+)\).*/\1/' | sort -u | tr '\n' ' ')
  echo "  keys seen: ${ev:-none}"
done
sudo chown -R "$USER:" "$OUT"
tar -C "$(dirname "$OUT")" -czf "$OUT.tar.gz" "$(basename "$OUT")"
echo; echo "Done. Results: $OUT.tar.gz  (tell your bot it's there)"
