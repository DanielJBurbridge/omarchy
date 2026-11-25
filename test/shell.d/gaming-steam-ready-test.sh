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
printf 'Name:\tsteamwebhelper\nPPid:\t20\n' > "$proc/21/status"
ln -s 'socket:[77]' "$proc/21/fd/4"
printf 'ffff: 00000002 00000000 00010000 0001 01 77 /tmp/.X11-unix/X1\n' > "$proc/net/unix"
DISPLAY=:0 steam_tree_has_ui "$proc" 20 || fail "a Steam child on Xwayland :1 counts as a UI"

mkdir -p "$proc/22/fd"
printf 'Name:\tsteamwebhelper\nPPid:\t1\n' > "$proc/22/status"
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

# The steam client's own X window is the bootstrap, the updater, or the
# offline error dialog. It is up before the gamepad UI. Counting it ready
# clears the crash counter on a start that never reached Steam's UI.
boot=$work/proc-boot
mkdir -p "$boot/20" "$boot/21/fd" "$boot/net"
printf 'Name:\tsteam\nPPid:\t1\n' > "$boot/20/status"
printf 'Name:\tsteam\nPPid:\t20\n' > "$boot/21/status"
ln -s 'socket:[77]' "$boot/21/fd/4"
printf 'ffff: 00000002 00000000 00010000 0001 01 77 /tmp/.X11-unix/X1\n' > "$boot/net/unix"
if steam_tree_has_ui "$boot" 20; then
  fail "a steam bootstrap X client counts as ready"
fi
pass "a steam bootstrap X client does not mark ready"

# 205 sorts between the Steam parent (200) and steamwebhelper (210). Its
# status is unreadable, the shape of a helper that exits after the glob.
# One awk aborts there and never records the child that holds the display.
race=$work/proc-race
mkdir -p "$race/200" "$race/205" "$race/210/fd"
printf 'Name:\tsteam\nPPid:\t1\n' > "$race/200/status"
printf 'Name:\treaped\nPPid:\t200\n' > "$race/205/status"
chmod 000 "$race/205/status"
printf 'Name:\tsteamwebhelper\nPPid:\t200\n' > "$race/210/status"
ln -s '/tmp/.X11-unix/X1' "$race/210/fd/4"
steam_tree_has_ui "$race" 200 || fail "an unreadable status hides steamwebhelper's display"
pass "an unreadable proc status is skipped and steamwebhelper's display still counts"

# Ally capture, 16 Nov 2026. Gamescope's Xwayland accepts clients on the
# abstract socket. /proc/net/unix names that socket on the server inode only,
# and steamwebhelper's fd is a path-less socket:[client]. gamescopereaper has
# reparented that process out of the launcher's children. ss pairs the client
# inode with the abstract path. A steamwebhelper in another cgroup does not
# count, even with the same socket shape.
ally=$work/proc-ally
scope='0::/user.slice/user-1000.slice/user@1000.service/app.slice/omarchy-gamescope-27.scope'
mkdir -p "$ally/300" "$ally/310" "$ally/400/fd" "$ally/999" "$ally/net"
printf 'Name:\tbash\nPPid:\t1\nUid:\t1000\t1000\t1000\t1000\n' > "$ally/300/status"
printf '%s\n' "$scope" > "$ally/300/cgroup"
printf 'Name:\tsteam\nPPid:\t300\nUid:\t1000\t1000\t1000\t1000\n' > "$ally/310/status"
printf '%s\n' "$scope" > "$ally/310/cgroup"
printf 'Name:\tgamescopereaper\nPPid:\t1\nUid:\t1000\t1000\t1000\t1000\n' > "$ally/999/status"
printf 'Name:\tsteamwebhelper\nPPid:\t999\nUid:\t1000\t1000\t1000\t1000\n' > "$ally/400/status"
printf '%s\n' "$scope" > "$ally/400/cgroup"
ln -s 'socket:[555]' "$ally/400/fd/12"
printf '%s\n' \
  'ffff: 00000002 00000000 00010000 0001 01 1718531 /tmp/.X11-unix/X0' \
  'ffff: 00000002 00000000 00010000 0001 01 1454770 @/tmp/.X11-unix/X0' \
  > "$ally/net/unix"
