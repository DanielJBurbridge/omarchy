echo "Point the Ally greeter at the InputPlumber profile helper"

# An enabled omarchy-ally-pointer.service in /etc may still exec the removed
# omarchy-ally-pointer-load program. install-greeter rewrites that unit. A
# disabled unit stays disabled. A mask is a symlink to /dev/null and is left
# in place. The profile switch service is a separate step for the gaming
# session package. Off the RC71L there is nothing to migrate.
if omarchy-hw-rog-ally; then
  sudo "$OMARCHY_PATH/bin/omarchy-inputplumber-profile" install-greeter
fi
