echo "Install the RC71L gaming power-button companion"

# The hardware leaf builds this during setup. An install that could not reach
# the build, or an Ally that was already set up, retries here. Off the RC71L
# there is nothing to migrate. The daemon stays a gamescope process.
if omarchy-hw-rog-ally; then
  omarchy-install-rog-ally-powerbutton
fi
