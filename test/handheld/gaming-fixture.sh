# shellcheck shell=bash
# Working-tree gaming scripts for the handheld review tests.
# Sourced by those tests; not a test itself. Power rollback still reads one
# release-tip script; that checkout is not part of this branch.

HANDHELD_RELEASE_SHA=c88d5344b2fdc64ba74e9221c52ccfca131b3ba2

handheld_release_blob() {
  local path=$1 dest=$2
  git -C "$ROOT" show "$HANDHELD_RELEASE_SHA:$path" > "$dest"
}

handheld_gaming_tree() {
  local tree=$1
  mkdir -p "$tree/bin" "$tree/default/gaming/bin" "$tree/default/hypr"
  cp "$ROOT/bin/omarchy-session-start" "$tree/bin/omarchy-session-start"
  sed -i 's|^source /usr/share/omarchy/default/bash/env-bootstrap$|:|' "$tree/bin/omarchy-session-start"
  cp "$ROOT/bin/omarchy-gaming-steam" "$tree/bin/omarchy-gaming-steam"
  cp "$ROOT/bin/omarchy-gaming-output" "$tree/bin/omarchy-gaming-output"
  cp "$ROOT/bin/omarchy-launch-gaming-desktop" "$tree/bin/omarchy-launch-gaming-desktop"
  cp "$ROOT/default/gaming/session.sh" "$tree/default/gaming/session.sh"
  cp "$ROOT/default/gaming/steam-ready.sh" "$tree/default/gaming/steam-ready.sh"
  cp "$ROOT/default/gaming/steam-path.sh" "$tree/default/gaming/steam-path.sh"
  cp "$ROOT/default/gaming/bin/steamos-session-select" "$tree/default/gaming/bin/steamos-session-select"
  cp "$ROOT/default/hypr/"{keyboard,paths}.lua "$tree/default/hypr/"
  sed -i -e "s|/etc/vconsole.conf|$tree/etc/vconsole.conf|g" \
    -e "s|/etc/omarchy/input-method|$tree/etc/omarchy/input-method|g" "$tree/default/hypr/keyboard.lua"
  cat > "$tree/default/gaming/input-profile-watch.py" <<'PY'
import subprocess
import sys

def load(name):
  return subprocess.run([
    "busctl", "--timeout=3s", "--auto-start=no", "call",
    "org.omarchy.InputPlumberProfile", "/org/omarchy/InputPlumberProfile",
    "org.omarchy.InputPlumberProfile", "Load", "s", name,
  ], check=False).returncode

status = load(sys.argv[1])
print("ready", flush=True)
sys.stdin.read()
if status == 0:
  load("pointer")
PY
  mkdir -p "$tree/default/systemd/user/omarchy-rog-ally-input.service.d" \
    "$tree/default/systemd/user/omarchy-ally-tdp-shim.service.d"
  cp "$ROOT/default/systemd/user/omarchy-gaming-session.target" \
    "$ROOT/default/systemd/user/omarchy-gaming-input-profile.service" \
    "$tree/default/systemd/user/"
  cp "$ROOT/default/systemd/user/omarchy-rog-ally-input.service.d/10-gaming-session.conf" \
    "$tree/default/systemd/user/omarchy-rog-ally-input.service.d/"
  cp "$ROOT/default/systemd/user/omarchy-ally-tdp-shim.service.d/10-gaming-session.conf" \
    "$tree/default/systemd/user/omarchy-ally-tdp-shim.service.d/"
  chmod +x "$tree/bin/"* "$tree/default/gaming/bin/"*
}

handheld_ally_dmi() {
  local dmi=$1
  mkdir -p "$dmi"
  printf 'ASUSTeK COMPUTER INC.\n' > "$dmi/sys_vendor"
  printf 'ROG Ally RC71L\n' > "$dmi/product_name"
  printf 'RC71L\n' > "$dmi/board_name"
  export OMARCHY_DMI_SYS_VENDOR_PATH=$dmi/sys_vendor
  export OMARCHY_DMI_PRODUCT_NAME_PATH=$dmi/product_name
  export OMARCHY_DMI_BOARD_NAME_PATH=$dmi/board_name
}

