# Gaming tools and data preservation

Source support and installed acceptance are separate. These commands have focused source tests; launcher sign-in, game compatibility, controllers, overlays and streaming still need verification on the target device by the sole rollout owner. The feature inventory is in `plans/rog-ally-parity.md`.

## Existing launchers

Keep the existing installers: `omarchy install gaming steam`, `heroic`, `lutris`, `battlenet` and `retroarch`. The Moonlight menu already uses `omarchy-install-and-launch Moonlight moonlight-qt com.moonlight_stream.Moonlight`; a second Moonlight installer is unnecessary. Steam includes Valve's selected Proton runtimes. Lutris and Battle.net already install UMU after selecting the correct lib32 Vulkan driver. Steam Remote Play is built into Steam.

The Steam, Heroic, Lutris, RetroArch and Moonlight removers now remove packages while retaining user data. Battle.net removal removes its desktop entry and keeps its prefix and shared runtimes. In particular, removing Lutris no longer deletes `~/.wine` or UMU data used by other launchers. Reinstalling RetroArch seeds defaults only when `retroarch.cfg` does not exist and preserves existing shader presets. Games, prefixes, ROMs, BIOS files and saves are never a package rollback target.

Before installation, save `pacman -Q` and back up launcher configuration and local saves to another device. Steam Cloud is per-game and may be disabled or incomplete. A filesystem snapshot does not replace a save backup. Record the existing Steam library folders and each launcher's prefix location; keep the same user account across desktop and gaming sessions.

For source rollback, revert the data-preservation commit; that restores the old destructive removal behaviour, so retain these fixes wherever possible. No user files need restoring after this increment. To undo a launcher package installation, run its `omarchy remove gaming ...` command after reviewing dependencies; these commands retain data. Battle.net can be restored by rerunning its installer against the retained prefix.

## Device acceptance for existing launchers

The rollout owner should record installed package versions, open each selected launcher, complete sign-in, and launch one already-owned game without moving its library or changing its runner. Save a known in-game state, switch desktop/gaming sessions, then load it again. Check Steam Cloud completion before closing Steam. Exercise an existing RetroArch core with the user's existing save path and a Moonlight host with actual video/audio/input; package presence alone proves none of those paths. Do not use a live library as a removal test fixture.

## Optional compatibility and performance tools

Run only the desired component; none is added to the default package set:

```bash
omarchy install gaming tools compatibility
omarchy install gaming tools protonplus
omarchy install gaming tools overlay
omarchy install gaming tools goverlay
omarchy debug gaming
```

`compatibility` installs Arch's `umu-launcher`, `protontricks` and `winetricks`, selecting lib32 GPU drivers first. The package dependencies supply their Wine/runtime libraries; this does not import CachyOS's metapackage, patched Wine, split-lock sysctl or repositories. It requires x86 multilib. Use `protontricks --gui` on a Steam game that has already run once, with the game closed, and back up that prefix before applying verbs. Never run prefix tools as root. For standalone UMU, preserve the chosen prefix and specify the runner per game:

```bash
WINEPREFIX="$HOME/Games/my-game" PROTONPATH=GE-Proton GAMEID=umu-default umu-run '/path/to/game.exe'
```

UMU downloads its container runtime and the selected automatic runner on first use. `GE-Proton` explicitly opts into the latest GE build; an absolute `PROTONPATH` pins an existing runner. A launcher-specific UMU database ID enables that game's fixes. UMU already serves the existing Lutris/Battle.net paths. Another default prefix launcher such as Faugus would duplicate these; it remains an optional upstream application rather than a replacement.

`protonplus` uses upstream's recommended `com.vysp3r.ProtonPlus` Flatpak, scoped to the current user. An existing system or user installation is reused. It adds no runner automatically: choose the correct launcher and tool in ProtonPlus, restart Steam, then select the runner under that game's Compatibility properties. Retain the old runner until saves and launch behaviour have been checked. Winetricks verbs, mods and runner changes can affect prefixes; the tooling cannot guarantee compatibility or anti-cheat support. Publisher-enabled Proton support is still required for affected multiplayer games.

