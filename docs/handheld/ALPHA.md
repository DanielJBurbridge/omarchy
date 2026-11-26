# Handheld alpha (ROG Ally RC71L)

The optional handheld session gives the original RC71L a controller-driven Omarchy desktop and a dedicated Steam Gaming Mode.

| On the handheld desktop | How to use it |
|---|---|
| Point and click | Move the right stick. RT left-clicks and LT right-clicks. |
| Type | Focus the field. With the [touch keyboard](../rog-ally-touch-keyboard.md) configured, tap **Keyboard** in the bar. You can also swipe up from the bottom-centre handle when enabled on the undocked Ally. Type by touch or with the pointer and RT. Tap **Keyboard** again to hide it. |
| Switch windows | Tap Armoury Crate. Use D-pad Up and Down to highlight a row, Right to select it and Left to go back. Choose **Switch Window** to select an open window by title or **Apps** to open the launcher. |
| Adjust brightness or volume | Tap Command Centre to open **Power**. The dock-aware candidate shows the handheld controls on the built-in panel. Brightness adjusts that screen. Volume adjusts the selected audio output, which may be the hub when docked. |
| Switch modes | Save your desktop work, then choose **Omarchy → System → Switch to Gaming**. To return from the dedicated Gaming session, choose **Steam → Power → Switch to Desktop**. |

`Super + W` asks the focused app to close. To close with the controller, put the active workspace in Omarchy’s **Floating** mode using its layout glyph in the top bar. Point at the window’s native titlebar × and press RT. The **Appearance → Workspace Layout** menu sets the global default.

The [feature-parity checklist](feature-parity.md) records the package versions, hardware results and open issues for the current build. Independent rear paddles, stick-ring lighting and output through the DisplayLink hub still need hardware work. The [gaming session reference](../rog-ally-gaming-session.md) covers the optional packages and session settings.

## Before you install the alpha

SSH is the way back if the screen sticks, and it only works if sshd is already running. A stock install ships OpenSSH with the service disabled and port 22 closed. While the desktop still works, run:

```bash
omarchy-setup-security-sshd
```

That authorizes a key, turns password logins off, then runs `sudo systemctl enable sshd.service` and `sudo systemctl reload-or-restart sshd.service`, and opens the port with `sudo ufw limit 22/tcp`. A bare `systemctl enable --now sshd` skips the key, the password lock, and the firewall.

From another machine, `ssh rog-ally` (or `ssh $USER@<ally-host>`) must log in before you go on. `rog-ally` is an alias on that client. The setup prints `ssh $USER@$(hostname)`.

## Install

The installer records the account under `[OmarchyHandheld]` in `/etc/sddm.conf.d/omarchy-handheld-user.conf`. If that file is absent, the companion can initialise it from the installer's `autologin.conf` or SDDM's `[Last] User=`. The record supplies the account for InputPlumber and later handheld logins.

With compatible runtime and settings on an Ally with the companion installed, `omarchy-handheld-autologin apply` puts the recorded user and `Session=omarchy-handheld.desktop` under `[Autologin]` in `/etc/sddm.conf.d/zz-omarchy-handheld.conf`. The boot unit `omarchy-handheld-autologin.service` runs this command before SDDM. The selected session runs `omarchy-session-start relogin`. Install Gamescope, Steam and the session package before running `apply`. [Gaming session package](../rog-ally-gaming-session.md)

On a fresh install, `install/hardware/all.sh` runs `install/hardware/handheld-autologin.sh`, which enables the unit and applies. That first apply finds no gaming package and leaves no drop-in. After the package is installed, run apply again (a reboot does the same, because the unit runs before SDDM):

```bash
sudo omarchy-handheld-autologin apply
```

On an existing Ally install, nothing in `migrations/` enables the unit or runs apply. Do it yourself, after the package is installed. The leaf does not reload systemd.

```bash
sudo install -Dm644 "$OMARCHY_PATH/default/systemd/system/omarchy-handheld-autologin.service" \
  /etc/systemd/system/omarchy-handheld-autologin.service
sudo systemctl daemon-reload
sudo systemctl enable omarchy-handheld-autologin.service
sudo omarchy-handheld-autologin apply
```

Check that `omarchy-hw-rog-ally` and `omarchy-pkg-present omarchy-gaming-session` succeed, `systemctl is-enabled omarchy-handheld-autologin.service` prints `enabled`, and the session drop-in names `Session=omarchy-handheld.desktop`. After reboot, Steam's Gaming UI comes up and `systemctl is-active omarchy-handheld-autologin.service` reports `active`. `Relogin=false` is expected when desktop sign-in is required or the failure limit has set `/run/omarchy/handheld-autologin/stop`.

## What you get

