#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export HOME="$test_tmp/home" PATH="$test_tmp/bin:$ROOT/bin:$PATH"
mkdir -p "$test_tmp/bin" "$HOME"
# External package/session boundaries only; file operations remain real.
for command in omarchy-pkg-add omarchy-pkg-drop omarchy-lifecycle-dispatch setsid update-desktop-database; do
  printf '#!/bin/bash\nexit 0\n' >"$test_tmp/bin/$command"
done
# Removal must never kill game processes or prompt to delete shared runtimes.
for command in pkill gum; do
  printf '#!/bin/bash\nexit 97\n' >"$test_tmp/bin/$command"
done
chmod +x "$test_tmp/bin/"*

paths=(
  '.local/share/Steam/steamapps/compatdata/123/pfx/save'
  '.local/share/Steam/compatibilitytools.d/GE-Proton/test'
  '.steam/steam/config/libraryfolders.vdf'
  '.config/heroic/config.json' 'Games/Heroic/save'
  '.local/share/lutris/runners/test' '.wine/user.reg'
  '.local/share/umu/test' '.cache/umu/test'
  'Games/battlenet/drive_c/game/save' '.config/retroarch/retroarch.cfg'
  '.config/retroarch/config/global.slangp' '.config/retroarch/saves/test.srm'
  'Games/roms/test' 'Games/bios/test' '.config/Moonlight Game Streaming Project/test'
)
for path in "${paths[@]}"; do
  mkdir -p "$(dirname "$HOME/$path")"
  printf 'preserved %s\n' "$path" >"$HOME/$path"
done
for app in steam heroic lutris battlenet retroarch moonlight; do
  "$ROOT/bin/omarchy-remove-gaming-$app" >"$test_tmp/output" 2>&1 ||
    fail "$app removal succeeds" "$(<"$test_tmp/output")"
done
for path in "${paths[@]}"; do
  [[ -f $HOME/$path && $(<"$HOME/$path") == "preserved $path" ]] ||
    fail "launcher removal preserves $path"
done
pass "launcher removals preserve libraries, saves, prefixes, settings and shared runtimes"

"$ROOT/bin/omarchy-install-gaming-retroarch" >"$test_tmp/output" 2>&1
[[ $(<"$HOME/.config/retroarch/retroarch.cfg") == 'preserved .config/retroarch/retroarch.cfg' ]] ||
  fail "RetroArch reinstall preserves existing save and core paths"
[[ $(<"$HOME/.config/retroarch/config/global.slangp") == 'preserved .config/retroarch/config/global.slangp' ]] ||
  fail "RetroArch reinstall preserves custom shaders"
pass "RetroArch reinstall preserves existing configuration and shaders"

rm "$HOME/.config/retroarch/retroarch.cfg"
"$ROOT/bin/omarchy-install-gaming-retroarch" >"$test_tmp/output" 2>&1
grep -q '^libretro_directory = "/usr/lib/libretro"$' "$HOME/.config/retroarch/retroarch.cfg" ||
  fail "fresh RetroArch installation still seeds core paths"
[[ $(<"$HOME/.config/retroarch/config/global.slangp") == 'preserved .config/retroarch/config/global.slangp' ]] ||
  fail "fresh RetroArch config preserves a pre-existing global shader"
pass "fresh RetroArch installation seeds defaults without replacing custom shaders"
