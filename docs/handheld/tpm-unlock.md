# TPM2 disk unlock

Status: runbook, 16 November 2026. Device it was read from: ASUS ROG Ally RC71L. You run this yourself, on a machine that is already installed and already encrypted. Nothing here enrols a slot for you, and the passphrase is typed at a prompt on that machine. It is not written into a file.

The handheld install choice that should do this for a new install is [tpm-unlock-installer-spec.md](tpm-unlock-installer-spec.md). This page is the same outcome, done by hand, because the packaged hook line is still the busybox `encrypt` hook.

Two choices:

| | Option 1. Unlock automatically | Option 2. TPM2 + PIN |
|---|---|---|
| Enrolment | `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7` | The same command, plus `--tpm2-with-pin=yes` |
| What you type at each later boot | Nothing, when PCR 7 matches | A PIN |
| Keyboard-free on this Ally today | Yes, after the first reboot has been proven with a keyboard nearby | No. The PIN prompt is Plymouth, which has no keypad. Touch needs more work ([L68](alpha-followups.md)). The built-in pad does not type |

Both choices keep the existing passphrase slot. Do not pass `--wipe-slot=password`.

PCR 7 only. Do not bind PCR 0, and do not bind PCR 11. The reasons are in [Security, in plain words](#security-in-plain-words).

## What this Ally is doing today

Read on 16 November 2026. Yours is the same shape when the commands below print the same kinds of lines. The ids are different; the commands print them.

- The disk is LUKS2. One passphrase slot, no token. `/etc/crypttab` is comments only, so nothing in it unlocks the disk.
- The image that actually boots is built from `/etc/mkinitcpio.conf.d/00-omarchy-hooks.conf`, the busybox line (`udev`, `plymouth`, `encrypt`, `btrfs-overlayfs`). `/etc/mkinitcpio.conf` still has an old systemd line, without `plymouth` and without `sd-encrypt`. That line is not the image. `00-omarchy-hooks.conf` assigns `HOOKS` again on every build. `omarchy_resume.conf` then does `HOOKS+=(resume)`.
- `btrfs-overlayfs` is a busybox late hook (`run_latehook` only). A systemd initramfs does not run it, so a read-only snapshot boot from the new UKI would not mount the overlay. `limine-mkinitcpio-hook` ships `sd-btrfs-overlayfs` instead. That hook installs `overlayfs-setup.service` and requires the `systemd` hook. The zz line uses `sd-btrfs-overlayfs`.
- The busybox `encrypt` hook unlocks through `cryptdevice=`. It does not read `rd.luks.*`, and it does not use a TPM token. `sd-encrypt` is the hook that does. It cannot parse `cryptdevice=`.
- Both parameters are already on the cmdline. They live in `/etc/default/limine` (`KERNEL_CMDLINE[default]+=...`). Limine writes `/boot/limine.conf` from that. Do not edit `/boot/limine.conf`.
- The boot file is a UKI under `/boot/EFI/Linux/`. There is no loose `/boot/*.img` to rebuild. `sudo limine-update` rebuilds the UKI.
- `tpm2-tss` is already installed. `tpm2-tools` is not required.
- Secure Boot is off (`bootctl status` prints `Secure Boot: disabled`). `/dev/tpm0` and `/dev/tpmrm0` are present. `systemd-cryptenroll --tpm2-device=list` names `/dev/tpmrm0`.
- Plymouth's theme is `omarchy`. The script draws passphrase bullets and has no keys (`default/plymouth/omarchy.script`).

`00-omarchy-hooks.conf` is a packaged file. An update overwrites an edit there. The change that survives is a later drop-in, `/etc/mkinitcpio.conf.d/zz-tpm-sd-encrypt.conf`, which assigns `HOOKS` again after `omarchy_resume.conf`. The installer should not leave a machine on that override forever. That is the installer spec, not this page.

## Before you start

A USB or 2.4 GHz keyboard is required for this sitting. It works at the passphrase prompt: on the omarchy kernel, `usbhid`, `hid-generic`, `atkbd` and `xhci` are built in, so they do not have to be listed in `MODULES`. Bluetooth does not type the passphrase. The touchscreen and the built-in pad do not type it either. If the new image fails, that keyboard is how you open Limine (the menu waits 1 second: `timeout: 1` in `default/limine/limine.conf`) and how you type the passphrase.

Do not pass `-h` or `--help` to `limine-update` or `limine-mkinitcpio`. On this machine those flags start a UKI rebuild. They do not print help.

Run the blocks in order, in one shell, from a terminal on the Ally. Stop at the first check that does not match. The disk still unlocks with the passphrase until you reboot into a broken image.

## 1. Read the current state

```bash
findmnt -no SOURCE,FSTYPE,UUID,FSROOT /
sudo cryptsetup luksDump "$(sudo cryptsetup status "$(basename "$(findmnt -no SOURCE --nofsroot /)")" | awk '/^[[:space:]]+device:/ { print $2; exit }')"
systemd-cryptenroll --tpm2-device=list
echo "--- hooks ---"
grep -n '^HOOKS' /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d/*.conf
echo "--- cmdline sources ---"
grep -nE 'cryptdevice=|rd\.luks\.' /etc/default/limine
echo "--- live cmdline ---"
cat /proc/cmdline
echo "--- crypttab (live lines only) ---"
sudo grep -nE '^[[:space:]]*[^#[:space:]]' /etc/crypttab || echo "no live crypttab entries"
bootctl status
```

Set the device you are about to change. This prints the mapper name, the disk path, and the LUKS UUID. Use those. Do not copy an id out of this document.

```bash
ROOT_SRC=$(findmnt -no SOURCE --nofsroot /)
MAPPER_NAME=$(basename "$ROOT_SRC")
LUKS_DEV=$(sudo cryptsetup status "$MAPPER_NAME" | awk '/^[[:space:]]+device:/ { print $2; exit }')
LUKS_UUID=$(sudo cryptsetup luksUUID "$LUKS_DEV")
printf 'mapper=%s\ndevice=%s\nuuid=%s\n' "$MAPPER_NAME" "$LUKS_DEV" "$LUKS_UUID"
```

Stop if any of these is true:

- `LUKS_DEV` or `LUKS_UUID` is empty, or `luksDump` does not say version 2. `systemd-cryptenroll` only writes a LUKS2 token.
- `luksDump` shows no enabled keyslot. There is nothing to fall back to.
- `systemd-cryptenroll --tpm2-device=list` prints no device.
- A live line in `/etc/crypttab` names this volume. This runbook does not edit a live crypttab. Comments only is the line this Ally is on, and that file stays as it is.
- `cryptdevice=` or `rd.luks.` shows up in a file other than `/etc/default/limine`. Look with `grep -nE 'cryptdevice=|rd\.luks\.' /etc/limine-entry-tool.d/*.conf /usr/share/limine-entry-tool.d/*.conf`. Leave `omarchy-defaults.conf`, `resume.conf` and `rtc-alarm.conf` alone. They add splash, `resume=` and the RTC alarm. They are not where `cryptdevice=` is edited.
- `/etc/vconsole.conf` sets `XKBLAYOUT` to a layout that does not type Latin letters (`af`, `am`, `ara`, `bd`, `bg`, `by`, `et`, `ge`, `gr`, `il`, `in`, `iq`, `ir`, `kg`, `kh`, `kz`, `la`, `lk`, `mk`, `mm`, `mn`, `mv`, `np`, `rs`, `ru`, `sy`, `th`, `tj`, `ua`). `omarchy_hooks.conf` leaves that layout out of `FILES`, and `omarchy_vconsole.conf` refuses the copy in `add_file`, because the passphrase you know would not be typeable. Switching on `sd-vconsole` must not undo that. Stop and keep the current image.
- `/usr/lib/initcpio/install/sd-btrfs-overlayfs` is missing. Do not switch hooks without it. The busybox `btrfs-overlayfs` hook is not a substitute.

`bootctl status` prints `Secure Boot: enabled` or `Secure Boot: disabled`. This Ally prints disabled. PCR 7 is still the register either way. The difference is what that register is worth, and it is spelled out below.

The hook line that matters is the one in `00-omarchy-hooks.conf`, plus `HOOKS+=(resume)` from `omarchy_resume.conf` when that file exists. The `HOOKS=` line in `/etc/mkinitcpio.conf` is not the image, even when it already says `systemd`.

## 2. Take a snapshot

Snapper's config on an Omarchy install is `root` (`install/config/snapper.sh`). `limine-snapper-sync` adds a Limine entry for it. That entry does not boot the UKI you are about to build. It boots the UKI archived for that snapshot under `limine_history` on the ESP, with the cmdline saved beside it. After this change those entries still have `cryptdevice=` and do not have `tpm2-device=auto`. They are the busybox `encrypt` image, and the passphrase still opens them.

Booting that entry mounts the snapshot read-only. Writes go to a tmpfs overlay and are gone at the next reboot. Editing `/etc` there, or running `limine-update` there, does not change the real root, and the next kernel update rebuilds whatever the real root still has. The snapshot is how you get in. The repair that lasts is the USB path in section 13.

```bash
sudo snapper -c root create --description "before TPM unlock"
sudo snapper -c root list
sudo grep -n 'limine_history\|Snapshots' /boot/limine.conf
sudo find /boot -path '*limine_history*' \( -name '*.efi' -o -name '*.EFI' \) -print
```

Stop if the create fails, if the new snapshot is not listed, or if `find` prints no archived UKI. On the checked Ally, `limine-snapper-sync` wrote the entry as soon as the snapshot existed. Do not change hooks or the cmdline without both the snapper row and the Limine entry.

A snapper snapshot does not copy the LUKS header. Enrolment rewrites that header. Back it up onto removable media before you enrol, and not onto this disk. Plug in a USB stick and mount it yourself. The example mount point is `/mnt/header-backup`.

```bash
backup_dir=/mnt/header-backup
src=$(findmnt -T "$backup_dir" -no SOURCE)
root_src=$(findmnt -no SOURCE --nofsroot /)
if [[ -z $src || $src == "$root_src" || $src == /dev/mapper/* ]]; then
  echo "stop: put the header backup on removable media, not this disk"
else
  backup=$backup_dir/luks-header-$(date +%Y%m%d).img
  sudo cryptsetup luksHeaderBackup "$LUKS_DEV" --header-backup-file "$backup"
  if sudo test -s "$backup"; then
    echo "header backup is non-empty: $backup"
  else
    echo "stop: header backup is missing or empty"
  fi
fi
```

Stop unless that last line says the file is non-empty. The file plus the passphrase from this moment opens the disk. Keep it the way you keep the passphrase. Do not copy it back onto the Ally. `luksHeaderRestore` in section 13 puts this header back. Do not enrol if you no longer have the file.

Opening the menu takes a key during the 1 second timeout, so the USB or 2.4 GHz keyboard has to be plugged in before you reboot. Limine's editor is on: `default/limine/limine.conf` does not set `editor_enabled: no`, and Limine's default is yes. That matters for what PCR 7 does and does not protect, in the security section. It does not change these steps.

## 3. tpm2-tss

`systemd-cryptenroll` needs the library. On this Ally the package is already installed. The command installs it only when it is missing.

```bash
pacman -Q tpm2-tss
omarchy-pkg-add tpm2-tss
```

## 4. Switch the hooks

Do this when the built image uses `encrypt` and not `sd-encrypt`, which is the stock line in `etc/mkinitcpio.conf.d/00-omarchy-hooks.conf`. If a UKI you already boot contains the `systemd` and `sd-encrypt` hooks, skip this section and go to the cmdline.

The systemd overlay hook has to be on disk before the drop-in is written. `limine-mkinitcpio-hook` ships it. Stop if this prints nothing:

```bash
[[ -f /usr/lib/initcpio/install/sd-btrfs-overlayfs ]] && echo "sd-btrfs-overlayfs present"
```

`/usr/lib/initcpio/install/btrfs-overlayfs` only adds a runscript, and `/usr/lib/initcpio/hooks/btrfs-overlayfs` only defines `run_latehook`. That is how a busybox initramfs mounts the overlay for a read-only snapshot. A systemd initramfs does not run late hooks, so leaving `btrfs-overlayfs` on the line would build an image whose snapshot boot does not set the overlay up. `sd-btrfs-overlayfs` installs `/usr/lib/limine/overlayfs-setup` and `overlayfs-setup.service`, and it refuses the build when the `systemd` hook is absent.

Read the other drop-ins before writing. They sort before `zz-`:

```bash
grep -nE 'HOOKS|FILES|MODULES|kms|add_file' /etc/mkinitcpio.conf.d/*.conf
```

- `omarchy_hooks.conf` strips `kms` only when `MODULES` contains `nvidia_drm` and every display controller is NVIDIA. An Ally is not that machine (`MODULES` is empty), so the `kms` in the line below stays. The same file adds `/etc/vconsole.conf` to `FILES` for a Latin layout. `FILES` is not `HOOKS`. Assigning `HOOKS` does not clear it.
- `omarchy_vconsole.conf` wraps `add_file` so a non-Latin layout is not copied in. It does not assign `HOOKS`. `sd-vconsole` still goes through that wrap. On this Ally `vconsole.conf` is a US keymap, so the file is included.
- `omarchy_resume.conf` does `HOOKS+=(resume)`. The assignment below replaces the array, so that append is dropped. That is intentional: the systemd hook ships `systemd-hibernate-resume` and reads `resume=` and `resume_offset=` from the cmdline. Leave `/etc/limine-entry-tool.d/resume.conf` in place so those parameters stay.
- `omarchy_compression.conf` sets the compressor. A thunderbolt drop-in may append to `MODULES`. Neither changes the hook line you are about to check.

Write a drop-in that sorts after `00-omarchy-hooks.conf` and after `omarchy_resume.conf`.

`systemd` replaces `udev`. `sd-vconsole` replaces `keymap` and `consolefont`. `sd-encrypt` replaces `encrypt`. `plymouth` and `kms` stay. `sd-btrfs-overlayfs` replaces `btrfs-overlayfs`.

```bash
sudo tee /etc/mkinitcpio.conf.d/zz-tpm-sd-encrypt.conf >/dev/null <<'EOF'
# Handheld TPM unlock. Sorts after 00-omarchy-hooks.conf and
# omarchy_resume.conf, so this assignment is the one mkinitcpio builds.
# systemd reads resume= from the cmdline; the busybox resume hook is not
# copied here. sd-btrfs-overlayfs replaces btrfs-overlayfs: the busybox
# hook is run_latehook only and does not run in this image.
# Do not edit 00-omarchy-hooks.conf: a settings update overwrites it.
HOOKS=(base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck sd-btrfs-overlayfs)
EOF
```

Print the line mkinitcpio will actually use. `00-omarchy-hooks.conf` runs `omarchy-hw-platform`, so this has to run on the Ally, not in a copy of the file.

```bash
sudo bash -c '
set -euo pipefail
HOOKS=()
MODULES=()
FILES=()
shopt -s nullglob
[[ -f /etc/mkinitcpio.conf ]] && source /etc/mkinitcpio.conf
for f in /etc/mkinitcpio.conf.d/*.conf; do
  source "$f"
done
printf "%s\n" "${HOOKS[*]}"
'
```

Stop, and delete `zz-tpm-sd-encrypt.conf`, unless that line is exactly:

```text
base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck sd-btrfs-overlayfs
```

`resume`, `udev`, `keymap`, `consolefont` or `btrfs-overlayfs` (the busybox name, not `sd-btrfs-overlayfs`) in that line means another file assigned `HOOKS` after `zz-tpm-sd-encrypt.conf`. Do not rebuild.

## 5. Edit `/etc/default/limine`

Drop `cryptdevice=...`. Keep `rd.luks.name=<luks-uuid>=root`. Append `,tpm2-device=auto` to the existing `rd.luks.options=<luks-uuid>=...` value. Do not add a second, bare `rd.luks.options=tpm2-device=auto`. Do not edit `/boot/limine.conf`, `/proc/cmdline`, or the files in `/etc/limine-entry-tool.d/`.

On this Ally the `cryptdevice=` value is a PARTUUID with trailing options (`:root:allow-discards,no-read-workqueue`), and `rd.luks.options=` is already `<luks-uuid>=discard,no-read-workqueue`. The script below removes whatever `cryptdevice=` token is on the line and appends the TPM option to the `rd.luks.options=` token that is already there. A line that does not mention `cryptdevice=` or `rd.luks.` is left alone, so a splash line in the same file would stay. A missing `rd.luks.options=` becomes `rd.luks.options=<luks-uuid>=tpm2-device=auto`.

`LUKS_UUID` is the variable from section 1.

```bash
sudo cp -a /etc/default/limine /etc/default/limine.pre-tpm2
sudo cat /etc/default/limine > /tmp/limine.default.in

rewrite_limine_default() {
  local file=$1 uuid=$2
  local line op value param key params=() out=() saw_opt quoted
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ ^[[:space:]]*KERNEL_CMDLINE\[default\][[:space:]]*(\+?)=[[:space:]]*(.*)$ ]]; then
      op=${BASH_REMATCH[1]}
      value=${BASH_REMATCH[2]}
      quoted=0
      if [[ $value == \"*\" && $value == *\" ]]; then
        quoted=1
        value=${value:1:${#value}-2}
      fi
      if [[ $value != *cryptdevice=* && $value != *rd.luks.options=* && $value != *rd.luks.name=* ]]; then
        out+=("$line")
        continue
      fi
      params=()
      saw_opt=0
      for param in $value; do
        key=${param%%=*}
        case $key in
          cryptdevice) continue ;;
          rd.luks.options)
            if [[ $param != *tpm2-device=auto* ]]; then
              param="${param},tpm2-device=auto"
            fi
            saw_opt=1
            ;;
        esac
        params+=("$param")
      done
      if ((saw_opt == 0)); then
        params+=("rd.luks.options=${uuid}=tpm2-device=auto")
      fi
      if ((quoted)); then
        out+=("KERNEL_CMDLINE[default]${op}=\"${params[*]}\"")
      else
        out+=("KERNEL_CMDLINE[default]${op}=${params[*]}")
      fi
    else
      out+=("$line")
    fi
  done <"$file"
  printf '%s\n' "${out[@]}"
}

rewrite_limine_default /tmp/limine.default.in "$LUKS_UUID" | sudo tee /etc/default/limine.new >/dev/null
sudo diff -u /etc/default/limine /etc/default/limine.new || true
rm -f /tmp/limine.default.in
```

Read the diff. The new line still has `root=/dev/mapper/root` (or whatever `root=` was), `rd.luks.name=<luks-uuid>=<mapper>`, and `rd.luks.options=<luks-uuid>=...,tpm2-device=auto`. It has no `cryptdevice=`. `resume=` is not in this file; it stays in `resume.conf`.

Install it only when every check passes. A failed check prints `stop` and does not copy the file. It does not exit the shell, so `LUKS_DEV` and `LUKS_UUID` stay set.

```bash
if sudo grep -q 'cryptdevice=' /etc/default/limine.new \
  || ! sudo grep -q 'tpm2-device=auto' /etc/default/limine.new \
  || ! sudo grep -q 'root=' /etc/default/limine.new \
  || ! sudo grep -q "rd.luks.name=${LUKS_UUID}=" /etc/default/limine.new
then
  echo "stop: /etc/default/limine.new is not the cmdline this runbook will install"
else
  sudo cp -a /etc/default/limine.new /etc/default/limine
fi
```

The shape, with your own ids filled in by the script, is:

```text
KERNEL_CMDLINE[default]+="root=/dev/mapper/root zswap.enabled=0 rootflags=subvol=@ rw rootfstype=btrfs rd.luks.name=<luks-uuid>=root rd.luks.options=<luks-uuid>=discard,no-read-workqueue,tpm2-device=auto systemd.tty.term.console=dumb"
```

## 6. Rebuild

`limine-update` rebuilds the UKI and rewrites the Limine entries. There is no loose initramfs image under `/boot` to pass to `mkinitcpio -P`.

Do not add `-h`. Do not add `--help`.

```bash
sudo limine-update
```

`limine-mkinitcpio` also rebuilds the UKI. Do not run it with `-h` either. This runbook uses `limine-update` only.

## 7. Verify the UKI before you enrol

Enrolment writes the LUKS header. A bad image should be caught before that, while the header is still passphrase-only.

```bash
UKI=$(ls -1t /boot/EFI/Linux/omarchy_linux*.efi | head -n 1)
printf 'uki=%s\n' "$UKI"
ls -l "$UKI"
echo "--- cmdline in the UKI ---"
sudo objcopy -O binary --only-section=.cmdline "$UKI" /dev/stdout | tr -d '\0'
echo
echo "--- generated limine.conf ---"
sudo grep -nE 'cryptdevice=|tpm2-device=|rd\.luks\.' /boot/limine.conf
```

The UKI cmdline and the default entry in `/boot/limine.conf` must contain `tpm2-device=auto`, `rd.luks.name=<luks-uuid>=` and `root=`. They must not contain `cryptdevice=`. Snapshot entries still contain `cryptdevice=`. That is the rollback, not a failed edit.

```bash
cmdline=$(sudo objcopy -O binary --only-section=.cmdline "$UKI" /dev/stdout | tr -d '\0'; echo)
printf '%s\n' "$cmdline"
if [[ $cmdline == *cryptdevice=* || $cmdline != *tpm2-device=auto* || $cmdline != *root=* ]]; then
  echo "stop: the UKI cmdline is missing root= or tpm2-device=auto, or it still has cryptdevice="
fi
```

Then the initrd inside the UKI. `ukify inspect` prints the sections when `ukify` is installed (`systemd-ukify`). It was not required on this Ally. Extracting `.initrd` uses `objcopy`, which is already there. Either one is enough; do both when `ukify` is present.

```bash
if command -v ukify >/dev/null; then
  sudo ukify inspect "$UKI"
fi
sudo objcopy -O binary --only-section=.initrd "$UKI" /tmp/omarchy-uki.initrd
sudo lsinitcpio -a /tmp/omarchy-uki.initrd
sudo lsinitcpio /tmp/omarchy-uki.initrd | grep -E 'libtss2|systemd-cryptsetup|plymouth|overlayfs-setup.service' || true
sudo rm -f /tmp/omarchy-uki.initrd
```

Stop if the `Hooks:` line from `lsinitcpio -a` does not contain `systemd`, `plymouth`, `sd-encrypt` and `sd-btrfs-overlayfs`. Stop if it contains `udev` or `resume`, or a hook that is the word `encrypt` rather than `sd-encrypt`, or `btrfs-overlayfs` without the `sd-` prefix. Stop if `libtss2` is missing: the TPM token cannot be read. Stop if `overlayfs-setup.service` is missing: snapshot boot will not mount the overlay. On the checked Ally that unit was in the initrd, with `/usr/lib/limine/overlayfs-setup`. Restore the backup and rebuild before you reboot:

```bash
sudo cp -a /etc/default/limine.pre-tpm2 /etc/default/limine
sudo rm -f /etc/mkinitcpio.conf.d/zz-tpm-sd-encrypt.conf
sudo limine-update
```

## 8. Option 1. Enrol, no PIN

Do not run this unless section 2's header file is still on the removable drive and non-empty. Do not run it while `/var/lib/omarchy/provisioning/luks-rekey.state` exists. `luks_rekey_retire` in `install/provisioning/luks-rekey.sh` kills every keyslot except the recorded owner slot, and `luks_dump_slots` lists a `systemd-tpm2` slot as an ordinary `luks2` slot. A rekey that runs after this enrolment deletes the TPM slot, and `luks_rekey_verify` fails while any other slot remains. Finish provisioning first, or leave this machine unenrolled. That gap is [L70](alpha-followups.md). It blocks the installer. It is already the reason this runbook refuses an open rekey journal.

The command asks for the existing passphrase. Type it. Do not put it on the command line, in the shell history, or in a file.

This adds a TPM slot bound to PCR 7. It does not remove the passphrase slot.

```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 "$LUKS_DEV"
```

`--tpm2-pcrs=7` is required. From systemd 258 the default PCR mask is empty, so omitting the option binds no PCR at all ([systemd v258 NEWS](https://github.com/systemd/systemd/releases/tag/v258)). Earlier `systemd-cryptenroll` bound the current literal value of PCR 7 when the option was left off. The systemd on this Ally is 262, which has the empty default. PCR 7 is the Secure Boot policy register. Binding nothing is not what this runbook does.

Go to section 10. Do not also run option 2.

## 9. Option 2. Enrol with a PIN

Same hooks, same cmdline, same PCR. The PIN is a second secret mixed into the TPM policy. It is not a replacement for the passphrase slot.

Not keyboard-free today. At boot, `systemd-cryptsetup` asks for the PIN through `systemd-ask-password`. The agents in this initramfs are Plymouth and the console agent. Plymouth's `omarchy` theme draws bullets (`display_password_callback` in `default/plymouth/omarchy.script`) and has no keypad. A USB or 2.4 GHz keyboard can type the PIN. The touchscreen and the pad cannot.

What is missing, and who builds it, is [L68](alpha-followups.md):

- Touch needs the `sd-unl0kr` hook from AUR `buffybox` (GPL-3.0-or-later; upstream [buffybox](https://gitlab.postmarketos.org/postmarketOS/buffybox), [AUR buffybox](https://aur.archlinux.org/packages/buffybox)). That hook is a systemd password agent, so it can answer this PIN prompt. The UKI on this Ally contains `hid-multitouch` and does not contain the I2C HID transport, and the panel is `hid-multitouch` on `i2c_hid_acpi`. The modules to add with the hook are `MODULES+=(i2c-hid i2c-hid-acpi hid-multitouch)`. `buffybox` is not installed by this runbook. Spec 03 has not accepted it for disk unlock.
- `osk-sdl` is not a path. It was removed from the AUR in 2025. postmarketOS moved off it ([Osk-sdl](https://wiki.postmarketos.org/wiki/Osk-sdl)).
- The pad cannot type in the initramfs. It is an XInput device (`xpad`, buttons as `BTN_*`, d-pad as `ABS_*`; [research/ally-hw-dump.md](research/ally-hw-dump.md)). `xpad` is not in the UKI. unl0kr's inputs are keyboard, mouse, trackpad and touch, not a gamepad. The N-KEY device (`hid-asus`) exposes function keys and chords, not digits. InputPlumber is not in the initramfs, so nothing there turns the pad into keys.

A wrong PIN counts toward the TPM's dictionary-attack lockout. That lockout is a property of the chip. `systemd-cryptenroll` does not configure it ([systemd-cryptenroll(1)](https://www.freedesktop.org/software/systemd/man/latest/systemd-cryptenroll.html)). The passphrase slot still works while the chip is locked out. The systemd on this Ally is 262, which accepts `--tpm2-with-pin=yes` and hardens that PIN with Argon2id. If your `systemctl --version` is older and rejects the flag, stop. Do not invent another flag.

```bash
systemctl --version | head -n 1
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes "$LUKS_DEV"
```

The command asks for the existing passphrase, then the PIN twice. If option 1 is already enrolled, do not add a second TPM slot. Replace it:

```bash
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes "$LUKS_DEV"
```

`--wipe-slot=tpm2` combined with an enrolment wipes the old TPM slots only after the new slot is written, and it does not wipe the new slot ([systemd-cryptenroll(1)](https://www.freedesktop.org/software/systemd/man/latest/systemd-cryptenroll.html)). It does not wipe a passphrase slot. Do not add `--wipe-slot=password`.

## 10. The token is there, and the passphrase slot is still there

```bash
sudo systemd-cryptenroll "$LUKS_DEV"
sudo cryptsetup luksDump "$LUKS_DEV"
```

`systemd-cryptenroll` with no enrolment flag lists slots. You want a `password` row and a `tpm2` row. `luksDump` shows a `systemd-tpm2` token and an enabled passphrase keyslot (a `luks2` slot with a PBKDF, the slot that was there before you started).

Stop if the password row is gone. Do not reboot. Put the passphrase slot back from your notes only if you still have the passphrase and `cryptsetup luksAddKey` is a step you already know; otherwise boot nothing new and use the snapshot path in section 13 after you restore the old image. A TPM-only header is not the outcome of this runbook.

## 11. Reboot

Plug in the keyboard first.

```bash
systemctl reboot
```

Option 1, PCR 7 matching: Plymouth shows the splash and does not ask for a passphrase. The session then autologins as it does today.

Option 2: Plymouth asks for the PIN. The keyboard types it.

The first boot after a hook change is the one that proves the passphrase still works if the TPM does not.

## 12. The TPM did not unlock

The passphrase prompt still appears, because the passphrase slot was kept. Plymouth is doing that with the bullets it already draws. Type the passphrase with the USB or 2.4 GHz keyboard. That keyboard does not depend on a module in the UKI: `usbhid`, `hid-generic`, `atkbd` and `xhci` are built into the omarchy kernel.

That prompt is expected when PCR 7 changed, and it is expected when the token is missing. It is not expected on every boot of option 1. If it appears on every boot, the UKI cmdline does not contain `tpm2-device=auto`, or the image is still the `encrypt` hook. Section 7 is how you look.

A later install will show two lines on that screen: that automatic unlock failed, and that a BIOS reset, a firmware update or a Secure Boot change can cause it. This runbook does not change the Plymouth theme. The words are in the installer spec.

After the session is up, re-enrol with section 14. The steps while you are stuck on the prompt, with no session yet, are also in [ALPHA.md](ALPHA.md) under "Handheld stuck at the passphrase prompt".

## 13. Roll back

From a booted system, with the passphrase:

```bash
ROOT_SRC=$(findmnt -no SOURCE --nofsroot /)
MAPPER_NAME=$(basename "$ROOT_SRC")
LUKS_DEV=$(sudo cryptsetup status "$MAPPER_NAME" | awk '/^[[:space:]]+device:/ { print $2; exit }')
sudo systemd-cryptenroll --wipe-slot=tpm2 "$LUKS_DEV"
sudo rm -f /etc/mkinitcpio.conf.d/zz-tpm-sd-encrypt.conf
sudo cp -a /etc/default/limine.pre-tpm2 /etc/default/limine
sudo limine-update
```

`--wipe-slot=tpm2` removes TPM slots only. The passphrase slot stays, so the disk still opens even before the old hooks are restored. Those three file commands only last when this system is the real root, not a snapshot boot.

If the header itself is damaged, put back the file from section 2. This replaces the whole header, including any TPM slot written after the backup. The passphrase from backup time opens the restored header. Type the confirmation cryptsetup asks for. Do not point `--header-backup-file` at a path on this disk.

```bash
sudo cryptsetup luksHeaderRestore "$LUKS_DEV" --header-backup-file "$backup"
```

If the new UKI will not boot, the Limine snapshot from section 2 gets you in and nothing more. Its UKI under `limine_history` still has `cryptdevice=` and no `tpm2-device=auto`, and the passphrase unlocks it. The root you land on is a read-only snapshot with writes in tmpfs. `rm` of the zz file, a restored `/etc/default/limine`, and `limine-update` run there are gone at the next reboot. The real `@` still has the new hook line, and the next kernel update rebuilds that UKI.

The repair that lasts is from an Arch or Omarchy live ISO. Find the locked partition with `lsblk -f` (`FSTYPE` `crypto_LUKS`) and the ESP (`vfat`, the EFI system partition). The passphrase is typed at `cryptsetup open`. SSH cannot reach this prompt.

```bash
sudo cryptsetup open "$LUKS_DEV" root
sudo mount -o subvol=@ /dev/mapper/root /mnt
sudo mount "$ESP" /mnt/boot
sudo rm -f /mnt/etc/mkinitcpio.conf.d/zz-tpm-sd-encrypt.conf
sudo cp -a /mnt/etc/default/limine.pre-tpm2 /mnt/etc/default/limine
sudo arch-chroot /mnt limine-update
```

`$ESP` is the EFI partition you found, not a guess. `/etc/default/limine.pre-tpm2` is the copy section 5 wrote on the real root. If that file is missing, do not invent a cmdline. Boot stays on the snapshot entry until the backup exists.

`snapper rollback` and `limine-snapper-restore` are a different operation: they change which subvolume is the real root. This runbook does not use them. A snapshot menu entry is not that restore.

## 14. Re-enrol after a firmware or Secure Boot change

PCR 7 no longer matches after Secure Boot is toggled, after the Secure Boot keys change (PK, KEK, db, dbx), after a BIOS reset, and after a firmware update that changes those certificates. A firmware update that does not touch them usually leaves PCR 7 alone. The passphrase prompt appears. The slot is still valid for the passphrase. Enrol a new TPM slot and drop the old one:

```bash
ROOT_SRC=$(findmnt -no SOURCE --nofsroot /)
MAPPER_NAME=$(basename "$ROOT_SRC")
LUKS_DEV=$(sudo cryptsetup status "$MAPPER_NAME" | awk '/^[[:space:]]+device:/ { print $2; exit }')
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 "$LUKS_DEV"
```

Option 2 adds `--tpm2-with-pin=yes` to that command. Then reboot. Section 10 applies again.

## Security, in plain words

The TPM releases the disk key only when PCR 7 has the value it had at enrolment. PCR 7 is the Secure Boot policy: whether Secure Boot is on, and which keys are enrolled (PK, KEK, db, dbx). It is not the firmware code, and it is not the UKI.

PCR 7 changes, and automatic unlock stops, when:

- Secure Boot is turned on or off
- Secure Boot keys change: PK, KEK, db, or dbx, including a fwupd or LVFS update of the UEFI dbx
- a BIOS update replaces those certificates
- the BIOS is reset, which restores or clears those keys
- the TPM is cleared
- an AMD fTPM reset prompt after an AGESA or BIOS update is answered yes. That destroys the sealed key. The passphrase slot still opens the disk. The TPM slot does not.

SSH cannot help at the initramfs prompt. Nothing is listening yet. The passphrase is typed on a USB or 2.4 GHz keyboard, on the machine.

PCR 0+7 is more brittle. PCR 0 is the firmware code itself and changes on a BIOS update even when the Secure Boot policy did not. You would type the passphrase after ordinary firmware updates. PCR 7 does not do that. That is why this runbook does not bind PCR 0.

PCR 11 is not the default. This machine boots a systemd-stub UKI, and systemd-stub measures that UKI into PCR 11. A literal PCR 11 binding would change on every `limine-update`, including a kernel update and an initramfs rebuild, and automatic unlock would fail until you re-enrol. PCR 7 survives those rebuilds. A signed PCR 11 policy (`ukify --pcr-private-key`) is a different mechanism. This runbook does not set one up.

Secure Boot is off on this Ally. PCR 7 is then a stable "Secure Boot is off" measurement. It survives a kernel and UKI rebuild. It does not check the bootloader, the kernel, or the command line.

With Secure Boot off, anyone holding the handheld can read every file on it. The desktop lock, the user password and sudo do not stop that. Only a drive removed from the handheld stays protected. Stock Omarchy treats the LUKS prompt as the boundary in front of autologin. This default removes that boundary, and the handheld desktop lock defaults to off. Two ways in, with no extra media and with any USB stick:

- Limine's editor is on. A USB keyboard during the 1 second menu can change the entry. With Secure Boot off, systemd-stub honours a command line the loader passes. PCR 7 does not measure that command line, so the TPM still unseals. `init=/bin/bash` or `rd.systemd.debug_shell` is a root shell on the unlocked disk.
- PCR 7 has the same value for any boot chain while Secure Boot stays off. Booting another Linux from USB and unlocking with `systemd-cryptsetup` and `tpm2-device=auto`, or `cryptsetup open` with the token, unseals the key and opens the raw disk.

Pulling the drive and fitting it in another machine does not: the key is sealed to this chip. That is the whole of what option 1 protects. Option 2 still asks for a PIN when the person holding the device is not you. It is not available without a keyboard until L68.

These attacks still apply with Secure Boot on and a binding of PCR 7 alone:

- A fake LUKS volume, or an initrd that unlocks a volume the attacker prepared, can unseal the key because PCR 7 never measured which volume it was. The write-up is oddlama, "Bypassing disk encryption on systems with automatic TPM2 unlock" (2025). The mitigation is to measure the volume key into PCR 15 (`tpm2-measure-pcr=yes` on the crypttab line) and bind that measurement, or to use `systemd-pcrlock` or a signed policy. This runbook does not do that. It is named under hardening, and it is not the default.
- Sniffing a TPM bus does not apply to this machine. The Ally's TPM is an AMD fTPM. There is no discrete chip on a bus to tap.
- Faulting an AMD fTPM has been shown on Zen 2 and Zen 3 (faulTPM). The Z1 is Zen 4. That attack is not verified on this CPU. Do not treat the fTPM as a defense against someone who can open the machine and fault the processor.

The passphrase slot is the way in when the chip will not unlock. Anyone who knows the passphrase can open the disk without the TPM. Write it down somewhere that is not only on this handheld.

Do not delete that slot to "finish" the enrolment.

## Optional hardening, not the default

Daniel's choice for the handheld is no input at boot. Nothing in this section is turned on by the steps above. Secure Boot on the handheld path is [L69](alpha-followups.md), and it is not done here.

When that work lands, the order is: create keys with `sbctl`, or enrol through Limine's own Secure Boot path; sign Limine and the UKI; set `editor_enabled: no` and enrol a hash of the Limine config (`limine enroll-config`) so the menu cannot be edited and a changed config does not boot; then re-enrol PCR 7, because turning Secure Boot on changes that register. The passphrase slot stays.

A later binding, still not this default, is PCR 7 plus PCR 15, or `systemd-pcrlock`, or a signed PCR 11 policy. PCR 7 alone, even with Secure Boot on, does not close the volume-confusion case above.

## Sources

- This tree: `etc/mkinitcpio.conf.d/00-omarchy-hooks.conf`, `etc/mkinitcpio.conf.d/omarchy_hooks.conf`, `etc/mkinitcpio.conf.d/omarchy_vconsole.conf`, `etc/limine-entry-tool.d/omarchy-defaults.conf`, `etc/limine-entry-tool.d/omarchy-uki.conf`, `default/limine/limine.conf`, `default/limine/default.conf`, `default/plymouth/omarchy.script`, `install/config/snapper.sh`, `bin/omarchy-hibernation-setup` (the `resume.conf` cmdline drop-in), `bin/omarchy-upgrade-to-quattro` (why `/etc/default/limine` holds `root=` and the unlock parameters once a `+=` drop-in exists).
- Checked on the RC71L, 16 November 2026: busybox `encrypt` is the image, `/etc/mkinitcpio.conf`'s systemd line is not, `/etc/crypttab` has no live entries, Secure Boot is disabled, the UKI is under `/boot/EFI/Linux/`, `limine-update` rebuilds it, `-h` on `limine-update` and `limine-mkinitcpio` starts that rebuild. `btrfs-overlayfs` is `run_latehook` only. `sd-btrfs-overlayfs` from `limine-mkinitcpio-hook` put `overlayfs-setup.service` in the rebuilt initrd. Snapshot entries boot archived UKIs from `limine_history` with the old cmdline. `usbhid`, `hid-generic`, `atkbd` and `xhci` are built into the omarchy kernel. `omarchy_hooks.conf` did not strip `kms` (no NVIDIA). `omarchy_vconsole.conf` and `FILES` were unchanged by the hook assignment.
- [systemd-cryptenroll(1)](https://www.freedesktop.org/software/systemd/man/latest/systemd-cryptenroll.html), [systemd v258 NEWS](https://github.com/systemd/systemd/releases/tag/v258) (the PCR mask defaults to empty), [systemd-ask-password(1)](https://www.freedesktop.org/software/systemd/man/latest/systemd-ask-password.html), [Arch Wiki: systemd-cryptenroll](https://wiki.archlinux.org/title/Systemd-cryptenroll).
- Threats: [oddlama, Bypassing disk encryption on systems with automatic TPM2 unlock](https://oddlama.org/blog/bypassing-disk-encryption-with-tpm2-unlock/) (2025). faulTPM, shown on AMD Zen 2 and Zen 3, not verified on the Z1: [arxiv 2304.14717](https://arxiv.org/abs/2304.14717). Limine's editor defaults to on when `editor_enabled` is unset (`default/limine/limine.conf`).
- Pad: [research/ally-hw-dump.md](research/ally-hw-dump.md). Touch path, not installed here: [buffybox](https://gitlab.postmarketos.org/postmarketOS/buffybox), [AUR buffybox](https://aur.archlinux.org/packages/buffybox). Retired: [Osk-sdl](https://wiki.postmarketos.org/wiki/Osk-sdl).
