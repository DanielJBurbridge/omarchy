echo "Install the InputPlumber profile switch with the gaming session"

# The system service, D-Bus policy and polkit rule are the optional gaming
# session, not part of every Ally. A machine without that package keeps the
# greeter pointer unit and nothing else.
if omarchy-hw-rog-ally && omarchy-pkg-present omarchy-gaming-session; then
  sudo "$OMARCHY_PATH/bin/omarchy-inputplumber-profile" install-service
fi
