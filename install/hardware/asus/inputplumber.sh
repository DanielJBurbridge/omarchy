# InputPlumber is a system service so the stick exists before SDDM. The
# greeter map is the pointer profile, loaded by omarchy-ally-pointer.service
# through omarchy-inputplumber-profile. The same helper serves desktop,
# gaming and osk switches. The stock Ally composite file is not copied.
# Greeter pointer motion is unverified. Enable can fail on an image's first
# boot before systemd will take the unit; the migration retries it.
if omarchy-hw-rog-ally; then
  omarchy-pkg-add inputplumber
  sudo "$OMARCHY_PATH/bin/omarchy-inputplumber-profile" install || true
fi
