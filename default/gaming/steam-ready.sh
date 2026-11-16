# shellcheck shell=bash
# Steam's UI is ready when one of its processes holds a display connection.
# Gamescope starts two Xwaylands and Steam may sit on either, or on Wayland.
# An fd whose path is only socket:[inode] still counts when that inode is one
# of those sockets in the unix table.

gaming_waiter_timeout_latch='Gaming failed; desktop selected until an explicit gaming choice.'

steam_ui_path() {
  local target=$1
  [[ $target =~ ^/tmp/\.X11-unix/X[0-9]+$ ]] && return 0
  [[ $target =~ (^|/)wayland-[0-9]+$ ]] && return 0
  return 1
}

steam_collect_ui_inodes() {
  local root=$1 found
  steam_ui_inodes=' '
  [[ -r $root/net/unix ]] || return 0
  found=$(awk '{
    path = $8
    for (i = 9; i <= NF; i++) path = path " " $i
    if ($7 ~ /^[0-9]+$/ && (path ~ /^\/tmp\/\.X11-unix\/X[0-9]+$/ || path ~ /(^|\/)wayland-[0-9]+$/))
      printf "%s ", $7
  }' "$root/net/unix")
  steam_ui_inodes+="$found"
}

steam_pid_has_ui() {
  local root=$1 pid=$2 fd target inode
  local dir=$root/$pid/fd
  [[ -d $dir ]] || return 1
  for fd in "$dir"/*; do
    [[ -e $fd || -L $fd ]] || continue
    target=$(readlink "$fd" 2>/dev/null) || continue
    steam_ui_path "$target" && return 0
    if [[ $target =~ ^socket:\[([0-9]+)\]$ ]]; then
      inode=${BASH_REMATCH[1]}
      [[ $steam_ui_inodes == *" $inode "* ]] && return 0
    fi
  done
  return 1
}

steam_tree_has_ui_from() {
  local root=$1 pid=$2 child
  steam_pid_has_ui "$root" "$pid" && return 0
  for child in "${!steam_ppid_of[@]}"; do
    [[ ${steam_ppid_of[$child]} == "$pid" ]] || continue
    steam_tree_has_ui_from "$root" "$child" && return 0
  done
  return 1
}

# root is a /proc-shaped directory. pid is the Steam parent.
# A helper can exit between the glob and the open. One awk over every status
# aborts on that file and drops every PPid after it, so the display held by
# steamwebhelper is never seen. Read each status and skip a miss.
steam_tree_has_ui() {
  local root=$1 pid=$2 entry name parent
  local -A steam_ppid_of=()
  steam_collect_ui_inodes "$root"
  for entry in "$root"/[0-9]*; do
    [[ -d $entry ]] || continue
    name=${entry##*/}
    parent=''
    while IFS=$' \t' read -r key value _; do
      if [[ $key == "PPid:" ]]; then
        parent=$value
        break
      fi
    done 2>/dev/null < "$entry/status" || true
    [[ $parent =~ ^[0-9]+$ ]] || continue
    steam_ppid_of[$name]=$parent
  done
  steam_tree_has_ui_from "$root" "$pid"
}

# The ready waiter used to kill a live Steam and write this exact sentence.
# Drop that latch once. A later, real exit uses a different sentence and stays.
gaming_clear_waiter_latch() {
  [[ -n ${gaming_state:-} && -f $gaming_state/recovery && ! -L $gaming_state/recovery ]] || return 0
  local reason
  IFS= read -r reason < "$gaming_state/recovery" || true
  if [[ $reason == "$gaming_waiter_timeout_latch" || $reason == "waiter-timeout:"* ]]; then
    rm -f -- "$gaming_state/recovery"
    printf '%s\n' "cleared recovery latch from the Steam ready waiter: $reason" >> "$gaming_state/fallback.log"
  fi
}
