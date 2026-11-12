#!/bin/bash
# migrations/1794367738.sh copies Steam Big Picture, Gaming Setup and Desktop
# Mode into every home. Desktop Mode and Gaming Setup have no TryExec, so
# they show up on machines with no Steam. Steam shortcuts belong where Steam
# is installed. Gaming Setup in the app launcher is the Ally shortcut.

set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$here/../shell.d/base-test.sh"

unset OMARCHY_DMI_SYS_VENDOR_PATH OMARCHY_DMI_PRODUCT_NAME_PATH OMARCHY_DMI_BOARD_NAME_PATH

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stub=$work/bin
db=$work/desktop-db
mkdir -p "$stub"
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

run_migration() {
  local home=$1 vendor=$2 product=$3 board=$4
  local dmi=$home/dmi
  mkdir -p "$dmi"
  printf '%s\n' "$vendor" > "$dmi/sys_vendor"
  printf '%s\n' "$product" > "$dmi/product_name"
  printf '%s\n' "$board" > "$dmi/board_name"
  PATH="$stub:$ROOT/bin:/usr/bin:/bin" \
    HOME=$home \
    OMARCHY_PATH=$ROOT \
    OMARCHY_DMI_SYS_VENDOR_PATH=$dmi/sys_vendor \
    OMARCHY_DMI_PRODUCT_NAME_PATH=$dmi/product_name \
    OMARCHY_DMI_BOARD_NAME_PATH=$dmi/board_name \
    HANDHELD_DESKTOP_DB=$db \
    bash -euo pipefail "$ROOT/migrations/1794367738.sh" >"$home/out" 2>"$home/err"
}

apps_of() {
  printf '%s/.local/share/applications\n' "$1"
}

laptop_vendor="LENOVO"
laptop_product="ThinkPad X1 Carbon"
laptop_board="20AA"

without_steam
home=$work/laptop-no-steam
run_migration "$home" "$laptop_vendor" "$laptop_product" "$laptop_board"
apps=$(apps_of "$home")
if [[ -e "$apps/Steam Big Picture.desktop" || -e "$apps/Gaming Setup.desktop" || -e "$apps/Desktop Mode.desktop" ]]; then
  fail "a laptop without Steam does not get gaming launchers" "$(find "$apps" -type f -printf '%f\n' 2>/dev/null)"
fi
pass "a laptop without Steam does not get gaming launchers"

with_steam
home=$work/laptop-steam
run_migration "$home" "$laptop_vendor" "$laptop_product" "$laptop_board"
apps=$(apps_of "$home")
[[ -f "$apps/Steam Big Picture.desktop" ]] || fail "Steam on a laptop installs Steam Big Picture"
[[ -f "$apps/Desktop Mode.desktop" ]] || fail "Steam on a laptop installs Desktop Mode"
[[ ! -e "$apps/Gaming Setup.desktop" ]] || fail "Steam on a laptop does not install the Ally Gaming Setup shortcut"
installed=$(wc -l < "$db")
(( installed > 0 )) || fail "Steam on a laptop installs launchers once"
run_migration "$home" "$laptop_vendor" "$laptop_product" "$laptop_board"
[[ $(wc -l < "$db") == "$installed" ]] || fail "a second run does not rewrite existing launchers"
pass "Steam on a laptop installs only the Steam launchers, once"

without_steam
home=$work/ally
run_migration "$home" "ASUSTeK COMPUTER INC." "ROG Ally RC71L" "RC71L"
apps=$(apps_of "$home")
[[ -f "$apps/Gaming Setup.desktop" ]] || fail "an Ally without Steam still gets Gaming Setup"
[[ ! -e "$apps/Steam Big Picture.desktop" && ! -e "$apps/Desktop Mode.desktop" ]] || fail "an Ally without Steam does not get Steam launchers"
pass "an Ally without Steam gets only Gaming Setup"

with_steam
home=$work/ally-keep
apps=$(apps_of "$home")
mkdir -p "$apps"
printf 'custom launcher\n' > "$apps/Gaming Setup.desktop"
run_migration "$home" "ASUSTeK COMPUTER INC." "ROG Ally RC71L" "RC71L"
[[ $(<"$apps/Gaming Setup.desktop") == "custom launcher" ]] || fail "an existing Gaming Setup entry is preserved"
[[ -f "$apps/Steam Big Picture.desktop" && -f "$apps/Desktop Mode.desktop" ]] || fail "an Ally with Steam still gets the Steam launchers"
pass "an existing launcher is preserved"
