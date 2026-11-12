echo "Add optional gaming launchers without replacing local entries"

# Steam shortcuts are useless without Steam. Gaming Setup in the app launcher
# is the Ally shortcut; other machines already reach it from Install > Gaming.
install_launcher() {
  local name=$1
  local apps="$HOME/.local/share/applications"
  local launcher="$apps/$name"
  if [[ -e $launcher || -L $launcher ]]; then
    return 0
  fi
  mkdir -p "$apps"
  cp "$OMARCHY_PATH/applications/$name" "$launcher"
  update-desktop-database "$apps"
}

if omarchy-cmd-present steam; then
  install_launcher "Steam Big Picture.desktop"
  install_launcher "Desktop Mode.desktop"
fi
if omarchy-hw-rog-ally; then
  install_launcher "Gaming Setup.desktop"
fi
