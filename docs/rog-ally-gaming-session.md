# ROG Ally standalone gaming session

Changed 12 November 2026 to match [spec 02](handheld/02-mode-switch-and-dock.md). Autologin into gaming is Daniel's decision (12 Nov 2026). The handheld variant autologins into gaming by default and falls back to the desktop if gaming does not start. What changed: the sentences that forbade autologin and promised a password in front of every login, and the later sentence that locked every desktop start. Until AUTH K07 (the lock-screen touch keyboard) has merged, the handheld ships `desktop-lock` as `default-off`, which is stored separately from a user's `explicit-off`. This package still does not guess a username. The SDDM file it may write is the persistent `User=` drop-in, and only on an Ally. It does not write PAM, `Session=` or `Relogin=`.

This optional implementation covers the SESSION work in G01–G12 for the original RC71L. It launches upstream Gamescope directly on DRM, with the installed Steam and existing library, and returns to Omarchy Hyprland. It does not install another desktop, change PAM, replace the kernel or repositories, or enable a hardware power writer. The one SDDM file it writes is `/etc/sddm.conf.d/omarchy-handheld-user.conf`, and only on an Ally, and only with a `User=` already recorded by the installer. That file is not in the package manifest. It does not guess a username, and it does not write `Session=` or `Relogin=`. Those stay in the file `apply` rewrites. Desktop Big Picture remains available separately.

## Session contract

The optional `omarchy-gaming-session` package registers three SDDM entries.

| File | Visible name | Behaviour after authentication |
| --- | --- | --- |
| `omarchy-gamescope.desktop` | Omarchy Gaming | Explicitly launch gaming, clearing the recovery latch |
| `omarchy-handheld.desktop` | Omarchy (session preference) | Apply the boot preference on the first automatic login, then use the SDDM relogin policy |
| `omarchy-managed-desktop.desktop` | Omarchy (handheld desktop) | Start the managed Hyprland desktop after local sign-in |

The existing `omarchy.desktop` / Omarchy (Hyprland uwsm) is an independent password sign-in and recovery route. The handheld variant autologins into **Omarchy (session preference)**. When the first automatic login selects Desktop and the desktop lock policy is `on`, the supervisor returns directly to SDDM for sign-in. If Gaming does not start, the supervisor falls back after one retry. Until K07, the handheld value is `default-off`, so the fallback desktop is unlocked. Before the marker is present, that same handheld also skips the ordinary lock on suspend unless a physical keyboard is attached at that moment. The Ally's built-in controller keyboard does not count, and an explicit `on` with no physical keyboard returns to gaming instead of locking. The marker brings the ordinary suspend lock back. Other variants stay `on` and lock before the first frame. A user's `explicit-off` is a different stored value and is not the shipped default.

`omarchy-session-start` is a pre-UWSM login entrypoint. It uses the existing canonical environment bootstrap, then runs UWSM or a Gamescope scope within the authenticated logind session. No username, UID, home directory or display number is guessed. UWSM intentionally excludes `XDG_SESSION_ID` from the desktop user manager; the selector carries its managed login ID as `OMARCHY_HANDHELD_SESSION` through UWSM's normal environment import and cleanup so desktop actions address the correct supervisor. On machines outside `omarchy-hw-rog-ally`, the optional entries run the ordinary Hyprland command without reading gaming preferences.

Gaming does not start `graphical-session.target`; desktop layer-shell panels and the Hyprland lock monitor do not run there. The scope `omarchy-gamescope-$XDG_SESSION_ID.scope` contains Gamescope, Steam, games and the optional power-button helper. Stop requests clean up that scope before starting UWSM. Games started independently through another service are outside this scope's ownership.

## Controller setup on a stock install

The optional `omarchy-gaming-session` companion depends on `inputplumber`. On an RC71L the companion installs the greeter pointer unit and the profile broker. The broker authorises the active local account recorded in `/etc/sddm.conf.d/omarchy-handheld-user.conf`. Managed desktop, gaming, and the return to the greeter use the integrated profiles. The historical `omarchy-rog-ally-input` companion is separate.

