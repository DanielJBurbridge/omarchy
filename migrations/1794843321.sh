echo "Install the RC71L gaming power-button companion when it is still missing"

# 1795075200 is a no-op. This migration is the one catch-up. A fresh install
# pre-marks it, so a user's skel marker skips it. The hardware leaf and
# omarchy-setup-gaming-session retry a companion that was never built. A
# failed build warns and returns 0 so later migrations still run.
if omarchy-hw-rog-ally && omarchy-pkg-present omarchy-gaming-session; then
  if ! omarchy-pkg-present omarchy-rog-ally-powerbutton; then
    if ! omarchy-install-rog-ally-powerbutton; then
      echo "warning: RC71L power-button companion was not installed. It will be tried again from omarchy-setup-gaming-session." >&2
    fi
  fi
fi
