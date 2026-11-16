# InputPlumber is a system service so the stick exists before SDDM. The
# pointer map is Omarchy's, loaded by omarchy-ally-pointer.service. The stock
# Ally composite file is not copied. Greeter pointer motion is unverified.
if omarchy-hw-rog-ally; then
  omarchy-pkg-add inputplumber
  sudo install -Dm644 "$OMARCHY_PATH/default/systemd/system/omarchy-ally-pointer.service" \
    /etc/systemd/system/omarchy-ally-pointer.service
  sudo systemctl enable omarchy-ally-pointer.service || true
fi
