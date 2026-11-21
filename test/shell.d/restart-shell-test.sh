#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
restart_pid_one=""
restart_pid_two=""

cleanup() {
  [[ -n $restart_pid_one ]] && kill "$restart_pid_one" 2>/dev/null || true
  [[ -n $restart_pid_two ]] && kill "$restart_pid_two" 2>/dev/null || true
  rm -rf "$test_tmp"
}
trap cleanup EXIT

restart_root="$test_tmp/restart-root"
restart_bin="$restart_root/bin"
restart_state="$test_tmp/restart-pids"
restart_log="$test_tmp/restart.log"
restart_env_log="$test_tmp/restart-env.log"
dispatch_log="$test_tmp/dispatch.log"
ipc_log="$test_tmp/ipc.log"
runtime_dir="$test_tmp/runtime"
mkdir -p "$restart_root/shell" "$restart_bin" "$runtime_dir" "$restart_root/default/lock-host"
chmod 700 "$runtime_dir"
# This fixture tests restart policy; native context identity is covered by
# trusted-lock-host-test, rather than pretending these sleep/qs stubs are Qt.
# WAYLAND_DISPLAY is not exported: a TTY/SSH restart recovers it from the
# runtime socket before context() runs. The stub records that recovered name.
export HYPRLAND_INSTANCE_SIGNATURE=restart-fixture
unset WAYLAND_DISPLAY
: >"$test_tmp/context-display"
python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$runtime_dir/wayland-7"
cat >"$restart_bin/omarchy-lock-host" <<'SH'
#!/bin/bash
if [[ $1 == "context" ]]; then
  printf '%s\n' "${WAYLAND_DISPLAY:-missing}" >>"$XDG_RUNTIME_DIR/context-display"
  # A TTY caller with no recovered display is not a validated session.
  [[ -n ${WAYLAND_DISPLAY:-} ]] || exit 1
  [[ ${OMARCHY_TEST_CONTEXT_VALID:-1} == "1" ]] || exit 1
  echo shell
else
  exec /usr/bin/python3 -I "$OMARCHY_PATH/default/lock-host/control.py" "$@"
fi
SH
chmod +x "$restart_bin/omarchy-lock-host"
cp "$ROOT/default/lock-host/control.py" "$restart_root/default/lock-host/"
touch "$restart_root/shell/shell.qml"
ln -s "$ROOT/bin/omarchy-shell" "$restart_bin/omarchy-shell"
ln -s "$ROOT/bin/omarchy-launch-shell" "$restart_bin/omarchy-launch-shell"
ln -s "$ROOT/bin/omarchy-cmd-missing" "$restart_bin/omarchy-cmd-missing"
cat >"$restart_bin/omarchy-hyprland-session-locked" <<'SH'
#!/bin/bash
if [[ -n ${OMARCHY_TEST_PROBE_RESULT:-} ]]; then
  exit "$OMARCHY_TEST_PROBE_RESULT"
else
  exec "$ROOT/bin/omarchy-hyprland-session-locked"
fi
SH
chmod +x "$restart_bin/omarchy-hyprland-session-locked"

cat >"$restart_bin/qs" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$OMARCHY_TEST_IPC_LOG"

case "$*" in
  *'shell ping')
    [[ $* == *"-p $OMARCHY_TEST_SESSION_PATH/shell"* ]] &&
      grep -Fx '303' "$OMARCHY_TEST_QS_STATE" >/dev/null &&
      printf 'ok\n'
    ;;
  *'lock lock')
    touch "$OMARCHY_TEST_QS_STATE.locked"
    printf 'ok\n'
    ;;
  *'lock status')
    if [[ -f $OMARCHY_TEST_QS_STATE.locked ]]; then
      printf '{"secure": true, "requested": true}\n'
    else
      printf '{"secure": false, "requested": false}\n'
    fi
    ;;
esac
SH

cat >"$restart_bin/quickshell" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$OMARCHY_TEST_QS_LOG"

# Other configs' instances, one "<config dir> <pid>" per line.
strays=${OMARCHY_TEST_QS_STRAYS:-/nonexistent}

