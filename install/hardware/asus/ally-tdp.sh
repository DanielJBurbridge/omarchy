# shellcheck shell=bash
# TDP units for the original ROG Ally. The shim and the power-profiles-daemon
# mask are the gaming session, not every Ally. Enable can fail on an image's
# first boot before systemd will take the unit. The migration retries it and
# stays pending when that install fails, including while the machine is offline.
if omarchy-hw-rog-ally; then
  if ! sudo "$OMARCHY_PATH/bin/omarchy-ally-tdp-install" hardware; then
    printf 'warning: Ally TDP hardware install failed; re-run: sudo %s hardware\n' \
      "$OMARCHY_PATH/bin/omarchy-ally-tdp-install" >&2
  fi
  if omarchy-pkg-present omarchy-gaming-session; then
    if ! sudo "$OMARCHY_PATH/bin/omarchy-ally-tdp-install" session; then
      printf 'warning: Ally TDP session install failed; re-run: sudo %s session\n' \
        "$OMARCHY_PATH/bin/omarchy-ally-tdp-install" >&2
    fi
  fi
fi
