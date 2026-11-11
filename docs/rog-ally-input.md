# Original ROG Ally input integration

This optional integration covers I01–I13 and P14 for the original ASUS ROG Ally RC71L. It uses Arch Extra InputPlumber, not HHD or a distribution handheld metapackage. Source validation is separate from installed and physical acceptance. The feature worker does not install anything on the Ally; the sole rollout owner runs the steps below after source integration.

## Dependencies and ownership

Checked 11 November 2026: [Arch Extra supplies inputplumber 0.84.0-1](https://archlinux.org/packages/extra/x86_64/inputplumber/). The inspected [upstream source](https://github.com/ShadowBlip/InputPlumber/tree/6aca9202fb8dfd6f31241c3f98b72df4a775c1a1) declares version 0.84.0 and GPL-3.0-or-later. The copied `50-rog_ally.yaml` retains its upstream notice and licence; Omarchy changes only LED ownership. Keep the installed version in the acceptance record. Newer versions need the same capability and physical checks.

InputPlumber is the sole input owner. Steam Input consumes its virtual controller and supplies per-game layouts. HHD, xboxdrv, input-remapper and another controller manager must not grab the same physical devices. Setup refuses recognised active/enabled competing system or user services and manually running owners; it does not remove them. Record their state and resolve them explicitly before retrying. OpenGamepadUI can control InputPlumber profiles/interception, so it must also have an agreed ownership handoff before enabling this desktop bridge. No new raw-input group membership, permissive device rules, PAM changes or power policy is installed. Existing upstream InputPlumber polkit policy applies; wheel users are supported without a new rule.

The central `omarchy-hw-rog-ally` predicate gates setup and the service. Upstream device matching additionally requires ASUS vendor and RC71L board. Ally X, Xbox Ally and ordinary laptops/desktops remain outside this opt-in integration. Do not broaden these matches to compensate for missing inputs.

## Build and install

The companion manifest is [`pkg/rog-ally-input/PKGBUILD`](../pkg/rog-ally-input/PKGBUILD). It builds from the reviewed checkout, with no fetched source, install scriptlet, automatic service start or user configuration writes. Install it alongside the Omarchy build containing the new `bin/` commands and AUTH's read-only lock producer (`887626c5d798da6420334c4bbe96a43934d277cf`); `omarchy-dev-pkg-test` can build the normal Omarchy packages from the integrated checkout. `omarchy dev link` alone does not publish these fixed system files. Companion 1.0.1 replaces 1.0.0's incomplete lock/overlay lifecycle guards; do not deploy 1.0.0.

Before installation, save package versions, `systemctl is-active inputplumber.service`, `systemctl is-enabled inputplumber.service`, any existing `/etc/inputplumber` configuration and competing owner states outside Git. An existing unowned `50-rog_ally.yaml` causes a pacman file conflict: review and back it up instead of forcing an overwrite. On upgrade pacman preserves local device edits through its backup handling; review `.pacnew` files.

Run in a terminal as the desktop user, from the integrated checkout:

```bash
cd pkg/rog-ally-input
# Prevent upstream udev activation during the first dependency transaction.
# Record any existing persistent mask and preserve it.
sudo systemctl mask --runtime inputplumber.service
omarchy-pkg-add inputplumber
makepkg --cleanbuild
pacman -Qip omarchy-rog-ally-input-1.0.1-1-any.pkg.tar.zst
bsdtar -tf omarchy-rog-ally-input-1.0.1-1-any.pkg.tar.zst
sudo pacman -U ./omarchy-rog-ally-input-1.0.1-1-any.pkg.tar.zst
sudo systemctl daemon-reload
sudo systemctl unmask --runtime inputplumber.service
omarchy-setup-rog-ally-input --enable
omarchy-hw-rog-ally-input status
omarchy-hw-rog-ally-input capabilities
```

`makepkg` requires the declared dependencies already installed. The temporary runtime mask prevents upstream hwdb/udev rules starting InputPlumber during the first dependency transaction, before the companion guard exists. Resolve competing owners first and keep a physical keyboard/touch recovery route available during this serial rollout. Do not install it in parallel with a live controller owner. Remove only the runtime mask created by this procedure; preserve a pre-existing persistent mask. Once the companion is installed, its system drop-in requires `/etc/omarchy/rog-ally-input-enabled`, including for udev-triggered starts.

The package owns these files:

| File | Purpose |
| --- | --- |
| `/etc/inputplumber/devices.d/50-rog_ally.yaml` | Upstream RC71L aggregation without LED capture; pacman backup file |
| `/usr/lib/systemd/system/inputplumber.service.d/90-omarchy-rc71l.conf` | Central hardware predicate and explicit opt-in guard |
| `/usr/lib/systemd/user/omarchy-rog-ally-input.service` | Event bridge bound to the Hyprland graphical session |
| `/usr/lib/omarchy-rog-ally-input/bridge.py` | Package-owned service implementation |
| `/usr/share/omarchy-rog-ally-input/profiles/{desktop,gamepad,dualsense}.yaml` | InputPlumber DeviceProfile v1 mappings |
| `/usr/share/doc/omarchy-rog-ally-input/README.md` | This installation and recovery guide |

The normal Omarchy package owns `omarchy-hw-rog-ally-input` and `omarchy-setup-rog-ally-input`. The former uses `$OMARCHY_PATH` for its runtime source. Keep the companion and Omarchy builds on the same integrated commit. The setup command creates the opt-in marker and enables this user's bridge; repeat enablement is safe. It does not enable InputPlumber globally: upstream udev starts it on recognised RC71L hardware. Setup starts it immediately for this installation.

Setup also enables upstream `inputplumber-suspend.service` if it was disabled. This maintained lifecycle hook calls `HookSleep`/`HookWake` around sleep to release and restore input. It does not request suspend or change power policy; RELIABILITY retains that ownership. `/etc/omarchy/rog-ally-input-suspend-owned` records enablement performed here. Disable removes only that owned enablement, preserving a previously enabled hook. A masked or otherwise unexpected hook state stops setup for explicit resolution.

## Controls and session contract

Desktop mode has mouse and keyboard targets only, so Steam's desktop controller layout cannot add a second pointer path. Stick movement does not need Steam. Gamepad mode adds exactly one Xbox Elite virtual controller; ordinary controls pass through without desktop shortcuts. Optional `dualsense` selects one DS5 Edge target for motion support. Choose the target before launching a game because changing it disconnects the previous virtual controller.

| Control | Desktop profile | Gamepad/DS5 profile |
| --- | --- | --- |
| Right stick | Pointer, 900 logical input pixels/second before compositor scaling | Normal game axis |
| A or RT | Hold left click to drag | Normal game button/trigger |
| B or LT | Right click | Normal game button/trigger |
| X | Middle click | Normal game button |
| Y / Start / Select | Enter / Escape / Tab | Normal game buttons |
| RB / LB | Scroll up/down | Normal game bumpers |
| D-pad | Arrow keys | Normal game D-pad |
| Back buttons | Left Shift / Left Ctrl while held | Xbox Elite paddles, or DS5 Edge paddles via 1→2 remap |
| Command Centre short | `omarchy-shell shell toggle omarchy.power` | Guide/Steam button |
| Command Centre long | `KeyLeftMeta` + `KeyLeftCtrl` + `KeyY` | Guide+West (Steam+X keyboard) |
| Armoury Crate short | `omarchy-menu` | Upstream QuickAccess → scheduled Guide+South QAM |
| Armoury Crate long | Toggle desktop/gamepad, with mode notification | Same toggle in Hyprland; consumed in direct gaming session |

The desktop keyboard chord targets TOUCH's optional RC71L+wvkbd Super+Ctrl+Y binding. The direct helper remains `omarchy-toggle-desktop-keyboard toggle`; keyboard installation and binding belong to TOUCH. No Guide+West interception is added to desktop mode. [Valve documents Steam+X for the gaming keyboard](https://help.steampowered.com/en/faqs/view/69e3-14af-9764-4c28); West is Xbox X/DS5 Square. Steam QAM and its performance controls belong to the gaming session. Desktop layer-shell panels cannot cross into Gamescope.

Short/long distinctions come from upstream `ally_type1.yaml`, using firmware/kernel F16, F20/Ctrl+Alt+Delete, Prog1/F19 and F17 events. No userspace hold timer guesses the duration. Both firmware variants and the absence of an unwanted short action on a long press need physical checks. Do not bind those raw keys globally.

The bridge watches D-Bus ObjectManager/device events, logind session changes and AUTH's one-way `$XDG_RUNTIME_DIR/omarchy-lock-$HYPRLAND_INSTANCE_SIGNATURE.sock` stream. The stream supplies an initial JSON line `{"locked":true|false}` and actual lock-request/compositor-secure transitions. Missing, malformed or disconnected state blocks desktop input. A same-user peer check and socket EOF provide producer identity/liveness; no saved file can leave an old `false` behind after shell death. The canonical `omarchy-shell lock isLocked` and compositor lock helper are also checked at state/action boundaries, catching a pending lock event or compositor-held lock surviving a shell restart. Logind `LockedHint` alone is insufficient for Omarchy's lock. There are no idle queries or polling timer.

Only an active, unlocked Hyprland session launches desktop actions. Lock/inactive transitions release an owned desktop profile into gamepad mode, then restore the selected profile on return. Normal bridge shutdown also releases owned desktop input. Every automatic lifecycle write requires interception mode zero and both an exact shipped profile name and its package-owned path; a name match alone does not grant ownership. Discovery can also claim the exact upstream Default bootstrap profile when interception is zero. Restart, hotplug, lock, unlock and shutdown leave another overlay's interception/custom profile intact and never reset interception. When an overlay releases interception while locked, a D-Bus property event releases any now-owned desktop profile. Service/device reappearance triggers discovery without polling. Physical lock and controller acceptance remains separate from these source checks.

Profile validation uses the upstream DeviceProfile and CompositeDevice schemas. In 0.84.0 the generated DeviceProfile schema omits `mouse.wheel`, although upstream's own mouse profile uses it and the Rust `MouseCapability.wheel`/`translate_button_to_wheel` implementation supports it. Validate that field against the Rust direction values (`up`, `down`, `left`, `right`); do not substitute `button: WheelUp`, which does not emit a scroll event in this version.

SESSION calls `omarchy-hw-rog-ally-input gamepad` before direct DRM Gamescope launch when the companion is installed. A failure prevents entry and returns to desktop. Gaming does not start this desktop bridge or `graphical-session.target`; normal Hyprland startup restores desktop input. POWER owns power settings; this integration only opens the agreed panel/QAM.

## Capabilities and limits

`status` prints JSON with `Name`, `ProfileName`, `ProfilePath`, `TargetDevices` (D-Bus object paths) and numeric `InterceptMode`. `capabilities` prints actual `Capabilities`, `TargetCapabilities`, `OutputCapabilities` and `SourceDevicePaths`. Both fail if the RC71L composite is missing or ambiguous. Capture these results in the private acceptance log; source paths can contain device identifiers. Service activation or a recognised HID node alone does not prove working input.

All InputPlumber D-Bus calls use `NO_AUTO_START`. Status/capability reads do not activate a missing backend, including when it disappears after a readiness check. Setup explicitly starts the backend; other commands fail closed until it is running. A mode command refuses active overlay interception; only the explicit `intercept none` command clears it.

- **Gyro:** the upstream profile uses `bmi323-imu` and its RC71L mount matrix. Xbox Elite has no motion output; select `dualsense` and configure Steam Input gyro per game. Verify sensor presence, axes and orientation on the device.
- **Rumble:** upstream evdev force feedback supplies the RC71L motors, including translation from DS5 rumble. Test both targets. RC71L does not gain adaptive/haptic triggers.
- **Back buttons:** the upstream driver attempts M1/M2 remapping. A newer `asus_ally_hid` driver may use a different gamepad-mode spelling; inspect the actual kernel driver, attributes and readback before claiming success. No speculative kernel replacement or raw sysfs workaround is installed here.
- **Deadzones and curves:** trigger-to-click threshold is 0.25. Upstream mouse translation fixes the per-axis deadzone at 0.20 and honours `speed_pps`; changing a profile source deadzone does not tune mouse drift in 0.84.0. Axis-to-axis mappings support quadratic scaling/inversion; use Steam Input for per-game calibration/deadzones/curves. There is no claimed general calibration API. Advanced profiles can be loaded through `inputplumber device N profile load /absolute/path.yaml`; use `inputplumber devices list` to find N. The next desktop session selects the shipped desktop profile.
- **RGB:** the companion excludes the LED source to preserve firmware colour and brightness, including when a DS5 game requests a colour. Upstream `Source.LEDDevice` exposes no writable brightness/effects API in 0.84.0. An available `ally:rgb:joystick_rings` node is hardware evidence, not a supported effects editor. Firmware/other RGB tools must retain one explicit owner; this integration does not write lighting.
- **Overlay interception:** `omarchy-hw-rog-ally-input intercept all` sends input to the upstream D-Bus overlay target; `intercept none` restores game delivery. A real overlay consumer must subscribe first and restore none on close, crash and session exit. No OGUI overlay is silently started. Do not use `pass` without an overlay owner: Guide can otherwise leave input intercepted. Verifying no button leakage into a game is still an installed acceptance requirement.

## Rollback

Keep a keyboard/touch route available. First disable the bridge and remove the opt-in marker while its package still exists:

```bash
omarchy-setup-rog-ally-input --disable
omarchy-pkg-drop omarchy-rog-ally-input
sudo systemctl daemon-reload
systemctl --user daemon-reload
```

If setup cannot run, `systemctl --user disable --now omarchy-rog-ally-input.service`, `sudo rm -f /etc/omarchy/rog-ally-input-enabled` and `sudo systemctl stop inputplumber.service` perform its disable steps. If InputPlumber was newly installed for this increment, remove it with `omarchy-pkg-drop inputplumber` before restoring an old owner: its upstream udev autostart returns after the companion guard is removed. If InputPlumber existed before, restore its saved device configuration and prior enablement/start state instead. Restore any previous input owner only after InputPlumber has stopped. Retain `.pacsave` and the pre-install backup until controls are verified. No user mappings, Steam layouts, RGB, power or login settings are deleted.

If `/etc/omarchy/rog-ally-input-suspend-owned` exists, the manual fallback also runs `sudo systemctl disable inputplumber-suspend.service` and removes that ownership marker. Leave an already enabled hook without this marker as recorded before installation.

## Acceptance owned by live rollout

Write full command output to logs outside Git. Record integrated SHA, installed package versions, changed files/backups, active kernel input driver and actual result for each check. Nothing below is established by the source tests.

1. Confirm RC71L using the central predicate; capture `status`, `capabilities`, service journal and device targets. Confirm exactly one virtual gamepad in gamepad mode, none in desktop mode, and no competing owner. Check an external controller remains separate.
2. Close Steam completely. In desktop mode move the pointer slowly/quickly; release to centre and check drift. Left/right/middle click, drag a real window, select text with back-button modifiers and scroll a real long page. Confirm clicks release when switching mode while a trigger is held.
3. Exercise each Command Centre and Armoury short/long press repeatedly. Check keyboard show/hide and actual text entry, menu/power route, mode notification, no accidental short action, no stuck modifier and no action while locked/inactive. Repeat with Steam open.
4. Enter direct gaming through SESSION. Verify Guide, QAM (Guide+South), keyboard (Guide+West), game controls, paddles and rumble in an actual game. Select DS5 before another launch and check gyro axes, motion aiming, back-button identity and rumble. Verify switching target does not leave duplicate controllers.
5. With an agreed overlay consumer, enable interception, navigate it and confirm the game receives no inputs; close/crash the overlay and restore none. Do not call the overlay complete until this is exercised.
6. Lock/unlock, switch to/from direct gaming, restart InputPlumber and suspend/resume through the reliability owner's route. Capture `journalctl -b -u inputplumber.service -u inputplumber-suspend.service`; check successful HookSleep/HookWake, restored mode, pointer, no stuck buttons, no duplicate gamepad, firmware lighting unchanged and external controller ordering. Verify a non-RC71L setup attempt changes nothing.
7. Disable the integration, verify firmware controller recovery, then re-enable once to check idempotence. Keep rollback evidence and all unresolved firmware/driver or physical limits in the release receipt.
