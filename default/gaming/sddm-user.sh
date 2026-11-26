#!/bin/bash
# Adapted from Pizzarchy deck_autologin.py parse_autologin, commit
# daa9376ab733880e612569467164754096a5f0f4. A User= outside [Autologin] does
# not count. The durable owner record uses [OmarchyHandheld]. SDDM only
# sees that owner under [Autologin] while the managed session is active.
#
# Copyright (c) 2026 Diego Huyke
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

sddm_conf_dir=${OMARCHY_SDDM_CONF_DIR:-/etc/sddm.conf.d}
sddm_user_dropin=$sddm_conf_dir/omarchy-handheld-user.conf
sddm_session_dropin=$sddm_conf_dir/zz-omarchy-handheld.conf
sddm_autologin_conf=$sddm_conf_dir/autologin.conf
sddm_state_conf=${OMARCHY_SDDM_STATE:-/var/lib/sddm/state.conf}
sddm_parse_section_name="[Autologin]"

sddm_parse_autologin() {
  local text=$1 section="" line key value wanted=$sddm_parse_section_name
  sddm_autologin_user=""
  sddm_autologin_session=""
  sddm_autologin_relogin=""
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [[ -z $line || $line == "#"* ]] && continue
    if [[ $line == "["*"]" ]]; then
      section=$line
      continue
    fi
    [[ $section == "$wanted" && $line == *"="* ]] || continue
    key=${line%%=*}
    value=${line#*=}
    key=${key%"${key##*[![:space:]]}"}
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    case $key in
      User)
        [[ -z $sddm_autologin_user && -n $value ]] && sddm_autologin_user=$value
        ;;
      Session)
        [[ -z $sddm_autologin_session && -n $value ]] && sddm_autologin_session=$value
        ;;
      Relogin)
        [[ -z $sddm_autologin_relogin && -n $value ]] && sddm_autologin_relogin=$value
        ;;
    esac
  done < <(printf '%s\n' "$text")
}

sddm_handheld_variant() {
  omarchy-cmd-present omarchy-hw-rog-ally || return 1
  omarchy-hw-rog-ally || return 1
  if [[ ${OMARCHY_GAMING_PACKAGE_PRESENT:-} == 1 ]]; then
    return 0
  fi
  omarchy-cmd-present omarchy-pkg-present && omarchy-pkg-present omarchy-gaming-session
}

