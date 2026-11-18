echo "Apply the Ally hardware check to the installed controller services"

# These units were copied to /etc. Update the two original copies while
# preserving administrator edits, masks and enablement.
reload=false
for unit in omarchy-ally-pointer omarchy-inputplumber-profile; do
  installed="/etc/systemd/system/$unit.service"
  [[ -f $installed && ! -L $installed ]] || continue
  case $unit in
    omarchy-ally-pointer) original=4b6c6091c267656696bd642c02e9bb1491182458fdf5c5c235c92adbd2caf9a2 ;;
    omarchy-inputplumber-profile) original=84d17fe26a798de5c6bb38b2a5c195d3f193885c1dc544912aa54840a7901aa6 ;;
  esac
  template="$OMARCHY_PATH/default/systemd/system/$unit.service"
  digest=$(sha256sum -- "$installed")
  if [[ ${digest%% *} == "$original" ]]; then
    sudo install -m 644 -- "$template" "$installed"
    reload=true
  elif cmp -s -- "$template" "$installed"; then
    # A previous run may have copied the file before the reload completed.
    pending=$(systemctl show "$unit.service" -P NeedDaemonReload)
    if [[ $pending == "yes" ]]; then
      reload=true
    fi
  fi
done
if $reload; then
  sudo systemctl daemon-reload
fi
