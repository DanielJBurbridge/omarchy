# shellcheck shell=bash
# TDP units for the original ROG Ally. The shim and the power-profiles-daemon
# mask are the gaming session, not every Ally. Enable can fail on an image's
# first boot before systemd will take the unit. The leaf warns and continues.
# A fresh install marks the migration before the script can run, so that
# marker is not a retry (L161).
# A non-login shell can source this under set -u with OMARCHY_PATH unset.
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
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
