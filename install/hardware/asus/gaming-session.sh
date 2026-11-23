# The InputPlumber profile switch is opt-in with the gaming session package.
# The greeter pointer unit is installed by inputplumber.sh on every Ally.
# A non-login shell can source this under set -u with OMARCHY_PATH unset.
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
if omarchy-hw-rog-ally && omarchy-pkg-present omarchy-gaming-session; then
  if ! sudo "$OMARCHY_PATH/bin/omarchy-inputplumber-profile" install-service; then
    printf 'warning: InputPlumber profile service install failed; re-run: sudo %s install-service\n' \
      "$OMARCHY_PATH/bin/omarchy-inputplumber-profile" >&2
  fi
fi
