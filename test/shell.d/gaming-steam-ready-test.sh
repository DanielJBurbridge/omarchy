#!/bin/bash
# Steam's ready check accepts any of its Xwaylands, a Wayland socket, or a
# socket inode. A waiter timeout does not stop a Gamescope that is still up,
# and the old waiter latch is cleared once.

set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$here/base-test.sh"
# shellcheck source=/dev/null
source "$ROOT/default/gaming/steam-ready.sh"

work=$(mktemp -d)
child=
cleanup() {
  if [[ -n $child ]]; then
    kill -- -"$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
  fi
  rm -rf "$work" "${HANDHELD_RUNTIME:-}" "${HANDHELD_HOME:-}"
}
trap cleanup EXIT

proc=$work/proc
mkdir -p "$proc/20" "$proc/21/fd" "$proc/net" "$proc/30/fd"
printf 'PPid:\t1\n' > "$proc/20/status"
printf 'PPid:\t20\n' > "$proc/21/status"
ln -s 'socket:[77]' "$proc/21/fd/4"
printf 'ffff: 00000002 00000000 00010000 0001 01 77 /tmp/.X11-unix/X1\n' > "$proc/net/unix"
DISPLAY=:0 steam_tree_has_ui "$proc" 20 || fail "a Steam child on Xwayland :1 counts as a UI"

mkdir -p "$proc/22/fd"
printf 'PPid:\t1\n' > "$proc/22/status"
ln -s '/run/user/1000/wayland-1' "$proc/22/fd/3"
steam_tree_has_ui "$proc" 22 || fail "a Wayland socket counts as a UI"

mkdir -p "$proc/23/fd"
printf 'PPid:\t1\n' > "$proc/23/status"
ln -s 'socket:[88]' "$proc/23/fd/5"
printf 'ffff: 00000002 00000000 00010000 0001 01 88 /tmp/steam.pipe\n' >> "$proc/net/unix"
if steam_tree_has_ui "$proc" 23; then
  fail "a pipe socket is not a display"
fi
pass "Steam is ready on another Xwayland, on Wayland, and not on an unrelated socket"

state=$work/state
mkdir -p "$state"
gaming_state=$state
printf '%s\n' "$gaming_waiter_timeout_latch" > "$state/recovery"
gaming_clear_waiter_latch
[[ ! -e $state/recovery ]] || fail "the waiter latch is still set" "$(cat "$state/recovery" 2>/dev/null)"
grep -q 'cleared recovery latch' "$state/fallback.log" || fail "clearing the waiter latch is not logged"
printf '%s\n' 'Steam or Gamescope exited; desktop selected until an explicit gaming choice.' > "$state/recovery"
gaming_clear_waiter_latch
[[ -f $state/recovery ]] || fail "a real Steam exit latch was cleared"
pass "only the waiter-timeout recovery latch is cleared"

source "$here/../handheld/gaming-fixture.sh"
handheld_prepare_gaming "$work/hang"
cat > "$HANDHELD_STUB/steam" <<'EOF'
#!/bin/bash
printf 'steam\n' >> "$HANDHELD_ACTIONS"
sleep 30
EOF
chmod +x "$HANDHELD_STUB/steam"
handheld_gaming_env
setsid timeout 12 "$HANDHELD_TREE/bin/omarchy-session-start" gaming >"$work/hang-out" 2>"$work/hang-err" &
child=$!
sleep 4
actions=$(cat "$HANDHELD_LOG" 2>/dev/null || true)
kill -- -"$child" 2>/dev/null || true
wait "$child" 2>/dev/null || true
if grep -q '^uwsm:' <<< "$actions"; then
  fail "a live Gamescope was stopped when the ready waiter timed out" "$actions"
fi
if grep -q 'systemctl:--user stop' <<< "$actions"; then
  fail "the ready waiter stopped the Gamescope scope" "$actions"
fi
fallback=$HANDHELD_HOME/.local/state/omarchy/gaming-session/fallback.log
grep -q 'leaving them up' "$fallback" || fail "the timeout did not record that Steam was left up" "$(cat "$fallback" 2>/dev/null)"
recovery=$HANDHELD_HOME/.local/state/omarchy/gaming-session/recovery
[[ ! -e $recovery ]] || fail "a live Steam wrote the recovery latch" "$(cat "$recovery")"
pass "a ready-waiter timeout leaves a live Gamescope and Steam running"