`overlay` installs `mangohud` plus `lib32-mangohud` on x86. `goverlay` adds the optional configuration UI. The launcher sets an environment for its child only; it does not edit MangoHud files, Steam launch options or login environment. Example Steam per-game launch options:

```text
omarchy-launch-gaming-overlay -- %command%
omarchy-launch-gaming-overlay --preset detailed --fps 60 -- %command%
```

The compact preset shows FPS, frametime and battery where supported. Detailed adds CPU/GPU load and temperatures, memory and a frametime graph; absent sensors are not evidence of zero consumption. Supported caps are 0 (unlimited), 30, 40, 60, 90 and 120 FPS. Choose one limiter per game. The wrapper replaces `MANGOHUD_CONFIG` only in its child, so remove the wrapper to return to existing custom configuration. Flatpak games require their matching MangoHud extension inside the sandbox; this host wrapper targets native launchers.

Gamescope uses `mangoapp`, not ordinary game-layer MangoHud injection. For a separate nested compositor test, use `omarchy-launch-gaming-overlay --gamescope --fps 60 -- game`. This applies Gamescope's `-r` cap to the game and leaves the overlay process uncapped. The dedicated gaming session owner must add `--mangoapp` to its own compositor launch; do not nest another Gamescope merely to add an overlay to that session. Never apply a MangoHud FPS cap to mangoapp and mistake it for a game cap. The source tests check argument/environment routing; real rendering and frame pacing remain device acceptance.

GameMode is separately available with `omarchy install gaming tools gamemode` on other hardware. This command refuses RC71L: current GameMode applies CPU governors and platform profiles even when the corresponding configuration values are empty. It would compete with the handheld POWER owner. Nothing here enables a persistent GameMode service or adds it to game launch options. Review other power managers before choosing `gamemoderun %command%` elsewhere.

### Tool rollback and acceptance

Remove the per-game overlay launch option to roll it back immediately. Remove only newly installed packages after checking the pre-install `pacman -Q` record and reverse dependencies, using `omarchy pkg drop ...`. Keep packages still required by Lutris, Battle.net or other launchers. Removing ProtonPlus with `flatpak uninstall --user com.vysp3r.ProtonPlus` retains its data and installed host runners; omit `--delete-data`. No user configuration backup needs restoring for the overlay or compatibility installer.

The rollout owner should record `omarchy debug gaming`, installed package versions and the Flatpak commit (`flatpak info com.vysp3r.ProtonPlus`). Run one known working Steam Proton game and one existing UMU game; check Protontricks lists the intended prefix, then cancel without applying verbs. Verify ProtonPlus sees the existing launchers. Compare a real game without overlay, with compact/detailed overlay, and capped at 40/60 FPS. Check readable text, genuine frametime/cap behaviour, missing sensor labels and successful exit. In the direct Gamescope session, verify its own mangoapp path separately. Preserve screenshots/logs outside Git. These checks have not been performed by this source worker.

## Performance evaluation boundaries

`omarchy debug gaming` is an on-demand, read-only report of installed gaming/graphics packages, the running kernel, NTSync device accessibility, sched-ext state, zram usage, block I/O scheduler and selected networking settings. It does not load a kernel module, change device permissions or infer runner support from `/dev/ntsync` alone. No watcher or polling daemon is added.

Omarchy already configures zram in `default/systemd/zram-generator.conf.d/90-omarchy.conf` (`zram-size = ram`). Retain it pending measured memory pressure. Mesa, Vulkan and firmware stay on the existing Omarchy/Arch update path. F05-F07 and F09 are deliberately optional experiments, not missing game-launch prerequisites: no Deckify/BORE kernel, sched-ext/LAVD daemon, CPU-targeted repository or compiler flag is installed here. NTSync (F08) needs both an accessible kernel device and a runner supporting it; do not force an environment flag across all Proton versions. Audio changes (F11) belong to RELIABILITY. Networking sysctls (F12), storage schedulers and memory tuning (F10) stay unchanged without an observed problem.