When pacman first installs InputPlumber alongside the companion on an RC71L, a post-transaction hook enables the daemon for the next boot. This puts it in the same systemd transaction as the greeter pointer unit, which waits for it. The hook skips masked units and only runs on installation of InputPlumber. If InputPlumber is already installed, its enablement remains the administrator's choice. Its own udev rules can still activate a disabled daemon on board `RC71L`; a mask blocks device activation. After boot, check `systemctl is-active inputplumber.service omarchy-inputplumber-profile.service`. Companion upgrades also preserve existing disables and masks on the Omarchy pointer and broker units.

Keyboard activation on menu search is a user preference. To opt in, merge `"onScreenKeyboard": true` into the `menu` object in `${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json`. The companion leaves that file and the user's session preference in place. [Desktop keyboard setup](rog-ally-touch-keyboard.md)

## Preferences and use

```bash
# Run as the signed-in user, never sudo.
omarchy-setup-gaming-session default auto
omarchy-setup-gaming-session default gaming
omarchy-setup-gaming-session default desktop
omarchy-setup-gaming-session default last
omarchy-setup-gaming-session next gaming
omarchy-setup-gaming-session next desktop
omarchy-setup-gaming-session next clear
omarchy-setup-gaming-session status
omarchy-setup-gaming-session reset
```

The preference selector (`omarchy-session-start preferred`) uses `auto` for a missing or invalid preference on an RC71L with the gaming companion. Auto selects Desktop when it detects an external display and Gaming otherwise. An invalid preference queues the “Session preference reset” notice for the next managed Desktop start. In the preference selector, `next` overrides the persistent choice once and is consumed **before** starting it, including when startup fails. It survives a reboot until a session consumes it. `last` remembers the most recently entered desktop or gaming mode. Returning from gaming enters desktop, making desktop the last mode. `reset` removes preferences, render settings, overlay selection, remembered library and recovery state. It preserves logs and all Steam data.

The first automatic SDDM login of each Linux boot uses this selector after logind confirms the local autologin session. The boot record is stored with per-user gaming state and survives an SDDM restart. Subsequent logins through this entry, or logins where the boot record or identity cannot be confirmed, use the relogin policy. That policy defaults to Gaming and consumes `next=desktop` once. A queued `next=gaming` remains available for the next preferred entry. The hard Gaming failure limit applies to both policies.

From the managed Hyprland session, save work and fully exit Steam, then choose the **Omarchy Gaming** application or run `omarchy-launch-gaming-session`. This closes desktop applications using Omarchy's existing logout action. A transient user worker owns the switch request and removes it if logout fails, so submitting a logout job cannot accidentally change a later ordinary logout. The launcher stops wvkbd while the departing Wayland display is still available. It refuses an unmanaged desktop, missing dependencies or a surviving Steam client rather than forwarding a gaming request to that client's old display. After installing the increment, sign out and choose the preference session once to enable this action.

In gaming, use Steam's Power → Switch to Desktop, exit Steam, or run `omarchy-launch-gaming-desktop` within that login. Steam's session-selector hook is supplied through a **private gaming PATH**, accepting only its `plasma` return argument and routing to Hyprland. `omarchy-gaming-steam` probes Steam's environ against `PATH=/usr/bin:/bin`. If that parent PATH still contains the private directory, or the environ cannot be read, the private directory stays. No global `steamos-session-select` binary or login policy is replaced. The return action ends running games/downloads in this session; save first. Downloads can resume when Steam next starts. If Steam's client build does not honour the PATH hook, Exit Steam is the fallback; that hook must be checked on the installed client.

Steam owns Guide+West (Xbox X) for its keyboard and Guide+South for quick access. INPUT owns translation of hardware buttons and calls `omarchy-hw-rog-ally-input gamepad` on entry when `omarchy-rog-ally-input` is installed. Its desktop bridge restores mouse mode at Hyprland start. Session code creates no second input mapper. Hardware button navigation, focus interception and the Steam quick-menu power controls still require physical acceptance.

## Removable library

On the original Ally with the optional Gaming Session installed, insert the card or drive in Desktop Mode. Open **Setup → Gaming → Removable Library** and tap the filesystem that holds your existing games. The second line shows its UUID so you can distinguish identical labels. To stop remembering it, open the same picker and tap **Forget remembered library**, even with the drive disconnected. This applies from the next Gaming login.

