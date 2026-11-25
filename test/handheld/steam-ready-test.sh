#!/bin/bash
# Drive the real Steam wrapper through launch, bootstrap and gamepad UI.

set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$here/../shell.d/base-test.sh"

work=$(mktemp -d)
child=
cleanup() {
  if [[ -n $child ]]; then
    kill -- -"$child" 2>/dev/null || kill "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
  fi
  rm -rf -- "$work"
}
trap cleanup EXIT

mkdir -p "$work/bin" "$work/home" "$work/proc" "$work/runtime"
mkfifo -m 600 "$work"/{spawn,scan,advance,quit} "$work/runtime/ready"
exec {spawn_fd}<>"$work/spawn" {scan_fd}<>"$work/scan" {advance_fd}<>"$work/advance" {quit_fd}<>"$work/quit"

cat > "$work/bin/omarchy-cmd-present" <<'EOF'
#!/bin/bash
[[ $* == omarchy-launch-gaming-powerbutton ]]
EOF
printf '#!/bin/bash\nexit 1\n' > "$work/bin/omarchy-pkg-present"

cat > "$work/bin/steam" <<'EOF'
#!/bin/bash
mkdir -p "$OMARCHY_STEAM_PROC_ROOT/$$/fd"
printf 'Name:\tsteam\nPPid:\t%s\n' "$PPID" > "$OMARCHY_STEAM_PROC_ROOT/$$/status"
ln -s '/tmp/.X11-unix/X77' "$OMARCHY_STEAM_PROC_ROOT/$$/fd/3"
printf '%s\n' "$$" > "$FIXTURE/spawn"
read -r -t 15 reply <> "$FIXTURE/quit" && [[ $reply == "quit" ]]
EOF

# Pause after each unsuccessful scan, so the test can control when the next
# scan happens without depending on how fast the fixture is scheduled.
cat > "$work/bin/sleep" <<'EOF'
#!/bin/bash
printf 'scan\n' > "$FIXTURE/scan"
read -r -t 5 reply <> "$FIXTURE/advance" && [[ $reply == "scan" ]]
EOF
chmod +x "$work/bin/"*

HOME="$work/home" XDG_RUNTIME_DIR="$work/runtime" PATH="$work/bin:/usr/bin:/bin" \
  OMARCHY_PATH="$ROOT" OMARCHY_GAMING_NETWORK_TIMEOUT=0 \
  OMARCHY_GAMING_RUNTIME="$work/runtime" OMARCHY_STEAM_PROC_ROOT="$work/proc" \
  OMARCHY_GAMING_READY_TIMEOUT=15 DISPLAY=:77 FIXTURE="$work" \
  setsid timeout --kill-after=2s 20 "$ROOT/bin/omarchy-gaming-steam" > "$work/output" 2>&1 &
child=$!
read -r -t 5 -u "$spawn_fd" steam_pid && [[ $steam_pid =~ ^[1-9][0-9]*$ ]] ||
  fail "Steam launches before the ready FIFO has a reader" "$(cat "$work/output")"
pass "Steam launches before the ready FIFO has a reader"

exec {ready_fd}<>"$work/runtime/ready"
read -r -t 3 -u "$scan_fd" event && [[ $event == "scan" ]] ||
  fail "the Steam wrapper scans before gamepad UI exists" "$(cat "$work/output")"
printf 'scan\n' >&"$advance_fd"
read -r -t 3 -u "$scan_fd" event && [[ $event == "scan" ]] ||
  fail "the Steam bootstrap display does not signal ready" "$(cat "$work/output")"
if read -r -t 0 -u "$ready_fd"; then
  fail "the Steam bootstrap display does not signal ready"
fi
pass "the Steam bootstrap display does not signal ready"

helper_pid=$((steam_pid + 1))
mkdir -p "$work/proc/$helper_pid/fd"
printf 'Name:\tsteamwebhelper\nPPid:\t%s\n' "$steam_pid" > "$work/proc/$helper_pid/status"
ln -s '/tmp/.X11-unix/X77' "$work/proc/$helper_pid/fd/3"
printf 'scan\n' >&"$advance_fd"
read -r -t 3 -u "$ready_fd" event && [[ $event == "started" ]] ||
  fail "a connected Steam webhelper signals ready" "$(cat "$work/output")"
printf 'quit\n' >&"$quit_fd"
wait "$child" || fail "Steam exits cleanly after ready" "$(cat "$work/output")"
child=
[[ $(< "$work/runtime/steam-exit") == "0" ]] || fail "the wrapper records Steam's exit status"
pass "a connected Steam webhelper signals ready and Steam exits cleanly"
