# Handheld alpha (ROG Ally RC71L)

Written for Daniel, against `feat/ally-parity-integration-20261111` at `d3747faff` (merge of #34, which includes #36, #30 and #27). This page says what that tree actually does. The specs in this directory are the design. Anything they describe that is not in the tree is under [Known gaps](#known-gaps), with the review notes in [alpha-followups.md](alpha-followups.md).

## What this alpha is

On an original 2023 ROG Ally (RC71L) this build can autologin into a Gamescope + Steam session and come back to the Omarchy desktop. It is an alpha on your own machine. It has not had a physical acceptance pass, and a lot of the handheld design (controller map, overlay, TDP, dock switching, the suspend broker) is still spec only.

## Install

You need the omarchy build from this tip, plus the optional `omarchy-gaming-session` package, Gamescope and Steam. `omarchy-handheld-autologin apply` writes `/etc/sddm.conf.d/zz-omarchy-handheld.conf` only when `omarchy-hw-rog-ally` succeeds and `omarchy-pkg-present omarchy-gaming-session` succeeds. Otherwise it deletes that file and writes nothing else. The drop-in is:

```
[Autologin]
Session=omarchy-handheld.desktop
Relogin=true
```

It does not set `User=`. The session entry runs `omarchy-handheld-autologin`, which starts `omarchy-session-start relogin`. The unit that rewrites the drop-in on boot is `omarchy-handheld-autologin.service` (`Before=sddm.service`, `ExecStart=/usr/bin/omarchy-handheld-autologin apply`). Build the session package the way [the gaming session note](../rog-ally-gaming-session.md) describes, and install Gamescope and Steam before you apply.

### Fresh install

`install/hardware/all.sh` runs `install/hardware/handheld-autologin.sh`. On an RC71L that leaf copies the unit to `/etc/systemd/system/omarchy-handheld-autologin.service`, enables it, and runs apply. The gaming package is not part of the base install, so that first apply finds no package and leaves no drop-in. After the package, Gamescope and Steam are installed, run apply once. A reboot does the same apply, because the unit is already enabled and it runs before SDDM:

```bash
sudo omarchy-handheld-autologin apply
```

The boot unit calls `/usr/bin/omarchy-handheld-autologin`. A checkout alone is not enough: the command has to be on that path (the package, or your usual dev link).

### Existing Ally install

Nothing in `migrations/` enables the unit or runs apply on a machine that is already installed. Do the leaf's steps yourself, after the gaming package is installed. The leaf does not reload systemd; reload first so enable can see the new unit.

```bash
sudo install -Dm644 "$OMARCHY_PATH/default/systemd/system/omarchy-handheld-autologin.service" \
  /etc/systemd/system/omarchy-handheld-autologin.service
sudo systemctl daemon-reload
sudo systemctl enable omarchy-handheld-autologin.service
sudo omarchy-handheld-autologin apply
```

`install/hardware/handheld-autologin.sh` is the same enable-and-apply sequence. It is sourced by the installer, not a command you run on its own.

### Check it worked

```bash
omarchy-hw-rog-ally && omarchy-pkg-present omarchy-gaming-session && echo ally-ok
systemctl is-enabled omarchy-handheld-autologin.service
cat /etc/sddm.conf.d/zz-omarchy-handheld.conf
```

You want `ally-ok`, `enabled`, and `Relogin=true` with `Session=omarchy-handheld.desktop`. Reboot. The greeter should not appear, and Steam's gaming UI should. After boot, `systemctl is-active omarchy-handheld-autologin.service` is `active` (it is a oneshot that stays up). If the drop-in is missing, the package was not installed when apply ran. If it says `Relogin=false`, the crash-loop stop file is present (`/run/omarchy/handheld-autologin/stop`).

## What works

- **Gaming session.** Undocked autologin starts Gamescope on DRM (`--backend drm -e --xwayland-count 2 --default-touch-mode 4`) and Steam (`-steamos3 -steampal -steamdeck -gamepadui`) in the scope `omarchy-gamescope-$XDG_SESSION_ID.scope`. The user target `omarchy-gaming-session.target` starts with it and stops when you leave gaming. Steam is ready when its process holds the X socket; that has 60 seconds. One retry follows, 3 seconds later. A second failure writes a recovery latch and goes to the desktop, with the notification “Gaming Mode didn’t start”. The log is `~/.local/state/omarchy/gaming-session/session.log`.
- **Coming back after a crash.** A Relogin (the autologin return) always starts gaming. It ignores the recovery latch and it ignores dock state. Three gaming starts in 60 seconds that never read `started` write the stop file, set `Relogin=false`, and restart SDDM onto the greeter. A `started` read clears the failure list and does not clear `stop`. `/run` is empty after a reboot, so the next boot writes `Relogin=true` again.
- **Desktop entry.** Until `/var/lib/omarchy/handheld/k07-landed` exists, this handheld ships `desktop-lock` as `default-off`, so the desktop is not locked. `omarchy-setup-gaming-session desktop-lock on` turns it on. `desktop-lock off` stores `explicit-off` and asks for your password in a terminal. When the effective value is `on`, `desktop()` in `omarchy-session-start` locks before Hyprland. With no physical keyboard and the value `on`, it goes back to gaming instead of showing an unlocked desktop. The Ally's own controller keyboard does not count; `omarchy-hw-physical-keyboard` ignores the N-KEY device (`0b05:1abe`), virtual devices, and uinput-like names.
- **Suspend from the desktop power button.** On the RC71L, `omarchy-system-power-button` runs `omarchy-system-sleep-lock` and then `systemctl suspend`. A failed lock cancels that suspend. With `default-off` and no physical keyboard, the lock is skipped and the button still suspends. With `on` and no physical keyboard, the button does not suspend; it tries to return to gaming. Other machines still get the power menu.
- **Gaming power button, if you installed it.** The session starts `steamos-powerbuttond` only when `omarchy-rog-ally-powerbutton` and `/usr/bin/steamos-powerbuttond` are both present. Otherwise use Steam's on-screen power menu.
- **Desktop on-screen keyboard, if wvkbd is installed.** On the RC71L, `Super + Ctrl + Y` toggles it. `omarchy-setup-rog-ally-keyboard --configure-reviewed-package` adds the bar button when `wvkbd-mobintl` is already installed. Switching to gaming runs `omarchy-toggle-desktop-keyboard stop` first.
- **Greeter keys after autologin stops.** `default/sddm/omarchy/Main.qml` draws a grid of letters and digits into the password field. A USB keyboard's Enter submits. The grid has no backspace, shift, enter, or symbols, and it is on every machine's greeter, not only the Ally.
- **Session preferences.** `omarchy-setup-gaming-session` can set `default` (`gaming`, `desktop`, `last`, `auto`), a one-shot `next`, render size / fps / upscaler, and `overlay on` (mangoapp, only when `mangoapp` is installed). Run it as yourself, never sudo, except `desktop-lock`.

The built-in pad is still the firmware Xbox 360 pad (`xpad`). Steam can use that pad without anything in this tree mapping it.

## Switching modes

Autologin uses **Omarchy (session preference)**. **Omarchy Gaming** at the greeter forces gaming and clears the recovery latch. **Omarchy (Hyprland uwsm)** is the ordinary desktop and does not run this supervisor. Sign in with the preference session once before the desktop launcher will switch.

**Keyboard or a terminal**

- Desktop to gaming: exit Steam, then run `omarchy-launch-gaming-session`, or open the **Omarchy Gaming** app. It logs the desktop out. Save your work first.
- Gaming to desktop: run `omarchy-launch-gaming-desktop` inside that login, or leave Steam. Steam's Power → Switch to Desktop is the same path: the session puts a private `steamos-session-select` on Steam's PATH, and it accepts only `plasma`.

There is no `Super + Ctrl + G` binding and no Omarchy menu row for the switch.

**Controller**

In Gaming Mode the Guide button (the Xbox button on the pad) is Steam's own button, because Steam is started with `-gamepadui`. Use Steam's menu, Power, Switch to Desktop. This tree does not map Armoury, Command Centre, or the back paddles, so there is no Omarchy controller chord for the switch.

**Dock**

Plugging in a dock does not change session. The `auto` preference would ask `omarchy-display-rog-ally docked`, and that command is not in this tree, so `auto` stays on gaming. A Relogin starts gaming even when a dock is plugged in.

## Escape and recovery

**Armoury long-press.** Spec 07 and spec 04 say the only Armoury escape is firmware `KEY_F17`, then 1 second, and the gaming bridge forces InputPlumber `InterceptMode` to 0. The bridge that would do that (`omarchy-rog-ally-input-gaming.service`) is not in this tree, and nothing here sets `InterceptMode`. Holding Armoury does not clear an intercept. The overlay watchdog (`WatchdogSec=1s` in spec 04) is not in this tree either.

**Crash loop and a black screen.** A gaming start that exits without the ready FIFO reading `started` is a failure. Three of those, whose timestamps sit inside 60 seconds, write `/run/omarchy/handheld-autologin/stop` (`root:root`, mode `0644`) and restart SDDM with `Relogin=false`. You should get the greeter, not another gaming attempt. The handheld session entry then exits immediately; pick **Omarchy (Hyprland uwsm)** to get a desktop. A reboot clears `/run`, and the boot unit writes `Relogin=true` again.

If the screen stays black and the greeter never shows, use SSH or a TTY. From there:

```bash
sudo rm -f /etc/sddm.conf.d/zz-omarchy-handheld.conf
sudo systemctl restart sddm
```

That drops autologin for this boot. To turn autologin back on without a reboot, remove the stop file and apply again:

```bash
sudo rm -f /run/omarchy/handheld-autologin/stop
sudo omarchy-handheld-autologin apply
```

**SSH.** This tree does not set the hostname and does not start sshd. If this Ally already answers as `rog-ally` and sshd is already up, `ssh rog-ally` from another machine on the same network is the way in. Set that up while you still have a desktop: `omarchy-setup-security-sshd`.

**TTY.** With a USB keyboard, Ctrl+Alt+F3 (or another function key) reaches a text login. It asks for your password. Nothing in this tree autologins a getty, and the built-in pad does not type there.

## Rollback

This returns you to ordinary Omarchy sign-in. It does not delete Steam games or saves.

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

Reboot, and at the greeter choose **Omarchy (Hyprland uwsm)**.

`/etc/sudoers.d/omarchy-handheld-autologin` is the passwordless grant for `fail`, `reset`, and `apply`. It ships with the settings package, so removing it lasts until that package is installed again. `/var/lib/omarchy/handheld/desktop-lock` is the lock value; remove that file if you set it. If you installed the power-button companion, `omarchy-pkg-drop omarchy-rog-ally-powerbutton` removes it. `omarchy-setup-rog-ally-keyboard --remove` drops the desktop keyboard button.

The session commands stay in the omarchy package until you roll that package back. With the drop-in gone and the stock session chosen, they do not run at boot.

## Known gaps

Still spec, not in this tree. Notes from review are in [alpha-followups.md](alpha-followups.md).

- Controller map, InputPlumber profiles, and the desktop and gaming bridges (spec 01). `omarchy-gaming-input-profile` loads `default/rog-ally-input/profiles/gaming.yaml`, which is not in this tree, and does nothing when the daemon is absent.
- Armoury escape (`KEY_F17`, then 1 second, `InterceptMode` 0) and the overlay watchdog (spec 04, spec 07 §3.6).
- Quick-access overlay, fan, RGB, and TDP. The session will restart `omarchy-ally-tdp-shim.service` if that unit is already installed. The unit is not in this tree. There is no TDP writer here.
- Dock prompts and any automatic dock or undock session change. `omarchy-display-rog-ally` is not in this tree.
- Menu row and `Super + Ctrl + G` for Switch to Gaming (spec 02).
- Suspend broker (`omarchy-handheld-suspend.service`), the handheld logind drop-in, the idle return to gaming, and the power-off backstop (spec 02 §7.7).
- First-boot handheld wizard and buffyboard (spec 03).
- Gaming notifications (spec 05) and the accessibility pack (spec 06).
- The `osk` controller profile, a themed wvkbd, and a Command Centre chord that opens a keyboard (spec 07).
- A greeter keyboard that can backspace, shift, enter symbols, and submit. AUTH still owns that (spec 02 AC 59).
- A migration that enables autologin on an Ally that is already installed. The commands are under [Existing Ally install](#existing-ally-install).
