echo "Install the greeter keyboard package"

# The handheld User= file belongs to omarchy-gaming-session. This migration
# does not call that helper and does not read OMARCHY_PATH, so a missing
# path cannot stop the queue.

omarchy-pkg-add qt6-virtualkeyboard
