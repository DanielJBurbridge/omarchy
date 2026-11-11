# ROG Ally handheld feature inventory and implementation

Research date: 11 November 2026. Target: Daniel's original ASUS ROG Ally RC71L running Omarchy. The goal is controller and touch operation from sign-in through gaming, with useful battery controls and reliable return to the desktop. Preserve Omarchy, existing user configuration and support for ordinary laptops and desktops.

This inventory covers the documented handheld, gaming, desktop and operating-system feature families in Bazzite and CachyOS. It is not a list of every package either distribution can install. Entries marked optional, hardware dependent or unverified must not be advertised as working defaults on the Ally. An implementation task is not complete until its installed behaviour has been checked; source presence alone is insufficient.

## What the distributions actually supply

Bazzite Deck supplies a dedicated Steam Gaming Mode session. Current Bazzite 44 and later use InputPlumber and OpenGamepadUI, with SteamOS Manager or PowerStation supplying supported-device power integration. HHD-era instructions describe an older stack. The current release manifest is [45.20261111](https://github.com/ublue-os/bazzite/releases/tag/45.20261111).

CachyOS Handheld supplies a Gamescope session and KDE Plasma desktop. Its current hardware profiles select InputPlumber, SteamOS Manager and SteamOS Powerbuttond for recognised devices. The live wiki describes Limine and automatic snapshots; the older handheld README disagrees on some boot and device details. Prefer current package recipes and hardware profiles for implementation. [CachyOS handheld guide](https://wiki.cachyos.org/installation/installation_handheld/), [hardware profiles](https://github.com/CachyOS/chwd/blob/master/profiles/pci/handhelds/profiles.toml).

Steam Big Picture is Steam's controller interface. Gamescope is a compositor that can run a dedicated gaming session. Feral GameMode temporarily adjusts system settings for a game. They serve different purposes.

## Status key

- **Included:** documented in the relevant handheld edition or current component configuration.
- **Available:** optional application, setting or integration; not necessarily preinstalled or enabled.
- **Device:** depends on the model, driver, firmware, connected display or game.
- **Unverified:** not established as a supported distribution default; an explicit Omarchy requirement can still cover it.
- **Different:** a distribution architecture rather than a feature to copy directly.

The final column assigns Omarchy work. Existing features still need an installed baseline check. Group source links apply to the distribution claims in that group; the Omarchy column specifies desired work rather than asserting distribution support.

## Gaming session and navigation

Sources: [Bazzite Gaming Mode](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Steam_Gaming_Mode/), [CachyOS session package](https://packages.cachyos.org/package/cachyos/any/gamescope-session-cachyos), [CachyOS session source](https://github.com/CachyOS/gamescope-session), [Gamescope](https://github.com/ValveSoftware/gamescope).

| ID | Feature | Bazzite | CachyOS | Omarchy work |
| --- | --- | --- | --- | --- |
| G01 | Dedicated Gamescope gaming session | Included | Included | SESSION: separate login session, not desktop Big Picture |
| G02 | Controller-first Steam library and settings | Included | Included | SESSION: retain existing Steam installation and library |
| G03 | Boot directly into gaming | Included | Included | SESSION: explicit, reversible user choice |
| G04 | Return to a full desktop | Included | Included | SESSION: return to Omarchy Hyprland |
| G05 | Return from desktop to gaming | Included | Included | SESSION: visible touch/controller action |
| G06 | Remember last session or select gaming on next boot | Included integration | Included integration | SESSION: avoid hard-coded user IDs and forced autologin |
| G07 | Recover when Steam or Gamescope fails | Session lifecycle | Session lifecycle | SESSION: usable greeter/desktop fallback and diagnostics |
| G08 | Quick access menu while playing | Included | Included Steam integration | INPUT and SESSION: hardware-button routes |
| G09 | Non-Steam titles in controller library | Available | Available | GAMES: reuse existing launchers and shortcuts |
| G10 | Independent game resolution and fullscreen presentation | Gamescope | Gamescope | DISPLAY: capability-tested configuration |
| G11 | Frame-rate limit and frame pacing | Gamescope/Steam | Gamescope/Steam | DISPLAY and PERFORMANCE: verify actual presentation |
| G12 | Upscaling and image filters | Gamescope | Gamescope | DISPLAY: expose supported options, distinguish game-native scaling |

## Controllers and desktop pointer

Sources: [InputPlumber capabilities](https://github.com/ShadowBlip/InputPlumber), [OpenGamepadUI](https://github.com/ShadowBlip/OpenGamepadUI), [Bazzite handheld controls](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/), [CachyOS model profiles](https://raw.githubusercontent.com/CachyOS/chwd/master/profiles/pci/handhelds/profiles.toml).

| ID | Feature | Bazzite | CachyOS | Omarchy work |
| --- | --- | --- | --- | --- |
| I01 | Detect and combine built-in controller devices | InputPlumber | InputPlumber | INPUT: model-specific service integration |
| I02 | Joystick moves the desktop cursor | Mapping capability | Mapping capability | INPUT: usable default independent of Steam running |
| I03 | Controller mouse clicks, scroll and drag | Mapping capability | Mapping capability | INPUT: document and verify mappings |
| I04 | Switch desktop mouse and gamepad modes | Profile capability | Profile capability | INPUT: clear mode state, no stuck keys |
| I05 | Controller keyboard shortcuts | Mapping capability | Mapping capability | INPUT: keyboard summon and desktop actions |
| I06 | Armoury Crate and command-centre buttons | Device | Device | INPUT: agree short/long press routes with session owner |
| I07 | Back buttons and paddles | Device/emulation target | Device | INPUT: preserve physical inputs and Steam Input remapping |
| I08 | Gyroscope and motion aiming | Device/emulation target | Device | INPUT: test supported virtual-controller target |
| I09 | Rumble and vibration | Device/emulation target | Device | INPUT: verify strength and no duplicate output |
| I10 | Deadzones, axis curves and stick calibration | Component/profile capability | Component/profile capability | INPUT: expose supported settings |
| I11 | Xbox, DualSense or Steam-compatible virtual controller | Device-dependent targets | Device-dependent targets | INPUT: choose target from actual supported features |
| I12 | Per-game input layouts | Steam Input/available OGUI | Steam Input | INPUT: preserve game-specific layouts |
| I13 | Overlay input interception without passing buttons to game | InputPlumber/OGUI | InputPlumber capability | INPUT: verify focus and interception |
| I14 | Bluetooth and USB external controllers | Device | Device | RELIABILITY: pairing, hotplug and reconnect |
| I15 | Multiple controllers and local multiplayer | Game/device | Game/device | RELIABILITY: verify controller ordering |
| I16 | Controller hotplug after resume | Device | Device | RELIABILITY: no duplicate or missing controllers |

## Touch and typing

Sources: [Bazzite desktop controller and keyboard setup](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/), [CachyOS handheld releases](https://github.com/CachyOS/CachyOS-Handheld/releases), [Bazzite installation and encryption](https://docs.bazzite.gg/General/Installation_Guide/install-guide/), [Bazzite password-login request](https://github.com/ublue-os/bazzite/issues/5659).

| ID | Feature | Bazzite | CachyOS | Omarchy work |
| --- | --- | --- | --- | --- |
| K01 | Steam on-screen keyboard in gaming | Included | Included | TOUCH: test invocation and text focus |
| K02 | Desktop floating keyboard | Steam setup/desktop integration | Desktop integration | TOUCH: build on existing wvkbd branch |
| K03 | Keyboard available without Steam | Desktop-dependent | Desktop-dependent | TOUCH: wvkbd or supported input-method integration |
| K04 | Touch/controller show and hide control | Mapping dependent | Mapping dependent | TOUCH and INPUT: discoverable, reliable access |
| K05 | Automatic keyboard on text-field focus | Desktop/application dependent | Desktop/application dependent | TOUCH: implement only where protocol support exists |
| K06 | Floating keyboard at password sign-in | Unverified universal default | Unverified universal default | AUTH: trusted greeter keyboard and touch submit |
| K07 | Floating keyboard to unlock session | Unverified universal default | Unverified universal default | AUTH: keyboard inside trusted lock surface |
| K08 | Visible session chooser at sign-in | Greeter/configuration dependent | Greeter/configuration dependent | AUTH: cooperate with dedicated gaming session |
| K09 | Non-US layouts, modifiers, symbols and editing keys | Keyboard/application dependent | Keyboard/application dependent | TOUCH and AUTH: exercise actual password characters |
| K10 | Touch-sized controls and useful display scaling | Desktop-dependent | KDE integration | TOUCH and DISPLAY: Ally-sized layouts |
| K11 | Keyboard during encrypted-disk unlock | Physical keyboard documented | Boot configuration dependent | AUTH: separate initramfs requirement; investigate explicitly |
| K12 | Fingerprint sign-in/unlock | Device/driver | Device/driver | AUTH: preserve existing PAM behaviour; do not promise absent driver |

An external desktop keyboard cannot type into a secure Wayland lock surface. SDDM, the Omarchy lock screen, desktop text entry and early-boot disk decryption require separate implementations and acceptance checks. Do not disable locking, weaken PAM or enable autologin as a substitute for touch authentication.

## Power and battery

Sources: [PowerStation APIs and Arch packaging](https://github.com/ShadowBlip/PowerStation), [Bazzite current TDP options](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/), [Bazzite stack transition](https://universal-blue.discourse.group/t/bazzites-biggest-update-deck-44-has-launched-happy-birthday-to-universal-blue/12373), [CachyOS handheld support](https://github.com/CachyOS/CachyOS-Handheld), [HHD alternative capabilities](https://github.com/hhd-dev/hhd).

| ID | Feature | Bazzite | CachyOS | Omarchy work |
| --- | --- | --- | --- | --- |
| P01 | Quiet, balanced and performance presets | Supported backend | Backend/device | POWER: integrate existing generic profiles |
| P02 | TDP presets in watts | Device | Device/backend | POWER: safe supported values and readback |
| P03 | Custom sustained/boost power limits | Device/backend | Device/backend | POWER: supported backend only |
| P04 | CPU boost control | Supported backend | Backend/device | POWER: detect capability |
| P05 | CPU frequency and governor controls | Supported backend | Backend/device | POWER: avoid competing profile daemons |
| P06 | SMT/core controls | Supported backend | Available/backend | POWER: expose only tested settings |
| P07 | GPU clocks and limits | Supported backend | Backend/device | POWER: respect shared APU power budget |
| P08 | Separate plugged-in and battery profiles | Integration/device | Integration/device | POWER: retain Omarchy AC/DC preferences |
| P09 | Per-game performance profiles | Steam/backend | Steam/backend | POWER: save and restore without leaks between games |
| P10 | Live battery, temperature and power information | Device | Device | POWER: event-driven state and honest sensor labels |
| P11 | Fan presets and custom curves | Device/optional; stack-transition limitations | Device/alternative backend | POWER: capability probe; retain firmware-safe fallback |
| P12 | Charging threshold and battery-care settings | Device/backend | Device/backend | POWER: supported limits and reversible changes |
| P13 | Battery bypass or charge inhibition | Device; not universal | Device; not universal | POWER: do not imply unsupported hardware support |
| P14 | RGB/LED brightness and effects | Device/optional plugin | Device/optional tool | INPUT: preserve firmware behaviour and detect support |
| P15 | Controller-accessible performance overlay | OGUI/Steam QAM | Steam integration/optional overlay | POWER and INPUT: controls usable while gaming |
| P16 | Save and restore power settings across resume | Device-dependent reliability | Device-dependent reliability | RELIABILITY and POWER: test AC/DC transitions |

Use one active writer for each hardware power setting. The preferred reuse candidates are InputPlumber, Gamescope session components and SteamOS Manager, with PowerStation where the supported device needs it. Do not enable HHD/Adjustor, asusctl, PowerStation and custom sysfs writers together without explicit ownership boundaries.

## Suspend and hardware reliability

Sources: [CachyOS current hardware selection](https://github.com/CachyOS/chwd/blob/master/profiles/pci/handhelds/profiles.toml), [Bazzite ASUS caveats](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/ASUS_ROG_Ally/), [Bazzite hardware setup](https://github.com/ublue-os/bazzite/blob/main/system_files/desktop/shared/usr/libexec/bazzite-hardware-setup).

| ID | Feature | Bazzite | CachyOS | Omarchy work |
| --- | --- | --- | --- | --- |
| R01 | Short power-button press suspends appropriately | Device/session integration | SteamOS Powerbuttond integration | RELIABILITY: no double handling with logind |
| R02 | Resume a running game | Game/device | Game/device | RELIABILITY: exercise real game and audio |
| R03 | Lock before desktop suspend | Desktop/session policy | Desktop/session policy | RELIABILITY: preserve existing lock monitor |
| R04 | Idle dimming, screen blanking and inhibition | Session integration | Session integration | RELIABILITY: active games prevent unwanted sleep |
| R05 | Wi-Fi reconnects after resume | Device | Device | RELIABILITY: check real association and traffic |
| R06 | Bluetooth reconnects after resume | Device | Device | RELIABILITY: controller and headset checks |
| R07 | Speakers, headphones and microphone | Device profiles | Model-specific PipeWire/WirePlumber | RELIABILITY: compare RC71L profile before borrowing |
| R08 | USB-C dock, charging and peripherals | Device | Device | RELIABILITY and DISPLAY: unplug/replug paths |
| R09 | Firmware and BIOS update route | Firmware tooling/device | Firmware tooling/device | RECOVERY: status and instructions, no speculative flashing |
| R10 | Model-specific kernel, input and firmware fixes | Device | chwd/deckify/kernel | RELIABILITY: upstream fix first, exact device gating |

## Display and docking

Sources: [Gamescope](https://github.com/ValveSoftware/gamescope), [Bazzite display quirks](https://docs.bazzite.gg/Handheld_and_HTPC_edition/quirks/), [CachyOS kernel features](https://wiki.cachyos.org/features/kernel/).

| ID | Feature | Bazzite | CachyOS | Omarchy work |
| --- | --- | --- | --- | --- |
| D01 | Correct internal orientation and touch mapping | Device | Device patches | DISPLAY: inspect actual panel geometry |
| D02 | Native resolution and refresh-rate selection | Device | Device | DISPLAY: retain known-good mode |
| D03 | Variable refresh rate | Display/driver | Display/driver | DISPLAY: supported internal/external output paths |
| D04 | HDR output and HDR game presentation | HDR display required | HDR display and patched stack required | DISPLAY: external compatible displays; internal SDR panel stays SDR |
| D05 | Brightness control from handheld UI | Device/session | Device/session | DISPLAY and INPUT: touch/controller access |
| D06 | External monitor selection and saved dock profiles | Desktop/session | Desktop/session | DISPLAY: test dock and undock recovery |
| D07 | Audio switches with HDMI/USB/Bluetooth output | Device/desktop | Device/desktop | RELIABILITY: preserve default-device choices |
| D08 | HDMI 2.1 FRL/VRR/DSC workarounds | Optional; compatibility risks | Kernel/driver/display | DISPLAY: no blanket kernel switches |
| D09 | Screenshots and recordings in gaming and desktop | Tool/session dependent | Tool/session dependent | DISPLAY: reuse Omarchy capture where applicable |
| D10 | Screen sharing and remote play capture | Session/tool dependent | Available bridge/tooling | GAMES and DISPLAY: test actual capture path |

## Game software and compatibility

Sources: [Bazzite launchers](https://docs.bazzite.gg/Gaming/Game_Launchers/), [game management](https://docs.bazzite.gg/Gaming/Managing_and_modding_games/), [Portal optional recipes](https://docs.bazzite.gg/Installing_and_Managing_Software/Bazzite_Portal/), [Sunshine current delivery](https://docs.bazzite.gg/Advanced/sunshine/), [CachyOS gaming guide](https://wiki.cachyos.org/configuration/gaming/), [gaming package recipes](https://github.com/CachyOS/CachyOS-PKGBUILDS/blob/master/cachyos-gaming-meta/PKGBUILD).

| ID | Feature | Bazzite | CachyOS | Omarchy work |
| --- | --- | --- | --- | --- |
| A01 | Steam and Proton for Windows games | Included | Included handheld | GAMES: retain existing installer and library |
| A02 | Choose alternate Proton runners | Available ProtonPlus/GE | Proton-CachyOS/available runners | GAMES: explicit install and per-game selection |
| A03 | UMU and shared compatibility runtimes | Available/tool dependent | Gaming meta integration | GAMES: package availability and launcher integration |
| A04 | Protontricks, Winetricks and prefix tools | Included/launcher dependent | Gaming tools | GAMES: reuse existing routes |
| A05 | Epic, GOG and Amazon via Heroic | Available | Available gaming apps | GAMES: existing Omarchy installer |
| A06 | Lutris and Windows storefronts | Included/available integrations | Available gaming apps | GAMES: existing Lutris/Battle.net setup |
| A07 | Faugus or other lightweight prefix launchers | Available | Available | GAMES: optional, avoid redundant defaults |
| A08 | Emulation and retro games | Available | Available | GAMES: existing RetroArch plus optional frontends |
| A09 | Moonlight and Steam Remote Play clients | Available | Available | GAMES: existing Moonlight installation |
| A10 | Sunshine streaming host | Optional Flatpak, no longer base | Available | GAMES: optional and capture-path dependent |
| A11 | Decky Loader and plugins | Optional | Available | GAMES: optional, rollback and update caveats |
| A12 | RGB tools and gamepad overlays | Device/optional | Device/optional | INPUT and POWER: use one backend per function |
| A13 | Mods, community launch options and compatibility fixes | Available | Available | GAMES: preserve user prefixes and saves |
| A14 | MicroSD/external game library | Device/filesystem integration | Device/filesystem integration | RECOVERY: safe mount permissions and no automatic formatting |
| A15 | Steam cloud/local save continuity | Steam/game-dependent | Steam/game-dependent | GAMES: confirm libraries and saves survive session switching |
| A16 | Anti-cheat compatibility | Publisher/game-dependent | Publisher/game-dependent | GAMES: explain limits; no universal Windows-game guarantee |

## Performance and resource management

Sources: [CachyOS kernel](https://wiki.cachyos.org/features/kernel/), [optimised repositories](https://wiki.cachyos.org/features/optimized_repos/), [system settings](https://github.com/CachyOS/CachyOS-Settings), [gaming tools](https://wiki.cachyos.org/configuration/gaming/), [Bazzite build and hardware integration](https://github.com/ublue-os/bazzite).

| ID | Feature | Bazzite | CachyOS | Omarchy work |
| --- | --- | --- | --- | --- |
| F01 | Modern Mesa, Vulkan and 32-bit gaming drivers | Included | Included gaming stack | PERFORMANCE: audit current Omarchy coverage |
| F02 | MangoHud performance overlay | Available/integrated gaming tools | Included handheld | PERFORMANCE: optional usable presets |
| F03 | GOverlay configuration UI | Available | Available gaming apps | PERFORMANCE: optional |
| F04 | Feral GameMode | Available | Available gaming tools | PERFORMANCE: avoid competing handheld power policy |
| F05 | Handheld-oriented kernel patches | Included image kernel | Deckify/CachyOS kernel | PERFORMANCE: evaluate specific needed fixes first |
| F06 | sched-ext and LAVD | Build/configuration dependent | Handheld default | PERFORMANCE: optional measured experiment |
| F07 | BORE and alternative scheduler kernels | Different kernel choices | Available variants | PERFORMANCE: preserve supported kernel fallback |
| F08 | NTSync and Wine synchronisation improvements | Kernel/runner dependent | Documented kernel/runner support | PERFORMANCE: verify running kernel and runner |
| F09 | CPU-targeted repositories and compiler optimisation | Build-specific | v3/v4/Zen4+; selected PGO/LTO/BOLT | PERFORMANCE: no wholesale repository replacement |
| F10 | Compressed memory and storage I/O tuning | Distribution configuration | CachyOS Settings | PERFORMANCE: compare existing zram/I/O settings |
| F11 | Audio power handling and latency tuning | Device/distribution | CachyOS Settings | RELIABILITY and PERFORMANCE: avoid audio regressions |
| F12 | Gaming-oriented networking tuning | Distribution configuration | Documented BBRv3/settings | PERFORMANCE: measure; no promised latency gains |

## Updates, security, recovery and general desktop

Sources: [Bazzite SteamOS comparison](https://docs.bazzite.gg/General/SteamOS_Comparison/), [Bazzite architecture and security](https://github.com/ublue-os/bazzite), [Bazzite desktop/software FAQ](https://docs.bazzite.gg/General/FAQ/), [CachyOS handheld installation](https://wiki.cachyos.org/installation/installation_handheld/), [CachyOS repositories](https://wiki.cachyos.org/features/optimized_repos/).

| ID | Feature | Bazzite | CachyOS | Omarchy work |
| --- | --- | --- | --- | --- |
| U01 | Guided first-run gaming setup | Portal/integration | Handheld setup | RECOVERY: extend existing Omarchy gaming setup |
| U02 | Controller/touch-readable update status | Gaming update integration | Package/session integration | RECOVERY: usable access to existing Omarchy updates |
| U03 | Updates and regression recovery | Atomic image deployments | Mutable Arch/pacman | Different: preserve Omarchy update model |
| U04 | Previous system state and boot recovery | Deployment rollback/pinning | Btrfs/Limine snapshots | RECOVERY: verify existing Omarchy snapshots and fallback |
| U05 | Repeated failed-boot recovery | Documented handheld rollback | Snapshot/boot configuration | RECOVERY: establish actual Omarchy behaviour |
| U06 | Secure Boot | Supported with enrolled key | Configurable | RECOVERY: preserve current boot trust; do not replace keys |
| U07 | Disk encryption | Optional | Configurable | AUTH: retain current encryption and recovery access |
| U08 | Mandatory access controls and signed images | SELinux/image infrastructure | Different architecture | Different: do not port Fedora policy/image machinery blindly |
| U09 | Graphical app delivery | Flatpak/Flathub/Bazaar | Arch tools; optional Flatpak | GAMES: reuse Omarchy package/install menus |
| U10 | Full general-purpose desktop | KDE or GNOME variants | KDE handheld; broader desktop editions | Existing Omarchy Hyprland; retain workflows |
| U11 | Browser, media codecs, audio and printing | Desktop/base applications | Desktop/packages | Existing: audit failures instead of replacing desktop |
| U12 | Containers and developer CLI tools | Distrobox/containers/Homebrew | Arch/container tooling available | Existing Omarchy developer tools; no handheld-specific rewrite |
| U13 | Diagnostics, logs and support information | Portal/system tools | CachyOS tools | RECOVERY: single handheld status report with redacted output |
| U14 | Backup and restore of user data | User/application setup | User/application setup | RECOVERY: snapshots are not save-data backups |

## Existing Omarchy baseline

- `7b9cb7b18` adds optional Steam Big Picture, Desktop Mode and gaming setup in the existing desktop. It explicitly does not implement a separate gaming session, controller mappings, power controls or suspend integration.
- `feat/desktop-touch-keyboard` contains `d5ef5a1cd` and `740a7ce7f`: optional on-demand wvkbd keyboard and instructions. It does not implement greeter, lock or disk-unlock typing.
- `cursor/rog-ally-rc71l-3178` contains `62d1d6f79`, `5252425c8` and `515d61405`: original Ally detection, laptop-asusctl/audio/microphone boundaries and setup invitation. Preserve these changes rather than implementing them again.
- Existing Omarchy includes general UPower/PowerProfiles controls, lock-before-suspend logic, monitor recovery, Steam, Heroic, Lutris, Battle.net, RetroArch and Moonlight installation routes. Availability still needs checking on the installed Ally.

## Reuse and licensing

Prefer upstream packages and their documented APIs over maintaining copied daemons. InputPlumber and PowerStation declare GPLv3+; OpenGamepadUI declares GPLv3; the CachyOS Gamescope session package declares MIT; the CachyOS handheld metapackage declares GPLv3-or-later; CachyOS Settings declares GPLv3; the Bazzite integration repository declares Apache-2.0. Check the exact file and dependency licences and retain notices when copying or modifying source. Steam remains third-party software with its own terms. Verify SteamOS Manager's exact packaged source and licence before copying it.

Do not install `cachyos-handheld` wholesale: its current [installation script](https://github.com/CachyOS/CachyOS-PKGBUILDS/blob/master/handheld/cachyos-handheld/cachyos-handheld.install) changes the display-manager service, guesses the autologin user and enables distribution-specific services. Do not replace Omarchy's desktop, repository set, bootloader or update model merely to obtain a controller daemon.

## Implementation work packages

Each work package gets a separate thread and worktree. All start from one integration baseline containing the existing gaming, keyboard and RC71L work plus this inventory. Package ownership is designed to avoid concurrent changes to shared setup files; the integration owner reconciles unavoidable shared-file edits.

| Owner | Scope and primary files | Dependencies and acceptance |
| --- | --- | --- |
| INPUT | InputPlumber setup, controller profiles, device detection, buttons, mouse mode, gyro/rumble/RGB capability handling; dedicated commands/config | Independent backend. Real stick movement, click, scroll, mode switch and game input on RC71L, including with Steam closed. Coordinate overlay buttons with SESSION and POWER. |
| POWER | Supported SteamOS Manager/PowerStation backend selection, handheld controls and power panel integration | Consume agreed input overlay routes; one power owner. Read back supported watts, AC/DC policy, temperatures and charging state; safely restore changes. |
| SESSION | Gamescope session entry, launcher/lifecycle, boot preference, return-to-desktop and failure recovery | Coordinate session chooser with AUTH without editing its QML. Launch actual direct gaming session, run a game and return to Hyprland. |
| AUTH | SDDM touch keyboard, submit/session selector, trusted Omarchy lock keyboard; investigate early boot input separately | Own SDDM theme and lock surface. Verify masked password entry, cancel/failure, non-US keys, PAM and physical keyboard. Keep encryption intact. |
| TOUCH | Existing desktop wvkbd integration, touch/controller summon, focus and layout | Coordinate INPUT shortcut. Type and edit real text, show/hide without focus theft; preserve normal desktop keyboard behaviour. |
| DISPLAY | Ally display capabilities, refresh/scaling/orientation, dock and external output behaviour, capture path | Coordinate SESSION configuration. Verify native modes, pointer/touch mapping and undock recovery; HDR only on capable outputs. |
| RELIABILITY | Power-button ownership, suspend/resume, audio profiles, Wi-Fi/Bluetooth/controller reconnection | Coordinate POWER and SESSION. Verify a suspend/resume cycle with actual game, audio and connectivity; no speculative kernel quirks. |
| GAMES | Existing launchers, Proton/UMU tools, optional Decky/emulation/streaming and performance tooling | Preserve saves/prefixes and avoid redundant defaults. Install optional tools through normal Omarchy helpers; verify launch paths. |
| RECOVERY | Handheld setup/status, update/recovery access, safe library mounts and backup/rollback guidance | Own top-level setup/menu/manual integration. Verify idempotent setup and unsupported-hardware handling; preserve generic update architecture. |
| INTEGRATION | Merge feature commits, focused tests, shared-file conflicts, release branches and deployment instructions | No unreviewed broad kernel/repo switch. Keep source and installed status distinct. Maintain this inventory and thread index. |
| ALLY DEPLOYMENT | Sole owner of changes to the live Ally; package builds, installations, screenshots/recordings and rollback | Apply tested increments serially. Other feature threads do not install, restart services or change the active session independently. |

## Live verification and rollout

The Ally is a linked T3 environment. Confirm the model, current packages, active session, firmware/kernel, local source and user modifications before changing it. Record a baseline and recovery path first. Capture evidence outside Git and keep secrets, serial numbers, addresses and personal desktop content out of the public source.

Use the repository's focused tests and write the complete output to logs. Use `omarchy dev link` only with its documented environment/reboot semantics. It does not install fixed `/etc`, systemd or udev files; use the documented package-build/install route for those. Do not overwrite the installed package tree ad hoc. Read the Omarchy end-user skill before user-configuration changes and `agents/skills/visual-verification.md` before live UI work.

For each increment record: source commit, installed package versions, changed config/backups, checks executed, screenshots/recording reviewed, measured outcome, unresolved limits and rollback command. Report software checks separately from physical input, dock and suspend checks that could not be exercised. Notify the user on the device before temporarily taking over the desktop. Restore the normal shell after temporary visual checks. Do not leave a temporary worktree shell running at handback.

## End-to-end acceptance

1. Cold boot to a usable sign-in surface; enter the password using touch without a physical keyboard. If disk encryption prompts first, explicitly record that separate input result.
2. Enter the Omarchy desktop; use the sticks to move the pointer, click, scroll and summon a keyboard while Steam is closed.
3. Launch the dedicated gaming session; navigate the library, start a game, open quick settings and change a supported power setting with visible readback.
4. Suspend and resume; check game, controller, speakers, Wi-Fi and Bluetooth.
5. Return to the desktop; dock and undock where hardware is available; lock and unlock using touch.
6. Reboot and repeat the selected boot/session preference; verify recovery and that ordinary non-Ally hardware is unchanged.

## Thread and installed status

Research is complete. Nine feature worktrees and one source integration worktree preserve the common `f7194066d` baseline. The [thread index](rog-ally-threads.md) identifies each owner and the sole live rollout thread. This ledger records reviewed source separately from installation and physical acceptance; the presence of a command, package or active service never completes an inventory row by itself.

### Reviewed source increments

| Increment | Owner commit → integrated commit | Source checks | Installed and physical evidence |
| --- | --- | --- | --- |
| Preserved gaming setup, desktop keyboard and RC71L laptop/audio boundaries | Common baseline `f7194066d` | Eight preserved focused logs reviewed; see below | Native baseline runtime/settings pair remains installed as `dev.28a5d89-1`; frozen release below is built/prepared but installation is blocked on authentication |
| Keyboard setup and menu accept the short Ally product name with RC71L board | INTEGRATION `28a5d89fc2ecb376cea9f06e66caa69530a5883d` | Regression failed before fix; hardware, gaming setup and keyboard suites passed afterwards | Rollout checked keyboard visibility/focus with automated `wtype`, Big Picture hiding and Desktop Mode retaining the Steam PID. Actual OSK taps/controllers remain unverified |
| Launcher removal preserves libraries, saves, prefixes and settings; RetroArch reinstall preserves configuration/shaders | GAMES `ed85c4121767c3b23a3f4121eb86245aefb2b512` → `d7d417e9f278e0c89a3313af5845b5fd85559ad7` | Integrated filesystem regression passed; obsolete English Battle.net removal prompts retired in `03c9872d6` | No live uninstall test authorised as acceptance; actual game/save continuity remains unverified |
| Existing removable game-library mount/check/unmount and save-backup guidance (A14/U14 partial) | RECOVERY `f55be85dd1d1d1135e69c35a623b202cf81cc220` → `c9b1441b1` | Integrated storage guards and picker tests passed; no real disk mounted | Actual microSD/USB, game launch and save restore remain unverified |
| RC71L desktop power button locks before requesting suspend; ordinary hardware retains its menu (R01/R03 partial) | RELIABILITY `17b2a97f52072156516c314f581972775029bf5b` → `12aa7fa0e` | Integrated hardware routing, failed-lock cancellation, exclusion and overlap checks passed | Physical button, lock/suspend/resume and touch unlock remain unverified; no logind change |
| Session-scoped Valve powerbuttond and narrow RC71L KEY_POWER access | RELIABILITY `947b7dd04` → `4c2f2a30e` | Hardware guards, foreground lifetime/exclusion and actual isolated hwdb token tests passed; worker built pinned Valve 4.2 companion | Install matching runtime and `packaging/rog-ally-powerbutton/PKGBUILD` companion together; SESSION owns PID/scope. Physical press/resume unverified |
| Optional compatibility tools, per-game overlays and disabled Decky lifecycle | GAMES `a820984f5`, `c178cbec9`, `3a788b648` → `b01a87777`, `c550c8f6b`, `e7ca57961` | Driver ordering, literal argv/FPS guards, failed-game status and Decky lifecycle tests passed; clean companion build/payload verified below | Optional packages remain opt-in. No game, rendered overlay, Decky UI or Sunshine host acceptance |
| Desktop keyboard button/shortcut, session guards and full-layout geometry | TOUCH `c2ce33d5d`, `bdb732d94`, `a66bec6b6` → `0bae8195d`, `42d6ac571`, `f09fa19c2` | Host-installed-keyboard isolation, process/session guards and conditional binding tests passed; bar manifest check passed, live widget check skipped without compositor | wvkbd is 264 logical pixels in both orientations; keep its button on the top bar. Real text/focus/Menu-AppGrid stacking remains unverified |
| Optional native display controls, touch preset/mapping, dock profiles and output-only Gamescope arguments | DISPLAY `4357ecd01` → `0a8c2524c`; owner prose correction `654bc148d` incorporated equivalently | Integrated monitor/capability, EDID rename/unplug/ambiguity, touch event and preset rollback tests passed | No display mode, touch-corner, dock, VRR, external HDR or capture acceptance; internal HDR refused |
| Handheld onboarding, redacted read-only status, delivered-feature routing and recovery access | RECOVERY through `e541ab2ed` → `2dcba15bc`; integration `67e8829d5` removes held writable power-panel route | Integrated picker/routing/privacy/failure/cancellation suite passed; status transport cannot autoactivate held backends | No live menu/controller/storage/snapshot recovery acceptance; INPUT/POWER activation stays gated in onboarding pending installation review |
| Dedicated authenticated Gamescope/preference sessions and desktop recovery | SESSION `c52affb7b` → `ae7cbafd2`, plus integration `63b49c8fe` | Integrated lifecycle, UWSM identity, one-shot, failure/return, acquired-service and async logout-failure tests passed; new failure regression was red before fix | Normal desktop entry unchanged. Same-release runtime and registration companion required; DRM game/session/reboot acceptance unverified |
| Capability-aware public SteamOS Manager client, desktop controls and single AC/DC/resume policy | POWER `d3d00ea8e`, `1256ff060` → `524637218`, `b9abad280`, plus non-activating transport `67e8829d5`; next-stage setup guard `180aa53b2` | Client findings corrected: requested-source persistence, profile-only watt bounds and startup signal cleanup. Integrated power/default-profile tests and actual isolated D-Bus delayed-readback smoke passed. Package review found separate deployment blockers below | **Blocked: unchanged Manager 26.4.1-3 must not be installed, even inactive.** No remediated package/artifact or hardware watts, thermal, charging, QAM or resume acceptance |
| InputPlumber profiles, desktop actions and actual lock/overlay ownership guards | INPUT `921fcec0f`, `27c434b38` → `844b41517`, `156faa7c3`, plus integration `adbe8541b` | 22 focused regressions and RC71L suite passed. Removed-device regression was red before fix; actual corrected AUTH producer/consumer pair passed snapshot/lock/unlock/EOF | Use companion **1.0.2-1**, including integrated hotplug fix; never deploy 1.0.0. Requires corrected lock producer. Physical sticks/buttons/held keys/gyro/rumble/interception/suspend remain unverified |
| Trusted SDDM touch keyboard/session chooser and read-only actual lock-state producer | AUTH `867c60e77`, `887626c5d`, `3e2b8ca4a`, `0dcf7c55a` → `f4526e1e1`, `6e2ea77e8`, `eec2632ce`, `75e0e2958` as one corrected set | Integrated real Qt SDDM and unrelated-importer/child-environment regressions passed; actual Unix socket rejects an unterminated byte. Offscreen dummy greeter capture inspected | Only SDDM receives Qt keyboard context. K07 lock touch keyboard is **held/unavailable**; physical password/fingerprint lock preserved. Real PAM/touch/sign-in/secure-lock acceptance pending |

All nine streams have delivered reviewed source increments; this is not full installed parity. The unsafe intermediate AUTH lock-keyboard mode is removed in the final tree: process-wide Qt Virtual Keyboard exposed the focused password QObject to an unrelated QML importer, and its environment leaked into child applications. Do not deploy the original AUTH commits alone or revert only the corrective commits. K07 remains an original requirement for a separately agreed safe implementation, not a dropped feature. K11 early-boot touch typing also remains unimplemented; preserve encryption and physical-keyboard recovery. Firmware/backend limitations in each owner document remain visible.

### Evidence retained on Sigil

The preserved logs are `/tmp/ally-baseline-{bigpicture,steamdesktop,gaming-setup,keyboard,hardware,laptop,quirks,i18n}.log`. They were reviewed without rerunning the unchanged baseline. Keyboard coverage explicitly checks process ownership/lifecycle, not real focus, touch entry or authentication.

Integration logs are `/tmp/ally-integration-hardware-before.log` (expected regression failure on the baseline), `/tmp/ally-integration-hardware.log`, `/tmp/ally-integration-gaming-setup.log`, `/tmp/ally-integration-keyboard.log`, `/tmp/ally-integration-gaming-data.log`, `/tmp/ally-integration-storage.log`, `/tmp/ally-integration-sleep-lock.log`, `/tmp/ally-integration-sleep-monitor.log` and `/tmp/ally-integration-i18n.log`. Complete logs remain outside Git. Read their results and exit status; a skipped compositor check is not a visual pass. Run a shared suite once at the end only if the integrated changes reach shared code that justifies it.

Additional integration logs cover `gaming-driver-order`, `gaming-overlay`, `decky`, `monitor`, `power`, `powerprofiles`, `power-dbus`, `auth-keyboard`, `launch-shell`, `lock-state`, `auth-pair`, `plugin-manifest`, `bar-widget`, `capture-picker-binds`, `color-reference` and `network-command`, using `/tmp/ally-integration-<name>.log`. Final catalogue and CLI results are `/tmp/ally-integration-i18n-final.log` and `/tmp/ally-integration-cli-release.log`. The initial source-host auth fixture lacked Qt's keyboard module; its failure logs are retained with `-without-qt`. The passing runs use the already extracted Qt 6.12 dependency under `/tmp/ally-auth-qt` and private offscreen/socket fixtures, without installing it on Sigil or touching the live session.

The clean Decky companion build completed with exit 0 in `/tmp/ally-integration-decky-build.log`; manifest and source-content comparisons are in `/tmp/ally-integration-decky-manifest.log`. Artifact SHA256: `18b6888e4ddb901c65027a6e3f104b120ee7e69f1ddf6d9dac35b9dbacf55c22`. This resolves the earlier interrupted-build evidence gap for the tiny companion only; the separate AUR Decky build and actual service/UI still require rollout evidence.

No whole-shell pass is claimed. AUTH's interrupted broad run retained 268 results/17 nonzero: 14 failures were reproduced on the preserved baseline, two baseline-passing timeout failures (`color-reference` and `network-captive-portal-command`) now pass independently on integration, and the partition baseline check was interrupted. Complete logs remain in `/tmp/omarchy-test-shell.LBkAYL` and `/tmp/ally-auth-base-checks`. These limits are not concealed by a new broad run under shared-host load. A final whole/shared run belongs to the completed combined rollout, with the actual host/session conditions recorded.

The initial live audit found original RC71L, BIOS 339, kernel `7.2.15-2-omarchy`, Omarchy `4.0.0.r7695.g7a9a1e9-1`, Steam and wvkbd present, Gamescope/InputPlumber/HHD absent, PPD active, existing ASUS power support and 30/43/53 W readback. These are baseline observations, not evidence for the new backend or new session. Existing SDDM autologin was observed and left unchanged; none of this work enables it. The first completed receipt in private Fleet `main` commit `4b57466` records two per-user helper updates, inspected private captures, keyboard visibility/focus with `wtype`, Big Picture hiding the keyboard, and Desktop Mode preserving the Steam PID. It explicitly does not prove physical OSK taps or controller operation. The full baseline package pair initially awaited sudo after two requests expired.

Subsequent coordinator reconciliation of the live owner confirms the native baseline pair **installed** as `dev.28a5d89-1`, with package integrity and configuration hashes unchanged and the same limited Gaming Setup/visibility-focus/Steam-return checks passing. Private Fleet receipt: `eeb1136`. Physical OSK taps, sticks, sign-in and secure-lock checks remain unverified.

### Frozen staged release

Runtime source **`47e0e976f47c86edf9962d0debde9b571fadc385`** is pushed to `origin/feat/ally-parity-release-20261111`. This remains the frozen code cut; later ledger and next-stage commits do not promote a different source into this rollout. The coordinator read the sole rollout owner's completed run 6 through final position 363: frozen runtime/settings packages and the powerbutton companion built on the Ally, local focused checks passed, and all 22 isolated INPUT tests passed, including the previously sandbox-restricted socket fixtures. Those are build/source checks on the device, not physical sticks, touch or real secure-lock acceptance.

**Frozen 47e is prepared, not installed.** Its single sudo card expired before the first dependency transaction. No prompt remains active, and this stage changed no installed packages, services, masks or configuration. The Ally remains on native `dev.28a5d89-1`. The prepared-stage receipt, backups, checksums and exact resume boundary are committed to private Fleet `main` as `d51ba01`, in `log/2026-11-11-ally-staged-release-47e0e976.md`.

Keep the prepared transaction pinned to 47e. Do not restart the rollout, launch another live owner or create a credential loop to acknowledge this receipt. When Daniel explicitly returns for credentials, resume the same sole owner at its recorded transaction boundary with one secure prompt. No next-stage source promotion, rebuild or Manager artifact approval is implied by these checks.

Source-matching clean companion builds completed with exit 0, without installing or checking dependency availability on Sigil:

| Companion | SHA256 | Complete build/manifest logs |
| --- | --- | --- |
| `omarchy-rog-ally-input-1.0.2-1-any.pkg.tar.zst` | `7c3c3261157c13fb1e802b617d9c0289250b250f26307b775f1b93fad95fb6c1` | `/tmp/ally-release-input-{build,manifest}.log` |
| `omarchy-gaming-session-1.0.0-1-x86_64.pkg.tar.zst` | `2a5090d0f5c824fe8e91622d30027cb48ba674b35e637f854a7552104e4a592a` | `/tmp/ally-release-session-{build,manifest}.log` |

Their private build root is `/tmp/ally-release-packages.z11dOA` on Sigil; archived bridge/registration content matches the frozen source. The Ally rebuilds from the exact release rather than assuming access to Sigil's temporary paths. Main runtime/settings, Qt dependency and fixed-path companions must use the documented serial installation route and preserve private backups. Runtime plus reliability companion arrive together. The completed independent Manager review blocks both POWER takeover and installation of unchanged Manager as an inactive prerequisite; no remediated package/artifact is approved. This does not change the frozen non-power rollout. Optional Decky stays disabled unless explicitly selected under its separate root-plugin contract.

K07's separately authorised trusted-host implementation continues in the existing AUTH thread and is outside this frozen cut. Its contract retains one lock/PAM owner and the canonical lock/status API, with no third-party QML in the trusted process. The existing logind delay inhibitor cannot veto already-issued external sleep; do not claim all-source suspend veto without a separate agreed policy change. The staged release retains the ordinary physical password/fingerprint lock and leaves K07 unavailable.

### Next-stage source candidate

RECOVERY `1348dfac81d9c1556921d8cd1f8f0f827ae909e4` is integrated as `8b72cb72e5981f5a02221e05823d48c4d22ef951`, independently of frozen release `47e0e976f47c86edf9962d0debde9b571fadc385`. Its parent tree matches the frozen release; the feature branch's dependency merge was not integrated. This candidate is for the next runtime build only. It does not change the current live rollout's pinned source, install packages or enable input by itself.

The frontend offers explicit input enablement only with both runtime helpers and the exact installed companion identity `omarchy-rog-ally-input 1.0.2-1`. A visible recovery/terminal confirmation precedes a second helper/package check. Missing, old, unreviewed newer, malformed or removed packages do not qualify. Status keeps source review, package eligibility, API readiness and physical unknown separate. POWER remains readiness/legacy-rollback-only following rejection of unchanged Manager; configuration and writable-panel routes remain absent.

Integrated verification passed: all 12 focused routing/status groups in `/tmp/ally-next-recovery-input.log` (including confirmation/cancel, package disappearance, missing helpers, privacy and POWER hold), Bash syntax, ShellCheck in `/tmp/ally-next-recovery-shellcheck.log`, and `git diff --check`. No broad suite was repeated for these local frontend changes. Source review found no blocker. Actual menu geometry, touch/controller operation and enable/disable behaviour still require the sole rollout owner's next-stage acceptance after installing the matching runtime and companion under INPUT's mask/ownership procedure. Reverting the frontend does not disable already-enabled input; run the owner's disable command before companion removal or restoring a prior writer.

### Manager package rejection and central setup guard

The independent read-only review of CachyOS recipe commit `ab15ca2048159897015eb0ac90eac8c756b86e7a` (PKGBUILD SHA256 `4cc9005e13cddf708f86bec2ad2dfb9effe1d249de65f5b95d4b6e85c999e403`) and upstream `a0d399defebd60db30ba38325d9cf47dbda49bee` rejected unchanged `steamos-manager 26.4.1-3`. It must not be installed even as an inactive prerequisite: install/upgrade enables its root unit for the next boot. Other blockers are unconditional root input-target/PlayStation management, unauthorised privileged RootManager methods including login policy, unavailable/out-of-scope networking dependencies and payload, and SPL-only readback that cannot verify restoration of all touched SPL/SPPT/FPPT limits. The Omarchy client's public-session API, caps and opt-in do not protect direct backend callers.

The review matched the official archive to the mirror and checked source/patch checksums. `/tmp/ally-manager-review/review-evidence.json`, `expected-package-files.txt`, closure reports and `rust-lock-dependencies.tsv` retain the evidence. The 41-file package manifest is predicted from source, not an actual archive. No binary artifact, successful package build, dependency proof or RC71L asus-armoury probe was accepted.

INTEGRATION owns tested central guard `180aa53b2c061c6687776b6d204a911416fe8e41`; POWER must preserve that exact correction instead of publishing a competing helper implementation. New setup refuses before package queries, service changes or state writes. The existing legacy rollback body is preserved, without claiming complete three-limit restoration or service ownership before package installation. The focused regression fails against the prior helper at its package query (`/tmp/ally-next-power-hold-before.log`, exit 1) and passes with the guard (`/tmp/ally-next-power-hold.log`, exit 0); Bash syntax, ShellCheck excluding test source-resolution SC1091 (`/tmp/ally-next-power-hold-shellcheck.log`) and diff checks passed. This guard is next-stage source only: frozen `47e0e976f` and its current rollout remain unchanged.

POWER's authorised bounded follow-up is an input-management opt-out prerequisite patch, immutable source/patch/Cargo.lock manifest and code-grounded power-only interface, server-authorisation and all-three-PPT transactional capture/apply/restore design. The opt-out alone does not resolve the privilege/API blockers. `omarchy-steamos-manager-power` is reserved only; no package/version/artifact is approved. Networking dependencies remain until both root and user Wi-Fi paths are absent. Full Rust builds, installation and takeover wait for an agreed remediated design. See [power reference](../docs/rog-ally-power.md#package-review-hold).

POWER delivered that finite increment as `0fbd941c8d73fc7287cf5098f0a469cb28967de1`, integrated as `b021f775ebd5803060bb7250499d15ba2629e509`. Only that atomic commit was selected; its parent `313ca7ae3` is the unchanged copy of central guard `180aa53b2` and was not integrated again (matching patch IDs verified). The frozen non-activating Python transport is unchanged in the resulting tree. The shared power guide retains central protective wording, links the new [remediation design](../docs/rog-ally-manager-remediation.md) and removes the obsolete full-Manager session-unit start/stop proposal. No new runtime implementation, installable recipe or activation is delivered.

The prerequisite patch against pristine upstream `a0d399d` adds a restart-only root input-management opt-out that gates both DeckService/DS inhibitor startup and later inhibitor commands before their state/hardware effects; upstream defaults remain enabled. Queued D-Bus acknowledgement remains unchanged. The patch is **unbuilt**, not a power-only or authorisation fix. Committed provenance pins source/recipe/patch/licence/Cargo.lock and original review/closure hashes with accepted package/version/artifact all null. The proposed snapshot schema and transaction contract cover profile plus original SPL/SPPT/FPPT, source/mutation epochs, root-held identity, partial-write recovery and verified restoration. Initial restricted scope excludes governor/manual-GPU writes after identifying incomplete CPU0/single-endpoint readback. The systemd-user proxy's actual-session delegation boundary remains explicitly unresolved; agree that boundary and the restricted entry point before a subsequent implementation/build increment.

Integrated focused power/client/guard checks passed in `/tmp/ally-integration-manager-design-power.log`, exit 0. `/tmp/ally-integration-manager-prerequisite.log` verifies recorded source/lockfile/patch/licence hashes, zero-fuzz temporary application and the exact patched-root hash. `/tmp/ally-integration-manager-provenance.log` verifies retained recipe/evidence hashes, rejects a deliberately changed source before patch application, and records Python AST/JSON parsing only. Bash syntax and ShellCheck excluding test source-resolution SC1091 passed (`/tmp/ally-integration-manager-shellcheck.log`). Default diff whitespace checking flags the preserved space-only unified-diff context lines in the canonical patch; all other added files pass and the unchanged patch bytes apply correctly. No formal JSON Schema validator, Rust test/build, Cargo fetch, artifact/signature review, live probe, service or hardware acceptance was executed. Stock Manager remains no-install, and frozen 47e remains prepared but uninstalled under its recorded credential boundary.

The coordinator assigned the existing POWER owner the next bounded source investigation: prove a real authenticated SDDM/logind registrar anchor before UWSM detachment and specify a root-issued, actual-sender/session-bound expiring proxy grant with renewal/revocation, or report the exact blocker. Active UID, environment and well-known bus names are not authority. Only a minimal denial-only/private-bus proof may support this design; a broad Manager build, hardware setters and the full PPT engine remain outside this increment. Unknown anchor/authority must fail before takeover. No implementation or proof result has been delivered yet.

Integration supplied the actual SESSION source boundaries: the optional session desktop entries invoke `bin/omarchy-session-start`, whose desktop path calls UWSM while its supervisor survives desktop/gaming transitions. Gamescope uses a user scope rather than a detached user service. The normal `default/wayland-sessions/omarchy.desktop` bypasses this selector. The imported `OMARCHY_HANDHELD_SESSION`, runtime directory and active/switch files are unprivileged routing data, not root-verifiable credentials; the transient logout worker is not a registrar. No new registration hook, grant or SESSION production change was made by integration.

SESSION's finite read-only authority answer confirms only a plausible pre-detachment Bash registrar location, **not a verified anchor**. The supervisor and all three relevant entries are unchanged between owner `c52affb7b`, integration `63b49c8fe` and frozen 47e (empty source diffs checked). Bash waits outside its UWSM child; the gaming user scope can relocate scoped processes under the user manager. The original source comment claiming that a scope preserves logind seat access is too strong and is not accepted as authority, cgroup or DRM/libseat evidence. No observed supervisor PID → `GetSessionByPID` → SDDM session mapping, session Service/Class/Type/User/Remote/Seat/Active/State/LockedHint values, or transition/resume lifetime proof exists. SESSION has no registration, pidfd binding, authentication attestation or resume revalidation; its fixtures fake the external systemd/logind boundaries.

The owner traced expected SDDM authenticate/openSession → PAM → selected Wayland command ancestry and inspected Sigil's local UWSM/SDDM/PAM files. Optional `pam_systemd` does not guarantee successful binding, and those local files are not verified Ally files. An actual system-bus sender's derived PID/UID and revalidated local active-seat/session/lifetime properties are required before any grant; an association alone still does not attest script contents or authorise a narrow action. POWER received these corrected source limits. The [session reference](../docs/rog-ally-gaming-session.md#session-contract) now distinguishes orchestration from authority. No runtime source, registration hook, device probe or takeover was changed by this documentation correction.

Separately, the coordinator resumed the same sole Ally owner for a read-only current-profile asus-armoury attribute existence/readability and complete SPL/SPPT/FPPT/ranges capture. This request permits no profile change, write, modprobe, package/service/configuration change or sudo prompt, and no source worker may probe the device. Completion evidence is pending; firmware defaults/ranges would not establish approved software burst caps. This is not promotion or a rebuild of frozen 47e or next-stage source. The credential-blocked prepared state and native `dev.28a5d89-1` installation remain as last recorded.

### Integration boundaries

Feature owners retain their dedicated implementations. RECOVERY owns top-level `bin/omarchy-setup-gaming`, menu and manual integration; AUTH owns greeter/lock surfaces; SESSION owns its optional session entries and launcher lifecycle. INTEGRATION reconciles their delivered shared-file changes and owns this ledger and the thread index. Preserve each unrelated menu row, catalogue key, package dependency and install hook when resolving conflicts. Retain both behavioural regressions when workers append to the same test file. New default hardware gates use `omarchy-hw-rog-ally`.

The agreed desktop keyboard route is the existing helper with explicit `toggle`, `show`, `hide` and `stop`; TOUCH supplies the optional RC71L `Super+Ctrl+Y` binding. INPUT's keyboard capability emits that chord on desktop and Steam Guide+X (West) in gaming. Steam QAM uses Guide+South. Desktop power opens `omarchy-shell shell toggle omarchy.power`; that desktop surface does not appear in DRM Gamescope. POWER owns SteamOS Manager configuration, AC/DC and resume power policy; RELIABILITY owns button/sleep routing and adds no second power writer. These contracts still require actual cross-feature acceptance.

SESSION's revised design leaves the existing Hyprland session entry unchanged and packages optional `omarchy-gamescope.desktop` (Omarchy Gaming) and `omarchy-handheld.desktop` (Omarchy session preference). AUTH lists the actual SDDM `sessionModel` rather than hard-coded session names. Desktop keyboard stops before gaming handoff; INPUT enters gamepad mode. DISPLAY emits only output selection arguments; SESSION owns render resolution/frame cap/filter settings. Gaming power-button handling runs inside the gaming lifecycle, never as a global service. Owner receipts define exact package manifests and commands before deployment.

### Release and deployment handoff

1. Feature owners deliver an immutable commit, dependencies, focused test commands/logs, shared-file edits, package recipe/fixed-path manifest, install/rollback instructions and remaining physical checks. Review the actual diff before integrating. Publish only reviewed, tested source to `origin/feat/ally-parity-release-20261111`; report its full resolved SHA in the handoff rather than asking rollout to follow a moving branch.
2. Send each concrete release to the sole rollout owner and copy the coordinator. Controllers, authentication and the gaming session remain the priority. Finish the current deployment increment before starting another; never create a second live writer or restart an uncertain run. The rollout owner retains its own exact package/config baseline and Fleet ownership.
3. On the Ally, fetch and pin the release in a clean source checkout. Runtime paths can be dev-linked only with the documented reboot semantics. Fixed `/etc`, `/usr/lib`, udev and packaged greeter/session files require the reviewed package build/install route. Check `omarchy dev pkg-test --help` and [file layout](../docs/file-layout.md) against the actual installed helper; inspect matching recipes in `omarchy-pkgs` and package payloads. A source file under `default/` alone does not prove it ships. Do not copy files ad hoc over the installed package tree or replay all user defaults.
4. A release receipt records the full source SHA, actual package versions/payloads, changed config and private backup paths, checks with outcomes, UI evidence reviewed, unresolved limits and exact rollback for the prior recorded state. Retain libraries, prefixes and saves on rollback. Updating runtime source alone does not undo installed units, selected backends or user configuration.
5. The remote rollout cannot send messages back across environment links (`capability_denied`). Sigil reads a bounded completion receipt through `t3_thread_wait` then `t3_thread_read` for the concrete increment. A timeout means the existing run is still in progress; do not loop, relaunch or infer completion. Update installed/physical columns only from an actual receipt, including any failed or unavailable checks. No timer, recurring watcher or polling loop is needed.
