echo "Create the root-owned handheld state directory"

# The desktop user has to be able to stat a missing K07 marker. The directory
# is 0755 and root-owned; the marker file is not created here.

if [[ -L /var/lib/omarchy || -L /var/lib/omarchy/handheld ]]; then
  echo "Refusing to repair a symlinked handheld state directory." >&2
  exit 1
fi

if (( EUID == 0 )); then
  "$OMARCHY_PATH/bin/omarchy-setup-handheld-dirs"
else
  sudo "$OMARCHY_PATH/bin/omarchy-setup-handheld-dirs"
fi