case " $* " in
  *' list '*)
    [[ -f $strays ]] && jq -R -s -c 'split("\n") | map(select(length > 0) | split(" ") | {config_path: (.[0] | if endswith(".qml") then . else . + "/shell.qml" end), pid: (.[1] | tonumber)})' "$strays"
    ;;
  *' kill -p '*)
    if [[ $3 != "$OMARCHY_TEST_SESSION_PATH/shell" ]]; then
      pid=$(awk -v dir="$3" '$1 == dir { print $2; exit }' "$strays" 2>/dev/null)
      [[ $pid =~ ^[0-9]+$ ]] || exit 1
      # The instance outlasts the client's timeout and exits a moment later.
      (
        sleep 0.5
        kill "$pid" 2>/dev/null
        awk -v dir="$3" '$1 != dir' "$strays" >"$strays.next"
        mv "$strays.next" "$strays"
      ) &
      exit 124
    fi

    pid=$(head -n 1 "$OMARCHY_TEST_QS_STATE")
    [[ $pid =~ ^[0-9]+$ ]] || exit 1
    kill "$pid" 2>/dev/null
    while kill -0 "$pid" 2>/dev/null; do sleep 0.01; done
    awk 'NR > 1' "$OMARCHY_TEST_QS_STATE" >"$OMARCHY_TEST_QS_STATE.next"
    mv "$OMARCHY_TEST_QS_STATE.next" "$OMARCHY_TEST_QS_STATE"
    ;;
  *' -n -p '*)
    printf '%s\n' "${OMARCHY_TEST_TRANSIENT_ENV-unset}" >"$OMARCHY_TEST_QS_ENV_LOG"
    printf '303\n' >"$OMARCHY_TEST_QS_STATE"
    [[ ! -f $strays ]] || cp "$strays" "$strays.at-launch"
    ;;
esac
SH

cat >"$restart_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ ${1:-} == "-j" && ${2:-} == "monitors" ]]; then
  # Hyprland reports an active session lock as a reason the monitor cannot hand
  # a client the whole screen, not as a workspace.
  if [[ ${OMARCHY_TEST_SESSION_LOCKED:-0} == 1 ]]; then
    printf '[{"name":"eDP-1","solitaryBlockedBy":["WINDOWED","LOCK","CANDIDATE"]}]\n'
  else
    printf '[{"name":"eDP-1","solitaryBlockedBy":["WINDOWED","CANDIDATE"]}]\n'
  fi
elif [[ ${1:-} == "dispatch" && ${2:-} == hl.dsp.exec_cmd* ]]; then
  printf '%s\n' "${2:-}" >>"$OMARCHY_TEST_DISPATCH_LOG"
  OMARCHY_PATH="$OMARCHY_TEST_SESSION_PATH" \
    env -u OMARCHY_TEST_TRANSIENT_ENV omarchy-launch-shell
  printf 'ok\n'
elif [[ ${1:-} == "dispatch" ]]; then
  exit 1
fi
SH

# Keep the test hermetic where journald has no usable stream socket.
cat >"$restart_bin/systemd-cat" <<'SH'
#!/bin/bash

