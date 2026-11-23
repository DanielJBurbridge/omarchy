# ROG Ally standalone gaming session

Changed 12 November 2026 to match [spec 02](handheld/02-mode-switch-and-dock.md). Autologin into gaming is Daniel's decision (12 Nov 2026). The handheld variant autologins into gaming by default and falls back to the desktop if gaming does not start. What changed: the sentences that forbade autologin and promised a password in front of every login, and the later sentence that locked every desktop start. Until AUTH K07 (the lock-screen touch keyboard) has merged, the handheld ships `desktop-lock` as `default-off`, which is stored separately from a user's `explicit-off`. This package still does not guess a username. The SDDM file it may write is the persistent `User=` drop-in, and only on an Ally. It does not write PAM, `Session=` or `Relogin=`.

This optional implementation covers the SESSION work in G01–G12 for the original RC71L. It launches upstream Gamescope directly on DRM, with the installed Steam and existing library, and returns to Omarchy Hyprland. It does not install another desktop, change PAM, replace the kernel or repositories, or enable a hardware power writer. The one SDDM file it writes is `/etc/sddm.conf.d/omarchy-handheld-user.conf`, and only on an Ally, and only with a `User=` already recorded by the installer. That file is not in the package manifest. It does not guess a username, and it does not write `Session=` or `Relogin=`. Those stay in the file `apply` rewrites. Desktop Big Picture remains available separately.

## Session contract

The optional `omarchy-gaming-session` package registers two SDDM entries:

| File | Visible name | Behaviour after authentication |
| --- | --- | --- |
| `omarchy-gamescope.desktop` | Omarchy Gaming | Explicitly launch gaming, clearing the recovery latch |
| `omarchy-handheld.desktop` | Omarchy (session preference) | Honour this user's saved preference and next-session override |

The existing `omarchy.desktop` / Omarchy (Hyprland uwsm) is unchanged. Use it as an independent recovery route. SDDM's last-selected session still applies; saved handheld preferences only apply when selecting **Omarchy (session preference)**. The handheld variant autologins into that preference session and starts in gaming when undocked (spec 02; Daniel, 12 Nov 2026). If gaming does not start, the supervisor falls back to the desktop after one retry. Every such desktop start goes through the one choke point in `desktop()` (spec 02). Until K07, the handheld value is `default-off`, so that desktop is not locked. Before the marker is present, that same handheld also skips the ordinary lock on suspend unless a physical keyboard is attached at that moment. The Ally's built-in controller keyboard does not count, and an explicit `on` with no physical keyboard returns to gaming instead of locking. The marker brings the ordinary suspend lock back. Other variants stay `on` and lock before the first frame. A user's `explicit-off` is a different stored value and is not the shipped default. The unchanged Omarchy entry remains a password login.

`omarchy-session-start` is a pre-UWSM login entrypoint. It uses the existing canonical environment bootstrap, then runs UWSM or a Gamescope scope within the authenticated logind session. No username, UID, home directory or display number is guessed. UWSM intentionally excludes `XDG_SESSION_ID` from the desktop user manager; the selector carries its managed login ID as `OMARCHY_HANDHELD_SESSION` through UWSM's normal environment import and cleanup so desktop actions address the correct supervisor. On machines outside `omarchy-hw-rog-ally`, both optional entries run the ordinary Hyprland command without reading gaming preferences.

Gaming does not start `graphical-session.target`; desktop layer-shell panels and the Hyprland lock monitor do not run there. The scope `omarchy-gamescope-$XDG_SESSION_ID.scope` contains Gamescope, Steam, games and the optional power-button helper. Stop requests clean up that scope before starting UWSM. Games started independently through another service are outside this scope's ownership.

## Preferences and use

```bash
# Run as the signed-in user, never sudo.
omarchy-setup-gaming-session default gaming
omarchy-setup-gaming-session default desktop
omarchy-setup-gaming-session default last
omarchy-setup-gaming-session next gaming
omarchy-setup-gaming-session next desktop
omarchy-setup-gaming-session next clear
omarchy-setup-gaming-session status
omarchy-setup-gaming-session reset
```

