# Existing Allys lost User= when the unencrypted first-boot cleanup deleted
# autologin.conf. Write it once into the installer-owned file. apply never
# touches that file. Also install the greeter keyboard package.

if omarchy-hw-rog-ally; then
  if [[ ! -e /etc/sddm.conf.d/omarchy-handheld-user.conf && ${USER:-} =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
    sudo "$OMARCHY_PATH/bin/omarchy-handheld-autologin" install-user "$USER"
  fi
fi

omarchy-pkg-add qt6-virtualkeyboard
