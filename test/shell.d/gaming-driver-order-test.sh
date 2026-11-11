#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
launcher_dir="$test_home/Games/battlenet/drive_c/Program Files (x86)/Battle.net"
mkdir -p "$stub_bin" "$launcher_dir"
# An existing launcher avoids the download and partial-prefix prompt.
touch "$launcher_dir/Battle.net Launcher.exe"

cat >"$stub_bin/omarchy-install-gaming-gpu-lib32" <<'SH'
#!/bin/bash
printf 'drivers\n' >>"$OMARCHY_TEST_CALLS"
exit "${OMARCHY_TEST_DRIVER_STATUS:-0}"
SH

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'packages %s\n' "$*" >>"$OMARCHY_TEST_CALLS"
SH

# Never change system files, launch a game, or update the host's desktop cache.
for command in sudo setsid update-desktop-database omarchy-hw-x86; do
  printf '#!/bin/bash\nexit 0\n' >"$stub_bin/$command"
done
# Unexpected download or prefix-recovery paths must not reach the host.
for command in curl pkill umu-run; do
  printf '#!/bin/bash\nexit 99\n' >"$stub_bin/$command"
done
chmod +x "$stub_bin"/*

run_installer() {
  local installer="$1" driver_status="$2"

  shift 2
  : >"$test_tmp/calls"
  HOME="$test_home" OMARCHY_PATH="$ROOT" PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_CALLS="$test_tmp/calls" OMARCHY_TEST_DRIVER_STATUS="$driver_status" \
    bash "$ROOT/bin/$installer" "$@" >"$test_tmp/output" 2>&1
}

for installer in omarchy-install-gaming-lutris omarchy-install-gaming-battlenet omarchy-install-gaming-tools; do
  args=()
  [[ $installer != "omarchy-install-gaming-tools" ]] || args=(compatibility)
  run_installer "$installer" 0 "${args[@]}" || fail "$installer completes with stubbed dependencies" "$(<"$test_tmp/output")"
  mapfile -t calls <"$test_tmp/calls"
  [[ ${calls[0]:-} == "drivers" && ${calls[1]:-} == "packages "* ]] ||
    fail "$installer installs GPU libraries before umu-launcher dependencies" "$(<"$test_tmp/calls")"
  pass "$installer installs GPU libraries before umu-launcher dependencies"

  if run_installer "$installer" 23 "${args[@]}"; then
    fail "$installer stops when GPU library installation fails"
  else
    status=$?
  fi
  (( status == 23 )) || fail "$installer preserves the GPU library failure status" "$status"
  [[ $(<"$test_tmp/calls") == "drivers" ]] ||
    fail "$installer installs no dependencies after GPU library failure" "$(<"$test_tmp/calls")"
  pass "$installer stops before dependency installation when GPU library installation fails"
done

# Real central hardware predicate: an RC71L must not acquire a second power
# writer through the optional GameMode route.
printf 'ASUSTeK COMPUTER INC.\n' >"$test_tmp/vendor"
printf 'ROG Ally RC71L_RC71L\n' >"$test_tmp/product"
printf 'RC71L\n' >"$test_tmp/board"
: >"$test_tmp/calls"
if HOME="$test_home" OMARCHY_PATH="$ROOT" PATH="$stub_bin:$ROOT/bin:$PATH" \
  OMARCHY_TEST_CALLS="$test_tmp/calls" \
  OMARCHY_DMI_SYS_VENDOR_PATH="$test_tmp/vendor" \
  OMARCHY_DMI_PRODUCT_NAME_PATH="$test_tmp/product" \
  OMARCHY_DMI_BOARD_NAME_PATH="$test_tmp/board" \
  "$ROOT/bin/omarchy-install-gaming-tools" gamemode >"$test_tmp/output" 2>&1; then
  fail "GameMode installation rejects RC71L"
fi
[[ ! -s $test_tmp/calls ]] || fail "RC71L refusal happens before installing any packages"
pass "RC71L cannot install a competing power writer via optional GameMode setup"

cat >"$stub_bin/flatpak" <<'STUB'
#!/bin/bash
printf 'flatpak %s\n' "$*" >>"$OMARCHY_TEST_CALLS"
if [[ $1 == info ]]; then
  [[ $2 == "${TEST_FLATPAK_SCOPE:-missing}" ]]
fi
STUB
chmod +x "$stub_bin/flatpak"
TEST_FLATPAK_SCOPE=--system run_installer omarchy-install-gaming-tools 0 protonplus
if grep -q 'flatpak install\|flatpak remote-add' "$test_tmp/calls"; then
  fail "existing system ProtonPlus is reused without creating another install"
fi
pass "ProtonPlus preserves an existing system Flatpak installation"
run_installer omarchy-install-gaming-tools 0 sunshine
grep -q '^flatpak install --user --noninteractive flathub dev.lizardbyte.app.Sunshine$' "$test_tmp/calls" ||
  fail "new Sunshine installs only for the current user" "$(<"$test_tmp/calls")"
if grep -q 'flatpak run\|systemctl\|sudo' "$test_tmp/calls"; then
  fail "Sunshine package delivery must not run privileged host setup or enable services"
fi
pass "Sunshine delivery installs the app without privileged host integration"