cat > "$ally/ss" <<'EOF'
u_str LISTEN 0 128 /tmp/.X11-unix/X0 1718531 * 0 users:(("Xwayland",pid=21,fd=4))
u_str LISTEN 0 128 @/tmp/.X11-unix/X0 1454770 * 0 users:(("Xwayland",pid=21,fd=5))
u_str ESTAB 0 0 @/tmp/.X11-unix/X0 1454800 * 555 users:(("Xwayland",pid=21,fd=8))
u_str ESTAB 0 0 * 555 * 1454800 users:(("steamwebhelper",pid=400,fd=12))
EOF
steam_tree_has_ui "$ally" 300 || fail "a reparented steamwebhelper on the abstract X socket counts as a UI"
pass "a reparented steamwebhelper on Gamescope's abstract X socket counts as a UI"

other=$work/proc-other-scope
mkdir -p "$other/300" "$other/400/fd" "$other/net"
printf 'Name:\tbash\nPPid:\t1\nUid:\t1000\t1000\t1000\t1000\n' > "$other/300/status"
printf '%s\n' '0::/user.slice/user-1000.slice/session-3.scope' > "$other/300/cgroup"
printf 'Name:\tsteamwebhelper\nPPid:\t1\nUid:\t1000\t1000\t1000\t1000\n' > "$other/400/status"
printf '%s\n' '0::/user.slice/user-1000.slice/session-4.scope' > "$other/400/cgroup"
ln -s 'socket:[555]' "$other/400/fd/12"
cp "$ally/net/unix" "$other/net/unix"
cp "$ally/ss" "$other/ss"
if steam_tree_has_ui "$other" 300; then
  fail "a steamwebhelper outside the gamescope scope counts as this session's UI"
fi
pass "a steamwebhelper in another cgroup is not this session's UI"

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

# The scan stops when the waiter's window ends. Steam keeps running; the
# 0.2s sleep does not continue for the rest of that process.
poll=$work/poll
mkdir -p "$poll/bin" "$poll/proc/1" "$poll/runtime"
printf 'PPid:\t0\n' > "$poll/proc/1/status"
mkfifo -m 600 "$poll/runtime/ready"
cat > "$poll/bin/steam" <<'EOF'
#!/bin/bash
/bin/sleep 3
EOF
cat > "$poll/bin/sleep" <<'EOF'
#!/bin/bash
if [[ ${1:-} == 0.2 ]]; then
  date +%s%N >> "$POLL_LOG"
fi
exec /bin/sleep "$@"
EOF
chmod +x "$poll/bin/steam" "$poll/bin/sleep"
: > "$poll/sleeps"
PATH="$poll/bin:/usr/bin:/bin" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_GAMING_RUNTIME="$poll/runtime" \
  OMARCHY_STEAM_PROC_ROOT="$poll/proc" \
  OMARCHY_GAMING_READY_TIMEOUT=1 \
  OMARCHY_GAMING_NETWORK_TIMEOUT=0 \
  DISPLAY=:9 \
  POLL_LOG="$poll/sleeps" \
  "$ROOT/bin/omarchy-gaming-steam" >"$poll/out" 2>"$poll/err" &
child=$!
wait "$child" || fail "the ready poller exited early" "$(cat "$poll/err" 2>/dev/null)"
child=
mapfile -t stamps < "$poll/sleeps"
(( ${#stamps[@]} > 0 )) || fail "the ready poll never slept" "$(cat "$poll/err" 2>/dev/null)"
first=${stamps[0]}
last=${stamps[-1]}
span=$(( (last - first) / 1000000000 ))
(( span < 2 )) || fail "the ready poll kept sleeping after the waiter window" "span=${span}s count=${#stamps[@]}"
pass "the ready poll stops when the waiter window ends"