handheld_prepare_gaming() {
  local work=$1
  HANDHELD_TREE=$work/tree
  HANDHELD_STUB=$work/bin
  HANDHELD_LOG=$work/actions
  HANDHELD_SCOPE_PID=$work/scope-pid
  HANDHELD_RUNTIME=$(mktemp -d)
  HANDHELD_HOME=$(mktemp -d)
  chmod 700 "$HANDHELD_RUNTIME"
  mkdir -p "$HANDHELD_STUB"
  : > "$HANDHELD_LOG"
  handheld_gaming_tree "$HANDHELD_TREE"
  handheld_ally_dmi "$work/dmi"

  cat > "$HANDHELD_STUB/systemd-run" <<'EOF'
#!/bin/bash
args=("$@")
while (( ${#args[@]} )) && [[ ${args[0]} == --* ]]; do
  args=("${args[@]:1}")
done
setsid "${args[@]}" &
child=$!
printf '%s\n' "$child" > "$HANDHELD_SCOPE_PID"
wait "$child"
EOF
  cat > "$HANDHELD_STUB/gamescope" <<'EOF'
#!/bin/bash
printf 'gamescope\n' >> "$HANDHELD_ACTIONS"
printf 'gamescope-keyboard:[%s] [%s]\n' "${XKB_DEFAULT_LAYOUT-<unset>}" "${XKB_DEFAULT_VARIANT-<unset>}" >> "$HANDHELD_ACTIONS"
while (( $# )) && [[ $1 != -- ]]; do
  if [[ $1 == "--prefer-output" ]]; then
    printf 'gamescope-output:%s\n' "${2:-}" >> "$HANDHELD_ACTIONS"
  fi
  shift
done
(( $# )) || exit 1
shift
DISPLAY=:77 "$@"
printf 'gamescope-child-exit:%s\n' "$?" >> "$HANDHELD_ACTIONS"
if [[ ${GAMESCOPE_STAYS_AFTER_STEAM:-0} == 1 ]]; then sleep 30; fi
exit 0
EOF
  cat > "$HANDHELD_STUB/uwsm" <<'EOF'
#!/bin/bash
printf 'uwsm:%s\n' "$*" >> "$HANDHELD_ACTIONS"
printf 'uwsm-keyboard:[%s] [%s]\n' "${XKB_DEFAULT_LAYOUT-<unset>}" "${XKB_DEFAULT_VARIANT-<unset>}" >> "$HANDHELD_ACTIONS"
exit 0
EOF
  cat > "$HANDHELD_STUB/pgrep" <<'EOF'
#!/bin/bash
# The fixture creates its own session for Gamescope and its Steam child.
[[ $* == "-u $UID -x steam" && -s $HANDHELD_SCOPE_PID ]] || exit 1
read -r scope_pid < "$HANDHELD_SCOPE_PID" || exit 1
[[ $scope_pid =~ ^[1-9][0-9]*$ ]] || exit 1
exec /usr/bin/pgrep -s "$scope_pid" "$@"
EOF
  cat > "$HANDHELD_STUB/busctl" <<'EOF'
#!/bin/bash
exit 1
EOF
  cat > "$HANDHELD_STUB/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >> "$HANDHELD_ACTIONS"
if [[ $* == '--user kill --kill-whom=all --signal=KILL '* && -f ${HANDHELD_SCOPE_PID:-} ]]; then
  scope_pid=$(cat "$HANDHELD_SCOPE_PID")
  kill -KILL -- "-$scope_pid" 2>/dev/null || true
elif [[ $* == *stop* && -f ${HANDHELD_SCOPE_PID:-} ]]; then
  scope_pid=$(cat "$HANDHELD_SCOPE_PID")
  kill -- -"$scope_pid" 2>/dev/null || kill "$scope_pid" 2>/dev/null || true
fi
exit 0
EOF
  cat > "$HANDHELD_STUB/omarchy-notification-send" <<'EOF'
#!/bin/bash
exit 0
EOF
  cat > "$HANDHELD_STUB/omarchy-system-lock" <<'EOF'
#!/bin/bash
printf 'lock:%s\n' "$*" >> "$HANDHELD_ACTIONS"
exit 0
EOF
  cat > "$HANDHELD_STUB/omarchy-system-sleep-lock" <<'EOF'
#!/bin/bash
printf 'sleep-lock:%s\n' "$*" >> "$HANDHELD_ACTIONS"
exit 0
EOF
  chmod +x "$HANDHELD_STUB/"*
}

handheld_gaming_env() {
  export PATH="$HANDHELD_STUB:$HANDHELD_TREE/bin:$ROOT/bin:/usr/bin:/bin"
  export OMARCHY_PATH=$HANDHELD_TREE
  export HOME=$HANDHELD_HOME
  export XDG_RUNTIME_DIR=$HANDHELD_RUNTIME
  export XDG_STATE_HOME=$HANDHELD_HOME/.local/state
  # This is a fresh greeter login, even when the suite runs inside a managed desktop.
  unset OMARCHY_HANDHELD_SESSION
  export XDG_SESSION_ID=redteam
  export HANDHELD_ACTIONS=$HANDHELD_LOG
  export HANDHELD_SCOPE_PID
  export OMARCHY_GAMING_READY_TIMEOUT=1
  export OMARCHY_GAMING_RETRY_GAP=0
  # The logon wait has its own test. A host NetworkManager must not hold these.
  export OMARCHY_GAMING_NETWORK_TIMEOUT=0
}

# Keep Steam alive without a GUI readiness signal, then use its normal menu
# command once the supervisor has decided to leave the session running.
handheld_late_desktop_return() {
  cat > "$HANDHELD_STUB/steam" <<'EOF'
#!/bin/bash
attempt=$(grep -cx gamescope "$HANDHELD_ACTIONS")
finish=$OMARCHY_GAMING_RUNTIME/test-steam-exit-$attempt
if [[ $* == "-ifrunning -shutdown" ]]; then
  printf 'steam:shutdown\n' >> "$HANDHELD_ACTIONS"
  printf 'exit\n' > "$finish"
else
  mkfifo "$finish" || exit 1
  log=$XDG_STATE_HOME/omarchy/gaming-session/fallback.log
  while :; do
    timeouts=$(grep -cs 'leaving them up' "$log" || true)
    (( timeouts >= attempt )) && break
    (( SECONDS < 6 )) || exit 1
    sleep 0.05
  done
  steamos-session-select plasma || exit 1
  read -r -t 6 reply <> "$finish" && [[ $reply == "exit" ]]
fi
EOF
  chmod +x "$HANDHELD_STUB/steam"
}
