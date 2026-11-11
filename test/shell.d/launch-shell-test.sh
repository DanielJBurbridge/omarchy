#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
launch_pid=""

# A supervisor that fails to stop would hang the run instead of failing it.
cleanup() {
  if [[ -n $launch_pid ]]; then
    pkill -TERM -P "$launch_pid" 2>/dev/null || true
    kill -KILL "$launch_pid" 2>/dev/null || true
    wait "$launch_pid" 2>/dev/null || true
  fi
  rm -rf "$test_tmp"
}
trap cleanup EXIT

fake_bin="$test_tmp/bin"
shell_root="$test_tmp/root"
launch_home="$test_tmp/home"
startup_wallpaper="$test_tmp/Selected wallpaper.webp"
mkdir -p "$fake_bin" "$shell_root/shell" "$launch_home/.local/state/omarchy/current"
touch "$startup_wallpaper"
ln -s "$startup_wallpaper" "$launch_home/.local/state/omarchy/current/background"

# Run a scratch copy of the supervisor with its 1s relaunch backoff and
# 0.5s compositor probe shortened; the scenarios only need the waiting
# to happen, not its real duration. The backoff stays well above the
# 0.05s launch poll below so the signal case lands inside it.
launch_shell_bin="$test_tmp/omarchy-launch-shell"
sed -e 's/^  sleep 1$/  sleep 0.3/' -e 's/sleep 0.5$/sleep 0.05/' \
  "$ROOT/bin/omarchy-launch-shell" >"$launch_shell_bin"
chmod +x "$launch_shell_bin"

# Each launch consumes the next status from OMARCHY_TEST_QS_STATUSES; "run"
# stands in for a healthy shell that keeps going until stopped.
cat >"$fake_bin/quickshell" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$OMARCHY_TEST_QS_LOG"
printf 'watcher=%s popup=%s im=%s modules=%s desktop=%s trusted=%s background=%s\n' \
  "${QS_DISABLE_FILE_WATCHER:-unset}" "${QS_NO_RELOAD_POPUP:-unset}" \
  "${QT_IM_MODULE:-unset}" "${QT_IM_MODULES:-unset}" "${QT_VIRTUALKEYBOARD_DESKTOP_DISABLE:-unset}" "${OMARCHY_TRUSTED_KEYBOARD:-unset}" "${OMARCHY_STARTUP_BACKGROUND:-unset}" >>"$OMARCHY_TEST_QS_ENV_LOG"

launches=$(wc -l <"$OMARCHY_TEST_QS_LOG")
status=$(awk -v n="$launches" 'NR == n { print; found = 1 } END { if (!found) print "0" }' <<<"$OMARCHY_TEST_QS_STATUSES")

if [[ $status == "run" ]]; then
  trap 'touch "$OMARCHY_TEST_QS_TERMINATED"; exit 143' TERM
  while true; do sleep 0.05; done
fi

exit "${status:-0}"
SH

cat >"$fake_bin/systemd-cat" <<'SH'
#!/bin/bash

while (( $# > 0 )); do
  [[ $1 == "--" ]] && { shift; break; }
  shift
done
exec "$@"
SH

cat >"$fake_bin/hyprctl" <<'SH'
#!/bin/bash

[[ ${OMARCHY_TEST_COMPOSITOR_GONE:-0} == 1 ]] && exit 4

# Refuse the first OMARCHY_TEST_HYPRCTL_MISSES queries, then answer.
if (( ${OMARCHY_TEST_HYPRCTL_MISSES:-0} > 0 )); then
  misses=$(cat "$OMARCHY_TEST_HYPRCTL_MISS_COUNT" 2>/dev/null || printf '0')
  if (( misses < OMARCHY_TEST_HYPRCTL_MISSES )); then
    printf '%s\n' "$(( misses + 1 ))" >"$OMARCHY_TEST_HYPRCTL_MISS_COUNT"
    exit 4
  fi
fi

printf '[]\n'
SH

cat >"$fake_bin/logger" <<'SH'
#!/bin/bash

shift 2
printf '%s\n' "$*" >>"$OMARCHY_TEST_LOGGER_LOG"
SH

cat >"$fake_bin/omarchy-hw-rog-ally" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_ALLY:-0} == "1" ]]
SH
chmod +x "$fake_bin/omarchy-hw-rog-ally"