For a future scheduler/kernel experiment, first retain a bootable supported kernel/UKI and snapshot/recovery instructions. Record game/runner/kernel versions, resolution, graphical settings, FPS cap, AC/DC state and the POWER owner's fixed wattage; warm shader caches, then run at least three repeatable 60-second scenes on the baseline and candidate. Compare median/low-percentile FPS, frametime spikes, temperatures, battery drain and any suspend/input regressions. Change one variable, restore it after each comparison and boot the known-good kernel if the candidate fails. Do not claim an FPS or latency improvement from a package name or static capability report.

## Packaging references

Checked 11 November 2026 against current primary sources. [CachyOS gaming meta](https://github.com/CachyOS/CachyOS-PKGBUILDS/blob/master/cachyos-gaming-meta/PKGBUILD) supplies UMU, prefix tools and its own runners; [Bazzite's launcher guide](https://docs.bazzite.gg/Gaming/Game_Launchers/) and [game management guide](https://docs.bazzite.gg/Gaming/Managing_and_modding_games/) document optional launchers and runner tools. Reuse those tools through the existing package sources rather than copying a distribution's whole package selection.

Official Arch package metadata at review: `umu-launcher` 1.4.4-1 (multilib), `protontricks` 1.14.1-1 (extra; testing had 1.15.0), `winetricks` 20260125-1 (extra), [MangoHud/lib32-MangoHud](https://archlinux.org/packages/extra/x86_64/mangohud/) 0.8.4-1, [GOverlay](https://archlinux.org/packages/extra/x86_64/goverlay/) 1.9.4-1 and [GameMode](https://archlinux.org/packages/extra/x86_64/gamemode/) 1.8.2-3 (lib32 1.8.2-1). These are research observations, not pins or installed versions. [ProtonPlus upstream](https://github.com/Vysp3r/ProtonPlus) recommends its Flatpak and lists supported launchers; [UMU upstream](https://github.com/Open-Wine-Components/umu-launcher) documents runtime downloads, prefixes and runner selection. [MangoHud upstream](https://github.com/flightlessmango/MangoHud) documents the Gamescope/mangoapp distinction. [GameMode's governor/profile implementation](https://github.com/FeralInteractive/gamemode/blob/master/daemon/gamemode-context.c) establishes why it is excluded from managed RC71L power policy. No upstream implementation source is copied into Omarchy by this increment.

## Optional Sunshine host

Moonlight is the existing client; host streaming is separate. `omarchy install gaming tools sunshine` installs upstream's stable `dev.lizardbyte.app.Sunshine` Flatpak for the current user, reusing an existing system/user install. Start it from the app launcher and select the desktop portal for Wayland capture. This step installs the application only: it does not open firewall ports, enable autostart or grant host input access.

[Sunshine's current installation guide](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html) requires its additional host setup for injected input and supplies `flatpak run --command=additional-install.sh dev.lizardbyte.app.Sunshine`. That is a separate privileged operation: the deployment owner must review the installed script's udev/service changes with INPUT before running it and record their exact files in the installation manifest. The Flatpak has no KMS capture; a direct Gamescope session cannot be advertised as a working host capture path from this installation. [Bazzite now also treats Sunshine as an optional stable Flatpak](https://docs.bazzite.gg/Advanced/sunshine/), rather than part of its base image.

Acceptance still requires an actual Moonlight client, portal grant, hardware encoder, video/audio and gamepad round trip; validate the desktop and Gamescope separately. Until the extra host integration and capture path are reviewed and exercised, A10/D10 remain installed-app capability only, not end-to-end streaming parity. To roll back a package-only install, quit the app and run `flatpak uninstall --user dev.lizardbyte.app.Sunshine` without `--delete-data`. If additional host setup was performed, first use the matching upstream `remove-additional-install.sh` against the recorded manifest. Keep pairing/settings data; do not remove another installation's shared host rules.
