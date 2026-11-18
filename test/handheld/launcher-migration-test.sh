#!/bin/bash
# Optional gaming launchers follow the Steam installation and the original Ally.
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$here/../shell.d/base-test.sh"

unset OMARCHY_DMI_SYS_VENDOR_PATH OMARCHY_DMI_PRODUCT_NAME_PATH OMARCHY_DMI_BOARD_NAME_PATH

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stub=$work/bin
db=$work/desktop-db
mkdir -p "$stub"
# The no-Steam case must also work on a host with Steam installed.
ln -s /usr/bin/{bash,cat,cmp,cp,getfattr,mkdir,mktemp,mv,rm,stat} "$stub/"
: > "$db"
cat > "$stub/update-desktop-database" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$HANDHELD_DESKTOP_DB"
exit 0
EOF
chmod +x "$stub/update-desktop-database"

with_steam() {
  printf '#!/bin/bash\nexit 0\n' > "$stub/steam"
  chmod +x "$stub/steam"
}
without_steam() {
  rm -f "$stub/steam"
}

run_launcher_command() {
  local home=$1 vendor=$2 product=$3 board=$4
  shift 4
  if (( $# == 0 )); then set -- omarchy-apply-gaming-launchers; fi
  local dmi=$home/dmi
  mkdir -p "$dmi"
  printf '%s\n' "$vendor" > "$dmi/sys_vendor"
  printf '%s\n' "$product" > "$dmi/product_name"
  printf '%s\n' "$board" > "$dmi/board_name"
  PATH="$stub:$ROOT/bin" \
    HOME=$home \
    OMARCHY_PATH=$ROOT \
    OMARCHY_DMI_SYS_VENDOR_PATH=$dmi/sys_vendor \
    OMARCHY_DMI_PRODUCT_NAME_PATH=$dmi/product_name \
    OMARCHY_DMI_BOARD_NAME_PATH=$dmi/board_name \
    HANDHELD_DESKTOP_DB=$db \
    "$@" >"$home/out" 2>"$home/err" ||
    fail "launcher command completes on $product" "$(cat "$home/err")"
}

apps_of() {
  printf '%s/.local/share/applications\n' "$1"
}

laptop_vendor="LENOVO"
laptop_product="ThinkPad X1 Carbon"
laptop_board="20AA"

without_steam
home=$work/laptop-no-steam
run_launcher_command "$home" "$laptop_vendor" "$laptop_product" "$laptop_board"
apps=$(apps_of "$home")
if [[ -e "$apps/Steam Big Picture.desktop" || -e "$apps/Gaming Setup.desktop" || -e "$apps/Desktop Mode.desktop" ]]; then
  fail "a laptop without Steam does not get gaming launchers" "$(find "$apps" -type f -printf '%f\n' 2>/dev/null)"
fi
pass "a laptop without Steam does not get gaming launchers"

with_steam
home=$work/laptop-steam
run_launcher_command "$home" "$laptop_vendor" "$laptop_product" "$laptop_board"
apps=$(apps_of "$home")
[[ -f "$apps/Steam Big Picture.desktop" ]] || fail "Steam on a laptop installs Steam Big Picture"
[[ -f "$apps/Desktop Mode.desktop" ]] || fail "Steam on a laptop installs Desktop Mode"
[[ ! -e "$apps/Gaming Setup.desktop" ]] || fail "Steam on a laptop does not install the Ally Gaming Setup shortcut"
installed=$(wc -l < "$db")
(( installed > 0 )) || fail "Steam on a laptop installs launchers once"
run_launcher_command "$home" "$laptop_vendor" "$laptop_product" "$laptop_board"
[[ $(wc -l < "$db") == "$installed" ]] || fail "a second run does not rewrite existing launchers"
pass "Steam on a laptop installs only the Steam launchers, once"

without_steam
home=$work/ally
run_launcher_command "$home" "ASUSTeK COMPUTER INC." "ROG Ally RC71L" "RC71L"
apps=$(apps_of "$home")
[[ -f "$apps/Gaming Setup.desktop" ]] || fail "an Ally without Steam still gets Gaming Setup"
[[ ! -e "$apps/Steam Big Picture.desktop" && ! -e "$apps/Desktop Mode.desktop" ]] || fail "an Ally without Steam does not get Steam launchers"
pass "an Ally without Steam gets only Gaming Setup"

with_steam
home=$work/ally-keep
apps=$(apps_of "$home")
mkdir -p "$apps"
printf 'custom launcher\n' > "$apps/Gaming Setup.desktop"
run_launcher_command "$home" "ASUSTeK COMPUTER INC." "ROG Ally RC71L" "RC71L"
[[ $(<"$apps/Gaming Setup.desktop") == "custom launcher" ]] || fail "an existing Gaming Setup entry is preserved"
[[ -f "$apps/Steam Big Picture.desktop" && -f "$apps/Desktop Mode.desktop" ]] || fail "an Ally with Steam still gets the Steam launchers"
pass "an existing launcher is preserved"

# User-provided launchers and removals survive Omarchy's ordinary desktop refresh.
rm "$apps/Desktop Mode.desktop"
ln -s "$work/absent-target" "$apps/Desktop Mode.desktop"
rm "$apps/Steam Big Picture.desktop"
ln -s "$ROOT/default/applications/Steam Big Picture.desktop" "$apps/Steam Big Picture.desktop"
run_launcher_command "$home" "ASUSTeK COMPUTER INC." "ROG Ally RC71L" "RC71L" omarchy-refresh-applications
run_launcher_command "$home" "ASUSTeK COMPUTER INC." "ROG Ally RC71L" "RC71L" omarchy-apply-gaming-launchers --remove-steam
[[ -L "$apps/Desktop Mode.desktop" && -L "$apps/Steam Big Picture.desktop" && ! -e "$work/absent-target" ]] || fail "both user links survive refresh and Steam removal"
[[ $(<"$apps/Gaming Setup.desktop") == "custom launcher" ]] || fail "refresh keeps existing Ally launcher content"
pass "refresh and Steam removal respect custom launchers and live or dangling links"

home=$work/laptop-steam
apps=$(apps_of "$home")
printf 'Hidden=true\n' >> "$apps/Steam Big Picture.desktop"
run_launcher_command "$home" "$laptop_vendor" "$laptop_product" "$laptop_board" omarchy-apply-gaming-launchers --remove-steam
[[ ! -e "$apps/Desktop Mode.desktop" && $(<"$apps/Steam Big Picture.desktop") == *"Hidden=true" ]] || fail "Steam removal retires only its unmodified launchers"
run_launcher_command "$home" "$laptop_vendor" "$laptop_product" "$laptop_board" omarchy-refresh-applications
[[ ! -e "$apps/Desktop Mode.desktop" && ! -e "$apps/Gaming Setup.desktop" ]] || fail "ordinary refresh does not recreate optional launchers"
pass "Steam removal preserves a hidden override and refresh respects the missing launcher"

home=$work/laptop-private
(umask 077; run_launcher_command "$home" "$laptop_vendor" "$laptop_product" "$laptop_board") || exit 1
apps=$(apps_of "$home")
[[ $(stat -c '%a' "$apps/Desktop Mode.desktop") == "600" ]] || fail "new entries respect the user's umask"
run_launcher_command "$home" "$laptop_vendor" "$laptop_product" "$laptop_board" omarchy-apply-gaming-launchers --remove-steam
[[ -f "$apps/Desktop Mode.desktop" ]] || fail "removal preserves a restrictive user mode"
pass "new entries respect the user's umask and Steam removal preserves private copies"

# A kernel write limit makes a real copy stop mid-file. Retrying must work.
without_steam
home=$work/ally-copy-failure
templates="$work/oversized/default/applications"
mkdir -p "$templates"
mkfifo "$templates/Gaming Setup.desktop"
head -c 8192 /dev/zero > "$templates/Gaming Setup.desktop" &
producer=$!
run_launcher_command "$home" "ASUSTeK COMPUTER INC." "ROG Ally RC71L" "RC71L" bash -c '
  ulimit -c 0
  ulimit -f 1
  export OMARCHY_PATH=$1
  ! omarchy-apply-gaming-launchers
' bash "$work/oversized"
wait "$producer" || true
apps=$(apps_of "$home")
[[ ! -e "$apps/Gaming Setup.desktop" ]] || fail "a failed copy leaves no partial desktop entry"
run_launcher_command "$home" "ASUSTeK COMPUTER INC." "ROG Ally RC71L" "RC71L"
cmp -s "$ROOT/default/applications/Gaming Setup.desktop" "$apps/Gaming Setup.desktop" || fail "retry publishes the complete launcher"
pass "a failed copy leaves no visible launcher and a retry publishes it"
