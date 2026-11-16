# The InputPlumber profile switch is opt-in with the gaming session package.
# The greeter pointer unit is installed by inputplumber.sh on every Ally.
if omarchy-hw-rog-ally && omarchy-pkg-present omarchy-gaming-session; then
  sudo "$OMARCHY_PATH/bin/omarchy-inputplumber-profile" install-service || true
fi
