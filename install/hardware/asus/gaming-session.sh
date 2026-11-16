# Opt-in Ally gaming session. The package owns the SteamOS update stub and the
# persistent SDDM User= drop-in. This leaf asks the installed helper to copy a
# recorded User=. It does not copy files into /usr/bin.

if omarchy-hw-rog-ally && omarchy-pkg-present omarchy-gaming-session && [[ -x /usr/lib/omarchy-gaming-session/sddm-user.sh && ! -L /usr/lib/omarchy-gaming-session/sddm-user.sh ]]; then
  sudo /usr/lib/omarchy-gaming-session/sddm-user.sh install-recorded
fi
