# shellcheck shell=bash

ally_tdp_profiles_enabled() {
  local record=${OMARCHY_ALLY_TDP_PPD_RECORD:-/var/lib/omarchy/handheld/power-profiles-daemon.state}
  [[ -f $record ]] || return 1
  case $(systemctl is-enabled power-profiles-daemon.service 2>/dev/null) in
    masked | masked-runtime) return 0 ;;
    *) return 1 ;;
  esac
}

# Print each preset, its requested SPL and whether the writer reports it active.
ally_tdp_profiles() {
  local status key value profile
  local -A tdp watts
  local presets=(power-saver balanced performance)
  status=$(omarchy-ally-tdp-apply --show 2>/dev/null) || return 1
  while IFS='=' read -r key value; do
    case $key in
      writable | profile | min | spl_policy_battery | spl_policy_ac)
        tdp[$key]=$value ;;
    esac
  done <<<"$status"
  [[ ${tdp[writable]:-} == "1" ]] || return 1
  for key in min spl_policy_battery spl_policy_ac; do
    [[ ${tdp[$key]:-} =~ ^(0|[1-9][0-9]*)$ ]] || return 1
  done

  watts=([power-saver]=${tdp[min]} [balanced]=${tdp[spl_policy_battery]} [performance]=${tdp[spl_policy_ac]})
  for profile in "${presets[@]}"; do
    if [[ $profile == "${tdp[profile]:-}" ]]; then
      printf '%s\t%s\t1\n' "$profile" "${watts[$profile]}"
    else
      printf '%s\t%s\t0\n' "$profile" "${watts[$profile]}"
    fi
  done
}