while (( $# > 0 )); do
  [[ $1 == "--" ]] && { shift; break; }
  shift
done
exec "$@"
SH

cat >"$restart_bin/systemctl" <<'SH'
#!/bin/bash

if [[ ${1:-} == "--user" && ${2:-} == "show-environment" ]]; then
  printf 'OMARCHY_PATH=%s\n' "$OMARCHY_TEST_SESSION_PATH"
elif [[ ${1:-} == "--user" && ${2:-} == "try-restart" ]]; then
  exit 0
else
  exit 1
fi
SH

cat >"$restart_bin/busctl" <<'SH'
#!/bin/bash
if [[ -z ${OMARCHY_TEST_NOTIFICATION_CHECKS:-} ]]; then
  echo 'b false'
else
  checks=0
  [[ ! -f $OMARCHY_TEST_NOTIFICATION_CHECKS ]] || read -r checks <"$OMARCHY_TEST_NOTIFICATION_CHECKS"
  (( checks += 1 ))
  printf '%s\n' "$checks" >"$OMARCHY_TEST_NOTIFICATION_CHECKS"
  # The service was running before the restart and, when asked to, never
  # comes back afterwards.
  if [[ ${OMARCHY_TEST_NOTIFICATIONS_DIE:-0} == 1 ]]; then
    (( checks == 1 )) && echo 'b true' || echo 'b false'
    exit 0
  fi
  if (( checks == 1 || checks >= 4 )); then
    echo 'b true'
  else
    echo 'b false'
  fi
fi
SH

chmod +x "$restart_bin/qs" "$restart_bin/quickshell" "$restart_bin/hyprctl" "$restart_bin/systemd-cat" "$restart_bin/systemctl" "$restart_bin/busctl"

sleep 30 &
restart_pid_one=$!
sleep 30 &
restart_pid_two=$!
printf '%s\n%s\n' "$restart_pid_one" "$restart_pid_two" >"$restart_state"

caller_root="$test_tmp/caller-root"
mkdir -p "$caller_root/shell"
touch "$caller_root/shell/shell.qml"

PATH="$restart_bin:$PATH" \
OMARCHY_PATH="$caller_root" \
XDG_RUNTIME_DIR="$runtime_dir" \
OMARCHY_TEST_QS_STATE="$restart_state" \
OMARCHY_TEST_QS_LOG="$restart_log" \
OMARCHY_TEST_QS_ENV_LOG="$restart_env_log" \
OMARCHY_TEST_DISPATCH_LOG="$dispatch_log" \
OMARCHY_TEST_IPC_LOG="$ipc_log" \
OMARCHY_TEST_SESSION_PATH="$restart_root" \
OMARCHY_TEST_TRANSIENT_ENV=leaked \
OMARCHY_TEST_NOTIFICATION_CHECKS="$test_tmp/notification-checks" \
  timeout 5 "$ROOT/bin/omarchy-restart-shell"

if kill -0 "$restart_pid_one" 2>/dev/null; then
  fail "restart stops the first matching shell instance"
fi
if kill -0 "$restart_pid_two" 2>/dev/null; then
  fail "restart stops duplicate matching shell instances"
fi
wait "$restart_pid_one" 2>/dev/null || true
wait "$restart_pid_two" 2>/dev/null || true
restart_pid_one=""
restart_pid_two=""
[[ $(<"$restart_state") == 303 ]] || fail "restart leaves exactly one fresh shell instance"
[[ $(grep -c '^-n -p ' "$restart_log") == 1 ]] || fail "restart launches one fresh shell process"
grep -F "kill -p $restart_root/shell --any-display" "$restart_log" >/dev/null || fail "restart stops the shell from the session checkout"
[[ $(<"$restart_env_log") == "unset" ]] || fail "restart uses the Hyprland session environment for the fresh shell"
grep -F 'hl.dsp.exec_cmd("omarchy-launch-shell")' "$dispatch_log" >/dev/null || fail "restart launches the fresh shell through Hyprland"
grep -F "ipc -n -p $restart_root/shell call -- shell ping" "$ipc_log" >/dev/null || fail "restart checks readiness in the session checkout"
pass "restart replaces duplicate shell instances from the session checkout"
[[ $(<"$test_tmp/notification-checks") == 4 ]] || fail "restart waits for the existing notification service after core IPC is ready"
pass "restart waits for notification readiness before one-time update hooks"

: >"$restart_log"
printf '303\n' >"$restart_state"
touch "$restart_state.locked"

locked_error=$(PATH="$restart_bin:$PATH" \
  OMARCHY_PATH="$restart_root" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  OMARCHY_TEST_SESSION_LOCKED=1 \
  OMARCHY_TEST_QS_STATE="$restart_state" \
  OMARCHY_TEST_QS_LOG="$restart_log" \
  OMARCHY_TEST_DISPATCH_LOG="$dispatch_log" \
  OMARCHY_TEST_IPC_LOG="$ipc_log" \
  OMARCHY_TEST_SESSION_PATH="$restart_root" \
  "$ROOT/bin/omarchy-restart-shell" 2>&1) && fail "restart refuses while the shell lock is active"

[[ $locked_error == "Refusing to restart Omarchy shell while the session is locked." ]] || fail "locked restart explains why it was refused" "$locked_error"
[[ $(<"$restart_state") == 303 ]] || fail "locked restart preserves the running shell"
[[ ! -s $restart_log ]] || fail "locked restart does not stop or launch Quickshell"
grep -qx 'wayland-7' "$runtime_dir/context-display" || fail "TTY restart recovers WAYLAND_DISPLAY before checking the lock" "$(<"$runtime_dir/context-display")"
pass "restart preserves the shell while its lock is active"
pass "TTY restart recovers the Wayland display from the session socket"

: >"$runtime_dir/context-display"
mv "$runtime_dir/wayland-7" "$runtime_dir/wayland-7.away"
locked_error=$(PATH="$restart_bin:$PATH" OMARCHY_PATH="$restart_root" XDG_RUNTIME_DIR="$runtime_dir" \
  OMARCHY_TEST_SESSION_LOCKED=1 OMARCHY_TEST_QS_STATE="$restart_state" \
  OMARCHY_TEST_QS_LOG="$restart_log" OMARCHY_TEST_SESSION_PATH="$restart_root" \
  "$ROOT/bin/omarchy-restart-shell" 2>&1) && fail "TTY restart without a display socket must refuse"
[[ $locked_error == "Refusing locked desktop restart without a validated graphical session context." ]] || fail "missing display socket is not mistaken for orphan recovery" "$locked_error"
mv "$runtime_dir/wayland-7.away" "$runtime_dir/wayland-7"
pass "TTY restart without a display socket refuses before killing the lock client"

locked_error=$(PATH="$restart_bin:$PATH" OMARCHY_PATH="$restart_root" XDG_RUNTIME_DIR="$runtime_dir" \
  OMARCHY_TEST_CONTEXT_VALID=0 OMARCHY_TEST_SESSION_LOCKED=1 OMARCHY_TEST_QS_STATE="$restart_state" \
  OMARCHY_TEST_QS_LOG="$restart_log" OMARCHY_TEST_SESSION_PATH="$restart_root" \
  "$ROOT/bin/omarchy-restart-shell" 2>&1) && fail "unsupported lock context must refuse restart"
[[ $locked_error == "Refusing locked desktop restart without a validated graphical session context." ]] || fail "unsupported lock context is not mistaken for orphan recovery" "$locked_error"
[[ ! -s $restart_log ]] || fail "unsupported lock context must not kill an active owner"
pass "unsupported lock context refuses restart before killing any lock client"

# Unknown, failed and unexpected probes must not be taken for unlocked.
# Each case owns a disposable process so a regressed kill cannot hit a real UI.
for probe_result in 2 127 137; do
  sleep 30 &
  restart_pid_one=$!
  printf '%s\n' "$restart_pid_one" >"$restart_state"
  : >"$restart_log"
  locked_error=$(PATH="$restart_bin:$PATH" OMARCHY_PATH="$restart_root" XDG_RUNTIME_DIR="$runtime_dir" \
    OMARCHY_TEST_PROBE_RESULT="$probe_result" OMARCHY_TEST_QS_STATE="$restart_state" \
    OMARCHY_TEST_QS_LOG="$restart_log" OMARCHY_TEST_QS_ENV_LOG="$restart_env_log" \
    OMARCHY_TEST_DISPATCH_LOG="$dispatch_log" OMARCHY_TEST_IPC_LOG="$ipc_log" \
    OMARCHY_TEST_SESSION_PATH="$restart_root" \
    timeout 5 "$ROOT/bin/omarchy-restart-shell" 2>&1) && fail "probe $probe_result must refuse restart"
  [[ $locked_error == "Refusing desktop restart: compositor lock state is unknown." ]] || fail "probe $probe_result reports unknown state" "$locked_error"
  [[ ! -s $restart_log ]] || fail "probe $probe_result must refuse before any Quickshell kill"
  kill -0 "$restart_pid_one" 2>/dev/null || fail "probe $probe_result preserves the existing client"
  kill "$restart_pid_one"
  wait "$restart_pid_one" 2>/dev/null || true
  restart_pid_one=""
  pass "probe $probe_result refuses restart and preserves the existing client"
done

# A LOCK session without an active locker — dead shell or a crash-handler
# relaunch holding no lock — is the failsafe: restart must proceed,
# re-acquire the session lock, and wait for it to report secure.
sleep 30 &
restart_pid_one=$!
printf '%s\n' "$restart_pid_one" >"$restart_state"
rm -f "$restart_state.locked"
: >"$restart_log"
: >"$ipc_log"

PATH="$restart_bin:$PATH" \
OMARCHY_PATH="$restart_root" \
XDG_RUNTIME_DIR="$runtime_dir" \
OMARCHY_TEST_SESSION_LOCKED=1 \
OMARCHY_TEST_QS_STATE="$restart_state" \
OMARCHY_TEST_QS_LOG="$restart_log" \
OMARCHY_TEST_QS_ENV_LOG="$restart_env_log" \
OMARCHY_TEST_DISPATCH_LOG="$dispatch_log" \
OMARCHY_TEST_IPC_LOG="$ipc_log" \
OMARCHY_TEST_SESSION_PATH="$restart_root" \
  timeout 5 "$ROOT/bin/omarchy-restart-shell" || fail "locked restart recovers when the lock client is dead"

if kill -0 "$restart_pid_one" 2>/dev/null; then
  fail "dead-lock recovery stops the stale shell instance"
fi
wait "$restart_pid_one" 2>/dev/null || true
restart_pid_one=""
[[ $(<"$restart_state") == 303 ]] || fail "dead-lock recovery leaves one fresh shell instance"
grep -F "ipc -n -p $restart_root/shell call -- lock lock" "$ipc_log" >/dev/null || fail "dead-lock recovery re-acquires the session lock"
grep -F "ipc -n -p $restart_root/shell call -- lock status" "$ipc_log" >/dev/null || fail "dead-lock recovery waits for the lock to become secure"
pass "restart recovers a locked session whose lock client died"

# Lock recovery must not wait on the notification plugin: a stranded user gets
# the lock back even when notifications never return, and the restart then
# reports the missing service rather than claiming success.
sleep 30 &
restart_pid_one=$!
printf '%s\n' "$restart_pid_one" >"$restart_state"
rm -f "$restart_state.locked" "$test_tmp/notification-checks"
: >"$restart_log"
: >"$ipc_log"

if PATH="$restart_bin:$PATH" \
  OMARCHY_PATH="$restart_root" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  OMARCHY_TEST_SESSION_LOCKED=1 \
  OMARCHY_TEST_QS_STATE="$restart_state" \
  OMARCHY_TEST_QS_LOG="$restart_log" \
  OMARCHY_TEST_QS_ENV_LOG="$restart_env_log" \
  OMARCHY_TEST_DISPATCH_LOG="$dispatch_log" \
  OMARCHY_TEST_IPC_LOG="$ipc_log" \
  OMARCHY_TEST_SESSION_PATH="$restart_root" \
  OMARCHY_TEST_NOTIFICATION_CHECKS="$test_tmp/notification-checks" \
  OMARCHY_TEST_NOTIFICATIONS_DIE=1 \
  timeout 10 "$ROOT/bin/omarchy-restart-shell" >"$test_tmp/dead-notifications.out" 2>&1; then
  fail "a restart whose notification service never returns must not report success"
fi
wait "$restart_pid_one" 2>/dev/null || true
restart_pid_one=""
grep -F "ipc -n -p $restart_root/shell call -- lock lock" "$ipc_log" >/dev/null || fail "lock recovery waited on the notification service" "$(cat "$ipc_log")"
[[ -f $restart_state.locked ]] || fail "lock recovery did not re-secure the session without notifications"
grep -q "notification service did not become ready" "$test_tmp/dead-notifications.out" || fail "a missing notification service is not reported" "$(cat "$test_tmp/dead-notifications.out")"
pass "restart recovers the lock even when the notification service never returns"

# A worktree's shell left running after a visual check holds the notification
# server and is out of omarchy-shell's reach, so a restart stops it too. A
# Quickshell config that is not an Omarchy tree is someone else's and stays.
worktree_root="$test_tmp/worktree"
other_root="$test_tmp/other"
mkdir -p "$worktree_root/shell" "$worktree_root/bin" "$other_root/shell"
ln -s "$ROOT/bin/omarchy-launch-shell" "$worktree_root/bin/omarchy-launch-shell"
sleep 30 &
restart_pid_one=$!
sleep 30 &
restart_pid_two=$!
printf '%s %s\n%s %s\n' "$worktree_root/shell" "$restart_pid_one" "$other_root/shell" "$restart_pid_two" >"$test_tmp/strays"
printf '303\n' >"$restart_state"
rm -f "$restart_state.locked" "$test_tmp/notification-checks"
: >"$restart_log"

PATH="$restart_bin:$PATH" \
OMARCHY_PATH="$restart_root" \
XDG_RUNTIME_DIR="$runtime_dir" \
OMARCHY_TEST_QS_STATE="$restart_state" \
OMARCHY_TEST_QS_STRAYS="$test_tmp/strays" \
OMARCHY_TEST_QS_LOG="$restart_log" \
OMARCHY_TEST_QS_ENV_LOG="$restart_env_log" \
OMARCHY_TEST_DISPATCH_LOG="$dispatch_log" \
OMARCHY_TEST_IPC_LOG="$ipc_log" \
OMARCHY_TEST_SESSION_PATH="$restart_root" \
  timeout 5 "$ROOT/bin/omarchy-restart-shell" || fail "restart with a worktree shell running succeeds"

if kill -0 "$restart_pid_one" 2>/dev/null; then
  fail "restart stops a worktree's shell" "$(cat "$restart_log")"
fi
! grep -q "^$worktree_root/shell " "$test_tmp/strays.at-launch" || fail "restart waits for a slow worktree shell to exit before launching"
kill -0 "$restart_pid_two" 2>/dev/null || fail "restart leaves a Quickshell config outside Omarchy running"
wait "$restart_pid_one" 2>/dev/null || true
restart_pid_one=""
[[ $(<"$restart_state") == 303 ]] || fail "restart with a worktree shell leaves one fresh session shell"
pass "restart stops a worktree's shell and leaves other Quickshell configs alone"

# An independently validated host permits a desktop restart while locked.
# The real peer/unit/start-time validation is exercised by lock-state-test;
# this fixture isolates the restart policy and exact config kill selection.
cat >"$restart_bin/omarchy-lock-host" <<'SH'
#!/bin/bash
case $1 in
  mode|context) echo host ;;
  status)
    [[ ${OMARCHY_TEST_HOST_VALID:-0} == "1" ]] || exit 1
    echo '{"protocol":1,"owner":"trusted-host","ready":true,"locked":true,"requested":true,"secure":true}' ;;
  run-shell) exec quickshell -n -p "$OMARCHY_PATH/shell" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$restart_bin/omarchy-lock-host"