chmod +x "$fake_bin/quickshell" "$fake_bin/systemd-cat" "$fake_bin/hyprctl" "$fake_bin/logger"

qs_log="$test_tmp/quickshell.log"
qs_env_log="$test_tmp/quickshell-env.log"
logger_log="$test_tmp/logger.log"
qs_terminated="$test_tmp/quickshell-terminated"
hyprctl_misses="$test_tmp/hyprctl-misses"

launch_shell() {
  : >"$qs_log"
  : >"$qs_env_log"
  : >"$logger_log"

  PATH="$fake_bin:$PATH" \
  HOME="$launch_home" \
  QT_IM_MODULE=fcitx QT_IM_MODULES=fcitx QT_VIRTUALKEYBOARD_DESKTOP_DISABLE=0 \
  OMARCHY_PATH="$shell_root" \
  OMARCHY_TEST_QS_LOG="$qs_log" \
  OMARCHY_TEST_QS_ENV_LOG="$qs_env_log" \
  OMARCHY_TEST_QS_STATUSES="$1" \
  OMARCHY_TEST_COMPOSITOR_GONE="${2:-0}" \
  OMARCHY_TEST_LOGGER_LOG="$logger_log" \
  OMARCHY_TEST_QS_TERMINATED="$qs_terminated" \
  OMARCHY_TEST_HYPRCTL_MISSES="${3:-0}" \
  OMARCHY_TEST_HYPRCTL_MISS_COUNT="$hyprctl_misses" \
    timeout 30 "$launch_shell_bin"
}

launches() {
  wc -l <"$qs_log" | tr -d ' '
}

OMARCHY_TEST_ALLY=1 launch_shell '0' || fail "a clean launch succeeds"
[[ $(launches) == 1 ]] || fail "a shell that exits cleanly is not relaunched" "$(<"$qs_log")"
grep -F -- "-n -p $shell_root/shell" "$qs_log" >/dev/null || fail "the shell launches from OMARCHY_PATH"
pass "a shell that exits cleanly is left alone"

# A misspelled variable would leave Quickshell hot-reloading the tree pacman
# rewrites underneath it, which is what crashes the restart that follows.
[[ $(<"$qs_env_log") == "watcher=1 popup=1 "* ]] ||
  fail "the shell launches with Quickshell's own reloading off" "$(<"$qs_env_log")"
pass "the shell launches with Quickshell's config watcher and reload popup off"
[[ $(<"$qs_env_log") == *"background=$startup_wallpaper" ]] || fail "the shell receives the resolved wallpaper path before startup" "$(<"$qs_env_log")"
pass "the selected wallpaper can decode as soon as Quickshell starts"

[[ $(<"$qs_env_log") == *"im=fcitx modules=fcitx desktop=0 trusted=unset "* ]] ||
  fail "Ally shell preserves caller IME while trusted keyboard activation is held" "$(<"$qs_env_log")"
pass "Ally shell does not activate process-wide Qt Virtual Keyboard"

OMARCHY_TEST_ALLY=0 launch_shell '0' || fail "ordinary desktop launch succeeds"
[[ $(<"$qs_env_log") == *"im=fcitx modules=fcitx desktop=0 trusted=unset "* ]] ||
  fail "ordinary hardware keeps its existing desktop IME" "$(<"$qs_env_log")"
pass "ordinary hardware preserves its desktop input method"

