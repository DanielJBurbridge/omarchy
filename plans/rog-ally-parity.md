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

Research is complete. Implementation and live verification are not yet complete. Thread links, branch names, commit IDs and verified installation results are added as work starts and lands. A row remains pending until its owner supplies appropriate evidence; an unsupported hardware feature is recorded as such rather than simulated.
