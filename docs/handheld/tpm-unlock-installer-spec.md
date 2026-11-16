# Disk unlock, installer choice

Status: draft, 16 November 2026. Owner: dev-ux for the screen, dev-lead for the default. Device: ROG Ally RC71L. No implementation in this change. The screen copy is the dev-ux pass of 16 November 2026. The procedure an owner runs on a machine that is already installed is [tpm-unlock.md](tpm-unlock.md).

This supersedes spec 03 D9 and spec 09 D9, which kept handheld encryption off because Plymouth has no keypad. A handheld install encrypts the disk. The default unlock is the TPM2, bound to PCR 7, with no PIN. The recovery passphrase is mandatory and stays in a passphrase slot.

## 0. Decisions

| # | Decision | Source |
|---|---|---|
| D1 | Handheld default is "Unlock automatically": TPM2, PCR 7, no PIN. The recovery passphrase is mandatory on every choice. | dev-lead, 16 Nov 2026 |
| D2 | "Passphrase every boot" stays available. It warns, before the user commits, that a USB or 2.4 GHz keyboard is required at every boot. | dev-ux screen |
| D3 | "Security chip + PIN" is on the screen, greyed, and not selectable. It is a build item ([L62](alpha-followups.md)), not a choice that stays grey forever. The card appears when the boot keypad can take a numeric PIN from the touchscreen or the pad. | dev-ux screen; Daniel, 16 Nov 2026 |
| D4 | PCR 7 alone. Not 0+7. Not 11. | dev-lead, 16 Nov 2026. [tpm-unlock.md](tpm-unlock.md) |
| D5 | The packaged hook line for this path is the installer's. A `zz-` drop-in is how the runbook wins on a machine that is already installed. It is not the long-term mechanism. | This spec, from the RC71L hook layout |

## 1. When the screen is shown

| Gate | Rule |
|---|---|
| Handheld | `omarchy-hw-rog-ally` succeeds (RC71L). A later handheld is the same screen only when its own detector succeeds. That detector is `omarchy-hw-match` on the model's DMI name, the same pattern as the other hardware leaves. A laptop does not get this screen. |
| TPM2 | `/dev/tpm0` or `/dev/tpmrm0` exists, and `systemd-cryptenroll --tpm2-device=list` prints a device. |
| No TPM | The screen is not the three-card screen. Automatic unlock is not offered. The only encryption choice is passphrase every boot, with the keyboard warning, and a line that says the security chip was not found. |
| Not a handheld | Stock Omarchy. This spec does not change it. |

The screen sits after the disk step and before the user and password, on the assumption that no keyboard is attached. A keyboard that is attached does not hide the screen.

## 2. Screen

Title: How should this handheld unlock its disk?

Subtitle: Your files are encrypted either way. This choice decides what happens each time you power on.

### Unlock automatically

Pre-selected. It is the only keyboard-free choice today. The label "Recommended for handhelds" is shown only when no keyboard is attached.

Body: Powers straight on to your games, no typing. The disk is locked to this device's security chip, so it's safe if the drive is pulled out. But anyone holding the handheld can switch it on and get into your session.

Small print: If the chip can't unlock it, you'll need your recovery passphrase and a keyboard. That happens when Secure Boot is toggled, when the Secure Boot keys change (PK, KEK, db, dbx), when a BIOS update changes those certificates, or when the BIOS is reset. A kernel or UKI rebuild does not, because this choice binds PCR 7 only. PCR 0+7 is not used: PCR 0 is the firmware code and changes on a BIOS update even when Secure Boot did not. PCR 11 is not used: this boot is a systemd-stub UKI, and a literal PCR 11 binding changes on every `limine-update`, so every kernel or initramfs rebuild would demand the passphrase. Secure Boot is off on the RC71L this was read from, so PCR 7 there is only a stable "Secure Boot is off" measurement. The body sentence stands: anyone who can switch the machine on reaches the session. Turning Secure Boot on is not part of this screen.

### Passphrase every boot

Body: Type a passphrase each time you power on. Most private: someone holding the handheld can't get in without it.

Warning row, amber, always visible: Needs a USB or 2.4 GHz wireless keyboard at every boot. The on-screen keyboard and Bluetooth keyboards don't work at that point.

### Security chip + PIN

Disabled. Body: Power on and enter a short PIN with the touchscreen or controller.

Tag: Not available yet.

Reason line, whenever the card is focused or tapped: The boot screen can't show an on-screen keypad yet. This option will appear in a later update.

The card is greyed and focusable, so the reason can be read. A or a tap shows the reason and does not select it. The card is never hidden. Selecting it becomes possible only when L62's keypad is in the image. Both the automatic choice and this choice get built. The screen does not offer the PIN until the keypad works with no USB keyboard.

Footer: Back (B) and Continue (A). Continue is enabled once an option is selected. One option is pre-selected, so Continue starts enabled.

## 3. Navigation

