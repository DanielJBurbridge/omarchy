#!/bin/bash
# Adapted from Pizzarchy deck_autologin.py parse_autologin, commit
# daa9376ab733880e612569467164754096a5f0f4. A User= outside [Autologin] does
# not count. This writer owns /etc/sddm.conf.d/omarchy-handheld-user.conf and
# no other SDDM file. It does not set Session= or Relogin=, and it does not
# guess a username.
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
sddm_autologin_conf=$sddm_conf_dir/autologin.conf
sddm_state_conf=${OMARCHY_SDDM_STATE:-/var/lib/sddm/state.conf}
sddm_update_stub=${OMARCHY_STEAMOS_UPDATE_PATH:-/usr/bin/steamos-polkit-helpers/steamos-update}
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

sddm_refuse_user_symlink() {
  local path
  for path in "$sddm_conf_dir" "$sddm_user_dropin" "$sddm_autologin_conf" "$sddm_state_conf"; do
    if [[ -L $path ]]; then
      echo "omarchy gaming session: refusing a symlink at $path" >&2
      return 1
    fi
  done
}

sddm_user_dropin_counts() {
  local text
  [[ -f $sddm_user_dropin && ! -L $sddm_user_dropin ]] || return 1
  text=$(cat -- "$sddm_user_dropin")
  sddm_parse_section_name="[Autologin]"
  sddm_parse_autologin "$text"
  [[ -n $sddm_autologin_user ]]
}

sddm_write_user() {
  local username=$1 temporary
  (( EUID == 0 )) || return 1
  sddm_refuse_user_symlink || return 1
  install -d -o root -g root -m 0755 "$sddm_conf_dir"
  temporary=$(mktemp)
  printf '[Autologin]\nUser=%s\n' "$username" >"$temporary"
  install -o root -g root -m 0644 "$temporary" "$sddm_user_dropin"
  rm -f -- "$temporary"
}

sddm_username_ok() {
  [[ $1 != "root" && $1 =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]
}

# Writes User= once. A file whose [Autologin] User= already counts is left
# alone, including when the name differs. A User= that sits outside that
# section is rewritten, because SDDM does not read it.
sddm_install_user() {
  local username=$1
  sddm_refuse_user_symlink || return 1
  sddm_username_ok "$username" || return 2
  sddm_handheld_variant || return 0
  if sddm_user_dropin_counts; then
    return 0
  fi
  sddm_write_user "$username"
}

# The installer-recorded user. autologin.conf's [Autologin] User= is first.
# After the unencrypted cleanup deletes that file, SDDM's [Last] User= is the
# same record configure_login wrote. No passwd scan and no $USER.
sddm_recorded_user() {
  local text user=""
  sddm_parse_section_name="[Autologin]"
  if [[ -f $sddm_autologin_conf ]]; then
    text=$(cat -- "$sddm_autologin_conf")
    sddm_parse_autologin "$text"
    user=$sddm_autologin_user
  fi
  if sddm_username_ok "$user"; then
    printf '%s' "$user"
    return 0
  fi
  sddm_parse_section_name="[Last]"
  if [[ -f $sddm_state_conf ]]; then
    text=$(cat -- "$sddm_state_conf")
    sddm_parse_autologin "$text"
    user=$sddm_autologin_user
  fi
  sddm_parse_section_name="[Autologin]"
  if sddm_username_ok "$user"; then
    printf '%s' "$user"
  fi
}

sddm_install_recorded() {
  local user
  sddm_refuse_user_symlink || return 1
  sddm_handheld_variant || return 0
  if sddm_user_dropin_counts; then
    return 0
  fi
  user=$(sddm_recorded_user)
  sddm_username_ok "$user" || return 0
  sddm_write_user "$user"
}

# The package owns the absolute path Steam calls. Copy it only when that
# path is absent, and only for the Ally gaming-session pair. Never replace
# a file the package already installed, and never follow a symlink.
gaming_install_update_stub() {
  local src=${OMARCHY_PATH:-}/default/gaming/steamos-update
  sddm_handheld_variant || return 0
  if [[ -L $sddm_update_stub ]]; then
    echo "omarchy gaming session: refusing a symlink at $sddm_update_stub" >&2
    return 1
  fi
  if [[ -e $sddm_update_stub ]]; then
    return 0
  fi
  [[ -f $src && ! -L $src ]] || return 1
  (( EUID == 0 )) || return 1
  install -D -o root -g root -m 0755 "$src" "$sddm_update_stub"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  set -euo pipefail
  case ${1:-} in
    install-recorded)
      sddm_install_recorded
      ;;
    install-user)
      sddm_install_user "${2:-}"
      ;;
    install-stub)
      gaming_install_update_stub
      ;;
    *)
      echo "usage: sddm-user.sh install-recorded|install-user|install-stub" >&2
      exit 2
      ;;
  esac
fi
