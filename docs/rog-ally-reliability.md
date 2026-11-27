# ROG Ally RC71L reliability

The rollout owner performs the physical checks below after installing a coordinated release. The 27 November controller investigation used read-only checks on the Ally.

## Gaming controller and suspend

On 27 November 2026, `rog-ally` running `linux-omarchy 7.2.15-6-omarchy` and `inputplumber 0.84.0-1.779` aborted two `s2idle` attempts at 11:18:38 and 11:18:40. The kernel reported that USB device `9-1` had yet to suspend and that `vhci_hcd.0` had one active connection, then returned `-16` (`EBUSY`). Sysfs identified that device as `28de:1205` (`Valve Corporation Steam Controller`), and InputPlumber listed `deck` on the gaming composite.

The gaming profile now uses `deck-uhid`. InputPlumber v0.84.0 creates the virtual pad through `/dev/uhid` and assigns `28de:12fd` (`ROG Ally Controller`) to the `ASUS ROG Ally` composite. Its Deck-format reports encode ABXY, gyro, L4/R4 and Quick Access. The USB/IP target's `28de:1205` identity depends on a USB interface number Steam checks. Steam Input can identify the Ally PID and display a different controller image. Verify glyphs and bindings in the installed Steam client. [InputPlumber UHID target](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/src/input/target/steam_deck_uhid.rs) · [InputPlumber product IDs](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/src/drivers/steam_deck/mod.rs) · [InputPlumber maintainer on Steam's Ally mapping](https://github.com/ShadowBlip/InputPlumber/issues/638)

The running kernel ships `uhid.ko.zst` with `CONFIG_UHID=m`, exposes the `/dev/uhid` character node and lets the root InputPlumber service see it. The installed Steam and InputPlumber udev rules grant active-seat access to Valve virtual hidraw devices. The broker checks both the D-Bus attachment and the Ally hidraw device because the former can appear before the driver creates the latter. It tries `ds5-edge` on failure and requires a live fallback pad. Fresh installs skip USB/IP module provisioning. Existing installations can have `vhci_hcd` loaded, since the suspend veto requires an active connection.

After installing the paired archives and starting a new gaming session, check that `inputplumber device 0 targets list` shows `deck-uhid` or a logged `ds5-edge` fallback. Check that the old `28de:1205` device is absent from the `vhci_hcd` bus and test suspend and resume in a game. Confirm ABXY glyphs, gyro, both grips and Quick Access in Steam. The read-only audit saw an IMU-only composite and no physical `0b05:1abe` HID device on the running Ally. If it remains IMU-only, record that separately. The profile broker requires a matching physical RC71L source before it replaces any target.

## Desktop power button (R01, R03)

The original RC71L’s desktop power button and **System → Suspend** both run `omarchy-system-suspend`. It shares the power-button process lock, checks suspend availability and asks the secure-lock helper to apply the current handheld policy before requesting sleep. A failed lock cancels the request. If sleep is disabled or Suspend is hidden, the button opens the power menu. Other hardware, including ROG laptops and the Ally X, retains the power menu on button press and goes directly to systemd from the Suspend row.

Keep `/etc/systemd/logind.conf.d/10-ignore-power-button.conf` with `HandlePowerKey=ignore`: logind must not handle the same press. Keep the existing `omarchy-sleep-lock.service` in the Hyprland session: it still protects suspend requested through the menu or another application. Its delay inhibitor is bounded by logind and cannot veto every externally requested suspend if locking fails. The new power-button path can cancel its own request before reaching logind.

Install this through the normal coordinated Omarchy package build/update; `bin/omarchy-system-power-button` and the matching `default/hypr/bindings/utilities.lua` must ship together. Do not copy only the binding. No fixed system file or package dependency changes are needed for the desktop increment. Custom user power bindings remain overrides. The rollout owner may reload the Hyprland configuration after installing both files; source workers must not reload the live session.

Rollback the desktop behaviour with a personal binding override in `~/.config/hypr/bindings.lua`:

```lua
o.rebind("XF86PowerOff", "Power menu", { menu = "system" }, { locked = true })
```

The rollout owner backs up that file before editing it and reloads Hyprland after the override. Removing that override restores the packaged policy. Leave the logind ignore setting and ordinary sleep-lock service intact.

## Gaming power button (R01, R02)

Use the maintained [Valve powerbuttond v4.2](https://gitlab.steamos.cloud/holo/powerbuttond/-/tree/v4.2), commit `9392e68883fdb0c40bc01ab39ae75c83a541e413`, under BSD-2-Clause. [CachyOS currently packages 4.2-1](https://packages.cachyos.org/package/cachyos/x86_64/steamos-powerbuttond). The upstream daemon reads input events and forwards Steam's short/long power-press URIs; Steam decides the gaming action. The unmodified daemon blocks waiting for input and does not poll hardware or suspend the system itself. No archived ShadowBlip power daemon is used.

The reviewed companion recipe is `default/rog-ally/powerbutton/PKGBUILD`. It builds the pinned upstream source and installs only these files:

| Installed path | Purpose |
| --- | --- |
| `/usr/bin/steamos-powerbuttond` | Unmodified upstream daemon |
| `/usr/share/licenses/omarchy-rog-ally-powerbutton/LICENSE` | Upstream BSD notice |
| `/usr/lib/udev/hwdb.d/70-omarchy-rog-ally-power-button.hwdb` | Mark KEY_POWER candidates using complete capability tokens |
| `/usr/lib/udev/rules.d/70-omarchy-rog-ally-power-button.rules` | Grant active-seat access only for the ACPI power button (input parent name `Power Button` and phys `PNP0C0C/button/input0` or `LNXPWRBN/button/input0`) when `/usr/bin/omarchy-hw-rog-ally` succeeds |

It does not install upstream's global input access/scancode overrides or the `gamescope-session.service.wants` link. It conflicts with separately installed Steam power-button daemon packages; resolve an existing handler deliberately rather than enabling both. InputPlumber must leave the real power button to this owner; no KEY_POWER mapping to an additional suspend action. No input-group membership is required.

On an RC71L with `omarchy-gaming-session` installed, run `omarchy-setup-gaming-session install-power-button` to install or repair the companion. The hardware leaf and its migration also attempt installation when the gaming-session package is already present. A fresh install can mark the migration before the build runs. If the companion is missing, use the explicit setup command to retry once network access is available. The command builds in a disposable directory and installs with `pacman -U`. The build is capped at 90 seconds. A git transfer under 1000 bytes/s for 30 seconds aborts. For a hand build, use the same recipe as an ordinary user, then run `sudo pacman -U /path/to/omarchy-rog-ally-powerbutton-4.2-1-x86_64.pkg.tar.zst`. Record the artifact hash and package version. The setup command reloads the hwdb and retriggers input devices after installation. A hand install needs the following steps so the active seat receives the access tag.

```bash
sudo systemd-hwdb update
sudo udevadm control --reload
sudo udevadm trigger --action=change --subsystem-match=input --sysname-match='event*'
sudo udevadm settle
```

These commands are rollout instructions, not actions executed by this source worker. Check the physical power-button event's `STEAMOS_POWER_BUTTON=1` property and active-seat ACL afterwards. Do not chmod input devices or give all users access. The program check preserves the central model predicate, including the short `ROG Ally` product with an RC71L board; a laptop or Ally X must not receive this policy.

SESSION calls `omarchy-launch-gaming-powerbutton` inside the Steam child wrapper after Gamescope supplies `DISPLAY`, with `XDG_CURRENT_DESKTOP=gamescope` and no `HYPRLAND_INSTANCE_SIGNATURE`. The helper runs the daemon in the foreground under the same exclusion lock used by the desktop button. SESSION owns its background PID, kill/wait on Steam exit and enclosing `omarchy-gamescope-$XDG_SESSION_ID.scope`. Neither this helper nor a global systemd unit starts on the desktop. If the optional companion is absent, SESSION must skip starting the helper and report button handling unavailable. If the daemon exits early, inspect device access and its journal/log instead of claiming a working button. Gamescope does not start UWSM or `graphical-session.target`; the desktop lock monitor starts with the returned desktop session.

Gaming acceptance: after installing SESSION and this companion together, press briefly in Steam and in a real game, check exactly one requested action, resume into the same game, then hold briefly to inspect Steam's power menu. Keep this distinct from firmware's emergency power-off hold. Return to desktop and confirm no daemon remains in the gaming scope and the desktop lock-before-suspend path works. Repeat session entry/exit and Steam failure recovery; no orphan handler may remain. Suspend from Steam does not prove a trusted desktop-style gaming lock; record the gaming authentication/resume behaviour separately and preserve the ordinary authenticated desktop login and lock policy.

Rollback: leave gaming through its normal return action, verify the session scope stopped the daemon, then remove the optional companion with `omarchy-pkg-drop omarchy-rog-ally-powerbutton`. Rebuild/reload the hwdb using the commands above. Old udev properties/tags may remain for already enumerated devices until replug or the next normal boot; do not treat a change event as proof every old seat ACL was removed. Sign out to release active-seat access, and check properties/ACLs after the next normal boot. Do not stop logind or restart the active desktop. Removing this package disables gaming button handling; use Steam's on-screen power menu while diagnosing. The desktop override described earlier independently restores its menu policy.

## Acceptance owned by the rollout thread

Record the exact release commit, kernel, BIOS revision (no serial numbers), package versions and installed configuration/backups outside Git. Never publish Wi-Fi names, Bluetooth addresses or personal game/library details from diagnostic output.

1. On desktop, with a recovery keyboard available, press the power button briefly. Record exactly one suspend cycle in the system journal. Confirm a secure lock was established before suspend and touch unlock works after wake. Repeat while already locked. In a disposable test session, a missing/failed lock must cancel this power-button request. Do not deliberately break the live lock/PAM setup to test it.
2. Check the effective logind policy and inhibitors with `systemd-analyze cat-config systemd/logind.conf`, `busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandlePowerKey` and `systemd-inhibit --list`. A power-button helper must never run alongside a second button handler in the same active session.
3. Capture a desktop screenshot of the resumed lock, then unlock. On non-Ally hardware verify the same physical button opens the existing system menu. These are physical/UI checks; the focused hardware suite only checks routing, cancellation, exclusion and sequencing against stubbed system interfaces.
4. Repeat on battery and AC with a real game running. Confirm the same game continues rendering and accepting input after resume, its audio stream returns and no second Steam/game process appeared. A daemon being active is not evidence of game resume.
5. Compare speakers, headphone insert/remove, microphone capture, USB/HDMI and Bluetooth outputs before and after suspend. Select an output explicitly, keep a playing stream running, then unplug/replug and dock/undock. Check the chosen profile/route and recording still work, and the fallback returns to speakers when appropriate. Preserve user choices and WirePlumber state.
6. Wi-Fi: confirm association and real traffic before and after resume, without a NetworkManager restart. Bluetooth: pair an external controller and headset using the existing panel, then check reconnect, audio and actual input after resume without restarting BlueZ. Never infer success from `Powered=true` or `Connected=true` alone.
7. Controllers (I14–I16): test USB insertion/removal, Bluetooth disconnect/reconnect and suspend with both an external controller and the built-in controller. Check actual input, one virtual controller per intended device, stable player ordering, then a two-player game. Controller enumeration alone cannot establish local multiplayer or reconnect success.
8. P16: compare TDP readback on battery, AC, AC unplugged during sleep and AC reattached during sleep. The writer is `bin/omarchy-ally-tdp-apply`. It stores the requested watts and writes SPL, then SPPT, then FPPT `current_value`, then reads all three back. Policy ceilings in that script are battery 20/20/25 (SPL/SPPT/FPPT) and AC SPL 30. On AC, SPPT and FPPT ceilings are the boot-captured max. On the stock tables that is 43 and 53, so an AC request of 30 applies 30/43/53 (`test/shell.d/ally-tdp-test.sh`). Each value is also clamped to the live firmware-attributes `min_value` and `max_value`. There is no hard 25 W battery cap and no hard 30 W cap on SPPT or FPPT. `--set` and `--reassert` flock `/run/omarchy-ally-tdp.lock`. Resume is `omarchy-ally-tdp-resume.service`: `ExecStop` runs `--reassert` after wake. A `Mains` supply going online or offline starts `omarchy-ally-tdp-source.service`, which runs the same verb (`default/udev/99-omarchy-ally-tdp.rules`). The session shim is `omarchy-ally-tdp-shim.service` (`bin/omarchy-ally-tdp-shim`, session-bus `TdpLimit1`). It does not write sysfs. Stock steamos-manager is not shipped and is not started. `omarchy-ally-power.service` is not in this tree. Do not start it. Missing `asus-armoury` attributes make the writer exit. `install/hardware/asus/ally-tdp.sh` runs `omarchy-ally-tdp-install`. RELIABILITY adds no second writer. DISPLAY owns dock/display recovery; RECOVERY owns firmware status/update instructions. Do not flash firmware during this acceptance run. The contract is [spec 04 §5.1](handheld/04-quick-access-overlay.md).

Useful read-only evidence for the rollout owner's private before/after logs:

```bash
uname -r
pacman -Q linux-firmware alsa-ucm-conf pipewire wireplumber networkmanager bluez inputplumber omarchy-rog-ally-powerbutton
wpctl status -n
pactl --format=json list cards
pactl --format=json list sinks
pactl --format=json list sources
pactl get-default-sink
pactl get-default-source
nmcli -f DEVICE,TYPE,STATE device status
systemctl --user status omarchy-sleep-lock.service omarchy-ally-tdp-shim.service
systemctl status omarchy-ally-tdp-resume.service
```

An absent package/unit is an explicit observation, not a reason to install a kernel or enable a second power owner. In the actual active session, retain the audio node names, active card profiles, available ports and default sink/source across each transition. Bluetooth node names and NetworkManager output may identify private devices; do not publish the raw logs. Check real traffic against an endpoint that worked before suspend, and record game/headset/controller operation separately. Capture only the relevant journal interval with `journalctl -b --since '<baseline time>' -u NetworkManager -u bluetooth` and the corresponding kernel and user-service interval when a failure is reproduced.

## Audio and reconnect evidence (R02, R04–R10, D07)

Omarchy's existing RC71L predicate already excludes the ROG laptop soft-mixer and microphone-gain scripts. Preserve those exclusions and the user's saved default routes. PipeWire/WirePlumber, NetworkManager, BlueZ and InputPlumber remain the owners of their device events. The desktop idle service respects Wayland idle inhibitors; a playing game must be checked with its actual inhibitor, including controller-only play. Do not disable idle locking globally as a workaround.

The current [Bazzite RC71L profiles](https://github.com/ublue-os/bazzite/tree/b8881a9db67c6a6c341413a4c770db2814a34329/system_files/deck/shared/usr/share/wireplumber/hardware-profiles/asustek%20computer%20inc.-rog%20ally%20rc71l_rc71l/wireplumber.conf.d) and [CachyOS RC71L rule](https://github.com/CachyOS/CachyOS-Handheld/blob/d38b9f0bc1d801262f71335ddc9763446ac087e9/usr/share/cachyos-handheld/rog-ally/wireplumber/alsa-card0.conf) tune the exact legacy node `alsa_output.pci-0000_09_00.6.analog-stereo` with period size 256, headroom 1024 and node suspend disabled. The Ally X rule uses a different PCI node. The common ACP microphone rule is not an HDMI profile. These are candidates for a reproduced dropout, not an instruction to force ACP instead of UCM or overwrite every audio profile. [WirePlumber documents](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/alsa.html) that disabling node suspend keeps the ALSA device busy, so battery impact and the actual installed node/profile must be checked before applying it. No such rule is installed by this source increment.

No RC71L failure has been reproduced that justifies a kernel argument, Wi-Fi module reload, Bluetooth reset, disabled USB autosuspend, ERTM override or a resume daemon. If acceptance fails, retain the pre/post state and relevant journal interval, reproduce the exact failure, then prefer the maintained driver/component fix. Do not borrow Bazzite's AYANEO-only Wi-Fi hook or a different Ally generation's profile.
