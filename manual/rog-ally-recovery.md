# ROG Ally setup and recovery

For the original ASUS ROG Ally RC71L, open **Setup > Gaming > ROG Ally handheld** or **Setup > ROG Ally Handheld**. You can also run `omarchy setup rog ally`. Each component is an explicit choice. Opening or cancelling setup does not install packages or change services. Steam Big Picture still works inside the existing desktop on other machines.

## Controller input

INPUT's source corrections have passed review. **Controller input > Enable reviewed input** appears only when matching runtime helpers and the reviewed `omarchy-rog-ally-input 1.0.2-1` companion are installed. It requires an explicit confirmation and opens the existing setup in a visible terminal. Opening setup or checking status never enables it or installs packages. Earlier companions and unreviewed newer versions are refused; use the reviewed release's matching package build.

Keep touch or a USB keyboard available before enabling InputPlumber. The backend setup refuses competing input owners; it does not remove them. Readiness and disable stay available even when activation prerequisites are missing. A source-review result or installed package does not establish physical controller acceptance.

Disable an already configured integration before removing its companion or restoring another owner. If InputPlumber was installed for this increment, remove it before restoring the old owner: removing the companion also removes its opt-in guard, leaving upstream udev activation possible. Keep touch or a USB keyboard available and follow the input component's exact installation and rollback instructions.

The shareable report shows composite readability, known profile name, interception state and advertised capability counts. It omits raw device names, paths and source identifiers. These software results do not prove gyro, rumble, buttons or pointer behaviour.

## Power readiness and rollback

POWER's client corrections have passed focused checks, but the independent package review rejected unchanged `steamos-manager 26.4.1-3`. Do not install it, even as an inactive prerequisite: its installation enables a root service for the next boot. No remediated power-only package is approved. **Power setup** offers per-control readiness and legacy rollback, without configuration/takeover or a writable power-panel action. Normal generic power remains in place.

The report lists only controls the running Manager backend can actually read. Missing TDP support stays unavailable; an installed package or older watt reading does not prove the required performance-profile/asus-armoury API. Charge `-1` is shown as the firmware default. Conflicts and policy errors suppress control values. Independent burst watts, CPU frequency limits, SMT, fan curves, bypass and thermal telemetry are unavailable in this backend API.

If rolling back a previously configured backend, reconnect AC if the recorded original limit exceeds the battery ceiling. Use the delivered rollback before removing Manager or restoring a different power owner; failed readback must be resolved first. A legacy receipt does not prove restoration of all three hardware power limits or the service state before the rejected package was installed. Keep the receipt for a reviewed recovery plan.

## Dedicated gaming session

When the session command is installed, **Gaming session** offers the delivered persistent desktop/gaming/last preference, one-shot choices, rendering and optional overlay controls. The matching main runtime and `omarchy-gaming-session` registration companion are both required. Choose **Omarchy (session preference)** at password sign-in for those preferences to apply; the original **Omarchy (Hyprland uwsm)** entry remains the independent recovery route. No autologin is enabled.

**Launch gaming session** asks you to save work and fully exit Steam first; it then uses the managed-session launcher, which closes desktop applications. An unmanaged desktop or missing dependencies are refused. In gaming, save before using Steam's **Switch to Desktop** or **Exit Steam**. This is a separate session, so returning ends the gaming session's games/downloads; it preserves library and save files.

Render size, requested FPS cap and spatial filter affect game presentation, not the physical panel mode. The optional overlay requires MangoHud/mangoapp tools. **Reset session preferences** confirms before clearing preferences, render/overlay settings and the recovery latch; it preserves Steam data and logs. Session registration, an actual game, physical controls, return-to-desktop and failure recovery still require rollout acceptance.

## Desktop keyboard

**Desktop keyboard > Configure reviewed keyboard** configures an already installed, reviewed wvkbd 0.21-1 without installing a package. The separate AUR action requires reviewing that package's source first. When wvkbd is installed, **Toggle desktop keyboard** shows or hides it. The delivered touch integration also adds the optional Keyboard bar control and `Super + Ctrl + Y`; reload/login may be needed for the binding. This keyboard belongs to the desktop; the greeter, lock screen and Steam gaming keyboard have separate owners. Automatic text-field activation is unavailable while Fcitx owns the input-method slot.

## Display and touch layout

When the display command is installed, **Display and touch layout** offers local display status, an optional 1.5× internal scale with a larger bar, and restoration of the preset's original backup. Apply the preset deliberately and check the layout on the device. Use status to identify the actual built-in touchscreen before configuring touch mapping through the display command. The setup does not choose a touchscreen for you or enable HDR on the internal SDR panel.

## Games and compatibility tools