Autologin starts Gamescope (`--backend drm -e --xwayland-count 2 --default-touch-mode 4`) and Steam in `omarchy-gamescope-$XDG_SESSION_ID.scope`, and starts `omarchy-gaming-session.target`. One retry, then the desktop. Steam’s explicit desktop request takes precedence on the next login. The log is `~/.local/state/omarchy/gaming-session/session.log`.

Steam waits up to 30 seconds for NetworkManager to report internet connectivity when a check is available. An `unknown` result or a timeout lets Steam start. A return before Steam is ready retries Gaming Mode once. If it happens again, the session follows the desktop lock setting.

InputPlumber presents a Steam Deck controller (`deck`, Valve `28de:1205`) in Gaming Mode. Setup configures `vhci_hcd` to load at boot. When that module is unavailable, the gaming profile uses DualSense Edge (`ds5-edge`) for that load. The desktop, greeter and on-screen keyboard profiles use Xbox Elite.

From the desktop, save your work, exit Steam and choose **Omarchy → System → Switch to Gaming**. To return, choose **Steam → Power → Switch to Desktop**.

With `desktop-lock on`, **Switch to Desktop** takes you to sign-in. Sign in by touch or USB keyboard. With the matched runtime, settings and `omarchy-gaming-session` package, the resulting desktop loads the handheld controller profile and offers **Switch to Gaming**. The next return to Desktop asks you to sign in again.

On the RC71L the desktop power button runs `omarchy-system-sleep-lock`, then `systemctl suspend`. A failed lock cancels the suspend. Until `/var/lib/omarchy/handheld/k07-landed` exists, `desktop-lock` is `default-off`: with no physical keyboard the lock is skipped and the button still suspends. `omarchy-setup-gaming-session desktop-lock on` turns the lock on. With the lock on and no physical keyboard, the button does not suspend. The Ally's own N-KEY device does not count as a keyboard.

## Escape and recovery

Recovery is `ssh rog-ally`, and only if sshd was already enabled and that check worked. At the greeter, tap **Keyboard** or the password field to type with Qt Virtual Keyboard, then tap **Sign in**. A USB keyboard also works, with Enter to submit. There is no session picker. This tree has no TTY switch.

The F17 escape and the watchdog aren't in this alpha because no InputPlumber intercept ships in the tree, so there's no stuck intercept to escape. They become required when the intercept lands. `omarchy-ally-pointer.service` loads Omarchy's stick-to-pointer profile before the greeter. Whether the pointer moves there is unverified.

The greeter embeds Qt Virtual Keyboard using `GreeterEnvironment` in `etc/sddm.conf.d/10-wayland.conf`. If the module is unavailable, the password field and physical keyboard still work.

### Handheld stuck at the passphrase prompt

Automatic unlock did not unseal the disk. Plymouth is asking for the recovery passphrase. Touch and the built-in pad do not type it. Plug in a USB or 2.4 GHz keyboard and type the passphrase. Bluetooth will not do it. SSH cannot help at this prompt: the session is not up.

When the session is up, enrol the TPM slot again. This asks for that passphrase, removes only TPM slots, and writes a new one bound to PCR 7. The passphrase slot stays. A token sealed on the busybox initrd misses os-separator and never unseals. This session, once the hooks are the systemd initrd, is the boot to enrol from. `--wipe-slot=tpm2` is in the same call.

```bash
ROOT_SRC=$(findmnt -no SOURCE --nofsroot /)
MAPPER_NAME=$(basename "$ROOT_SRC")
LUKS_DEV=$(sudo cryptsetup status "$MAPPER_NAME" | awk '/^[[:space:]]+device:/ { print $2; exit }')
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 "$LUKS_DEV"
```

`LUKS_DEV` is the path `cryptsetup status` prints. Do not pass `--wipe-slot=password`. The rest of the procedure, including the hook and cmdline this command expects, is [tpm-unlock.md](tpm-unlock.md).

If the new image will not boot at all, a Limine snapshot entry still takes the passphrase. That boot is a read-only snapshot. Writes go to tmpfs and do not last, so restoring files there does not fix the next boot. The repair that lasts is an Arch or Omarchy live ISO. `findmnt /` there is the live system, and `LUKS_DEV` from another shell is unset. `lsblk -f` lists the Ally: `FSTYPE` `crypto_LUKS` is the locked partition, and `vfat` on the internal disk is the ESP. Set the three variables from those lines. `backup` is the header file from the runbook, on a drive that is not the Ally's internal disk. Type the passphrase at `cryptsetup open`.