The absent preference is desktop. `next` overrides the persistent choice once and is consumed **before** starting it, including when startup fails. It survives a reboot until the next managed sign-in. `last` remembers the most recently entered desktop or gaming mode. Returning from gaming enters desktop, making desktop the last mode. `reset` removes preferences, render settings, overlay selection and recovery state; it preserves logs and all Steam data.

From the managed Hyprland session, save work and fully exit Steam, then choose the **Omarchy Gaming** application or run `omarchy-launch-gaming-session`. This closes desktop applications using Omarchy's existing logout action. A transient user worker owns the switch request and removes it if logout fails, so submitting a logout job cannot accidentally change a later ordinary logout. The launcher stops wvkbd while the departing Wayland display is still available. It refuses an unmanaged desktop, missing dependencies or a surviving Steam client rather than forwarding a gaming request to that client's old display. After installing the increment, sign out and choose the preference session once to enable this action.

In gaming, use Steam's Power → Switch to Desktop, exit Steam, or run `omarchy-launch-gaming-desktop` within that login. Steam's session-selector hook is supplied through a **private gaming PATH**, accepting only its `plasma` return argument and routing to Hyprland. `omarchy-gaming-steam` probes Steam's environ against `PATH=/usr/bin:/bin`. If that parent PATH still contains the private directory, or the environ cannot be read, the private directory stays. No global `steamos-session-select` binary or login policy is replaced. The return action ends running games/downloads in this session; save first. Downloads can resume when Steam next starts. If Steam's client build does not honour the PATH hook, Exit Steam is the fallback; that hook must be checked on the installed client.

Steam owns Guide+West (Xbox X) for its keyboard and Guide+South for quick access. INPUT owns translation of hardware buttons and calls `omarchy-hw-rog-ally-input gamepad` on entry when `omarchy-rog-ally-input` is installed. Its desktop bridge restores mouse mode at Hyprland start. Session code creates no second input mapper. Hardware button navigation, focus interception and the Steam quick-menu power controls still require physical acceptance.

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

When DISPLAY's `omarchy-display-rog-ally` is installed, `gamescope-args` supplies only `--prefer-output` and its connected connector, one argument per line. Empty output means automatic output choice; an error aborts gaming entry and returns desktop. SESSION supplies no hard-coded connector or resolution for the RC71L SDR panel.

Overlay selection adds `--mangoapp` only when enabled and `mangoapp` is installed. Install the GAMES owner's optional overlay tools first. Ordinary MangoHud injection and its `fps_limit` are not used for this compositor session.

TDP does not start `steamos-manager.service`. `omarchy-ally-power.service` is not in this tree. Do not enable either unit. The writer is `bin/omarchy-ally-tdp-apply`. It clamps to the live firmware-attributes `min_value`, `max_value` and boot-captured `default_value` / `max_value`. The policy ceilings in that script are battery 20/20/25 (SPL/SPPT/FPPT) and AC SPL 30. On AC, SPPT and FPPT ceilings are the boot-captured max. On the stock tables that is 43 and 53, so `--set 30` applies 30/43/53 (`test/shell.d/ally-tdp-test.sh`). `--set` and `--reassert` take an exclusive flock on `/run/omarchy-ally-tdp.lock`. The session shim is `bin/omarchy-ally-tdp-shim`. It owns `com.steampowered.SteamOSManager1.TdpLimit1` on the session bus. The interface is vendored from evlaV/steamos-manager `85fbd8f` (MIT; `default/ally-tdp/NOTICE.steamos-manager`). `bin/omarchy-session-start` copies the gaming drop-in and restarts `omarchy-ally-tdp-shim.service` when that unit is installed. Resume is `omarchy-ally-tdp-resume.service` (`ExecStop=/usr/bin/omarchy-ally-tdp-apply --reassert`). A mains online change starts `omarchy-ally-tdp-source.service`, which runs the same verb. `install/hardware/asus/ally-tdp.sh` runs `omarchy-ally-tdp-install`. Stock steamos-manager is not shipped. The contract is [spec 04 §5.1](handheld/04-quick-access-overlay.md). The session does not start `steamos-manager.service` or `omarchy-ally-power.service`. Those units are not in this tree, and `bin/omarchy-session-start` no longer names them. TDP for the gaming session is the Ally writer and its shim. Do not create an `omarchy/ally-power/enabled` marker.

