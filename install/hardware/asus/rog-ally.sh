# This leaf also runs offline on an image's first boot, before a user exists.
# asusctl stays a ROG laptop package. The power-button companion is the RC71L
# binary and udev pair only. omarchy-gaming-steam starts the daemon later,
# inside gamescope, and this leaf never enables a unit. A failed build must
# not stall the rest of hardware setup; the migration retries it.
if omarchy-hw-rog-ally; then
  echo "ROG Ally RC71L: skipping ROG laptop asusctl setup. Steam is optional under Install > Gaming."
  if ! omarchy-install-rog-ally-powerbutton; then
    printf 'warning: RC71L power-button companion was not installed; re-run: sudo omarchy-install-rog-ally-powerbutton\n' >&2
  fi
fi
