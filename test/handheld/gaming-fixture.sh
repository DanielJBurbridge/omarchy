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
  mkdir -p "$tree/bin" "$tree/default/gaming/bin"
  cp "$ROOT/bin/omarchy-session-start" "$tree/bin/omarchy-session-start"
  sed -i 's|^source /usr/share/omarchy/default/bash/env-bootstrap$|:|' "$tree/bin/omarchy-session-start"
  cp "$ROOT/bin/omarchy-gaming-steam" "$tree/bin/omarchy-gaming-steam"
  cp "$ROOT/bin/omarchy-launch-gaming-desktop" "$tree/bin/omarchy-launch-gaming-desktop"
  cp "$ROOT/default/gaming/session.sh" "$tree/default/gaming/session.sh"
  cp "$ROOT/default/gaming/bin/steamos-session-select" "$tree/default/gaming/bin/steamos-session-select"
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
while (( $# )) && [[ $1 != -- ]]; do
  shift
done
(( $# )) || exit 1
shift
DISPLAY=:77 "$@"
printf 'gamescope-exit:%s\n' "$?" >> "$HANDHELD_ACTIONS"
exit 0
EOF
  cat > "$HANDHELD_STUB/uwsm" <<'EOF'
#!/bin/bash
printf 'uwsm:%s\n' "$*" >> "$HANDHELD_ACTIONS"
exit 0
EOF
  cat > "$HANDHELD_STUB/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
  cat > "$HANDHELD_STUB/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >> "$HANDHELD_ACTIONS"
if [[ $* == *stop* && -f ${HANDHELD_SCOPE_PID:-} ]]; then
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
  export XDG_SESSION_ID=redteam
  export HANDHELD_ACTIONS=$HANDHELD_LOG
  export HANDHELD_SCOPE_PID=$work/scope-pid
  export OMARCHY_GAMING_READY_TIMEOUT=1
  export OMARCHY_GAMING_RETRY_GAP=0
}