sddm_username_ok() {
  [[ $1 != "root" && $1 != "sddm" && $1 =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]
}

sddm_lock_conf_dir() {
  local owner mode
  (( EUID == 0 )) || return 1
  if [[ ! -e $sddm_conf_dir && ! -L $sddm_conf_dir ]]; then
    install -d -o root -g root -m 0755 "$sddm_conf_dir" || return 1
  fi
  if [[ -L $sddm_conf_dir || ! -d $sddm_conf_dir ]] ||
    ! read -r owner mode < <(stat -c '%u %a' -- "$sddm_conf_dir") ||
    [[ $owner != 0 ]] || (( (8#$mode & 8#022) != 0 )); then
    printf 'omarchy gaming session: refusing untrusted SDDM directory %s\n' "$sddm_conf_dir" >&2
    return 1
  fi
  # The caller runs in a subshell. Closing its descriptor releases the lock.
  exec {sddm_lock_fd}< "$sddm_conf_dir" && flock -x "$sddm_lock_fd"
}

sddm_generated_file() {
  [[ -f $1 && ! -L $1 && $(stat -c '%u:%g:%a' -- "$1") == "0:0:644" ]]
}

sddm_owner_config() {
  local username=$1 format=$2
  if [[ $format == "managed" ]]; then
    printf '# Managed by Omarchy handheld setup (User=%s)\n[OmarchyHandheld]\n' "$username"
  else
    printf '[Autologin]\n'
  fi
  printf 'User=%s\n' "$username"
}

sddm_session_config() {
  local relogin=$1 format=$2 username=${3:-}
  if [[ $format == "managed" ]]; then
    printf '# Managed by Omarchy handheld setup (Relogin=%s, User=%s)\n' "$relogin" "$username"
  fi
  printf '[Autologin]\nSession=omarchy-handheld.desktop\nRelogin=%s\n' "$relogin"
  if [[ -n $username ]]; then
    printf 'User=%s\n' "$username"
  fi
}

sddm_owner_matches() {
  local format=$1 sddm_parse_section_name="[Autologin]"
  sddm_generated_file "$sddm_user_dropin" || return 1
  if [[ $format == "managed" ]]; then
    sddm_parse_section_name="[OmarchyHandheld]"
  fi
  sddm_parse_autologin "$(<"$sddm_user_dropin")"
  sddm_username_ok "$sddm_autologin_user" &&
    cmp -s -- "$sddm_user_dropin" <(sddm_owner_config "$sddm_autologin_user" "$format")
}

sddm_session_matches() {
  local format=$1 sddm_parse_section_name="[Autologin]"
  sddm_generated_file "$sddm_session_dropin" || return 1
  sddm_parse_autologin "$(<"$sddm_session_dropin")"
  [[ $sddm_autologin_relogin == "true" || $sddm_autologin_relogin == "false" ]] || return 1
  if [[ -n $sddm_autologin_user ]]; then
    [[ $format == "managed" ]] && sddm_username_ok "$sddm_autologin_user" || return 1
  fi
  cmp -s -- "$sddm_session_dropin" <(sddm_session_config "$sddm_autologin_relogin" "$format" "$sddm_autologin_user")
}

# Preserve unmarked legacy fragments byte for byte outside SDDM's *.conf glob.
sddm_archive_legacy() {
  local file=$1 backup
  backup=$(mktemp --tmpdir="$sddm_conf_dir" ".${file##*/}.omarchy-disabled.XXXXXXXX") || return 1
  if cp -p -- "$file" "$backup"; then
    printf 'omarchy gaming session: saved legacy SDDM configuration at %s\n' "$backup" >&2
  else
    rm -f -- "$backup"
    return 1
  fi
}

sddm_write_config() {
  local file=$1 temporary
  temporary=$(mktemp --tmpdir="$sddm_conf_dir" .omarchy-handheld.XXXXXXXX) || return 1
  if cat > "$temporary" && chown root:root "$temporary" && chmod 0644 "$temporary" && mv -fT -- "$temporary" "$file"; then
    return 0
  fi
  rm -f -- "$temporary"
  return 1
}

sddm_migrate_owner() {
  if sddm_owner_matches legacy; then
    sddm_archive_legacy "$sddm_user_dropin" &&
      sddm_owner_config "$sddm_autologin_user" managed | sddm_write_config "$sddm_user_dropin"
  fi
}

sddm_deactivate_autologin() {
  # Neutralise the legacy User= first. Removing only Session= can make SDDM
  # autologin into its last session. Earlier guards may already have done so.
  sddm_migrate_owner || return 1
  if sddm_session_matches managed; then
    rm -f -- "$sddm_session_dropin"
  elif sddm_session_matches legacy; then
    sddm_archive_legacy "$sddm_session_dropin" && rm -f -- "$sddm_session_dropin"
  elif [[ -e $sddm_session_dropin || -L $sddm_session_dropin ]]; then
    printf 'omarchy gaming session: leaving administrator SDDM configuration at %s\n' "$sddm_session_dropin" >&2
  fi
}

sddm_activate_autologin() {
  local relogin=$1 username=""
  if [[ -e $sddm_session_dropin || -L $sddm_session_dropin ]]; then
    if sddm_session_matches legacy; then
      sddm_archive_legacy "$sddm_session_dropin" || return 1
    elif ! sddm_session_matches managed; then
      printf 'omarchy gaming session: leaving administrator SDDM configuration at %s\n' "$sddm_session_dropin" >&2
      return 1
    fi
  fi
  sddm_migrate_owner || return 1
  if sddm_owner_matches managed; then
    username=$sddm_autologin_user
  fi
  sddm_session_config "$relogin" managed "$username" | sddm_write_config "$sddm_session_dropin"
}

sddm_install_user() (
  local username=$1
  sddm_username_ok "$username" || return 2
  sddm_handheld_variant || return 0
  sddm_lock_conf_dir || return 1
  if [[ ! -e $sddm_user_dropin && ! -L $sddm_user_dropin ]]; then
    sddm_owner_config "$username" managed | sddm_write_config "$sddm_user_dropin"
  fi
)

# The installer-recorded user. autologin.conf's [Autologin] User= is first.
# After the unencrypted cleanup deletes that file, SDDM's [Last] User= is the
# same record configure_login wrote. No passwd scan and no $USER.
sddm_recorded_user() {
  local text user="" sddm_parse_section_name="[Autologin]"
  if [[ -f $sddm_autologin_conf && ! -L $sddm_autologin_conf ]]; then
    text=$(cat -- "$sddm_autologin_conf")
    sddm_parse_autologin "$text"
    user=$sddm_autologin_user
  fi
  if sddm_username_ok "$user"; then
    printf '%s' "$user"
    return 0
  fi
  sddm_parse_section_name="[Last]"
  if [[ -f $sddm_state_conf && ! -L $sddm_state_conf ]]; then
    text=$(cat -- "$sddm_state_conf")
    sddm_parse_autologin "$text"
    user=$sddm_autologin_user
  fi
  if sddm_username_ok "$user"; then
    printf '%s' "$user"
  fi
}

sddm_install_recorded() (
  local user
  sddm_handheld_variant || return 0
  sddm_lock_conf_dir || return 1
  if [[ -e $sddm_user_dropin || -L $sddm_user_dropin ]]; then
    return 0
  fi
  user=$(sddm_recorded_user)
  sddm_username_ok "$user" || return 0
  sddm_owner_config "$user" managed | sddm_write_config "$sddm_user_dropin"
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  set -euo pipefail
  case ${1:-} in
    install-recorded)
      sddm_install_recorded
      ;;
    install-user)
      sddm_install_user "${2:-}"
      ;;
    deactivate-autologin)
      if [[ -e $sddm_conf_dir || -L $sddm_conf_dir ]]; then
        sddm_lock_conf_dir && sddm_deactivate_autologin
      fi
      ;;
    *)
      echo "usage: sddm-user.sh install-recorded|install-user|deactivate-autologin" >&2
      exit 2
      ;;
  esac
fi
