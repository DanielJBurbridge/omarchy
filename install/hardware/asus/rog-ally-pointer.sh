omarchy-hw-rog-ally || return 0

unit=omarchy-ally-pointer.service
package_unit="$OMARCHY_PATH/default/systemd/system/$unit"
receipt=/var/lib/omarchy/handheld/ally-pointer-provisioned

if [[ ! -f $receipt ]]; then
  # Claim a vacant name or retry a partial enable of the packaged unit.
  unit_status=0
  unit_state=$(systemctl is-enabled "$unit" 2>/dev/null) || unit_status=$?
  case $unit_state in
    not-found) ;;
    "") (( unit_status == 4 )) || return 0 ;;
    enabled | linked)
      [[ $(readlink -- "/etc/systemd/system/$unit") == "$package_unit" ]] || return 0
      ;;
    *) return 0 ;;
  esac

  if [[ $unit_state != "enabled" ]]; then
    omarchy-pkg-add inputplumber
    systemctl enable "$package_unit"
  fi
  # Disabling a unit enabled by path removes both systemd links.
  install -Dm644 /dev/null "$receipt"
fi

# An image's graphical start jobs may already be queued on first boot.
if [[ ${OMARCHY_IMAGE_DEFERRED_HARDWARE:-} == "1" &&
      $(readlink -- "/etc/systemd/system/$unit") == "$package_unit" &&
      $(systemctl is-enabled "$unit" 2>/dev/null) == "enabled" ]]; then
  systemctl start --no-block "$unit"
fi
