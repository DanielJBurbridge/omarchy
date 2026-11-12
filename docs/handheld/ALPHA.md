# Handheld alpha (ROG Ally RC71L)

The alpha is the gaming session, autologin (the apply step below), the RC71L desktop power button, and this page. Tip `d3747faff` on `feat/ally-parity-integration-20261111`. Review notes are in [alpha-followups.md](alpha-followups.md).

What's missing:

- Controller map, InputPlumber profiles, and the desktop and gaming bridges (spec 01). No `gaming.yaml` ships, so `omarchy-gaming-input-profile` does nothing.
- The F17 escape and the overlay watchdog (spec 04, spec 07). No InputPlumber intercept ships, so there is nothing to escape yet.
- Quick-access overlay, fan, RGB, and TDP. `omarchy-ally-tdp-shim.service` is not in this tree.
- Dock switching. `omarchy-display-rog-ally` is not in this tree.
- A menu row and `Super + Ctrl + G` for Switch to Gaming (spec 02).
- The suspend broker, the idle return to gaming, and the power-off backstop (spec 02 §7.7).
- The first-boot wizard and buffyboard (spec 03).
- Gaming notifications (spec 05) and the accessibility pack (spec 06).
- The `osk` profile, a themed wvkbd, and a Command Centre keyboard chord (spec 07).
- A greeter keyboard that can backspace, shift, enter symbols, and submit (spec 02 AC 59).
- A migration that enables autologin on an Ally that is already installed.

## Before you install the alpha

SSH is the way back if the screen sticks, and it only works if sshd is already running. A stock install ships OpenSSH with the service disabled and port 22 closed. While the desktop still works, run:

```bash
omarchy-setup-security-sshd
```

That authorizes a key, turns password logins off, then runs `sudo systemctl enable sshd.service` and `sudo systemctl reload-or-restart sshd.service`, and opens the port with `sudo ufw limit 22/tcp`. A bare `systemctl enable --now sshd` skips the key, the password lock, and the firewall.

From another machine, `ssh rog-ally` must log in before you go on. The setup prints `ssh $USER@$(hostname)`. If that name is not `rog-ally`, set it with `sudo hostnamectl set-hostname rog-ally` and check `ssh rog-ally` again.

## Install

`omarchy-handheld-autologin apply` writes `/etc/sddm.conf.d/zz-omarchy-handheld.conf` only when `omarchy-hw-rog-ally` and `omarchy-pkg-present omarchy-gaming-session` both succeed. Otherwise it deletes that file. The drop-in is `Session=omarchy-handheld.desktop` and `Relogin=true`, with no `User=`. The session runs `omarchy-handheld-autologin`, which starts `omarchy-session-start relogin`. The boot unit is `omarchy-handheld-autologin.service` (`Before=sddm.service`, `ExecStart=/usr/bin/omarchy-handheld-autologin apply`). Install Gamescope, Steam, and the session package ([gaming session note](../rog-ally-gaming-session.md)) before apply. The command has to be `/usr/bin/omarchy-handheld-autologin`.

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

Check: `omarchy-hw-rog-ally` and `omarchy-pkg-present omarchy-gaming-session` succeed, `systemctl is-enabled omarchy-handheld-autologin.service` prints `enabled`, and the drop-in says `Relogin=true`. Reboot. The greeter stays down and Steam's gaming UI comes up. `systemctl is-active omarchy-handheld-autologin.service` is `active`. `Relogin=false` means `/run/omarchy/handheld-autologin/stop` is present.

## What you get

Autologin starts Gamescope (`--backend drm -e --xwayland-count 2 --default-touch-mode 4`) and Steam in `omarchy-gamescope-$XDG_SESSION_ID.scope`, and starts `omarchy-gaming-session.target`. One retry, then the desktop. A Relogin always returns to gaming. The log is `~/.local/state/omarchy/gaming-session/session.log`.

From the desktop, exit Steam and run `omarchy-launch-gaming-session`. From gaming, Steam's Power → Switch to Desktop (the private `steamos-session-select` accepts only `plasma`) or `omarchy-launch-gaming-desktop`.

On the RC71L the desktop power button runs `omarchy-system-sleep-lock`, then `systemctl suspend`. A failed lock cancels the suspend. Until `/var/lib/omarchy/handheld/k07-landed` exists, `desktop-lock` is `default-off`: with no physical keyboard the lock is skipped and the button still suspends. `omarchy-setup-gaming-session desktop-lock on` turns the lock on. With the lock on and no physical keyboard, the button does not suspend. The Ally's own N-KEY device does not count as a keyboard.

## Escape and recovery

Recovery is `ssh rog-ally`, and only if sshd was already enabled and that check worked. The other way in is a USB keyboard: Enter submits the password. The greeter grid cannot submit by touch, and there is no session picker. This tree has no TTY switch.

The F17 escape and the watchdog aren't in this alpha because no InputPlumber intercept ships in the tree, so there's no stuck intercept to escape. They become required when the intercept lands.

Three gaming starts in 60 seconds that never read `started` write `/run/omarchy/handheld-autologin/stop` and set `Relogin=false`. SDDM shows the greeter. You cannot pick a session there. Use SSH, or a USB keyboard's Enter. A reboot clears `/run` and the next boot writes `Relogin=true` again. From SSH, drop autologin for this boot with:

```bash
sudo rm -f /etc/sddm.conf.d/zz-omarchy-handheld.conf
sudo systemctl restart sddm
```

`systemctl restart sddm` kills the current graphical session.

### Turn autologin back on without a reboot

`apply` rewrites the drop-in and does not restart SDDM. After the stop file is gone, restart SDDM or reboot.

```bash
sudo rm -f /run/omarchy/handheld-autologin/stop
sudo omarchy-handheld-autologin apply
sudo systemctl restart sddm
```

That restart kills the current graphical session. Reboot instead if you want to keep this session until you are ready. The boot unit writes `Relogin=true` on its own once `/run` is empty.

## Rollback

```bash
sudo systemctl disable --now omarchy-handheld-autologin.service
sudo rm -f /etc/systemd/system/omarchy-handheld-autologin.service
sudo rm -f /etc/sddm.conf.d/zz-omarchy-handheld.conf
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

Reboot. Autologin is gone, so the greeter is up. A USB keyboard's Enter submits the password. There is no session picker. That leaves Steam's games and saves. `/etc/sudoers.d/omarchy-handheld-autologin` is the passwordless `fail` / `reset` / `apply` grant. `/var/lib/omarchy/handheld/desktop-lock` is the lock value.