The d-pad or the left stick moves focus between the three cards, Back and Continue. A selects the focused card, or activates the focused button. B is Back. Touch: tap a card to select it, tap the buttons. The focus ring is visible from the first paint. The selected card is a radio dot plus a highlighted border, not colour alone (spec 06). When spec 06's screen reader is on, it reads each card's label and body as one item. Nothing on this screen is a hold or a timer (spec 01 D5).

## 4. Recovery passphrase

Every choice sets one. Continue on this step stays disabled until the passphrase is entered twice and "I've saved my recovery passphrase" is ticked, by A or by tap.

Title: Set a recovery passphrase

Body, option 1: Only needed if automatic unlock fails. Store it somewhere other than this handheld.

Entry: the installer keyboard. Passphrase and confirm, plus Show/Hide. Or "Generate one for me": a word-based key on screen, a QR code to photograph, and the line "Write this down or photograph it now. It won't be shown again."

Option 2 uses the same fields as the boot passphrase, with the line "You'll type this at every power-on, using a physical keyboard."

The passphrase is the LUKS passphrase. `install/provisioning/luks-rekey.sh` already re-keys the install slot to the owner's secret. The journal still records no key material. The TPM enrolment adds a slot. It does not replace this one, and it does not pass `--wipe-slot=password`.

## 5. Install summary

One row:

- Unlock automatically: "Disk unlock: Automatic (security chip). Recovery passphrase set."
- Passphrase every boot: "Disk unlock: Passphrase every boot (keyboard needed)."

The PIN choice has no summary row until it can be selected.

## 6. What the installer runs

No code in this change. The commands are the ones in [tpm-unlock.md](tpm-unlock.md). The installer owns them so the owner does not.

### Hooks, owned by the install

On an installed RC71L the image is the busybox line in `etc/mkinitcpio.conf.d/00-omarchy-hooks.conf` (`udev`, `plymouth`, `encrypt`, and `btrfs-overlayfs`). `/etc/mkinitcpio.conf` can still contain an older `HOOKS=(base systemd ...)` line without `plymouth` and without `sd-encrypt`. That line is not the image: `00-omarchy-hooks.conf` assigns `HOOKS` again. `omarchy_resume.conf` appends the busybox `resume` hook when hibernation was set up. `omarchy_hooks.conf` strips `kms` only on an NVIDIA-only machine, and its `FILES` addition is not a hook. `omarchy_vconsole.conf` wraps `add_file` and does not assign `HOOKS`. Neither is cleared by replacing `HOOKS`.

The runbook writes `/etc/mkinitcpio.conf.d/zz-tpm-sd-encrypt.conf` so a later assignment wins on a machine the person is editing by hand:

```text
HOOKS=(base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck sd-btrfs-overlayfs)
```

`systemd` replaces `udev`. `sd-vconsole` replaces `keymap` and `consolefont`. `sd-encrypt` replaces `encrypt`. `plymouth` and `kms` stay. There is no `resume` hook: the systemd hook honours `resume=` and `resume_offset=` on the cmdline. The cmdline drop-in that carries those parameters stays.

The overlay hook is `sd-btrfs-overlayfs`, not `btrfs-overlayfs`. The busybox hook is `run_latehook` only, so it does not run in a systemd initramfs, and a read-only snapshot boot from that UKI would not mount the overlay. `limine-mkinitcpio-hook` ships `sd-btrfs-overlayfs`, which installs `overlayfs-setup.service` and requires the `systemd` hook. The package-owned hook line uses `sd-btrfs-overlayfs`. The installer checks that `/usr/lib/initcpio/install/sd-btrfs-overlayfs` exists before it writes the line, and the UKI check requires `overlayfs-setup.service` in the initrd.

The installer does not leave the handheld on a `zz-` file. A later drop-in that sorts after `zz-` would put the busybox line back, and a settings update already rewrites `00-omarchy-hooks.conf`. The installer writes the systemd line as the hook line for the handheld TPM path: either a branch inside `00-omarchy-hooks.conf` when `omarchy-hw-rog-ally` (or the later handheld detector) is the machine and this choice was automatic unlock, or a drop-in the package owns and sorts so that it is the assignment mkinitcpio keeps. That line is the one above, including `sd-btrfs-overlayfs`. The `zz-` file remains the documented manual override, not the install path.

Passphrase every boot does not change the hooks. It keeps `encrypt` and `cryptdevice=`.

### Cmdline

Edit `/etc/default/limine`, which is where the ISO's `KERNEL_CMDLINE[default]+=` fragment holds `cryptdevice=` and `rd.luks.*` (`default/limine/default.conf` is the template). Drop `cryptdevice=`. Append `,tpm2-device=auto` to the existing `rd.luks.options=<luks-uuid>=...` value. Keep `rd.luks.name=<luks-uuid>=root` aligned with `root=/dev/mapper/root`. Do not edit `/boot/limine.conf`. Leave `/etc/limine-entry-tool.d/omarchy-defaults.conf`, `resume.conf` and `rtc-alarm.conf` alone.

