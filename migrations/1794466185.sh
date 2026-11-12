echo "Land the lock-screen touch keyboard and turn handheld desktop lock on unless it was turned off explicitly"

if (( EUID == 0 )); then
  "$OMARCHY_PATH/bin/omarchy-setup-handheld-k07"
else
  sudo env OMARCHY_PATH="$OMARCHY_PATH" "$OMARCHY_PATH/bin/omarchy-setup-handheld-k07"
fi

# The marker is root-owned. The host opt-in is this user's file, so the next
# graphical session loads the touch keyboard inside the trusted lock host.
PATH="$OMARCHY_PATH/bin:$PATH" "$OMARCHY_PATH/bin/omarchy-setup-handheld-lock-host"
