# Handheld alpha (ROG Ally RC71L)

The original RC71L can switch between Steam Gaming Mode and the managed Hyprland desktop. On the tested desktop, the right stick moves the pointer, RT left-clicks, LT right-clicks, Armoury Crate opens the Omarchy menu and Command Centre opens the power panel. Touch and RT can type on the optional themed keyboard.

The [feature-parity checklist](feature-parity.md) records the package versions, hardware results and open issues for the current build. Independent rear paddles, stick-ring lighting and output through the DisplayLink hub still need hardware work. The [gaming session reference](../rog-ally-gaming-session.md) covers the optional packages and session settings.

## Before you install the alpha

SSH is the way back if the screen sticks, and it only works if sshd is already running. A stock install ships OpenSSH with the service disabled and port 22 closed. While the desktop still works, run:

```bash
omarchy-setup-security-sshd
```

That authorizes a key, turns password logins off, then runs `sudo systemctl enable sshd.service` and `sudo systemctl reload-or-restart sshd.service`, and opens the port with `sudo ufw limit 22/tcp`. A bare `systemctl enable --now sshd` skips the key, the password lock, and the firewall.

From another machine, `ssh rog-ally` (or `ssh $USER@<ally-host>`) must log in before you go on. `rog-ally` is an alias on that client. The setup prints `ssh $USER@$(hostname)`.

## Install

`omarchy-handheld-autologin apply` writes `/etc/sddm.conf.d/zz-omarchy-handheld.conf` only when `omarchy-hw-rog-ally` and `omarchy-pkg-present omarchy-gaming-session` both succeed. Otherwise it deletes that file. The drop-in is `Session=omarchy-handheld.desktop` and `Relogin=true`, with no `User=`. `User=` is `/etc/sddm.conf.d/omarchy-handheld-user.conf`. The installer writes it: `configure_login` in `bin/omarchy-provision-owner` calls `omarchy-handheld-autologin install-user` with the account it just created. The gaming-session scriptlet writes that same file only when `[Autologin] User=` is still empty, copying the installer record from `autologin.conf` or SDDM's `[Last] User=`. The name is per machine, so the file is not in any package and `pacman -Qo` names none. `zz-omarchy-handheld.conf` has no username; `apply` rewrites it. `install-user` does not replace a `User=` that already sits inside `[Autologin]`. apply does not rewrite the User= file while the variant is installed, and deletes it together with `zz-omarchy-handheld.conf` when the variant is gone. That apply is the desktop-mode cleanup: a leftover `User=` would autologin into the last desktop. Switching the session preference to desktop does not delete the file, because a later return to gaming still needs the name. Removing the package runs `pre_remove` and `post_remove`, which delete `/etc/sddm.conf.d/omarchy-handheld-user.conf`. The session runs `omarchy-handheld-autologin`, which starts `omarchy-session-start relogin`. The boot unit is `omarchy-handheld-autologin.service` (`Before=sddm.service`, `ExecStart=/usr/bin/omarchy-handheld-autologin apply`). Install Gamescope, Steam, and the session package ([gaming session note](../rog-ally-gaming-session.md)) before apply. The command has to be `/usr/bin/omarchy-handheld-autologin`. The package also installs `/usr/bin/steamos-polkit-helpers/steamos-update`, a stub that updates nothing, so Gaming Mode setup does not stop on a missing SteamOS updater.

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

Check: `omarchy-hw-rog-ally` and `omarchy-pkg-present omarchy-gaming-session` succeed, `systemctl is-enabled omarchy-handheld-autologin.service` prints `enabled`, and the drop-in names `Session=omarchy-handheld.desktop`. `omarchy-handheld-user.conf` has `User=` and nothing else. Reboot. The greeter stays down and Steam's gaming UI comes up. `systemctl is-active omarchy-handheld-autologin.service` is `active`. `Relogin=false` is expected when desktop sign-in is required or the failure limit has set `/run/omarchy/handheld-autologin/stop`.

## What you get

Autologin starts Gamescope (`--backend drm -e --xwayland-count 2 --default-touch-mode 4`) and Steam in `omarchy-gamescope-$XDG_SESSION_ID.scope`, and starts `omarchy-gaming-session.target`. One retry, then the desktop. Steam’s explicit desktop request takes precedence on the next login. The log is `~/.local/state/omarchy/gaming-session/session.log`.

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

Repeated failed gaming starts pin relogin off using `/run/omarchy/handheld-autologin/stop` and `Relogin=false`. The supervisor returns to the existing greeter when desktop sign-in is required. With passwordless Desktop enabled it opens the recovery desktop with the on-screen keyboard. The failure handler leaves the current SDDM daemon running. A reboot clears `/run`; the user’s repeated-failure record is stored in `~/.local/state/omarchy/gaming-session/`. From SSH, you can remove the session and account drop-ins to return to the greeter. This also removes the recorded account for future boots. Use the recovery step below to restore it when you are ready.

```bash
sudo rm -f /etc/sddm.conf.d/zz-omarchy-handheld.conf
sudo rm -f /etc/sddm.conf.d/omarchy-handheld-user.conf
sudo systemctl restart sddm
```

`systemctl restart sddm` kills the current graphical session.

### Restore handheld autologin

If you removed the account drop-in above, sign in as the account that should own the handheld session. Restore that account record before applying the policy. The boot service writes the session preference and relies on the saved account.

```bash
sudo omarchy-handheld-autologin install-user "$(id -un)"
sudo rm -f /run/omarchy/handheld-autologin/stop
sudo omarchy-handheld-autologin apply
sudo systemctl restart sddm
```

That restart kills the current graphical session. Reboot instead if you want to keep this session until you are ready. On boot the unit applies the desktop sign-in policy again.

## Rollback

```bash
sudo systemctl disable --now omarchy-handheld-autologin.service
sudo rm -f /etc/systemd/system/omarchy-handheld-autologin.service
sudo rm -f /etc/sddm.conf.d/zz-omarchy-handheld.conf
sudo rm -f /etc/sddm.conf.d/omarchy-handheld-user.conf
sudo systemctl daemon-reload
omarchy-setup-gaming-session reset
systemctl --user stop omarchy-gaming-session.target || true
rm -f ~/.config/systemd/user/omarchy-gaming-session.target \
  ~/.config/systemd/user/omarchy-gaming-input-profile.service \
  ~/.config/systemd/user/omarchy-rog-ally-input.service.d/10-gaming-session.conf \
  ~/.config/systemd/user/omarchy-ally-tdp-shim.service.d/10-gaming-session.conf
rmdir ~/.config/systemd/user/omarchy-rog-ally-input.service.d \
  ~/.config/systemd/user/omarchy-ally-tdp-shim.service.d 2>/dev/null || true
systemctl --user daemon-reload
omarchy-pkg-drop omarchy-gaming-session
```

Reboot. Autologin is gone, so the greeter is up. A USB keyboard's Enter submits the password. There is no session picker. That leaves Steam's games and saves. `omarchy-gaming-session` installs `/etc/sudoers.d/omarchy-handheld-autologin` at mode 0440, the passwordless `fail` / `reset` / `apply` grant. The base tree does not ship it. `/var/lib/omarchy/handheld/desktop-lock` is the lock value.
