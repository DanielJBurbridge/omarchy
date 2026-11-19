echo "Link the ROG Ally boot pointer to the installed package"

if omarchy-hw-rog-ally; then
  sudo "$OMARCHY_PATH/bin/omarchy-inputplumber-profile" install-greeter
fi