**Game software > Game installers** opens the existing Steam and launcher installation menu. When the delivered gaming-tools command is installed, this picker also offers optional UMU/Protontricks/Winetricks, ProtonPlus, MangoHud, GOverlay and Sunshine. These are explicit installations; they do not replace existing runners or prefixes. Sunshine host input permissions and actual streaming acceptance remain separate. GameMode is excluded from this handheld picker because its power writes would compete with the Ally power owner.

## Readiness and updates

Choose **Status** for a readable report, or run:

```bash
omarchy hw rog ally status
omarchy hw rog ally status --updates
```

The normal report is offline. It lists selected package versions and service states, and checks whether the usual root snapshot configuration is readable. A package being installed, a service running and a feature working on the physical device are separate results. An active service alone does not prove that it controls the Ally. Physical controller, touch, game, dock and suspend checks remain necessary.

**Update and recovery > Check updates** checks the configured package repositories without installing anything. A failed or timed-out check means availability is unknown. This check excludes AUR and firmware updates. Use **Omarchy updates** to open the existing Update menu and run the normal full Omarchy update; do not run a partial package upgrade. Keep the Ally powered and save your game before updating.

The shareable status report excludes raw journals, host/user names, storage labels, device identifiers, network details and account configuration. Review any additional logs before sharing them; launcher logs and firmware device listings can contain personal information.

## Optional Decky

When its delivered commands are installed, **Game software > Decky** separates reviewed AUR package installation from activation. Activation requires the reviewed companion package and an explicit **Allow root plugins** choice: Decky plugins run as root and Steam debugging is enabled. No plugins are installed by this picker. Use **Disable Decky** before updating it through packages; the in-app self-updater is incompatible with this integration. The companion safeguards, source review and rollback are documented in `docs/gaming-tools.md`. This optional loader is not required for ordinary Steam games or the handheld power backend.

## Recover an update

Before an increment, create a system snapshot using **Update and recovery > Create system snapshot** or `omarchy snapshot create`. Snapper must be configured; an installed Snapper package by itself does not make a recovery point. Check the command succeeded, then confirm that the snapshot is visible in Limine before relying on it. The status report does not prove a snapshot is bootable.

If an update prevents normal startup, select a known-good snapshot from the Limine boot menu. After booting it, use **Restore system snapshot** or `omarchy snapshot restore` to open the existing restore tool. Review the selection before applying it. With Direct Boot enabled, choose Limine from firmware boot options first. Keep a USB keyboard available for firmware menus and disk unlock until those physical input paths are verified.

Repeated failed boots do not promise automatic rollback. If neither the normal system nor a snapshot boots, use the existing installer/recovery environment and your disk-unlock credentials; do not format the disk. Follow [System snapshots](47-system-snapshots.md) for the existing recovery model.

A root snapshot does not restore `/home`, game saves, Proton prefixes or user configuration. Omarchy's migration record also survives in home, so migrations are not automatically replayed after a root rollback. Back up user data separately before changing applications that may migrate its format.

## External game libraries and save backups

Use **Game libraries** to choose an already formatted microSD or USB partition. The tool mounts through the desktop's UDisks policy, never formats a disk, edits boot mounts or changes ownership recursively. Internal/system disks are refused. Close games, downloads and launchers before unmounting. Add the mounted folder in **Steam > Settings > Storage**; this does not move or delete an existing library.

Use an executable Linux filesystem such as ext4 or Btrfs for Proton prefixes. Windows/shared filesystems need extra care; do not assume that a writable folder supports Proton's symlinks, filename rules and permissions. **Check** validates access and mount options, not every game's compatibility. Keep a second copy of valuable saves outside the microSD card.

Steam Cloud coverage varies by game. Close the game and let synchronisation finish before copying saves. Back up `userdata`, the relevant games' `steamapps/compatdata` prefixes, and game-specific native save folders. External Steam libraries have their own `compatdata`. Do not publish these backups: they can contain identifiers or account information. See the [explicit copy and restore examples](https://github.com/DanielJBurbridge/omarchy/blob/feat/ally-parity-release-20261111/docs/rog-ally-storage.md#user-data-backup-and-restore-u14).

## Firmware and boot security

This setup does not flash firmware, enrol keys, change Secure Boot or alter disk encryption. The status report only lists firmware-tool availability. Firmware support depends on the device and the updates offered by LVFS or ASUS. Inspect available updates locally before choosing any firmware operation; do not assume a generic update route supports the Ally BIOS. The existing **Update > Firmware** action can install firmware and may require a restart, so it is separate from the read-only handheld checks. Follow the vendor's power and recovery requirements.

## Undo handheld integration

Leaving this setup needs no rollback: it is a menu, not a background service. Unmount a library through **Game libraries** after closing applications. Library files and Steam's saved storage choice remain intact. Disable or restore a component through its documented setup/rollback command; do not enable a second controller or power daemon to compensate for a broken first one. Reverting a source/package increment restores the previous menu and commands; it does not undo another component's service or user-configuration changes.
