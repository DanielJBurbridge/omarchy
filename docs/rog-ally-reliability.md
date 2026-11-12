# ROG Ally RC71L reliability

Source behaviour and physical acceptance are separate. No suspend, reboot, service restart or installation was performed on the Ally by the reliability source worker. The single rollout owner performs the device checks below after installing a coordinated release.

## Desktop power button (R01, R03)

The default Hyprland power-button binding calls `omarchy-system-power-button`. On the original RC71L, it takes a non-blocking process lock, checks suspend availability, calls the existing secure-lock helper and requests `systemctl suspend` only after that helper succeeds. A failed lock cancels this button-initiated suspend. Concurrent button events are ignored while the request is in progress. If sleep is disabled or Suspend is hidden, the existing power menu opens. Other hardware, including ROG laptops and the Ally X, retains the power menu.

Keep `/etc/systemd/logind.conf.d/10-ignore-power-button.conf` with `HandlePowerKey=ignore`: logind must not handle the same press. Keep the existing `omarchy-sleep-lock.service` in the Hyprland session: it still protects suspend requested through the menu or another application. Its delay inhibitor is bounded by logind and cannot veto every externally requested suspend if locking fails. The new power-button path can cancel its own request before reaching logind.

Install this through the normal coordinated Omarchy package build/update; `bin/omarchy-system-power-button` and the matching `default/hypr/bindings/utilities.lua` must ship together. Do not copy only the binding. No fixed system file or package dependency changes are needed for the desktop increment. Custom user power bindings remain overrides. The rollout owner may reload the Hyprland configuration after installing both files; source workers must not reload the live session.

Rollback the desktop behaviour with a personal binding override in `~/.config/hypr/bindings.lua`:

```lua
o.rebind("XF86PowerOff", "Power menu", { menu = "system" }, { locked = true })
```

The rollout owner backs up that file before editing it and reloads Hyprland after the override. Removing that override restores the packaged policy. Leave the logind ignore setting and ordinary sleep-lock service intact.

## Acceptance owned by the rollout thread

Record the exact release commit, kernel, BIOS revision (no serial numbers), package versions and installed configuration/backups outside Git. Never publish Wi-Fi names, Bluetooth addresses or personal game/library details from diagnostic output.

1. On desktop, with a recovery keyboard available, press the power button briefly. Record exactly one suspend cycle in the system journal. Confirm a secure lock was established before suspend and touch unlock works after wake. Repeat while already locked. In a disposable test session, a missing/failed lock must cancel this power-button request. Do not deliberately break the live lock/PAM setup to test it.
2. Check the effective logind policy and inhibitors with `systemd-analyze cat-config systemd/logind.conf`, `busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandlePowerKey` and `systemd-inhibit --list`. A power-button helper must never run alongside a second button handler in the same active session.
3. Capture a desktop screenshot of the resumed lock, then unlock. On non-Ally hardware verify the same physical button opens the existing system menu. These are physical/UI checks; the focused hardware suite only checks routing, cancellation, exclusion and sequencing against stubbed system interfaces.
4. Repeat on battery and AC with a real game running. Confirm the same game continues rendering and accepting input after resume, its audio stream returns and no second Steam/game process appeared. A daemon being active is not evidence of game resume.
5. Compare speakers, headphone insert/remove, microphone capture, USB/HDMI and Bluetooth outputs before and after suspend. Select an output explicitly, keep a playing stream running, then unplug/replug and dock/undock. Check the chosen profile/route and recording still work, and the fallback returns to speakers when appropriate. Preserve user choices and WirePlumber state.
6. Wi-Fi: confirm association and real traffic before and after resume, without a NetworkManager restart. Bluetooth: pair an external controller and headset using the existing panel, then check reconnect, audio and actual input after resume without restarting BlueZ. Never infer success from `Powered=true` or `Connected=true` alone.
7. Controllers (I14–I16): test USB insertion/removal, Bluetooth disconnect/reconnect and suspend with both an external controller and the built-in controller. Check actual input, one virtual controller per intended device, stable player ordering, then a two-player game. Controller enumeration alone cannot establish local multiplayer or reconnect success.
8. P16: compare the selected power backend's readback on battery, AC, AC unplugged during sleep and AC reattached during sleep. POWER owns restoration and AC/DC policy; RELIABILITY adds no competing sysfs writer. DISPLAY owns dock/display recovery; RECOVERY owns firmware status/update instructions. Do not flash firmware during this acceptance run.

## Audio and reconnect evidence (R02, R04–R10, D07)

Omarchy's existing RC71L predicate already excludes the ROG laptop soft-mixer and microphone-gain scripts. Preserve those exclusions and the user's saved default routes. PipeWire/WirePlumber, NetworkManager, BlueZ and InputPlumber remain the owners of their device events. The desktop idle service respects Wayland idle inhibitors; a playing game must be checked with its actual inhibitor, including controller-only play. Do not disable idle locking globally as a workaround.

The current [Bazzite RC71L profiles](https://github.com/ublue-os/bazzite/tree/b8881a9db67c6a6c341413a4c770db2814a34329/system_files/deck/shared/usr/share/wireplumber/hardware-profiles/asustek%20computer%20inc.-rog%20ally%20rc71l_rc71l/wireplumber.conf.d) and [CachyOS RC71L rule](https://github.com/CachyOS/CachyOS-Handheld/blob/d38b9f0bc1d801262f71335ddc9763446ac087e9/usr/share/cachyos-handheld/rog-ally/wireplumber/alsa-card0.conf) tune the exact legacy node `alsa_output.pci-0000_09_00.6.analog-stereo` with period size 256, headroom 1024 and node suspend disabled. The Ally X rule uses a different PCI node. The common ACP microphone rule is not an HDMI profile. These are candidates for a reproduced dropout, not an instruction to force ACP instead of UCM or overwrite every audio profile. [WirePlumber documents](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/alsa.html) that disabling node suspend keeps the ALSA device busy, so battery impact and the actual installed node/profile must be checked before applying it. No such rule is installed by this source increment.

No RC71L failure has been reproduced that justifies a kernel argument, Wi-Fi module reload, Bluetooth reset, disabled USB autosuspend, ERTM override or a resume daemon. If acceptance fails, retain the pre/post state and relevant journal interval, reproduce the exact failure, then prefer the maintained driver/component fix. Do not borrow Bazzite's AYANEO-only Wi-Fi hook or a different Ally generation's profile.