`/etc/crypttab` on the checked machine has no live entries. The installer does not add one. If a live line for this volume exists, `tpm2-device=auto` goes on that line too, so the file and the cmdline do not disagree.

### Build and enrol

`omarchy-pkg-add tpm2-tss` when the package is missing. It was already installed on the checked Ally.

Rebuild with `limine-update`. The boot file is the Limine UKI under `/boot/EFI/Linux/`. There is no loose initramfs image. Do not pass `-h` or `--help` to `limine-update` or `limine-mkinitcpio`. On the checked machine those flags start a rebuild.

Verify before enrol, and before reboot. `ukify inspect` on the UKI, or `objcopy` of the `.initrd` section into `lsinitcpio`. The hooks in that initrd include `systemd`, `plymouth`, `sd-encrypt` and `sd-btrfs-overlayfs`. They do not include busybox `encrypt` as the unlock hook, and they do not include `btrfs-overlayfs`. `libtss2` is present. `overlayfs-setup.service` is present. The UKI cmdline contains `tpm2-device=auto` and does not contain `cryptdevice=`. Snapshot entries keep booting the UKIs archived under `limine_history`, with the cmdline saved for each one, so they stay a passphrase rollback.

Enrol with the recovery passphrase the user just set:

```text
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 <luks-device>
```

`<luks-device>` is the path `cryptsetup status` prints for the mapper, found the way the runbook finds it. The passphrase is read from the enrolment prompt. It is not an argument. `--tpm2-pcrs=7` is required: omitting it binds no PCR.

Then `systemd-cryptenroll` with no enrolment flag, and `cryptsetup luksDump`. A `password` row and a `tpm2` row, and a `systemd-tpm2` token. Missing password row: do not reboot; treat it as a failed install of this choice.

A snapper snapshot of config `root` is taken before the hook and cmdline change, the same as the runbook. The Limine snapshot entry keeps the previous UKI.

PIN enrolment (`--tpm2-with-pin=yes`) is not run until L62. When it is run, it is the same command plus that flag, and the image also contains `sd-unl0kr` and `MODULES+=(i2c-hid i2c-hid-acpi hid-multitouch)`.

## 7. Failure

| When | What happens |
|---|---|
| `limine-update` fails, or the UKI check fails | Restore the previous `/etc/default/limine` and do not keep the new hook line. Rebuild. The choice falls back to passphrase every boot, and the summary row says so. Do not reboot into an image that failed the check. |
| Enrolment fails | The passphrase slot is unchanged. If a TPM slot was written, `--wipe-slot=tpm2` removes it and nothing else. The summary row does not say automatic. The next boot asks for the passphrase. An `sd-encrypt` image with `rd.luks.name=` still accepts that passphrase. |
| Boot, TPM does not unseal | Plymouth asks for the passphrase. The target text, which this spec does not put into the theme, is: "Couldn't unlock automatically. Connect a USB or 2.4 GHz keyboard and type your recovery passphrase." Second line: "This can happen after a BIOS reset, firmware update or Secure Boot change." The events in section 2 are the full list. |
| After that passphrase unlocks the session | One notification, once. Gaming: the Steam or overlay toast. Desktop: mako. "Automatic unlock stopped working. Turn it back on?" Actions: Re-enable, Not now. Re-enable runs `systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7` on the LUKS device and asks for the recovery passphrase. That prompt is the OSK or polkit path in spec 09, which is L37. Until L37, Re-enable works from the desktop with a keyboard, or over SSH, and the toast says so. |
| No keyboard, still on the prompt | [ALPHA.md](ALPHA.md), "Handheld stuck at the passphrase prompt". |

## 8. Acceptance

On an Ally, no keyboard attached, unless the row says otherwise.

1. With no keyboard, the screen opens with "Unlock automatically" pre-selected. Continue is reachable by d-pad and A alone, and by touch alone.
2. The trade-off sentence is visible without scrolling at 1080p, at 1.5× scale. Check the scale on an RC71L.
3. "Security chip + PIN" is visible, focusable, shows its reason, and cannot be selected by A or by touch.
4. The passphrase option always shows the keyboard warning.
5. The install cannot finish without a recovery passphrase set and the saved box ticked.
6. Automatic unlock: power-on reaches the gaming session with no input. This is spec 09 AC 1, and it waits on the same waiter fix.
7. With the TPM slot invalidated (TPM cleared, or PCR 7 changed): the boot shows the failure text, the recovery passphrase typed on a USB keyboard boots, and the re-enable toast appears once.
8. Re-enable, then reboot, reaches gaming with no input.

## 9. Not in this change

The Plymouth strings, the toast, the hook branch in `00-omarchy-hooks.conf`, and the PIN keypad. L62 is the keypad. The runbook is the manual path until the installer owns the hooks.
