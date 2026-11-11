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

gaming_runtime_init() {
  [[ -n ${XDG_RUNTIME_DIR:-} && -d $XDG_RUNTIME_DIR && -O $XDG_RUNTIME_DIR ]] || return 1
  local session=${OMARCHY_HANDHELD_SESSION:-${XDG_SESSION_ID:-}}
  [[ $session =~ ^[[:alnum:]_-]+$ ]] || return 1
  gaming_runtime=$XDG_RUNTIME_DIR/omarchy-gaming-$session
  umask 077
  mkdir -p "$gaming_runtime"
  [[ -d $gaming_runtime && ! -L $gaming_runtime && -O $gaming_runtime ]]
}

gaming_selection() {
  local choice=desktop
  if [[ -f $gaming_state/next ]]; then
    read -r choice < "$gaming_state/next" || true
    rm -f "$gaming_state/next"
  elif [[ -f $gaming_state/preference ]]; then
    read -r choice < "$gaming_state/preference" || true
    if [[ $choice == "last" ]]; then
      read -r choice < "$gaming_state/last" 2>/dev/null || choice=desktop
    fi
  fi
  case $choice in desktop | gaming) ;; *) choice=desktop ;; esac
  # An unsuccessful gaming launch never becomes an automatic login loop.
  if [[ -f $gaming_state/recovery ]]; then choice=desktop; fi
  printf '%s\n' "$choice"
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
