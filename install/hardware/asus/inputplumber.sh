# InputPlumber is a system service so the stick exists before SDDM. The
# greeter map is the pointer profile, loaded by omarchy-ally-pointer.service
# through omarchy-inputplumber-profile. The profile switch service is
# installed with the gaming session package, not here. The stock Ally
# composite file is not copied. Greeter pointer motion is unverified.
# Enable can fail on an image's first boot before systemd will take the
# unit; the migration retries it. The failure stays non-fatal and names
# the command to re-run.
# A non-login shell can source this under set -u with OMARCHY_PATH unset.
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
if omarchy-hw-rog-ally; then
  omarchy-pkg-add inputplumber
  if ! sudo "$OMARCHY_PATH/bin/omarchy-inputplumber-profile" install-greeter; then
    printf 'warning: Ally greeter pointer setup failed; re-run: sudo %s install-greeter\n' \
      "$OMARCHY_PATH/bin/omarchy-inputplumber-profile" >&2
  fi
  # The deck target is a virtual USB device. This writes the modules-load.d
  # entry on an Ally only. A failed modprobe stays non-fatal: the next boot
  # loads the module, and a gaming load falls back to ds5-edge until then.
  if ! sudo "$OMARCHY_PATH/bin/omarchy-inputplumber-profile" install-vhci; then
    printf 'warning: Ally vhci_hcd setup failed; re-run: sudo %s install-vhci\n' \
      "$OMARCHY_PATH/bin/omarchy-inputplumber-profile" >&2
  fi
fi
