#!/bin/bash
# Keyboard setup still keys off omarchy-hw-asus-rog and an unanchored
# product/family match. omarchy-hw-rog-ally accepts board RC71L with the
# short product name, and rejects a different board whose product string
# merely contains the same pattern. Release tip already calls
# omarchy-hw-rog-ally; this tree does not. Left failing.

set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$here/../shell.d/base-test.sh"

unset OMARCHY_DMI_SYS_VENDOR_PATH OMARCHY_DMI_PRODUCT_NAME_PATH OMARCHY_DMI_BOARD_NAME_PATH

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stub=$work/bin
mkdir -p "$stub" "$work/home"
cat > "$stub/pacman" <<'EOF'
#!/bin/bash
printf 'pacman:%s\n' "$*" >> "$HANDHELD_ACTIONS"
exit 1
EOF
chmod +x "$stub/pacman"

write_dmi() {
  local sys=$1 vendor=$2 product=$3 family=$4 board=$5
  mkdir -p "$sys/class/dmi/id"
  printf '%s\n' "$vendor" > "$sys/class/dmi/id/sys_vendor"
  printf '%s\n' "$product" > "$sys/class/dmi/id/product_name"
  printf '%s\n' "$family" > "$sys/class/dmi/id/product_family"
  printf '%s\n' "$board" > "$sys/class/dmi/id/board_name"
}

probe() {
  local sys=$1
  local actions=$work/actions-$2
  : > "$actions"
  PATH="$stub:$ROOT/bin:/usr/bin:/bin" \
    OMARCHY_PATH=$ROOT \
    HOME=$work/home \
    HANDHELD_ACTIONS=$actions \
    unshare --user --map-root-user --mount bash -c '
      mount --bind "$1" /sys || exit 99
      if omarchy-hw-rog-ally >/dev/null 2>&1; then
        detector=0
      else
        detector=$?
      fi
      set +e
      message=$(omarchy-setup-rog-ally-keyboard --configure-reviewed-package 2>&1)
      status=$?
      printf "detector=%s\nstatus=%s\nmessage=%s\n" "$detector" "$status" "$message"
    ' bash "$sys"
}

write_dmi "$work/ally-sys" "ASUSTeK COMPUTER INC." "ROG Ally" "ROG Ally" "RC71L"
write_dmi "$work/laptop-sys" "ASUSTeK COMPUTER INC." "ASUS ROG Ally RC71L sticker" "ROG Strix" "G614"

ally=$(probe "$work/ally-sys" ally)
laptop=$(probe "$work/laptop-sys" laptop)
ally_detector=${ally#*detector=}; ally_detector=${ally_detector%%$'\n'*}
laptop_detector=${laptop#*detector=}; laptop_detector=${laptop_detector%%$'\n'*}
ally_message=${ally#*message=}; ally_message=${ally_message%%$'\n'*}
laptop_message=${laptop#*message=}; laptop_message=${laptop_message%%$'\n'*}

problems=
if [[ $ally_detector != 0 ]]; then
  problems+="Ally fixture was not accepted by omarchy-hw-rog-ally (status $ally_detector). "
fi
if [[ $ally_message != *"Install the reviewed wvkbd"* ]]; then
  problems+="Keyboard setup rejects product ROG Ally with board RC71L: $ally_message "
fi
if [[ $laptop_detector == 0 ]]; then
  problems+="Laptop fixture was accepted by omarchy-hw-rog-ally. "
fi
if [[ $laptop_message != *"This optional setup is for ASUS ROG Ally RC71L."* ]]; then
  problems+="Keyboard setup accepts a non-Ally whose product name merely contains the pattern: $laptop_message "
fi
if [[ -z $problems ]]; then
  pass "keyboard setup follows omarchy-hw-rog-ally"
else
  fail "keyboard setup follows omarchy-hw-rog-ally" "$problems"
fi
