echo "Replace the Ally pointer loader with the InputPlumber profile helper"

# Machines that enabled omarchy-ally-pointer.service still have the #48 unit
# in /etc, calling the loader this tree no longer ships. install rewrites that
# unit, adds the profile service and its D-Bus policy, and leaves a disabled
# or masked unit disabled. Off the RC71L there is nothing to migrate.
if omarchy-hw-rog-ally; then
  sudo "$OMARCHY_PATH/bin/omarchy-inputplumber-profile" install
fi
