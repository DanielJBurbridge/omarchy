echo "Load vhci_hcd on the ROG Ally so the Steam Deck gaming pad survives a kernel upgrade"

# The deck target is a virtual USB device. Without vhci_hcd, a kernel
# upgrade that has not rebooted leaves the gaming profile with no pad.
# install-vhci writes /etc/modules-load.d/omarchy-rog-ally-vhci.conf and
# tries the module now. Off the RC71L there is nothing to write.
if omarchy-hw-rog-ally; then
  sudo "$OMARCHY_PATH/bin/omarchy-inputplumber-profile" install-vhci
fi