# Qt leaves through _exit(), so Quickshell's crash handler never relaunches it.
launch_shell $'255\n0' || fail "a shell that died on a Wayland error is relaunched"
[[ $(launches) == 2 ]] || fail "the dead shell is relaunched exactly once" "$(<"$qs_log")"
grep -F 'exited with status 255' "$logger_log" >/dev/null || fail "the relaunch is recorded in the journal"
pass "a shell that dies without a signal is relaunched"

launch_shell $'255\n255\n255\n255\n255\n255\n255\n255' && fail "a shell that keeps dying is given up on"
[[ $(launches) == 6 ]] || fail "relaunches stop after the attempt budget" "$(<"$qs_log")"
grep -F 'Giving up' "$logger_log" >/dev/null || fail "giving up is recorded in the journal"
pass "a shell that keeps dying is not relaunched forever"

# The compositor takes the shell with it, and the session is already going.
launch_shell $'255\n0' 1 || fail "a shell outliving the compositor exits cleanly"
[[ $(launches) == 1 ]] || fail "the shell is not relaunched into a dead session" "$(<"$qs_log")"
pass "the shell is not relaunched once the compositor is gone"

# A compositor mid-modeset can miss a query without being gone.
rm -f "$hyprctl_misses"
launch_shell $'255\n0' 0 2 || fail "a shell survives a compositor that misses a query"
[[ $(launches) == 2 ]] || fail "a missed compositor query does not end supervision" "$(<"$qs_log")"
pass "a compositor too busy to answer is not mistaken for one that is gone"

# A signal mid-backoff only reaches the trap once the sleep is over.
: >"$qs_log"
: >"$qs_env_log"
: >"$logger_log"

PATH="$fake_bin:$PATH" \
OMARCHY_PATH="$shell_root" \
OMARCHY_TEST_QS_LOG="$qs_log" \
OMARCHY_TEST_QS_ENV_LOG="$qs_env_log" \
OMARCHY_TEST_QS_STATUSES=$'255\n0' \
OMARCHY_TEST_COMPOSITOR_GONE=0 \
OMARCHY_TEST_LOGGER_LOG="$logger_log" \
OMARCHY_TEST_QS_TERMINATED="$qs_terminated" \
  "$launch_shell_bin" &
launch_pid=$!

for (( waited = 0; waited < 100; waited++ )); do
  [[ $(launches) == 1 ]] && break
  sleep 0.05
done
[[ $(launches) == 1 ]] || fail "the supervised shell launched before the signal" "$(<"$qs_log")"

kill -TERM "$launch_pid"
wait "$launch_pid" || fail "a signalled supervisor exits cleanly"
launch_pid=""
[[ $(launches) == 1 ]] || fail "the shell is not relaunched after the session asked to stop" "$(<"$qs_log")"
pass "a signal during backoff stops the supervisor before it relaunches"

# Stopping the launcher used to stop the shell, back when it exec'd Quickshell.
: >"$qs_log"
: >"$qs_env_log"
: >"$logger_log"
rm -f "$qs_terminated"

PATH="$fake_bin:$PATH" \
OMARCHY_PATH="$shell_root" \
OMARCHY_TEST_QS_LOG="$qs_log" \
OMARCHY_TEST_QS_ENV_LOG="$qs_env_log" \
OMARCHY_TEST_QS_STATUSES='run' \
OMARCHY_TEST_COMPOSITOR_GONE=0 \
OMARCHY_TEST_LOGGER_LOG="$logger_log" \
OMARCHY_TEST_QS_TERMINATED="$qs_terminated" \
  "$launch_shell_bin" &
launch_pid=$!

for (( waited = 0; waited < 100; waited++ )); do
  [[ $(launches) == 1 ]] && break
  sleep 0.05
done
[[ $(launches) == 1 ]] || fail "the healthy shell launched before the signal" "$(<"$qs_log")"

