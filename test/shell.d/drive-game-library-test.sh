#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Catches unsafe selection of internal/system disks, shell-splitting of a
# mount path, mistaken readiness on noexec/Windows filesystems and lost
# cancellation/backend errors. No block device or real mount is touched.
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export HOME="$scratch/home" STORAGE_FIXTURE="$scratch/devices.json" STORAGE_LOG="$scratch/calls"
export STORAGE_MENU="$scratch/menu" STORAGE_TARGET="$scratch/library with spaces"
mkdir -p "$HOME" "$scratch/bin" "$STORAGE_TARGET"
export PATH="$scratch/bin:$ROOT/bin:$PATH"
command="$ROOT/bin/omarchy-drive-game-library"

cat >"$scratch/bin/omarchy-hw-rog-ally" <<'STUB'
#!/bin/bash
exit "${HARDWARE_STATUS:-0}"
STUB
cat >"$scratch/bin/lsblk" <<'STUB'
#!/bin/bash
cat "$STORAGE_FIXTURE"
STUB
cat >"$scratch/bin/udisksctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$STORAGE_LOG"
exit "${UDISKS_STATUS:-0}"
STUB
cat >"$scratch/bin/findmnt" <<'STUB'
#!/bin/bash
jq -n --arg source "${STORAGE_SOURCE:-/dev/sdb1}" --arg target "$STORAGE_TARGET" \
  --arg options "${STORAGE_OPTIONS:-rw,relatime}" \
  '{filesystems:[{source:$source,target:$target,fstype:"ext4",options:$options}]}'
STUB
cat >"$scratch/bin/omarchy-menu-select" <<'STUB'
#!/bin/bash
if [[ -s $STORAGE_MENU ]]; then
  head -1 "$STORAGE_MENU"
  sed -i '1d' "$STORAGE_MENU"
else
  exit "${MENU_STATUS:-1}"
fi
STUB
chmod +x "$scratch/bin/"*

fixture() {
  cat >"$STORAGE_FIXTURE" <<'JSON'
{"blockdevices":[
  {"path":"/dev/nvme0n1","type":"disk","rm":false,"tran":"nvme","mountpoints":[],"children":[
    {"path":"/dev/nvme0n1p1","type":"part","fstype":"ext4","mountpoints":[null]}]},
  {"path":"/dev/mmcblk0","type":"disk","rm":true,"tran":null,"mountpoints":[],"children":[
    {"path":"/dev/mmcblk0p1","type":"part","fstype":"vfat","mountpoints":["/boot"]},
    {"path":"/dev/mmcblk0p2","type":"part","fstype":"ext4","mountpoints":[null]}]},
  {"path":"/dev/sda","type":"disk","rm":true,"tran":"usb","mountpoints":[],"children":[
    {"path":"/dev/sda1","type":"part","fstype":"crypto_LUKS","mountpoints":[null],"children":[
      {"path":"/dev/mapper/root","type":"crypt","fstype":"btrfs","mountpoints":["/"]}]},
    {"path":"/dev/sda2","type":"part","fstype":"ext4","mountpoints":[null]}]},
  {"path":"/dev/sdb","type":"disk","rm":false,"tran":"usb","mountpoints":[],"children":[
    {"path":"/dev/sdb1","type":"part","fstype":"ext4","mountpoints":[null]}]},
  {"path":"/dev/sdc","type":"disk","rm":true,"tran":null,"mountpoints":[],"children":[
    {"path":"/dev/sdc1","type":"part","fstype":"exfat","mountpoints":[null]}]}
]}
JSON
  : >"$STORAGE_LOG"
  : >"$STORAGE_MENU"
}

run() {
  "$command" "$@" >"$scratch/output" 2>&1
}

fixture
HARDWARE_STATUS=1 run mount /dev/sdb1 && fail "unsupported hardware refuses storage mutation"
[[ ! -s $STORAGE_LOG ]] || fail "unsupported hardware does not call UDisks2"
pass "unsupported hardware refuses storage changes"

for device in /dev/nvme0n1p1 /dev/mmcblk0p2 /dev/sda2 /dev/sdb /dev/sdb1/../sda2 '--force'; do
  if run mount "$device"; then fail "unsafe device is refused: $device"; fi
done
[[ ! -s $STORAGE_LOG ]] || fail "refused disks never reach UDisks2"
pass "internal disks and all partitions on boot/system disks are refused"

run mount /dev/sdb1 || fail "a USB data partition mounts" "$(cat "$scratch/output")"
[[ $(cat "$STORAGE_LOG") == "mount --block-device /dev/sdb1" ]] || fail "only the selected partition is passed to UDisks2"
jq '(.blockdevices[] | select(.path == "/dev/sdb") | .children[0].mountpoints) = ["/run/media/USER/Games"]' "$STORAGE_FIXTURE" >"$scratch/next"
mv "$scratch/next" "$STORAGE_FIXTURE"
run mount /dev/sdb1 || fail "already mounted is harmless"
[[ $(wc -l <"$STORAGE_LOG") == "1" ]] || fail "mounting an already mounted partition calls no backend"
pass "USB SSDs are accepted and repeated mounts are harmless"

UDISKS_STATUS=7 run unmount /dev/sdb1 && fail "backend unmount errors propagate"
[[ $? == 7 ]] || fail "backend failure retains its exit status"
pass "a busy or unauthorised backend unmount fails visibly"

fixture
run check "$STORAGE_TARGET" || fail "mounted Linux directory passes software checks" "$(cat "$scratch/output")"
STORAGE_OPTIONS=rw,noexec run check "$STORAGE_TARGET" && fail "noexec fails readiness"
STORAGE_SOURCE=/dev/nvme0n1p1 run check "$STORAGE_TARGET" && fail "internal library check is refused"
STORAGE_SOURCE=/dev/sdc1 run check "$STORAGE_TARGET" && fail "exFAT is not advertised as a working Proton library"
[[ ! -s $STORAGE_LOG ]] || fail "checking libraries never mounts or changes permissions"
pass "readiness handles spaces and rejects noexec, internal and unsuitable Proton filesystems"

printf '/dev/sdb1\tLinux data\nMount\n' >"$STORAGE_MENU"
run --menu || fail "menu routes an existing partition to mount" "$(cat "$scratch/output")"
[[ $(cat "$STORAGE_LOG") == "mount --block-device /dev/sdb1" ]] || fail "picker mount routes the selected device"
: >"$STORAGE_LOG"
run --menu || fail "cancelled picker succeeds"
MENU_STATUS=2 run --menu && fail "unavailable menu is not cancellation"
[[ $? == 2 && ! -s $STORAGE_LOG ]] || fail "menu errors propagate without mutations"
pass "storage picker dispatches selected devices, accepts cancellation and retains errors"
