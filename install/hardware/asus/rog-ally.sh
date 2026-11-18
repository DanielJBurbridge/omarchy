# This leaf also runs offline on an image's first boot, before a user exists.
# asusctl stays a ROG laptop package. The power-button companion is installed
# only with the opt-in gaming session. This leaf builds it when that package
# is already present. omarchy-setup-gaming-session builds it online, including
# after a fresh install has marked the migration. omarchy-gaming-steam starts
# the daemon later, inside gamescope, and this leaf never enables a unit.
# A failed build must not stall the rest of hardware setup.
if omarchy-hw-rog-ally; then
  echo "ROG Ally RC71L: skipping ROG laptop asusctl setup. Steam is optional under Install > Gaming."
  if omarchy-pkg-present omarchy-gaming-session; then
    if ! omarchy-install-rog-ally-powerbutton; then
      printf 'warning: RC71L power-button companion was not installed; re-run: omarchy-setup-gaming-session install-power-button\n' >&2
    fi
  fi
fi
