echo "Install the RC71L gaming power-button companion when it is still missing"

# 1795075200 returns 0 when the installer fails, and a fresh install pre-marks
# that migration, so neither path retries a companion that was never built.
# This runs for an existing user who does not yet have this marker. A fresh
# user's skel marker skips it. Setup and the hardware leaf still call the
# installer. A failed build warns and returns 0 so later migrations still run.
if omarchy-hw-rog-ally && omarchy-pkg-present omarchy-gaming-session; then
  if ! omarchy-pkg-present omarchy-rog-ally-powerbutton; then
    if ! omarchy-install-rog-ally-powerbutton; then
      echo "warning: RC71L power-button companion was not installed. It will be tried again from omarchy-setup-gaming-session." >&2
    fi
  fi
fi
