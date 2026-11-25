# shellcheck shell=bash
# Shared, unprivileged session state. Never source saved preferences as code.
gaming_state=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/gaming-session

gaming_fail() { echo "Omarchy Gaming: $*" >&2; }

gaming_state_init() {
  umask 077
  mkdir -p "$gaming_state"
  [[ -d $gaming_state && ! -L $gaming_state && -O $gaming_state ]]
}

gaming_save() {
  local temporary
  temporary=$(mktemp "$gaming_state/.setting.XXXXXX") || return 1
  printf '%s\n' "$2" > "$temporary" && mv -f "$temporary" "$gaming_state/$1"
}

gaming_runtime_path() {
  [[ -n ${XDG_RUNTIME_DIR:-} && -d $XDG_RUNTIME_DIR && -O $XDG_RUNTIME_DIR ]] || return 1
  local session=${OMARCHY_HANDHELD_SESSION:-${XDG_SESSION_ID:-}}
  [[ $session =~ ^[[:alnum:]_-]+$ ]] || return 1
  gaming_runtime=$XDG_RUNTIME_DIR/omarchy-gaming-$session
}

gaming_runtime_init() {
  gaming_runtime_path || return 1
  umask 077
  mkdir -p "$gaming_runtime"
  [[ -d $gaming_runtime && ! -L $gaming_runtime && -O $gaming_runtime ]]
}

# Spec 02 §7.4. One path. ENOENT is absent; any other stat error is present.
gaming_k07_marker=/var/lib/omarchy/handheld/k07-landed
# Spec 02 does not name the value file. It lives beside the marker, root-owned.
gaming_desktop_lock_file=/var/lib/omarchy/handheld/desktop-lock

gaming_handheld_variant() {
  omarchy-hw-rog-ally && omarchy-pkg-present omarchy-gaming-session
}

# present or absent. A clean ENOENT (missing file or missing directory) is
# absent. Permission, I/O, and every other stat failure are present.
gaming_k07_marker_state() {
  local err
  if err=$(LC_ALL=C stat -c %u -- "$gaming_k07_marker" 2>&1); then
    printf '%s\n' present
    return
  fi
  if [[ $err == *"No such file or directory"* ]]; then
    printf '%s\n' absent
    return
  fi
  printf '%s\n' present
}

# on, default-off, explicit-off, missing, corrupt, or error.
# A user-owned, group-writable, or world-writable file is not the setting.
gaming_desktop_lock_stored() {
  local meta owner mode kind value
  if ! meta=$(LC_ALL=C stat -c '%u %a %F' -- "$gaming_desktop_lock_file" 2>&1); then
    if [[ $meta == *"No such file or directory"* ]]; then
      printf '%s\n' missing
    else
      printf '%s\n' error
    fi
    return
  fi
  read -r owner mode kind _ <<< "$meta"
  if [[ $owner != 0 || $kind != regular ]]; then
    printf '%s\n' missing
    return
  fi
  if (( (8#$mode & 8#022) != 0 )); then
    printf '%s\n' missing
    return
  fi
  if ! value=$(head -n 1 -- "$gaming_desktop_lock_file" 2>/dev/null); then
    printf '%s\n' error
    return
  fi
  case $value in
    on | default-off | explicit-off) printf '%s\n' "$value" ;;
    *) printf '%s\n' corrupt ;;
  esac
}

gaming_desktop_lock_effective() {
  local stored marker
  stored=$(gaming_desktop_lock_stored)
  marker=$(gaming_k07_marker_state)
  case $stored in
    explicit-off) printf '%s\n' explicit-off; return ;;
    on) printf '%s\n' on; return ;;
  esac
  if [[ $marker == present || $stored == error ]]; then
    printf '%s\n' on
    return
  fi
  if gaming_handheld_variant; then
    case $stored in
      missing | corrupt | default-off) printf '%s\n' default-off; return ;;
    esac
  fi
  printf '%s\n' on
}

gaming_selection() {
  local choice=''
  if [[ -f $gaming_state/next ]]; then
    read -r choice < "$gaming_state/next" || true
    rm -f "$gaming_state/next"
  elif [[ -f $gaming_state/preference ]]; then
    read -r choice < "$gaming_state/preference" || true
    if [[ $choice == "last" ]]; then
      read -r choice < "$gaming_state/last" 2>/dev/null || choice=desktop
    fi
  elif gaming_handheld_variant; then
    # Handheld default is auto. Docked auto is desktop; otherwise gaming.
    choice=auto
  else
    choice=desktop
  fi
  case $choice in
    desktop | gaming) ;;
    auto)
      if omarchy-hw-external-monitors; then
        choice=desktop
      else
        choice=gaming
      fi
      ;;
    *)
      if gaming_handheld_variant; then
        printf '%s\n' reset > "$gaming_state/preference-reset"
        choice=gaming
      else
        choice=desktop
      fi
      ;;
  esac
  # An unsuccessful gaming launch never becomes an automatic login loop.
  if [[ -f $gaming_state/recovery ]]; then choice=desktop; fi
  printf '%s\n' "$choice"
}

# Failed-start counter. The shape follows gamescope-session-plus (MIT,
# Copyright 2020-2023 Joaquín Ignacio Aramendía,
# https://github.com/ChimeraOS/gamescope-session): count failed gaming starts,
# and once the count reaches the limit start the desktop instead of gamescope.
# A healthy ready, or an explicit return to the desktop, clears the count.
# The count lives in the gaming state directory so a relogin and a reboot
# still see it. Steam's bootstrap re-extract is not used.
# The same three-start limit as omarchy-handheld-autologin.
gaming_failure_limit=3
gaming_fail_limit_latch='Gaming failed repeatedly; desktop selected until an explicit gaming choice.'

