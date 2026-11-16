# Opt-in Ally gaming session files. The package owns the SteamOS update stub
# and the persistent SDDM User= drop-in. Other hardware is left alone. This
# leaf does not install sudoers and does not grant NOPASSWD.

if omarchy-hw-rog-ally && omarchy-pkg-present omarchy-gaming-session; then
  sudo "$OMARCHY_PATH/default/gaming/sddm-user.sh" install-stub
  sudo "$OMARCHY_PATH/default/gaming/sddm-user.sh" install-recorded
fi
