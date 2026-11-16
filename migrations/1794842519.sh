echo "Install the ROG Ally TDP limit"

# Hardware units are every Ally. The shim and the power-profiles-daemon mask
# are the gaming session. A failed install exits non-zero so this script is
# not marked done when it runs. A fresh install marks every migration before
# the script can run, so that marker is not a retry (L161).
if ! omarchy-hw-rog-ally; then
  exit 0
fi

if ! sudo "$OMARCHY_PATH/bin/omarchy-ally-tdp-install" hardware; then
  echo "Ally TDP hardware install failed." >&2
  exit 1
fi

if omarchy-pkg-present omarchy-gaming-session; then
  if ! sudo "$OMARCHY_PATH/bin/omarchy-ally-tdp-install" session; then
    echo "Ally TDP session install failed." >&2
    exit 1
  fi
fi
