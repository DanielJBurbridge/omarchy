# shellcheck shell=bash
# Steam's UI is ready when one of its processes holds a display connection.
# Gamescope's Xwayland takes clients on the abstract socket @/tmp/.X11-unix/Xn
# as well as the filesystem socket. /proc/net/unix prints that path on the
# server inode only. The client's fd is socket:[other], with no path, so the
# client inode is never the one beside the path. ss (iproute2, named by
# omarchy-gaming-session) is the peer table: a client whose peer is one of
# those sockets holds the display.
# gamescopereaper is a subreaper, and Steam's runtime double-forks. The
# steamwebhelper that owns the UI can sit outside the launcher's children.
# It stays in the launcher's cgroup. Only steamwebhelper counts. The steam
# client's own window (bootstrap, updater, the offline error dialog) is up
# before the gamepad UI, and treating it as ready clears the crash counter.
# gamescope-session-plus (ChimeraOS, MIT) waits on gamescope's startup socket
# and does not probe Steam's window, so there is no UI check there to copy.
# Handheld Daemon names the same steamwebhelper process by its X window. That
# code is LGPL-2.1 and is not copied; the signal here stays the display socket.

gaming_waiter_timeout_latch='Gaming failed; desktop selected until an explicit gaming choice.'

steam_ui_path() {
  local target=$1
  [[ $target =~ ^@?/tmp/\.X11-unix/X[0-9]+$ ]] && return 0
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
    if ($7 ~ /^[0-9]+$/ && (path ~ /^@?\/tmp\/\.X11-unix\/X[0-9]+$/ || path ~ /(^|\/)wayland-[0-9]+$/))
      printf "%s ", $7
  }' "$root/net/unix")
  steam_ui_inodes+="$found"
}

# ss -Hxn columns, after the queues: local path, local inode, peer path, peer
# inode. The peer path is "*" ; the peer inode is the other end. -p is left
# off: the users column is not read, and it walks every process fd.
# A test proc root carries the transcript at $root/ss. The kernel's /proc
# has no such file. Called only once a steamwebhelper holds an inode the
# unix table did not already name.
steam_collect_peer_inodes() {
  local root=$1 found=''
  if [[ -f $root/ss ]]; then
    found=$(steam_peer_inodes_from "$root/ss") || true
  elif [[ $root == "/proc" ]]; then
    found=$(ss -Hxn 2>/dev/null | steam_peer_inodes_from) || true
  else
    return 0
  fi
  steam_ui_inodes+="$found"
}

steam_peer_inodes_from() {
  awk -v known="$steam_ui_inodes" '
    function is_ui(path) {
      return path ~ /^@?\/tmp\/\.X11-unix\/X[0-9]+$/ || path ~ /(^|\/)wayland-[0-9]+$/
    }
    BEGIN {
      n = split(known, parts, " ")
      for (i = 1; i <= n; i++)
        if (parts[i] ~ /^[0-9]+$/ && parts[i] != "0")
          server[parts[i]] = 1
    }
    $1 ~ /^u_/ && $6 ~ /^[0-9]+$/ && $8 ~ /^[0-9]+$/ {
      count++
      la[count] = $5
      li[count] = $6
      pa[count] = $7
      pi[count] = $8
      if (is_ui($5) && $6 != "0") server[$6] = 1
      if (is_ui($7) && $8 != "0") server[$8] = 1
    }
    END {
      for (i = 1; i <= count; i++) {
        if (server[li[i]] && pi[i] != "0") out[pi[i]] = 1
        if (server[pi[i]] && li[i] != "0") out[li[i]] = 1
        if (is_ui(la[i]) && li[i] != "0") out[li[i]] = 1
        if (is_ui(pa[i]) && pi[i] != "0") out[pi[i]] = 1
      }
      for (ino in out)
        if (ino != "0") printf "%s ", ino
    }
  ' "$@"
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

# steam_read_status fills these. A missing status leaves them empty.
steam_status_name=''
steam_status_ppid=''
steam_status_uid=''

steam_read_status() {
  local file=$1 key value
  steam_status_name=''
  steam_status_ppid=''
  steam_status_uid=''
  [[ -r $file ]] || return 1
  # Uid is the last field this needs. /proc/status keeps Name, then PPid,
  # then Uid, and the rest of the file is not the scan.
  while IFS=$' \t' read -r key value _; do
    case $key in
      Name:) steam_status_name=$value ;;
      PPid:) steam_status_ppid=$value ;;
      Uid:)
        steam_status_uid=$value
        break
        ;;
    esac
  done < "$file" || true
}

