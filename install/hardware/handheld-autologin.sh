# Handheld SDDM autologin. The leaf runs on every machine: an Ally keeps the
# drop-in, and every other machine loses it, including after the variant is
# removed. The gaming package still has to be installed before apply writes
# Relogin=true. Laptops are not given a drop-in.
# A non-login shell can source this under set -u with OMARCHY_PATH unset.
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

if omarchy-hw-rog-ally; then
  sudo install -Dm644 "$OMARCHY_PATH/default/systemd/system/omarchy-handheld-autologin.service" \
    /etc/systemd/system/omarchy-handheld-autologin.service
  sudo systemctl enable omarchy-handheld-autologin.service || true
else
  sudo systemctl disable omarchy-handheld-autologin.service || true
  sudo rm -f /etc/systemd/system/omarchy-handheld-autologin.service
fi
sudo "$OMARCHY_PATH/bin/omarchy-handheld-autologin" apply || true