```bash
lsblk -f
LUKS_DEV=/dev/REPLACE_WITH_CRYPTO_LUKS
ESP=/dev/REPLACE_WITH_ESP
backup=/REPLACE_WITH_HEADER_BACKUP_PATH
printf 'device=%s\nesp=%s\nbackup=%s\n' "$LUKS_DEV" "$ESP" "$backup"
if [[ ! -b $LUKS_DEV || ! -b $ESP ]]; then
  echo "stop: set LUKS_DEV to the crypto_LUKS partition and ESP to the vfat EFI partition that lsblk printed"
else
  sudo cryptsetup open "$LUKS_DEV" root
  sudo mount -o subvol=@ /dev/mapper/root /mnt
  sudo mount "$ESP" /mnt/boot
  sudo rm -f /mnt/etc/mkinitcpio.conf.d/zz-tpm-sd-encrypt.conf
  sudo cp -a /mnt/etc/default/limine.pre-tpm2 /mnt/etc/default/limine
  sudo arch-chroot /mnt limine-update
fi
```

`/etc/default/limine.pre-tpm2` is the copy taken before the cmdline edit. If that file is missing, do not invent a cmdline. Stay on the snapshot entry. A damaged header is `cryptsetup luksHeaderRestore`, with this `LUKS_DEV` and this `backup`, and only when `backup` is a non-empty file on the removable drive. The ESP and any other partition of the internal disk are the wrong place for that file. The runbook's section 13 is the full restore.

### Return from a stuck Gaming session

Save your game and choose **Steam → Power → Switch to Desktop**. If Steam's menu won't open, SSH in as the same Linux user and send the request to the session on the Ally's screen.

```bash
seat_session=$(loginctl show-seat seat0 --property=ActiveSession --value)
if [[ -n $seat_session ]]; then
  OMARCHY_HANDHELD_SESSION="$seat_session" omarchy-launch-gaming-desktop
else
  echo "No active session on seat0."
fi
```

When desktop sign-in is enabled, enter your password at the greeter. Otherwise the desktop opens directly. After repeated failed starts the supervisor can already have opened the greeter or a recovery desktop. If the screen stays stuck, check `~/.local/state/omarchy/gaming-session/session.log` or use the recovery greeter below.

### Open a recovery greeter

Keep your SSH connection open and have the owner's password ready. Create a temporary SDDM override to request password sign-in. Save the filename it prints.

```bash
if recovery=$(sudo mktemp /etc/sddm.conf.d/zzz-omarchy-recovery.XXXXXXXX.conf); then
  if printf '[Autologin]\nUser=\nSession=omarchy.desktop\nRelogin=false\n' | sudo tee "$recovery" >/dev/null; then
    printf '%s\n' "$recovery"
  else
    sudo rm -- "$recovery"
  fi
fi
```

Continue once the command prints the recovery filename. SDDM reads the files in `/etc/sddm.conf.d/` in name order and `/etc/sddm.conf` last. Check any later local file for an `[Autologin]` section. If it sets a non-empty `User=`, resolve that override before continuing. Keep backups outside the configuration directory.

Once your work is saved, run `sudo systemctl restart sddm.service` from SSH. This closes the graphical session. Sign in on the Ally. When the desktop is usable, remove only the temporary file from the same SSH shell.

```bash
sudo rm -- "$recovery"
```

If you reconnected, use the saved filename. Your original policy applies on the next SDDM start. The gaming failure history is preserved.

## Rollback

A one-off **Switch to Desktop** keeps Gaming Mode installed. To restore the ordinary desktop login and keep Steam, remove the optional companion.

Start from the desktop with work saved and SSH available. From `omarchy-gaming-session` version `1.0.0-16`, switching either Omarchy package to stock or removing the companion deactivates generated handheld SDDM autologin. It retains the owner record and saves the original legacy fragments in hidden backup files in `/etc/sddm.conf.d/`. Older companion versions can delete locally edited handheld SDDM files during removal. Back up customisations before removing the package. On a standard Snapper installation, `omarchy-snapshot create` followed by `sudo snapper -c root list` gives you a numbered system snapshot.

Use the non-recursive Pacman transaction to keep Steam, Gamescope and InputPlumber. Confirm that only `omarchy-gaming-session` is listed for removal. Running the base Omarchy helper afterwards clears the surviving handheld session setting.

```bash
sudo pacman -R omarchy-gaming-session && sudo omarchy-handheld-autologin apply
```

If a scriptlet warns about a failed helper, rerun the named command with `sudo` and check its result. If `apply` reports a symlink at `zz-omarchy-handheld.conf`, move that link to a backup outside SDDM's configuration directory and rerun `sudo omarchy-handheld-autologin apply`. Keep any personal settings for an installed session in a separate administrator-owned file.

Before signing out, review any remaining `[Autologin]` settings, including `/etc/sddm.conf.d/autologin.conf` and `/etc/sddm.conf` if present. With no configured user, SDDM shows the password greeter. A separate configuration can still sign the owner into an installed desktop automatically. The base Omarchy session is `omarchy.desktop`. Keep SSH open through the first sign-in.

Pacman removes the companion's three session entries, packaged user units and sudoers grant. The base boot helper, greeter pointer service, user's gaming preferences, Steam library and saves stay in place. The stored desktop-lock choice and any separate power-button package also survive removal.