# cgroup v2 is the 0:: line. The path is what systemd put this process in.
steam_cgroup_path() {
  local file=$1 line path='' v2=''
  [[ -r $file ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == 0::* ]]; then
      v2=${line#0::}
    elif [[ $line == *:* ]]; then
      path=${line##*:}
    fi
  done < "$file"
  if [[ -n $v2 ]]; then
    path=$v2
  fi
  [[ $path == /* ]] || return 1
  printf '%s\n' "$path"
}

# pid is the Steam launcher. Clients reparented onto gamescopereaper are not
# its descendants, but they inherit its cgroup.
steam_scope_has_ui() {
  local root=$1 pid=$2 anchor_uid=$3
  local scope cand cand_name cand_uid cand_cg
  shift 3
  [[ $anchor_uid =~ ^[0-9]+$ ]] || return 1
  scope=$(steam_cgroup_path "$root/$pid/cgroup") || return 1
  for cand in "$@"; do
    cand_cg=$(steam_cgroup_path "$root/$cand/cgroup") || continue
    [[ $cand_cg == "$scope" ]] || continue
    steam_read_status "$root/$cand/status" || continue
    cand_name=$steam_status_name
    cand_uid=$steam_status_uid
    [[ $cand_name == "steamwebhelper" ]] || continue
    [[ $cand_uid == "$anchor_uid" ]] || continue
    steam_pid_has_ui "$root" "$cand" && return 0
  done
  return 1
}

steam_tree_has_ui_from() {
  local root=$1 pid=$2 child
  if [[ ${steam_name_of[$pid]:-} == steamwebhelper ]] && steam_pid_has_ui "$root" "$pid"; then
    return 0
  fi
  for child in "${!steam_ppid_of[@]}"; do
    [[ ${steam_ppid_of[$child]} == "$pid" ]] || continue
    steam_tree_has_ui_from "$root" "$child" && return 0
  done
  return 1
}

# A socket:[inode] whose inode is not already one of the display servers.
# The peer table is the only way to name that inode.
steam_has_unresolved_socket() {
  local root=$1 pid=$2 fd target inode
  local dir=$root/$pid/fd
  [[ -d $dir ]] || return 1
  for fd in "$dir"/*; do
    [[ -e $fd || -L $fd ]] || continue
    target=$(readlink "$fd" 2>/dev/null) || continue
    if [[ $target =~ ^socket:\[([0-9]+)\]$ ]]; then
      inode=${BASH_REMATCH[1]}
      [[ ${steam_ui_inodes:- } == *" $inode "* ]] && continue
      return 0
    fi
  done
  return 1
}

# Descendant of the launcher, or the same uid and cgroup after reparenting.
steam_webhelper_in_session() {
  local root=$1 launcher=$2 anchor_uid=$3 cand=$4
  local cursor=$cand guard=0 scope cand_cg
  if [[ $cand == "$launcher" ]]; then
    return 0
  fi
  while [[ -n ${steam_ppid_of[$cursor]:-} ]] && (( guard < 64 )); do
    cursor=${steam_ppid_of[$cursor]}
    if [[ $cursor == "$launcher" ]]; then
      return 0
    fi
    guard=$((guard + 1))
  done
  [[ $anchor_uid =~ ^[0-9]+$ ]] || return 1
  steam_read_status "$root/$cand/status" || return 1
  [[ $steam_status_uid == "$anchor_uid" ]] || return 1
  scope=$(steam_cgroup_path "$root/$launcher/cgroup") || return 1
  cand_cg=$(steam_cgroup_path "$root/$cand/cgroup") || return 1
  [[ $cand_cg == "$scope" ]]
}

# root is a /proc-shaped directory. pid is the Steam parent.
# A helper can exit between the glob and the open. One awk over every status
# aborts on that file and drops every PPid after it, so the display held by
# steamwebhelper is never seen. Read each status and skip a miss.
steam_tree_has_ui() {
  local root=$1 pid=$2 entry name proc_name parent uid anchor_uid='' cand
  local -A steam_ppid_of=()
  local -A steam_name_of=()
  local -a steam_clients=()
  for entry in "$root"/[0-9]*; do
    [[ -d $entry ]] || continue
    name=${entry##*/}
    steam_read_status "$entry/status" || true
    proc_name=$steam_status_name
    parent=$steam_status_ppid
    uid=$steam_status_uid
    [[ -n $proc_name ]] && steam_name_of[$name]=$proc_name
    [[ $parent =~ ^[0-9]+$ ]] || continue
    steam_ppid_of[$name]=$parent
    if [[ $name == "$pid" ]]; then
      anchor_uid=$uid
    fi
    if [[ $proc_name == "steamwebhelper" ]]; then
      steam_clients+=("$name")
    fi
  done
  # No steamwebhelper means the steam client's own window is not the UI.
  # Skip the peer table entirely.
  (( ${#steam_clients[@]} > 0 )) || return 1
  steam_collect_ui_inodes "$root"
  steam_tree_has_ui_from "$root" "$pid" && return 0
  steam_scope_has_ui "$root" "$pid" "$anchor_uid" "${steam_clients[@]}" && return 0
  for cand in "${steam_clients[@]}"; do
    steam_webhelper_in_session "$root" "$pid" "$anchor_uid" "$cand" || continue
    steam_has_unresolved_socket "$root" "$cand" || continue
    steam_collect_peer_inodes "$root"
    steam_tree_has_ui_from "$root" "$pid" && return 0
    steam_scope_has_ui "$root" "$pid" "$anchor_uid" "${steam_clients[@]}"
    return $?
  done
  return 1
}

# First-run waits with nm-online before it treats the link as up
# (install/user/first-run/wifi.sh). That client also returns for a site-only
# connection. On the Ally that is the logon race: Wi-Fi is associated, and
# Steam CM is not. nmcli's "full" is the connectivity check. "unknown" means
# the check has not run, so it is not a reason to spend the budget. limited
# and portal still wait. A missing client skips the wait. A timeout launches
# Steam anyway.
gaming_log_steam_network_timeout() {
  local state_dir=${gaming_state:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/gaming-session}
  local timeout=$1
  [[ -d $state_dir && ! -L $state_dir ]] || return 0
  printf '%s\n' "network connectivity wait timed out after ${timeout}s; launching Steam anyway." >> "$state_dir/fallback.log"
}

# nmcli translates its answer. Read it in the C locale, the same way
# omarchy-network-captive-portal does, and cap the client so it cannot hang.
gaming_nm_connectivity() {
  LC_ALL=C timeout 2 nmcli networking connectivity 2>/dev/null || true
}

gaming_wait_for_steam_network() {
  local timeout=${OMARCHY_GAMING_NETWORK_TIMEOUT:-30}
  local state='' start=$SECONDS have_nmcli=0 have_online=0
  [[ $timeout =~ ^[0-9]+$ ]] || timeout=30
  # Tests set 0 so a host NetworkManager cannot hold the session harness.
  if (( timeout == 0 )); then
    return 0
  fi
  if omarchy-cmd-present nmcli; then
    have_nmcli=1
  fi
  if omarchy-cmd-present nm-online; then
    have_online=1
  fi
  if (( have_nmcli == 0 && have_online == 0 )); then
    return 0
  fi
  if (( have_online )); then
    if ! nm-online -q -t "$timeout"; then
      gaming_log_steam_network_timeout "$timeout"
      return 0
    fi
  fi
  if (( have_nmcli == 0 )); then
    return 0
  fi
  state=$(gaming_nm_connectivity)
  if [[ $state == "full" || $state == "unknown" || -z $state ]]; then
    return 0
  fi
  while (( SECONDS - start < timeout )); do
    sleep 1
    state=$(gaming_nm_connectivity)
    if [[ $state == "full" || $state == "unknown" || -z $state ]]; then
      return 0
    fi
  done
  gaming_log_steam_network_timeout "$timeout"
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