gaming_failure_count() {
  local count=0
  [[ -n ${gaming_state:-} && -f $gaming_state/start-failures && ! -L $gaming_state/start-failures ]] || {
    printf '0\n'
    return 0
  }
  IFS= read -r count < "$gaming_state/start-failures" || true
  [[ $count =~ ^[0-9]+$ ]] || count=0
  printf '%s\n' "$count"
}

gaming_failure_record() {
  local count
  count=$(gaming_failure_count)
  gaming_save start-failures "$((count + 1))"
}

gaming_failure_reset() {
  [[ -n ${gaming_state:-} && -f $gaming_state/start-failures && ! -L $gaming_state/start-failures ]] || return 0
  rm -f -- "$gaming_state/start-failures"
  printf '%s\n' 'cleared the gaming start failures' >> "$gaming_state/fallback.log"
}

# Pre-ready Switch to Desktop requests in this login. The second one opens
# the desktop. Ready clears the count, and the next login starts again at zero.
gaming_early_return_count() {
  local count=0
  [[ -n ${gaming_state:-} && -f $gaming_state/early-returns && ! -L $gaming_state/early-returns ]] || {
    printf '0\n'
    return 0
  }
  IFS= read -r count < "$gaming_state/early-returns" || true
  [[ $count =~ ^[0-9]+$ ]] || count=0
  printf '%s\n' "$count"
}

gaming_early_return_record() {
  local count
  count=$(gaming_early_return_count)
  count=$((count + 1))
  gaming_save early-returns "$count" || return 1
  printf '%s\n' "$count"
}

gaming_early_return_reset() {
  [[ -n ${gaming_state:-} && -f $gaming_state/early-returns && ! -L $gaming_state/early-returns ]] || return 0
  rm -f -- "$gaming_state/early-returns"
}

gaming_fail_limit_reached() {
  local count
  count=$(gaming_failure_count)
  (( count >= gaming_failure_limit ))
}

gaming_fail_limit_latched() {
  local reason=''
  [[ -n ${gaming_state:-} && -f $gaming_state/recovery && ! -L $gaming_state/recovery ]] || return 1
  IFS= read -r reason < "$gaming_state/recovery" || true
  [[ $reason == "$gaming_fail_limit_latch" ]]
}

# The ordinary recovery latch still lets Relogin try gaming again. This one
# does not: the fail limit already tripped.
gaming_fail_limit_blocked() {
  gaming_fail_limit_latched || gaming_fail_limit_reached
}

# SDDM Relogin comes back to gaming. The recovery latch and a docked auto
# preference decide a preferred login, not this return. The one exception is
# next=desktop, the session user's one-shot at
# ${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/gaming-session/next (mode 0600,
# in the mode 0700 state directory). An explicit Switch to Desktop writes it.
# This consumes that value once. Any other relogin stays on gaming and leaves
# the file alone, unless the fail-limit latch is set.
gaming_entry_selection() {
  local choice=''
  if [[ $1 == relogin ]]; then
    if [[ -f $gaming_state/next ]]; then
      read -r choice < "$gaming_state/next" || true
      if [[ $choice == "desktop" ]]; then
        rm -f -- "$gaming_state/next"
        printf '%s\n' desktop
        return
      fi
    fi
    if gaming_fail_limit_latched; then
      printf '%s\n' desktop
      return
    fi
    printf '%s\n' gaming
    return
  fi
  gaming_selection
}

# Before K07 the handheld has no touch keyboard. allow keeps the caller's
# lock. skip leaves the desktop alone. return ends it and goes back to gaming.
# 0 allow, 10 skip, 11 return. Callers exit 0 or 1 from those.
gaming_lock_decision() {
  # A missing detector is not the handheld. Keep its "not found" off the
  # journal: sleep lock records its own stderr as the unlocked-suspend trace.
  if ! gaming_handheld_variant 2>/dev/null; then
    printf '%s\n' allow
    return
  fi
  if [[ $(gaming_k07_marker_state) == present ]]; then
    printf '%s\n' allow
    return
  fi
  if omarchy-hw-physical-keyboard >/dev/null 2>&1; then
    printf '%s\n' allow
    return
  fi
  if [[ $(gaming_desktop_lock_effective) == on ]]; then
    printf '%s\n' return
  else
    printf '%s\n' skip
  fi
}

gaming_apply_lock_gate() {
  case $(gaming_lock_decision) in
    allow) return 0 ;;
    skip) return 10 ;;
    return)
      if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} && -n ${WAYLAND_DISPLAY:-} ]]; then
        omarchy-launch-gaming-session --confirm >/dev/null 2>&1 || true
      fi
      return 11
      ;;
  esac
  return 0
}

gaming_display_args() {
  local size=native fps=0 filter=linear extra=''
  if [[ -f $gaming_state/display ]]; then
    read -r size fps filter extra < "$gaming_state/display" || return 1
  fi
  [[ -z $extra ]] || return 1
  case $size in
    native) gamescope_args=() ;;
    720p) gamescope_args=(-w 1280 -h 720) ;;
    900p) gamescope_args=(-w 1600 -h 900) ;;
    1080p) gamescope_args=(-w 1920 -h 1080) ;;
    *) return 1 ;;
  esac
  case $fps in 0 | 30 | 40 | 45 | 60 | 90 | 120) ;; *) return 1 ;; esac
  case $filter in linear | nearest | fsr | nis) ;; *) return 1 ;; esac
  gamescope_args+=(--framerate-limit "$fps" -F "$filter")
}