If the `omarchy-rog-ally-powerbutton` companion and `/usr/bin/steamos-powerbuttond` are installed, the Steam child wrapper starts `omarchy-launch-gaming-powerbutton` after Gamescope provides DISPLAY. It owns that process's PID and kill/wait cleanup. The helper forwards upstream Steam power URIs; it does not run the desktop lock flow. No global powerbuttond unit is enabled.

## Failure recovery and evidence

The supervisor waits for process events and private FIFOs. A single 60-second startup deadline (`OMARCHY_GAMING_READY_TIMEOUT`, default 60) bounds a compositor whose Steam child never gains a display connection. There is no background polling. The ready signal is written only after that Steam process holds the X socket for `DISPLAY`. A live pid with no display connection is not ready. Steam can remain on its own update/sign-in UI after that without a further time limit. One automatic retry follows a retryable failure, 3 seconds apart.

An early compositor exit, nonzero Steam result, invalid settings or a missing dependency returns to Hyprland and writes a recovery latch. Spec 02 adds one automatic retry before that fallback, then the latch. Further preference logins choose desktop until an explicit `default`, `next`, or direct Gaming choice clears it. Steam is not relaunched in a loop. Normal Steam exit and explicit desktop return also start Hyprland. That desktop start uses the spec 02 choke point, and locks first only when `desktop-lock` is `on`. If Hyprland itself fails, the selector exits to SDDM rather than retrying it.

State is private to the user under `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/gaming-session`. Current and previous logs are `session.log` and `session.previous.log`. They contain upstream diagnostic output and may contain personal paths; review/redact before sharing. Runtime FIFOs and mode markers are under the existing user's runtime directory, separated by logind session ID.

Focused regression coverage extends `test/shell.d/gaming-setup-test.sh`. It executes the actual preference parser, supervisor, Steam wrapper and private return hook, with external compositor/logind/systemd boundaries replaced by fixtures. It checks consumed one-shot selection, parser rejection, compositor crash/early exit/timeout, Steam failure even when Gamescope masks its status, desktop return, wvkbd departure, missing dependencies, hardware and input guards, overlay/output argument handoff. It does not start an ally-power unit. This is orchestration evidence, not a GPU, controller, touch, power-button or game test.

## Package build and deployment

Only the designated Ally rollout owner installs this increment. First build and install the main **omarchy runtime package from this exact reviewed source** through the existing `omarchy-pkgs` workflow. It must contain the five new `bin/omarchy-*` scripts and the complete `default/gaming/` runtime tree, including the executable private shim. `omarchy dev link` alone cannot register SDDM session files. The standalone registration package depends on the matching runtime being installed; an older repository `omarchy` package is insufficient.

Build the optional companion locally from the same commit. The install script does not enable a service:

```bash
# In the reviewed source checkout. Run makepkg from this directory.
cd packages/omarchy-gaming-session
makepkg --nodeps --nocheck
bsdtar -tf omarchy-gaming-session-1.0.0-9-x86_64.pkg.tar.zst
# Install dependencies through the normal helpers; main runtime already updated.
omarchy-pkg-add gamescope
# Steam and lib32 drivers use Omarchy's existing gaming installer if absent.
sudo pacman -U omarchy-gaming-session-1.0.0-9-x86_64.pkg.tar.zst
```

`--nodeps` permits an isolated build host without Steam; the installation transaction still enforces dependencies. Arch Extra currently supplies Gamescope 3.17.0-1, checked against its primary package page on 11 November 2026. The companion requires Gamescope ≥3.17.0 and `iproute2` (`ss` in `default/gaming/steam-ready.sh`). The checksums in the PKGBUILD are of the files beside it. `package()` reads the session files and the licence from this checkout. Do not overwrite package files using `cp` or edit installed package trees.

