echo "Install the SteamOS update stub and the handheld SDDM User= drop-in on an Ally with the gaming session package"

# Same path #48 already writes: /etc/sddm.conf.d/omarchy-handheld-user.conf.
# Nothing moves, and a second drop-in is not created. apply still does not
# write User=. The stub is copied only when Steam's absolute path is empty.

if ! omarchy-hw-rog-ally; then
  exit 0
fi
if ! omarchy-pkg-present omarchy-gaming-session; then
  exit 0
fi

sudo "$OMARCHY_PATH/default/gaming/sddm-user.sh" install-stub
sudo "$OMARCHY_PATH/default/gaming/sddm-user.sh" install-recorded
if [[ ${USER:-} != root && ${USER:-} =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
  sudo "$OMARCHY_PATH/bin/omarchy-handheld-autologin" install-user "$USER"
fi
