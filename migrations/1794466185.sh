echo "Leave the Ally lock-screen keyboard dormant until a device lock test is recorded"

# A laptop is not an RC71L. Do not ask for a password and do not write a marker.
PATH="$OMARCHY_PATH/bin:$PATH"
if ! omarchy-hw-rog-ally; then
  exit 0
fi

# The Ally stays dormant too. This migration does not record a device lock
# test and does not write /var/lib/omarchy/handheld/k07-landed.
exit 0
