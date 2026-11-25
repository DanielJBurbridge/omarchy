# This package and its dependencies are also in the ISO's offline repository.
omarchy-hw-rog-ally || return 0

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
# The Deck target needs a virtual USB device. If the running kernel cannot
# load it, the modules-load entry covers the next boot.
if ! "$OMARCHY_PATH/bin/omarchy-inputplumber-profile" install-vhci; then
  printf 'warning: Ally vhci_hcd setup failed; re-run: sudo %s install-vhci\n' \
    "$OMARCHY_PATH/bin/omarchy-inputplumber-profile" >&2
fi

unit=omarchy-ally-pointer.service
package_unit="$OMARCHY_PATH/default/systemd/system/$unit"
admin_unit="/etc/systemd/system/$unit"
legacy_want="/etc/systemd/system/graphical.target.wants/$unit"
state_dir=/var/lib/omarchy/handheld
provisioned="$state_dir/ally-pointer-provisioned"
enable_daemon="$state_dir/ally-pointer-enable-inputplumber"

# Only claim a vacant systemd name, resume our link, or replace an enabled
# unit from the previous managed installation. Leave administrator units
# and disabled legacy copies in place.
legacy_target=$(readlink -- "$legacy_want" 2>/dev/null || true)
unit_status=0
unit_state=$(systemctl is-enabled "$unit" 2>/dev/null) || unit_status=$?
case $unit_state in
  masked | masked-runtime) return 0 ;;
esac

if [[ -e $admin_unit || -L $admin_unit ]]; then
  if [[ -L $admin_unit ]]; then
    [[ $(readlink -- "$admin_unit") == "$package_unit" ]] || return 0
  elif [[ ! -f $provisioned && $unit_state == "enabled" && -f $admin_unit &&
    ( $legacy_target == "$admin_unit" || $legacy_target == "../$unit" ) ]]; then
    # An earlier migration can already have copied the current template.
    digest=$(sha256sum -- "$admin_unit")
    case ${digest%% *} in
      4b6c6091c267656696bd642c02e9bb1491182458fdf5c5c235c92adbd2caf9a2 | 589761aa26403848514b7f62e553e6cc61672a7d303c235dd1460deaf2a5a8d2) ;;
      *) cmp -s -- "$admin_unit" "$package_unit" || return 0 ;;
    esac
    stage=$(mktemp -d -- "${admin_unit%/*}/.omarchy-ally-pointer.XXXXXXXX")
    if ! ln -s -- "$package_unit" "$stage/$unit" ||
      ! mv -fT -- "$stage/$unit" "$admin_unit"; then
      rm -f -- "$stage/$unit"
      rmdir -- "$stage"
      return 1
    fi
    rmdir -- "$stage"
  else
    return 0
  fi
elif [[ $unit_state != "not-found" ]]; then
  # Use systemctl’s missing-unit exit code when it prints no state.
  [[ -z $unit_state && $unit_status == 4 ]] || return 0
fi

if [[ ! -f $provisioned ]]; then
  # Record a new daemon before installing it, so a retry can still enable it.
  # An already present daemon keeps its administrator's enablement state.
  if omarchy-pkg-missing inputplumber; then
    install -Dm644 /dev/null "$enable_daemon"
  fi
  omarchy-pkg-add inputplumber
  if [[ -f $enable_daemon ]]; then
    case $(systemctl is-enabled inputplumber.service 2>/dev/null || true) in
      masked | masked-runtime) ;;
      *) systemctl enable inputplumber.service ;;
    esac
    rm -f -- "$enable_daemon"
  fi

  # Link to the package's unit. The receipt distinguishes a later deliberate
  # disable from an interruption before enable completed.
  systemctl enable "$package_unit"
  install -Dm644 /dev/null "$provisioned"
fi

# Image provisioning runs after boot has queued its normal service starts.
if [[ ${OMARCHY_IMAGE_DEFERRED_HARDWARE:-} == "1" ]] &&
  systemctl is-enabled --quiet inputplumber.service && systemctl is-enabled --quiet "$unit"; then
  systemctl start --no-block inputplumber.service "$unit"
fi
