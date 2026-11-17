echo "Install the greeter keyboard package on a ROG Ally"

# The handheld User= file belongs to omarchy-gaming-session. This migration
# does not call that helper and does not read OMARCHY_PATH, so a missing
# path cannot stop the queue.
#
# qt6-virtualkeyboard stays in install/omarchy-base.packages. The greeter
# sets GreeterEnvironment for every machine in etc/sddm.conf.d/10-wayland.conf,
# so a fresh install of a laptop still needs the package. This catch-up is
# the handheld greeter only. The stamp stays 1794830400.
if omarchy-hw-rog-ally; then
  omarchy-pkg-add qt6-virtualkeyboard
fi
