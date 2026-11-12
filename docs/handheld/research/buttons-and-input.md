# ROG Ally (RC71L) buttons and input stack: kernel, HHD, InputPlumber, Steam

Researched 12 Nov 2026 (AWST). Every non-obvious claim has a source link. **Unverified** marks anything I could not confirm from a primary source. Device facts come from `ally-hw-dump.md` (Daniel's RC71L, kernel `7.2.15-2-omarchy`, BIOS 339).

## TL;DR
- **Physical layout:** **Command Centre is the LEFT button and Armoury Crate is the RIGHT button.** The brief had them swapped. The back grips are M1 and M2. Sources: [ASUS RC71L manual (PDF)](https://dlcdnets.asus.com/pub/ASUS/IOTHMD/RC71L/0421_ID25271_NR2301L_V5_A.pdf?model=ROG+Ally+%282023%29) (items 6 and 7, plus the "Gamepad shortcuts" table) and [hipc.jp](https://hipc.jp/15090). Windows behaviour: Command Centre tap opens Command Centre and hold sends Ctrl+Alt+Del. Armoury tap opens Armoury Crate SE and hold shows the controller overview. M1/M2 + d-pad/ABXY are shortcut combos (OSK, screenshot and others).
- **The ecosystem has consolidated on InputPlumber.** Bazzite announced in Jan 2026 that it is moving from HHD to InputPlumber, and Bazzite Deck 44 shipped it in Aug 2026. SteamOS, ChimeraOS, Nobara, CachyOS Handheld, Manjaro Handheld and Playtron already used it. [Bazzite announcement](https://universal-blue.discourse.group/t/a-brighter-future-for-bazzite/11575), [Bazzite handheld wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/), [GamingOnLinux on Bazzite 44](https://www.gamingonlinux.com/2026/08/bazzite-linux-44-for-handhelds-finally-launches-with-some-massive-upgrades/).
- **Recommendation for Omarchy: InputPlumber.** It is in Arch `extra` (0.84.0), uses YAML config, has a D-Bus API, is GPL-3.0-or-later, and Omarchy already ships an RC71L config. **One catch:** InputPlumber's Ally driver programs the back paddles only through the **out-of-tree `hid-asus-ally` kernel driver**, which mainline and the current Omarchy kernel do not have. Details and fixes in section 5.

## 1. Kernel exposure (mainline)

| Piece | What it does | Kernel / source |
|---|---|---|
| MCU (USB `0b05:1abe`, "N-KEY Device") | 3 HID interfaces: keyboard (if0), mouse (if1), vendor/consumer (if2). Extra buttons arrive as keyboard/vendor usages. | `hid-asus` binds it. Device ID added by [commit 08b50c6 "HID: asus: add ROG Ally N-Key ID and keycodes"](https://github.com/jhovold/linux/commit/08b50c6b0b0940a304b481346cc187d489c6a751) (Luke Jones, Apr 2024; first released in **6.10**). Ally X `0x1b4c` followed in [6.11, backported to 6.10.y](https://ratatoskr.run/linux-patches/2024/09/7029736). |
| Gamepad | MCU in XInput mode shows up as `Microsoft X-Box 360 pad` `045e:028e` via `xpad`. 11 buttons, **no paddle codes.** | Seen on the device (`ally-hw-dump.md`). InputPlumber's config uses the same source ([50-rog_ally.yaml](https://github.com/ShadowBlip/InputPlumber/blob/main/rootfs/usr/share/inputplumber/devices/50-rog_ally.yaml)). |
| Vendor usage → keycode map in [`hid-asus.c`](https://github.com/torvalds/linux/blob/master/drivers/hid/hid-asus.c) (mainline 7.4-rc2) | `0x38→KEY_PROG1` ("ROG key", i.e. **Armoury tap**). `0xa5→KEY_F15` ("left back"). `0xa6→KEY_F16` ("QAM button", i.e. **Command Centre tap**). `0xa7→KEY_F17` (**Armoury long-press**). `0xa8→KEY_F18` (Armoury long-press release). | Kernel comments name them from the driver's view. The physical mapping is inferred from HHD's [`rog_ally/base.py`](https://github.com/hhd-dev/hhd/blob/master/src/hhd/device/rog_ally/base.py) (`0xA6` "left" → Guide; `0x38` "right" → QAM; `0xA7`/`0xA4` right hold) and InputPlumber's [`ally_type1.yaml`](https://github.com/ShadowBlip/InputPlumber/blob/main/rootfs/usr/share/inputplumber/capability_maps/ally_type1.yaml). |
| Command Centre long-press | The MCU sends **Ctrl+Alt+Del** on the keyboard interface. InputPlumber matches `KeyLeftCtrl+KeyLeftAlt+KeyDelete`. | [ally_type1.yaml](https://github.com/ShadowBlip/InputPlumber/blob/main/rootfs/usr/share/inputplumber/capability_maps/ally_type1.yaml), [ASUS manual](https://dlcdnets.asus.com/pub/ASUS/IOTHMD/RC71L/0421_ID25271_NR2301L_V5_A.pdf?model=ROG+Ally+%282023%29). |
| M1/M2 back paddles | Their output is **programmed into the MCU**. HHD writes them to F17/F18 (`REMAP_M1M2_F17F18`) and InputPlumber (via `hid-asus-ally` sysfs) writes them to F15/F14. Factory/default codes: **unverified**. The device logged `Unmapped Asus vendor usagepage code 0xa2`, which may be a paddle; it needs a press test. | HHD [`const.py`](https://github.com/hhd-dev/hhd/blob/master/src/hhd/device/rog_ally/const.py) (`REMAP_M1M2_DEFAULT` = `KB_M1/KB_M2`, `REMAP_M1M2_F17F18`). InputPlumber [`drivers/rog_ally/driver.rs`](https://github.com/ShadowBlip/InputPlumber/blob/main/src/drivers/rog_ally/driver.rs). |
| `hid-asus-ally` (out of tree) | Luke Jones's driver (GPL-2.0-or-later). Exposes sysfs `btn_*/remap`, `gamepad_mode`, `apply_all`, deadzones, vibration intensity, and the RGB LED `ally:rgb:joystick_rings`. **Not in mainline** (`drivers/hid/hid-asus-ally.c` returns 404 on torvalds/master). | Carried in [CachyOS `0001-handheld.patch`](https://raw.githubusercontent.com/cachyos/kernel-patches/master/6.19/misc/0001-handheld.patch) for kernels 6.x to 7.3 ([kernel-patches](https://github.com/CachyOS/kernel-patches)), used by `linux-cachyos-deckify` ([PKGBUILD](https://github.com/CachyOS/linux-cachyos/blob/master/linux-cachyos-deckify/PKGBUILD), 7.3.4), and the OGC kernel ([OGC commit](https://github.com/OpenGamingCollective/linux/commit/9058f72b2ca37262d55f89818a7dda177abe4d07)). |
| MCU firmware check | Mainline `hid-asus` reads the MCU version. Below **319** (Ally) or 313 (Ally X) it warns *"The MCU firmware version must be 319 or greater to avoid issues with suspend"* and keeps the asus-wmi CSEE suspend hack. At or above that version it disables the hack and turns on `mcu_powersave`. The warning only prints after a successful version parse, so **Daniel's unit very likely has MCU firmware below 319** (inference from the code). | [hid-asus.c](https://github.com/torvalds/linux/blob/master/drivers/hid/hid-asus.c) `validate_mcu_fw_version()`. [Refactor patch v4 (Mar 2025)](https://lists.openwall.net/linux-kernel/2025/03/23/21). [Firmware 319 announcement (Oct 2024)](https://lists.openwall.net/linux-kernel/2024/10/05/311). |

## 2. How each stack maps the buttons

### Bazzite (Deck 44+): InputPlumber, OpenGamepadUI, steamos-manager, PowerStation
- **Armoury Crate tap opens the Steam QAM. Armoury Crate long-press opens the OpenGamepadUI (OGUI) overlay.** Guide+B is the fallback for OGUI and Ctrl+2 opens the QAM from a keyboard. [Bazzite handheld wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/).
- Known issue: *"The Ally does not support button holding for the Steam or QAM buttons… Steam Input's chords may not work by default"*. The workaround is swapping Start/Select. [Bazzite ASUS page](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/ASUS_ROG_Ally/). A user also notes that *"the left ROG button doesn't support long press"* under InputPlumber, and the Bazzite lead confirmed an HHD-style "swap" is feasible ([thread](https://universal-blue.discourse.group/t/a-brighter-future-for-bazzite/11575)).
- Paddles: use a DualSense Edge or Steam Deck target. Paddles are off by default because some games mis-map them. Use the `deck-uhid` target if gyro is flaky. [Bazzite wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/).

### Bazzite (before 44) / HHD (legacy, still maintained by its author for Anatase)
- **Armoury (right) single tap opens the Steam QAM. Double tap opens the HHD overlay. Hold (0.4 s) toggles MCU mouse mode** on RC71L (`0xA7`, with a 1-buzz/2-buzz rumble cue). Sources: HHD [README](https://github.com/hhd-dev/hhd) ("double tapping the side menu button"), [`controller/base.py`](https://github.com/hhd-dev/hhd/blob/master/src/hhd/controller/base.py) (`QAM_HOLD_TIME=0.4`, `QAM_MULTI_PRESS_DELAY=0.2`), [`rog_ally/base.py`](https://github.com/hhd-dev/hhd/blob/master/src/hhd/device/rog_ally/base.py), [Bazzite ASUS page](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/ASUS_ROG_Ally/) ("Holding the Armoury Crate button… Mouse Mode").
- **Command Centre (left) maps to Guide (Steam menu).**
- QAM delivery: HHD uses the emulated controller's native QAM ("share") button when available. Otherwise it falls back to a **Guide+A chord** (Guide+B with `nintendo_qam`). [base.py L1569-1628](https://github.com/hhd-dev/hhd/blob/master/src/hhd/controller/base.py).
- Options ([`controllers.yml`](https://github.com/hhd-dev/hhd/blob/master/src/hhd/device/rog_ally/controllers.yml)): `swap_armory` (swaps ROG buttons with Start/Select), `nintendo_mode`, `select_reboots`, `imu`/`imu_hz`, RGB at boot/charging. Emulation targets ([`outputs.yml`](https://github.com/hhd-dev/hhd/blob/master/src/hhd/plugins/outputs.yml)): DualSense (Edge), Xbox / Xbox Elite, Steam controller (`hori_steam`), or hidden.
- Config: `HHD_CONFIG_DIR` (default `/etc/hhd`) holds `state.yml` and `profiles/`. Older `~/.config/hhd/state.yml` is migrated ([`__main__.py`](https://github.com/hhd-dev/hhd/blob/master/src/hhd/__main__.py)). An HTTP API (bearer token in `~/.config/hhd/token`) is documented in [`docs/http.md`](https://github.com/hhd-dev/hhd/blob/master/docs/http.md). There is **no D-Bus control API** (HHD does ship a PPD D-Bus shim: `usr/share/dbus-1/system.d/hhd-net.hadess.PowerProfiles.conf`).
- HHD reads the MCU's vendor hidraw (usage page `0xFF31`) directly and programs paddles over HID. **It does not need `hid-asus-ally`.**

### CachyOS Handheld: InputPlumber
- README: *"ROG Ally… InputPlumber is used for controller support"*, and steam-powerbuttond handles the power button. [CachyOS-Handheld README](https://github.com/CachyOS/CachyOS-Handheld). The `chwd` generic handheld profile installs `steamos-manager inputplumber steamos-powerbuttond`, and the `rog-ally` sub-profile (board `RC71L|RC72LA|RC73XA|RC73YA`) adds audio configs ([profiles.toml](https://github.com/CachyOS/chwd/blob/master/profiles/pci/handhelds/profiles.toml)). Whether the sub-profile inherits the parent package list is **unverified** (it appears to).
- Mapping = InputPlumber defaults (below). An HHD drop-in remains (`hhd@.service.d/override.conf`, commented out) for Legion devices.

### InputPlumber default Ally map (used by SteamOS, CachyOS, ChimeraOS, Bazzite 44, Nobara)
From [`ally_type1.yaml`](https://github.com/ShadowBlip/InputPlumber/blob/main/rootfs/usr/share/inputplumber/capability_maps/ally_type1.yaml) (id `aly1`) and [`50-rog_ally.yaml`](https://github.com/ShadowBlip/InputPlumber/blob/main/rootfs/usr/share/inputplumber/devices/50-rog_ally.yaml):

| Physical | Source event | IP capability | What Steam sees |
|---|---|---|---|
| Command Centre (L) tap | F16 | `Guide` | Steam menu |
| Command Centre (L) hold | Ctrl+Alt+Del (or F20 with `hid-asus-ally`) | `Keyboard` | OSK (target-dependent) |
| Armoury (R) tap | PROG1 (or F19) | `QuickAccess` | QAM: a native "…" button on the Steam Deck targets, a **Guide+South chord** on Xbox/DualSense targets ([xpad.rs](https://github.com/ShadowBlip/InputPlumber/blob/main/src/input/target/xpad.rs), [dualsense.rs](https://github.com/ShadowBlip/InputPlumber/blob/main/src/input/target/dualsense.rs), [steam_deck.rs](https://github.com/ShadowBlip/InputPlumber/blob/main/src/input/target/steam_deck.rs)) |
| Armoury (R) hold | F17 | `QuickAccess2` | OGUI overlay (Bazzite/ChimeraOS) |
| M1 / M2 | F15 / F14 (after MCU remap) | `RightPaddle1` / `LeftPaddle1` (note: M1 is programmed to F15, and the map labels F15 "Right Paddle". Which physical side that is remains **unverified**) | Paddles on Elite/DS Edge/Deck targets |

Default targets are `xbox-elite`, `mouse` and `keyboard`. IMU: `bmi323-imu` (iio). LED: `ally:rgb:joystick_rings` (needs `hid-asus-ally`). Auto-start is enabled by DMI `rnRC71L` in [60-inputplumber-autostart.hwdb](https://github.com/ShadowBlip/InputPlumber/blob/main/rootfs/usr/lib/udev/hwdb.d/60-inputplumber-autostart.hwdb).

**Remapping config (InputPlumber):**
- Device configs are read from `/etc/inputplumber/devices.d` and then `/usr/share/inputplumber/devices`. Capability maps come from `/etc/inputplumber/capability_maps.d` and then `/usr/share/...` ([`config/path.rs`](https://github.com/ShadowBlip/InputPlumber/blob/main/src/config/path.rs)). Profiles live in `/usr/share/inputplumber/profiles/*.yaml`.
- `DeviceProfile` YAML ([schema](https://raw.githubusercontent.com/ShadowBlip/InputPlumber/main/rootfs/usr/share/inputplumber/schema/device_profile_v1.json)) is loaded at runtime with D-Bus `org.shadowblip.Input.CompositeDevice.LoadProfilePath`. Capability maps v2 support `chord` and `delayed_chord` ([usage docs](https://github.com/ShadowBlip/InputPlumber/blob/main/docs/usage.md)).
- `InterceptMode` (0 none, 1 pass-until-Guide, 2 all, 3 gamepad-only) lets an overlay take input. A virtual keyboard can `SendKey` over D-Bus. The `inputplumber device 0 test|info|targets list` CLI is useful for the button press test.

### SteamOS (Valve)
- Ships InputPlumber for non-Deck handhelds, auto-started per device from about 3.7.15 ([SteamOS #2048](https://github.com/ValveSoftware/SteamOS/issues/2048); [PC Gamer/Bazzite quote](https://www.pcgamer.com/software/linux/a-whole-bunch-of-different-linux-gaming-distros-are-teaming-up-to-improve-the-open-source-gaming-ecosystem/)). 3.7.13 fixed *"grip buttons not registering on the Asus ROG Ally"* and *"controller input occasionally disappearing"* ([GamingOnLinux 3.7.13 notes](https://www.gamingonlinux.com/2025/06/steamos-3-7-13-update-gets-fixes-for-more-handhelds-fixes-wifi-regression-on-steam-deck-oled/)). The original Ally has "improved", not "official", support ([Ars Technica on 3.7](https://arstechnica.com/gadgets/2025/05/steamos-3-7-brings-valves-gaming-os-to-other-handhelds-and-generic-amd-pcs/)). Since 3.8, *"Reduced handheld controller input latency from 5-8ms to 100-500us"* ([GamingOnLinux 3.8](https://www.gamingonlinux.com/2026/06/steamos-3-8-is-out-with-initial-steam-machine-support-desktop-mode-upgrades-new-graphics-drivers/), [VideoCardz](https://videocardz.com/newz/valve-releases-steamos-3-8-stable-with-steam-machine-support)).
- Without InputPlumber or HHD, Steam sees only the X-Box 360 pad. Guide gives the Steam menu, and the QAM needs the Guide+A chord (ChimeraOS docs refer to `guide + A` for the QAM: [ChimeraOS General Configuration](https://github.com/ChimeraOS/chimeraos/wiki/General-Configuration)).

### ChimeraOS
- InputPlumber and OGUI, with PowerStation for TDP. Sessions: `steam`, `steam-plus` (Steam plus an OGUI overlay, **Guide+B opens the overlay**), `opengamepadui` and `desktop`, selected with `chimera-session`. [ChimeraOS General Configuration](https://github.com/ChimeraOS/chimeraos/wiki/General-Configuration). The Ally is listed as supported, including extra buttons ([Supported Hardware](https://github.com/ChimeraOS/chimeraos/wiki/Supported-Hardware)).

## 3. Hold vs tap summary (RC71L)

| Button | HHD | InputPlumber (default) | Omarchy dev (current) |
|---|---|---|---|
| Cmd Centre (L) tap | Guide | Guide | Power action |
| Cmd Centre (L) hold | not handled in HHD's Ally code (**unverified**) | `Keyboard` (OSK) | wvkbd / Steam OSK |
| Armoury (R) tap | Steam QAM | QAM | Omarchy menu |
| Armoury (R) double tap | HHD overlay | none | none |
| Armoury (R) hold | MCU mouse-mode toggle (0.4 s) | `QuickAccess2` (OGUI) | Mode switch |
| M1/M2 | extra_l1/r1 → Steam paddles or keyboard ("noob mode") | Paddle1 L/R | Shift/Ctrl (desktop), paddle 2 (DS) |

Timing values exist only in HHD (0.4 s hold, 0.2 s double-tap window). On the original Ally, long-press on the Armoury button is generated by the MCU (`0xA7`/F17), so the hold threshold is set by firmware, not software (**unverified** exact ms). The Command Centre has no MCU long-press code other than Ctrl+Alt+Del.

## 4. HHD vs InputPlumber for Omarchy

| | **InputPlumber** | **HHD** |
|---|---|---|
| Licence | GPL-3.0-or-later ([README](https://github.com/ShadowBlip/InputPlumber)) | LGPL-2.1-or-later, a few files dual MIT ([README](https://github.com/hhd-dev/hhd)) |
| Language | Rust | Python |
| Arch packaging | **Official `extra/inputplumber` 0.84.0** ([install docs](https://github.com/ShadowBlip/InputPlumber/blob/main/docs/install.md)). AUR `inputplumber-git` (stale, 2025-02). | AUR `hhd` 4.1.12 (maintainer antheas, 2026-07), `hhd-git` (2026-10), `hhd-ui`, `adjustor`. Upstream says *"Using COPR or AUR… is not recommended"* and points to a curl install script or Anatase ([README](https://github.com/hhd-dev/hhd)). |
| Latest release / activity | v0.84.0, 5 Nov 2026. Repo pushed 9 Nov 2026. | v4.1.12, 10 Jul 2026. master pushed 10 Nov 2026. |
| Who ships it | SteamOS, ChimeraOS, Nobara, Playtron, Manjaro Handheld, CachyOS Handheld, Bazzite 44 ([Bazzite](https://universal-blue.discourse.group/t/a-brighter-future-for-bazzite/11575)) | Anatase only. Bazzite: *"the only project… shipping HHD"*, and its *"maintainer is no longer a part of this project"* (same thread). |
| RC71L support | Yes (`50-rog_ally.yaml`). **Paddle remap, gamepad_mode and RGB need `hid-asus-ally`** ([driver.rs](https://github.com/ShadowBlip/InputPlumber/blob/main/src/drivers/rog_ally/driver.rs) aborts if the driver isn't `asus_rog_ally`/`asus_ally_hid`) | Yes, the most complete: paddles, RGB, mouse mode, gyro, all from userspace HID. Works on mainline. Upstream warns that free-floating mainline kernels *"will increasingly break devices"* (README). |
| Steam / gamescope | Emits Deck/DS5/Elite/Horipad targets. QAM via native button or Guide+South chord. Pairs with steamos-manager (Steam's native TDP/RGB UI). | Native QAM via DS/Steam targets. Own gamescope overlay. `HHD_QAM_GAMESCOPE` env. TDP via `adjustor` plus a PPD shim. |
| Hyprland / desktop | Mouse and keyboard targets, runtime profile switch over D-Bus (Omarchy's `bridge.py` already does this) | Desktop app `hhd-ui`, "noob mode" maps extra buttons to keyboard |
| API | **D-Bus** system service `org.shadowblip.InputPlumber`, polkit ([D-Bus docs](https://shadowblip.github.io/InputPlumber/dbus-interface/composite_device/)) | HTTP REST on localhost with a token ([docs/http.md](https://github.com/hhd-dev/hhd/blob/master/docs/http.md)) |
| Config format | YAML (JSON-schema'd): CompositeDevice, CapabilityMap, DeviceProfile | YAML state and profiles in `/etc/hhd` |
| Hold/tap logic | Chords and delayed chords in capability maps. No double-tap primitive found (**unverified**) | Built-in single, double and hold for QAM |

**Recommendation: InputPlumber.** It is in `extra` (no AUR dependency), on the shared OGC/SteamOS path, has a D-Bus API Omarchy already drives, and Omarchy already ships its own RC71L config and profiles. HHD is only worth it if Daniel refuses a patched kernel *and* needs paddles; even then the useful part (HHD's MCU init bytes, LGPL-2.1-or-later) can be ported rather than taking the daemon. Do not run HHD and InputPlumber together; both grab/hide the same evdev nodes ([IP `HIDE_DEVICES_FROM_ROOT`](https://github.com/ShadowBlip/InputPlumber/blob/main/docs/usage.md), HHD `hide=True` in base.py).

## 5. Prioritised recommendations
1. **Run the per-button press test first** (`inputplumber device 0 test`, or `evtest` on `event6`/`event7`). It confirms the L=Command Centre / R=Armoury codes on the device and what M1/M2 emit **without** `hid-asus-ally` (is `0xa2` a paddle?).
2. **Decide the paddle path.** InputPlumber can't remap M1/M2 on the Omarchy kernel. Options, best first:
   - (a) Offer the `linux-cachyos-deckify` kernel (BORE, includes `hid-asus-ally`; [PKGBUILD](https://github.com/CachyOS/linux-cachyos/blob/master/linux-cachyos-deckify/PKGBUILD)) or the OGC kernel (AUR `linux-ogc`, currently flagged out of date) as an opt-in handheld kernel.
   - (b) Package `hid-asus-ally` as DKMS (GPL-2.0-or-later, extracted from the CachyOS handheld patch). No AUR DKMS exists today.
   - (c) Ship a tiny oneshot that writes the M1/M2 → F15/F14 remap over hidraw if2 using HHD's documented byte layout (`const.py`, LGPL-2.1-or-later). This is mainline-safe but must re-run after resume.
3. **Fix the Omarchy config for mainline:** keep the `KeyProg1`/`F16`/`F17` and Ctrl+Alt+Del sources (present on mainline). `F19`/`F20` only exist with `hid-asus-ally`; harmless, but don't rely on them. Drop the LED source unless `hid-asus-ally` is present (Omarchy already does).
4. **Mirror the community default in gaming mode** so muscle memory transfers from Bazzite/SteamOS: Armoury tap = QAM, Armoury hold = Omarchy overlay, Command Centre tap = Steam menu, Command Centre hold = OSK. Keep Omarchy's own bindings for desktop mode only.
5. **Use a Steam Deck (`deck-uhid`) or DualSense Edge target in gaming mode** for a native QAM button and paddles. Use Xbox Elite only for compatibility ([Bazzite wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/)).
6. **Add a "swap ROG ↔ View/Menu" option** in the InputPlumber profile (HHD feature parity; Bazzite users ask for it). It helps Steam Input chords that need a hold.
7. **Update the MCU to ≥319** (Windows Armoury Crate / MyASUS) before chasing suspend or controller-loss bugs.