The package manifest contains `/usr/share/wayland-sessions/omarchy-gamescope.desktop`, `/usr/share/wayland-sessions/omarchy-handheld.desktop`, `/usr/share/applications/omarchy-gaming.desktop`, `/usr/bin/steamos-polkit-helpers/steamos-update`, `/usr/lib/omarchy-gaming-session/sddm-user.sh`, `/usr/lib/omarchy-gaming-session/omarchy-handheld-autologin-guard`, `/usr/share/libalpm/hooks/omarchy-handheld-autologin-guard.hook`, `/etc/sudoers.d/omarchy-handheld-autologin` and its MIT licence. `steamos-update` is a stub adapted from Pizzarchy (MIT, copyright (c) 2026 Diego Huyke, commit `daa9376`). It updates nothing. Exit 7 tells Steam there is nothing to apply, so first-run setup does not reboot. Its install script creates `/var/lib/omarchy` and `/var/lib/omarchy/handheld` at mode `0755`, root-owned, so the desktop user can see that `/var/lib/omarchy/handheld/k07-landed` is absent. It does not write that marker. On an Ally it writes `/etc/sddm.conf.d/omarchy-handheld-user.conf` when that file has no counted `User=`. The name is `[Autologin] User=` from `autologin.conf`, then `[Last] User=` from `/var/lib/sddm/state.conf`. It does not scan the password file and it does not use the account that ran pacman. Removing the package runs `pre_remove` and `post_remove`, which delete that file. An earlier checkout may have copied `steamos-update` into `/usr/bin/steamos-polkit-helpers/` without pacman owning it. If `pacman -Qo /usr/bin/steamos-polkit-helpers/steamos-update` does not name `omarchy-gaming-session`, remove that file before installing this package, or the transaction stops with "exists in filesystem". Core does not delete it. It does not enable a service or change PAM. The package installs `/etc/sudoers.d/omarchy-handheld-autologin` at mode 0440, a NOPASSWD grant for `fail`, `reset` and `apply` only. That file is not in the base tree. Runtime updates remain the main package's responsibility.

## The installer User= file

`/etc/sddm.conf.d/omarchy-handheld-user.conf` holds `[Autologin] User=<installer-created user>` and nothing else. `bin/omarchy-provision-owner` `configure_login` writes it, on an Ally, by calling `omarchy-handheld-autologin install-user` with the account that installer just created. If the gaming-session package is not installed yet, that call does not write: the helper requires the package. `post_install` then runs `sddm-user.sh install-recorded`, which copies `[Autologin] User=` from `autologin.conf`, or `[Last] User=` from `/var/lib/sddm/state.conf` after the unencrypted cleanup deletes `autologin.conf`. It does not scan the password file and it does not use the account that ran pacman. A counted `User=` is left in place.

The file cannot be packaged. The username differs per machine, and a package file is the same bytes on every install. `pacman -Qo` names no package. `zz-omarchy-handheld.conf` is the other drop-in: `omarchy-handheld-autologin apply` writes `Session=omarchy-handheld.desktop` and `Relogin=true` or `false`, and no `User=`. It is not a static package file either. It has no username, so apply can rewrite it on every Ally. `User=` stays in its own file so that rewrite cannot drop the name.

Uninstall deletes the User= file in both `pre_remove` and `post_remove`. Desktop-mode cleanup is `apply` when the machine is not the handheld variant (not an Ally, or the gaming package is gone): it deletes `omarchy-handheld-user.conf` and `zz-omarchy-handheld.conf` together, so a leftover `User=` cannot autologin into the last desktop session. Choosing desktop as the session preference does not delete the file. A later return to gaming still needs the name. There is no sudoers grant for this file.

## Rollback and physical acceptance

Return to desktop, run `omarchy-setup-gaming-session reset`, then sign out and choose the unchanged Omarchy (Hyprland uwsm) entry. Remove registration with `omarchy-pkg-drop omarchy-gaming-session`. Restore the previous main runtime package through the established package/snapshot recovery route if necessary. This leaves Steam libraries, saves, prefixes and system login configuration untouched. Retain optional input/power packages only according to those owners' rollback instructions.

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