kill -TERM "$launch_pid"
for (( waited = 0; waited < 100; waited++ )); do
  kill -0 "$launch_pid" 2>/dev/null || break
  sleep 0.05
done
kill -0 "$launch_pid" 2>/dev/null && fail "a signalled supervisor stops instead of waiting on a live shell"
wait "$launch_pid" 2>/dev/null || true
launch_pid=""

[[ -f $qs_terminated ]] || fail "the running shell is signalled when the supervisor is"
[[ $(launches) == 1 ]] || fail "the signalled shell is not relaunched" "$(<"$qs_log")"
pass "stopping the supervisor stops the shell it is watching"

# The real launcher, Quickshell and Qt input-context getter must keep an
# unrelated QML importer away from the populated lock field. A child then
# reports the three exact inherited values, including unset versus empty.
if command -v quickshell >/dev/null 2>&1; then
  context_root="$test_tmp/input-context"
  mkdir -p "$context_root/shell" "$context_root/runtime" "$context_root/bin"
  chmod 700 "$context_root/runtime"
  cp "$SHELL_TEST_DIR/fixtures/lock-input-context/"*.qml "$context_root/shell/"
  ln -s "$ROOT/shell/Ui" "$context_root/shell/Ui"
  ln -s "$ROOT/shell/Commons" "$context_root/shell/Commons"
  cp "$fake_bin/systemd-cat" "$fake_bin/omarchy-hw-rog-ally" "$context_root/bin/"
  for variant in unset empty custom; do
    context_env=()
    case $variant in
      unset) context_env=(-u QT_IM_MODULE -u QT_IM_MODULES -u QT_VIRTUALKEYBOARD_DESKTOP_DISABLE) ;;
      empty) context_env=(QT_IM_MODULE= QT_IM_MODULES= QT_VIRTUALKEYBOARD_DESKTOP_DISABLE=) ;;
      custom) context_env=(QT_IM_MODULE=fcitx QT_IM_MODULES='fcitx;ibus' QT_VIRTUALKEYBOARD_DESKTOP_DISABLE=0) ;;
    esac
    PATH="$context_root/bin:$PATH" OMARCHY_TEST_ALLY=1 HOME="$launch_home" \
      XDG_RUNTIME_DIR="$context_root/runtime" OMARCHY_PATH="$context_root" \
      OMARCHY_AUTH_SOURCE_ROOT="$ROOT" OMARCHY_AUTH_CHILD_RESULT="$context_root/$variant.json" \
      OMARCHY_AUTH_EXPECT_EXPOSED=0 QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software \
      env "${context_env[@]}" timeout 15 "$ROOT/bin/omarchy-launch-shell" >"$context_root/$variant.log" 2>&1 || {
        cat "$context_root/$variant.log" >&2
        fail "real launcher input-context check runs ($variant)"
      }
    if ! grep -q 'LOCK_INPUT_CONTEXT_TEST_PASS' "$context_root/$variant.log" || grep -q 'LOCK_INPUT_CONTEXT_TEST_FAIL' "$context_root/$variant.log"; then
      cat "$context_root/$variant.log" >&2
      fail "unrelated QML cannot read lock password ($variant)"
    fi
    for _ in {1..30}; do
      [[ -s $context_root/$variant.json ]] && break
      sleep 0.1
    done
    python3 - "$context_root/$variant.json" "$variant" <<'PY_CHILD'
import json, sys
keys = ['QT_IM_MODULE', 'QT_IM_MODULES', 'QT_VIRTUALKEYBOARD_DESKTOP_DISABLE']
values = {'unset': [None, None, None], 'empty': ['', '', ''], 'custom': ['fcitx', 'fcitx;ibus', '0']}[sys.argv[2]]
with open(sys.argv[1]) as result:
  actual = json.load(result)
assert actual == dict(zip(keys, values)), actual
PY_CHILD
    pass "unrelated importer cannot read password and real child preserves exact $variant IME environment"
  done
fi