At Gaming login and on reinsertion, the session asks UDisks to mount that UUID using the signed-in user's permissions. It reuses an existing desktop mount and leaves a safely unmounted card alone until reinsertion or the next Gaming login. The session skips the mounted root filesystem, drives UDisks marks as system or excluded from automount, filesystems configured in fstab and duplicate UUIDs visible at the same time. After a duplicate, disconnect both copies and insert only the intended one. A single attached clone with the same UUID is indistinguishable from the original.

Stock Omarchy follows the e2fsprogs rule that disables automatic mounting of ext2, ext3 and ext4 filesystems. For an existing ext4 library, mount the card in the desktop file manager before switching to Gaming Mode. Steam can use that existing mount. After removing the card, return to the desktop to mount it again.

UDisks chooses the mount point. Two drives with the same label can receive different paths depending on insertion order. If Steam needs the existing library folder selected again, use its **Settings → Storage** controls. Mount errors and read-only results are recorded in the user's Gaming Session log. The companion keeps the filesystem's existing ownership and permissions.

## Render settings and optional integrations

```bash
omarchy-setup-gaming-session display native
omarchy-setup-gaming-session display 720p 40 fsr
omarchy-setup-gaming-session display 900p 60 linear
omarchy-setup-gaming-session display 1080p 0 nis
omarchy-setup-gaming-session overlay on
omarchy-setup-gaming-session overlay off
```

These select game rendering dimensions, Gamescope's `--framerate-limit` and its `-F` upscaling filter. FPS choices are 0 (disabled), 30, 40, 45, 60, 90 and 120. Filter choices are linear, nearest, fsr and nis. Native leaves dimensions to Gamescope. They do not force a physical output mode, refresh rate, HDR, orientation or VRR. Gamescope's simple frame limiter rounds to refresh-rate divisors; the requested number is not proof of measured game performance. FSR/NIS here are compositor spatial filters, not game-native frame generation or temporal upscaling.

For a fixed 120 Hz panel, 30, 40 and 60 fps each allow an even number of refreshes per frame. At a fixed 60 Hz, try 30 or 60 fps. Apply the render preference before starting Gaming Mode. The timing overlay can show whether the game sustains it. [Gamescope frame limiter](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L6845-L6875)

On the original ROG Ally, run `omarchy games output` after connecting a dock to see the next session’s preference and the native outputs you can select. For example, `omarchy games output DP-1` saves a listed external display, `omarchy games output internal` chooses the built-in panel and `omarchy games output auto` lets Gamescope choose. Omarchy follows the external display’s EDID across connector renames on the internal panel’s graphics card. If that display is unplugged or two connected screens report the same identity, the command shows the built-in fallback and keeps the saved preference for when the display returns.

If sound moves to the hub when you connect it, open **Audio** on the desktop with `Super + Ctrl + A` and select the built-in speakers. You can also cycle outputs with `Shift + Mute`. Selecting the speakers moves playing apps and saves the output preference. Display selection is independent, so you can use the speakers while playing on an external screen.

Overlay selection adds `--mangoapp` only when enabled and `mangoapp` is installed. Install the GAMES owner's optional overlay tools first. Ordinary MangoHud injection and its `fps_limit` are not used for this compositor session.

### Gaming Mode power controls

On the original ROG Ally, open **Quick Access → Performance → Advanced** in Gaming Mode. The performance presets request the live firmware minimum, 20 W or 30 W for Low Power, Balanced and Performance. Choose **Custom** to adjust **TDP Limit** directly. Custom keeps the current limit when selected. Performance can still be selected at 20 W on battery because the writer retains the 30 W request for when AC returns. These are TDP presets. The firmware's fan and thermal profile remains under firmware control.

If the controls are missing, switch to Desktop and open **Setup → Gaming**, or **System → Gaming Recovery → Gaming power limits**. The status distinguishes a missing Steam power service, unavailable firmware controls and a competing power service. It is also available as `omarchy setup ally-power gaming-status`. If the service needs repair, verify that the runtime, settings and Gaming Session companion come from the same build.

If ASUS owns power tuning, the Gaming setup offers **Ally Power Controls**. Open it on the built-in display and select **Use Omarchy power controls**. This authorises a systemd mask that pauses `asusd` across reboots, including ASUS-managed features such as Aura. The existing firmware limits are left in place during the handoff. Return to Gaming Mode to use Steam's controls. **Restore ASUS power controls** in Desktop Mode restores the recorded ASUS service states. Compare the current wattage and charge ceiling after restoring because the services may apply their own settings. The command also provides `omarchy setup ally-power status`, `use-omarchy` and `restore-asus`, including for retry after an interruption.

