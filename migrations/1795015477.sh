echo "Retire gaming shortcuts that older Omarchy packages copied to every account"

apps="$HOME/.local/share/applications"
[[ ! -L $apps ]] || exit 0
templates="$OMARCHY_PATH/default/applications"
has_steam=false
is_ally=false
changed=false
if omarchy-cmd-present steam; then has_steam=true; fi
if omarchy-hw-rog-ally; then is_ally=true; fi

repair_launcher() {
  local name=$1 eligible=$2 entry="$apps/$1.desktop" template="$templates/$1.desktop"
  shift 2
  local identity digest known backup attributes
  [[ -f $entry && ! -L $entry && -O $entry ]] || return 0
  [[ $(stat -c '%a:%h' -- "$entry") == "644:1" ]] || return 0
  attributes=$(getfattr --absolute-names -m - -- "$entry") || return 0
  [[ -z $attributes ]] || return 0
  if $eligible && cmp -s -- "$entry" "$template"; then return 0; fi

  # Only the exact launchers shipped in the old skeletons qualify. Save the
  # user's original even then: a deliberately identical copy is indistinguishable.
  identity=$(stat -c '%d:%i:%z' -- "$entry")
  read -r digest _ < <(sha256sum < "$entry")
  for known in "$@"; do
    [[ $digest == "$known" ]] || continue
    backup=$(mktemp -- "$entry.omarchy-backup.XXXXXX")
    cp --preserve=all -- "$entry" "$backup"
    if [[ -L $entry || $(stat -c '%d:%i:%z' -- "$entry") != "$identity" ]] || ! cmp -s -- "$entry" "$backup" || [[ $(sha256sum < "$backup") != "$digest  -" ]]; then
      echo "Gaming shortcut changed during repair. Left it in place: $entry" >&2
      return 0
    fi
    if $eligible; then
      local replacement
      replacement=$(mktemp -- "$entry.omarchy-new.XXXXXX")
      install -m644 -- "$template" "$replacement"
      mv -T -- "$replacement" "$entry"
    else
      rm -- "$entry"
    fi
    echo "Saved $name in $backup"
    changed=true
    return 0
  done
}

repair_launcher "Desktop Mode" "$has_steam" cf5717fc1e87988ac8f02cc830bd2d55cfe52c68a798ec01022867e95e7f908a
repair_launcher "Steam Big Picture" "$has_steam" b5d31ba3fbc4a9ddbc757ead3e6d2ff40359540957376e5522b51c94540b7b72 31de6e87e20a750ea6b174782edd16e5d30cfcec0bd7ab451e6895a2c7421aa1
repair_launcher "Gaming Setup" "$is_ally" dc67fd5929d5712b5afd75895dbb358a558b890487b0238d3323489ffcd59a69 47ee18465ea250af32144b5ddd93e0cb8127cb14880d98fc278c48488f2f6782
if $changed; then update-desktop-database "$apps"; fi