sleep 30 &
restart_pid_one=$!
printf '%s\n' "$restart_pid_one" >"$restart_state"
printf '%s %s\n' "$restart_root/shell/lock-host.qml" "$restart_pid_two" >"$test_tmp/strays"
: >"$restart_log"
: >"$ipc_log"
PATH="$restart_bin:$PATH" OMARCHY_PATH="$restart_root" XDG_RUNTIME_DIR="$runtime_dir" \
  HYPRLAND_INSTANCE_SIGNATURE=trusted-fixture OMARCHY_TEST_HOST_VALID=1 OMARCHY_TEST_SESSION_LOCKED=1 \
  OMARCHY_TEST_QS_STATE="$restart_state" OMARCHY_TEST_QS_LOG="$restart_log" \
  OMARCHY_TEST_QS_ENV_LOG="$restart_env_log" OMARCHY_TEST_DISPATCH_LOG="$dispatch_log" \
  OMARCHY_TEST_IPC_LOG="$ipc_log" OMARCHY_TEST_SESSION_PATH="$restart_root" \
  OMARCHY_TEST_QS_STRAYS="$test_tmp/strays" \
  timeout 5 "$ROOT/bin/omarchy-restart-shell" || fail "validated trusted lock permits broker-only restart"
wait "$restart_pid_one" 2>/dev/null || true
restart_pid_one=""
kill -0 "$restart_pid_two" 2>/dev/null || fail "desktop restart preserves the independent lock host"
if grep -qF 'kill -p '"$restart_root/shell/lock-host.qml" "$restart_log"; then
  fail "desktop restart never targets the trusted host config"
fi
if grep -qF 'lock lock' "$ipc_log"; then
  fail "broker restart does not reacquire an independently owned active lock"
fi
pass "validated independent owner survives locked desktop broker restart"

: >"$restart_log"
if PATH="$restart_bin:$PATH" OMARCHY_PATH="$restart_root" XDG_RUNTIME_DIR="$runtime_dir" \
  HYPRLAND_INSTANCE_SIGNATURE=trusted-fixture OMARCHY_TEST_HOST_VALID=0 OMARCHY_TEST_SESSION_LOCKED=1 \
  OMARCHY_TEST_QS_STATE="$restart_state" OMARCHY_TEST_QS_LOG="$restart_log" \
  OMARCHY_TEST_SESSION_PATH="$restart_root" \
  "$ROOT/bin/omarchy-restart-shell" >"$test_tmp/unvalidated-host.log" 2>&1; then
  fail "restart refuses an unvalidated locked owner"
fi
[[ ! -s $restart_log ]] || fail "unvalidated owner refusal occurs before killing any shell"
pass "unvalidated external lock owner keeps restart conservative"
