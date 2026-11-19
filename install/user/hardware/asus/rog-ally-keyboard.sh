# The stock bar already provides the touch keyboard on the built-in screen.
# Enable its desktop gesture during installation, on the untouched skel only.
case ${OMARCHY_SETUP_CONTEXT:-runtime} in
  iso-chroot | provision-owner) ;;
  *) return 0 ;;
esac

if omarchy-hw-rog-ally && omarchy-pkg-present wvkbd; then
  shell_config="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"
  if [[ -f $shell_config && ! -L $shell_config ]] && cmp -s "$shell_config" "$OMARCHY_PATH/config/omarchy/shell.json"; then
    updated=$(mktemp -- "${shell_config}.XXXXXXXX")
    if jq '.desktopKeyboard.edgeSwipe = true' "$shell_config" >"$updated" &&
      chmod --reference="$shell_config" "$updated" && mv -- "$updated" "$shell_config"; then
      echo 'Enabled the ROG Ally desktop keyboard gesture.'
    else
      rm -f -- "$updated"
      return 1
    fi
  fi
fi