Desktop Power Saver, Balanced and Performance use the same request while Omarchy owns tuning. The desktop panel leaves its presets unselected when Steam uses Custom. Desktop-only installations use Power Profiles Daemon with separate AC and battery preferences.

The session shim `omarchy-ally-tdp-shim` advertises the SteamOS Manager `TdpLimit1` and `PerformanceProfile1` interfaces on the session bus when the writer reports writable firmware. The writer `omarchy-ally-tdp-apply` serialises changes with `/run/omarchy-ally-tdp.lock`. It clamps the firmware's sustained, boost and peak limits to 20/20/25 W on battery. AC is capped at 30 W sustained and the firmware's boot-captured boost and peak maxima, normally 43 and 53 W. The resume unit and the mains change watcher reapply the saved request. See the [writer contract](handheld/04-quick-access-overlay.md#51-power-authority) and the [SteamOS Manager interface](https://github.com/evlaV/steamos-manager/blob/85fbd8f/data/interfaces/com.steampowered.SteamOSManager1.xml).

If the `omarchy-rog-ally-powerbutton` companion and `/usr/bin/steamos-powerbuttond` are installed, the Steam child wrapper starts `omarchy-launch-gaming-powerbutton` after Gamescope provides DISPLAY. It owns that process's PID and kill/wait cleanup. The helper forwards upstream Steam power URIs; it does not run the desktop lock flow. No global powerbuttond unit is enabled.

## Failure recovery and evidence

The supervisor waits for process events and private FIFOs. A single 60-second startup deadline (`OMARCHY_GAMING_READY_TIMEOUT`, default 60) bounds a compositor whose Steam child never gains a display connection. There is no background polling. The ready signal is written only after that Steam process holds the X socket for `DISPLAY`. A live pid with no display connection is not ready. Steam can remain on its own update/sign-in UI after that without a further time limit. One automatic retry follows a retryable failure, 3 seconds apart.

An early compositor exit, nonzero Steam result, invalid settings or a missing dependency returns to Hyprland and writes a recovery latch. Spec 02 adds one automatic retry before that fallback, then the latch. Further preference logins choose desktop until an explicit `default`, `next`, or direct Gaming choice clears it. Steam is not relaunched in a loop. Normal Steam exit and explicit desktop return also start Hyprland. That desktop start uses the spec 02 choke point, and locks first only when `desktop-lock` is `on`. If Hyprland itself fails, the selector exits to SDDM rather than retrying it.

State is private to the user under `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/gaming-session`. Current and previous logs are `session.log` and `session.previous.log`. They contain upstream diagnostic output and may contain personal paths; review/redact before sharing. Runtime FIFOs and mode markers are under the existing user's runtime directory, separated by logind session ID.

Focused regression coverage extends `test/shell.d/gaming-setup-test.sh`. It executes the actual preference parser, supervisor, Steam wrapper and private return hook, with external compositor/logind/systemd boundaries replaced by fixtures. It checks consumed one-shot selection, parser rejection, compositor crash/early exit/timeout, Steam failure even when Gamescope masks its status, desktop return, wvkbd departure, missing dependencies, hardware and input guards, overlay/output argument handoff. It does not start an ally-power unit. This is orchestration evidence, not a GPU, controller, touch, power-button or game test.

## Package build and deployment

Only the designated Ally rollout owner installs this increment. First build and install the Omarchy runtime and settings packages from this exact reviewed source through the existing `omarchy-pkgs` workflow. The runtime supplies the handheld entry points. Settings supplies the `default/gaming/` tree, including the executable private shim. The companion registers the SDDM sessions. Its unversioned `omarchy` dependency currently accepts stock packages, so verify the runtime and settings are the matched handheld pair before installing it.

Build the companion from the same checkout. The PKGBUILD uses `file://` sources for checkout files, so makepkg verifies the same inputs for a local build and a source archive. Use `makepkg --allsource` to move the recipe to a clean builder. The source archive carries the declared payload and the install scriptlet.

```bash
cd packages/omarchy-gaming-session
makepkg --nodeps
sudo pacman -U omarchy-gaming-session-1.0.0-19-x86_64.pkg.tar.zst
```

The install transaction resolves dependencies from the configured repositories, including InputPlumber ≥0.84.0, Gamescope ≥3.17.0 and Steam. Steam requires multilib on x86. MangoHud adds the overlay, `omarchy-rog-ally-powerbutton` adds Gaming Mode power-button handling, and UDisks provides remembered removable libraries. For an offline install, stage the dependency closure as well as the matched runtime and settings packages.

The package manifest contains `/usr/share/wayland-sessions/omarchy-gamescope.desktop`, `/usr/share/wayland-sessions/omarchy-handheld.desktop`, `/usr/share/wayland-sessions/omarchy-managed-desktop.desktop`, `/usr/share/applications/omarchy-gaming.desktop`, `/usr/bin/steamos-polkit-helpers/steamos-update`, `/usr/lib/omarchy-gaming-session/sddm-user.sh`, `/usr/lib/omarchy-gaming-session/omarchy-handheld-autologin-guard`, `/usr/share/libalpm/hooks/omarchy-handheld-autologin-guard.hook`, `/etc/sudoers.d/omarchy-handheld-autologin` and its MIT licence. `steamos-update` is a stub adapted from Pizzarchy (MIT, copyright (c) 2026 Diego Huyke, commit `daa9376`). It updates nothing. Exit 7 tells Steam there is nothing to apply, so first-run setup does not reboot. Its install script creates `/var/lib/omarchy` and `/var/lib/omarchy/handheld` at mode `0755`, root-owned, so the desktop user can see that `/var/lib/omarchy/handheld/k07-landed` is absent. It does not write that marker. On an Ally it writes `/etc/sddm.conf.d/omarchy-handheld-user.conf` if the path is vacant. The name comes from `[Autologin] User=` in `autologin.conf`, then `[Last] User=` in `/var/lib/sddm/state.conf`. The `[OmarchyHandheld]` section retains this account without enabling SDDM autologin. Removing the companion or replacing the runtime or settings with stock deactivates generated handheld autologin and retains the owner record. After reinstalling compatible runtime and settings from the same checkout, `sudo omarchy-handheld-autologin apply` reactivates the recorded user. An earlier checkout may have copied `steamos-update` into `/usr/bin/steamos-polkit-helpers/` without pacman owning it. If `pacman -Qo /usr/bin/steamos-polkit-helpers/steamos-update` does not name `omarchy-gaming-session`, remove that file before installing this package, or the transaction stops with "exists in filesystem". Core does not delete it. The package installs `/etc/sudoers.d/omarchy-handheld-autologin` at mode 0440, a NOPASSWD grant for `fail`, `reset` and `apply` only. That file is not in the base tree. Runtime updates remain the main package's responsibility.

The package ships the gaming target and the gaming drop-ins for the bridge and TDP shim. On an Ally the scriptlet provisions the system profile service and starts it if enabled. The active login requests the `gaming` profile before Gamescope starts and reapplies it when InputPlumber or the Ally composite returns. It requests InputPlumber's `deck-uhid` target, which uses Steam Deck reports under Valve's Ally-specific ID `28de:12fd` and avoids the USB/IP connection that blocked suspend. The broker waits for the attached target and its HID device, and tries `ds5-edge` if `/dev/uhid` is absent or the target fails to attach. Both targets require working kernel UHID, so the broker reports failure if neither can attach. The observer restores the greeter pointer profile on orderly Gaming or Desktop teardown after a successful load. [Suspend evidence and checks](rog-ally-reliability.md#gaming-controller-and-suspend)

Steam waits for NetworkManager connectivity before it starts. Full or unknown connectivity lets it launch, and an unavailable check or a timeout also lets it proceed. A desktop request before Steam is ready retries Gaming once. On the second request, a required desktop lock returns to SDDM for authentication.

## The installer User= file

`/etc/sddm.conf.d/omarchy-handheld-user.conf` holds `[Autologin] User=<installer-created user>` and nothing else. `bin/omarchy-provision-owner` `configure_login` writes it, on an Ally, by calling `omarchy-handheld-autologin install-user` with the account that installer just created. If the gaming-session package is not installed yet, that call does not write: the helper requires the package. `post_install` then runs `sddm-user.sh install-recorded`, which copies `[Autologin] User=` from `autologin.conf`, or `[Last] User=` from `/var/lib/sddm/state.conf` after the unencrypted cleanup deletes `autologin.conf`. It does not scan the password file and it does not use the account that ran pacman. A counted `User=` is left in place.

The file cannot be packaged. The username differs per machine, and a package file is the same bytes on every install. `pacman -Qo` names no package. `zz-omarchy-handheld.conf` is the other drop-in: `omarchy-handheld-autologin apply` writes `Session=omarchy-handheld.desktop` and `Relogin=true` or `false`, and no `User=`. It is not a static package file either. It has no username, so apply can rewrite it on every Ally. `User=` stays in its own file so that rewrite cannot drop the name.

Uninstall deletes the User= file in both `pre_remove` and `post_remove`. Desktop-mode cleanup is `apply` when the machine is not the handheld variant (not an Ally, or the gaming package is gone): it deletes `omarchy-handheld-user.conf` and `zz-omarchy-handheld.conf` together, so a leftover `User=` cannot autologin into the last desktop session. Choosing desktop as the session preference does not delete the file. A later return to gaming still needs the name. There is no sudoers grant for this file.

## Rollback and physical acceptance

The alpha guide covers [returning from a stuck Gaming session](handheld/ALPHA.md#return-from-a-stuck-gaming-session) and [removing the optional companion](handheld/ALPHA.md#rollback). The documented removal transaction retains Steam and the owner’s preferences. The base helper clears the remaining handheld session setting. Other SDDM configuration determines whether the next login shows the greeter or starts the desktop automatically.

The rollout owner must record the exact runtime and companion packages, installed file manifest, source SHA and logs, then exercise:

1. Undocked cold boot autologins into gaming with no password prompt (Daniel, 12 Nov 2026). A switch or fallback to the desktop locks before any desktop frame only when `desktop-lock` is `on`. Until K07, a handheld install is `default-off` and the desktop is unlocked; `explicit-off` is a separate stored value. The unchanged Omarchy entry still asks for a password. Confirm the only SDDM file this package writes is `omarchy-handheld-user.conf`, with `User=` and no `Session=`.
2. A real DRM gaming session, Steam sign-in, controller library navigation and an actual game. Record `gamescope` backend evidence and test Guide+West/Guide+South, touch and the optional power controls.
3. Switch to Desktop and Exit Steam separately; confirm Hyprland, desktop input mode, keyboard summon and lock/suspend services return, and no gaming scope/helper remains.
4. From managed desktop: save work, exit Steam and launch gaming; check keyboard cleanup. Confirm a running Steam client or missing Gamescope refuses the action without closing desktop.
5. Default desktop/gaming/last and next overrides across sign-out and reboot. Exercise a failing Gamescope launch in a controlled test, then verify recovery and the unchanged desktop entry.
6. Verify the selected game resolution, frame pacing and upscaling in-game; dock/undock with DISPLAY's preferences. An untested or unsupported mode stays unverified.

No physical/session/GPU acceptance has been performed by the source worker. Live changes are reserved for the sole rollout owner.

## Upstream basis and licences

The implementation reuses the installed upstream [Gamescope](https://github.com/ValveSoftware/gamescope) and Steam packages. Its launch flags were checked against [Gamescope's main source](https://github.com/ValveSoftware/gamescope/blob/master/src/main.cpp) and the [Arch package](https://archlinux.org/packages/extra/x86_64/gamescope/). Steam startup arguments and its `steamos-session-select plasma` contract were checked against [CachyOS gamescope-session](https://github.com/CachyOS/gamescope-session) commit `f151b891b3936f1a90ae3c7a659adf2298f484ea`. The [CachyOS recipe](https://github.com/CachyOS/CachyOS-PKGBUILDS/blob/master/handheld/gamescope-session-cachyos/PKGBUILD) declares MIT and depends on `jupiter-hw-support`; it is not installed wholesale. No upstream daemon or script is copied. The update stub, the Steam PATH probe, the `[Autologin]` `User=` check and the console keymap pin are adapted from [Pizzarchy](https://github.com/villenull/Pizzarchy) commit `daa9376ab733880e612569467164754096a5f0f4`, which is MIT, copyright (c) 2026 Diego Huyke. The copyright and permission notice are on the adapted files. The `NOPASSWD` sudoers, the SDDM restart and the timezone helper from that tree were not taken. Omarchy's new integration remains under this repository's MIT licence; dependency licences stay with their packages.
