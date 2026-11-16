echo "Install the RC71L gaming power-button companion"

# Off the original Ally, or without the opt-in gaming session, there is
# nothing to migrate. A conflicting handler or a failed build warns and
# returns 0 so later migrations still run. This script does not write the
# migration marker. A fresh install marks every migration before this script
# can run, so a missing companion is retried by omarchy-setup-gaming-session.
if omarchy-hw-rog-ally && omarchy-pkg-present omarchy-gaming-session; then
  if ! omarchy-install-rog-ally-powerbutton; then
    echo "warning: RC71L power-button companion was not installed. It will be tried again from omarchy-setup-gaming-session." >&2
  fi
fi
