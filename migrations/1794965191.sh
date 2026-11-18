echo "Watch for ROG Ally power source changes"

if omarchy-hw-rog-ally; then
  sudo "$OMARCHY_PATH/bin/omarchy-ally-tdp-install" power-source
fi
