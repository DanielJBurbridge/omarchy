echo "Record the handheld SDDM User= on an Ally that already has the gaming session helper"

# Same path #48 already writes: /etc/sddm.conf.d/omarchy-handheld-user.conf.
# Nothing moves. The package owns /usr/bin/steamos-polkit-helpers/steamos-update.
# This step does not copy that stub. An older package has no helper yet, and
# its upgrade writes User= from the installer record.

if ! omarchy-hw-rog-ally; then
  exit 0
fi
if ! omarchy-pkg-present omarchy-gaming-session; then
  exit 0
fi
if [[ ! -x /usr/lib/omarchy-gaming-session/sddm-user.sh || -L /usr/lib/omarchy-gaming-session/sddm-user.sh ]]; then
  exit 0
fi
sudo /usr/lib/omarchy-gaming-session/sddm-user.sh install-recorded
