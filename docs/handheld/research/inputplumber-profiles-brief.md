# InputPlumber profiles: implementation brief

16 Nov 2026, revised after the dev-red review on PR #51. For dev-blue. Docs only. The profile YAML below is ours and lives next to the pointer profile #48 already ships. The upstream composite file stays out of this MIT tree.

The button map is [spec 01](../01-controller-button-map.md) (revision 4, decisions D1–D7, map §5, contexts §6, chords §7, gaming profile §12, sketch in Appendix A). This brief implements that spec. A capability the daemon does not have is a finding at the end. It does not change the decision.

Pin: InputPlumber annotated tag [`v0.84.0`](https://github.com/ShadowBlip/InputPlumber/releases/tag/v0.84.0) → commit [`117cb04e949f842397b96178bcc0d7fc7ba23acf`](https://github.com/ShadowBlip/InputPlumber/commit/117cb04e949f842397b96178bcc0d7fc7ba23acf), tagged 2026-11-05. That is the version in Arch extra (`inputplumber` 0.84.0-1, x86_64, built 2026-11-05, packager Peter Jung). The companion comment cites `6aca920` (2026-11-08, "chore: add AGENTS.md"), which is after the tag. `50-rog_ally.yaml` and `ally_type1.yaml` are byte-identical at the tag, at `6aca920`, and on `main` as fetched 16 Nov 2026. Cite the tag.

Checked against the schema [`device_profile_v1.json`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/rootfs/usr/share/inputplumber/schema/device_profile_v1.json) and the daemon sources at that tag. "Schema" means that JSON file. "Daemon" means the Rust at the tag. Nothing here was run on an RC71L.

## 1. Upstream composite device

Upstream file: [`rootfs/usr/share/inputplumber/devices/50-rog_ally.yaml`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/rootfs/usr/share/inputplumber/devices/50-rog_ally.yaml) at `v0.84.0`. Installed path: `/usr/share/inputplumber/devices/50-rog_ally.yaml`.

`version: 1`, `kind: CompositeDevice`, `name: ASUS ROG Ally`, `single_source: false`, `options.auto_manage: true`. DMI match: `board_name: RC71L`, `sys_vendor: ASUSTeK COMPUTER INC.`. `capability_map_id: aly1`. Default `target_devices`: `xbox-elite`, `mouse`, `keyboard`. A profile load replaces that list (§3).

Source devices, in order:

1. hidraw `vendor_id: 0x0b05`, `product_id: 0x1abe`, `interface_num: 2` (group `gamepad`).
2. evdev name `Microsoft X-Box 360 pad`, `vendor_id: 045e`, `product_id: 028e`.
3. evdev `vendor_id: 0b05`, `product_id: 1abe`, `unique: false`. Events exclude `*`, then include `KeyProg1`, `KeyF14`–`KeyF17`, `KeyF19`, `KeyF20`, `KeyLeftCtrl`, `KeyLeftAlt`, `KeyDelete`, the face buttons, both bumpers, Select, Start, Guide, both stick buttons, both stick axes, the d-pad, and both triggers. Volume keys are not in that include list (spec OQ-8, still open).
4. iio `bmi323-imu`, mount matrix `x [1,0,0]`, `y [0,0,1]`, `z [0,-1,0]`.
5. udev LED `sys_name: ally:rgb:joystick_rings`, subsystem `leds`.

Capability map [`ally_type1.yaml`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/rootfs/usr/share/inputplumber/capability_maps/ally_type1.yaml), id `aly1`. These names are the map's labels. They are not a press test of this unit (OQ-1, OQ-2, OQ-17, all TBC).

| Map name | Source keys | Capability |
|---|---|---|
| Control Center (Short) | `KeyF16` | `Guide` |
| Control Center (Long) | `KeyLeftCtrl` + `KeyLeftAlt` + `KeyDelete`, and a second mapping for `KeyF20` | `Keyboard` |
| Armory Crate (Short) | `KeyProg1`, and a second mapping for `KeyF19` | `QuickAccess` |
| Armory Crate (Long) | `KeyF17` | `QuickAccess2` |
| Left Paddle | `KeyF14` | `LeftPaddle1` |
| Right Paddle | `KeyF15` | `RightPaddle1` |

`KeyF19` and the paddle codes need `hid-asus-ally`. `KeyProg1`, `KeyF16`, `KeyF17` and the Ctrl+Alt+Delete chord are on the N-Key include list, so they can arrive on the stock kernel. Design for both CC-long codes (spec §4). Do not assume `LeftPaddle1` / `KeyF14` is the left grip. The kernel comment on `0xa5` → `KEY_F15` says "left back", and `aly1` labels `KeyF15` as the right paddle (spec §4).

The Ally driver refuses to start unless the parent driver is `asus_rog_ally` or `asus_ally_hid`. On interface `02` it writes `btn_m1/remap` = `KB_F15` and `btn_m2/remap` = `KB_F14` ([`driver.rs`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/src/drivers/rog_ally/driver.rs)). That driver is out of tree. Kernel `7.2.15-2-omarchy` does not have it ([`ally-hw-dump.md`](ally-hw-dump.md), [`buttons-and-input.md`](buttons-and-input.md)). Until OQ-17, the desktop profile maps neither grip.

### What this tree ships, and where

Do not copy `50-rog_ally.yaml` or `ally_type1.yaml` into the MIT tree. Use the packaged capability map. The composite override already lives on `feat/ally-input-20261111` at `95a0992ce5` (`default/rog-ally-input/50-rog_ally.yaml`), installed by `omarchy-rog-ally-input` 1.0.3-1 to `/etc/inputplumber/devices.d/50-rog_ally.yaml` (`backup=` in the PKGBUILD). That copy drops the LED source so the firmware keeps the rings, and keeps the other sources, the `aly1` id, and the default target list. It is not on this branch. The 12 Nov dump saw the files under `/usr/share/omarchy/default/rog-ally-input/` with the service not installed.

Search order for devices ([`path.rs`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/src/config/path.rs)): the source-tree `rootfs` path (absent on an install), then `/etc/inputplumber/devices.d`, then `/usr/share/inputplumber/devices`. The same filename sorts the earlier directory first, and the manager takes the first DMI match. So `/etc/inputplumber/devices.d/50-rog_ally.yaml` replaces the packaged file for RC71L. Keep that filename.

Capability maps load the other way round in the code. `get_base_path()` is the first existing XDG data directory for `inputplumber`, and `/usr/share/inputplumber` when none exist. On a stock install that is the package directory, and it is listed before `/etc/inputplumber/capability_maps.d`. The doc comment's example lists `/etc` first. Ignore the comment. The loader inserts by id into a `HashMap`, so a later file with the same id wins. An `/etc` file named `ally_type1.yaml` overrides the packaged map. Do not add one unless a press test forces a label change. A new label is still OQ-1, not a decision this brief makes.

Profiles are not picked up from a directory. `LoadProfilePath` opens whatever path the caller sends ([`DeviceProfile::from_yaml_file`](https://github.com/ShadowBlip/InputPlumber/blob/117cb04e949f842397b96178bcc0d7fc7ba23acf/src/config/mod.rs#L56-L68) at `117cb04`, a 512 KiB cap and no directory check). The session never passes that path. One directory holds every Omarchy profile, the directory #48 already uses: repo `default/inputplumber/profiles/`, installed as `/usr/share/omarchy/default/inputplumber/profiles/`. That directory is root-owned on an install. Do not add a second directory such as `/usr/share/omarchy/inputplumber/profiles/` beside it, and do not drop files into `/usr/share/inputplumber/profiles/`. The helper in §3 hardcodes the installed prefix. It does not read `$OMARCHY_PATH`, because a checkout is writable by the user who has it.

`default/inputplumber/profiles/omarchy-ally-pointer.yaml` is already that directory's greeter profile (name `Omarchy Ally pointer`). Left stick moves the pointer, South clicks, and `target_devices` keeps `xbox-elite` with the mouse and keyboard. Keep it. `desktop.yaml` is the Hyprland profile from §2 and does not replace it at the greeter.

Upstream udev hwdb [`60-inputplumber-autostart.hwdb`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/rootfs/usr/lib/udev/hwdb.d/60-inputplumber-autostart.hwdb) sets `USE_INPUTPLUMBER=1` for `dmi:*svnASUSTeKCOMPUTERINC.:*rnRC71L:*`. The unit is `WantedBy=multi-user.target`, so it can be up before SDDM. The companion drop-in `90-omarchy-rc71l.conf` adds `ConditionPathExists=/etc/omarchy/rog-ally-input-enabled` and `ExecCondition=/usr/bin/omarchy-hw-rog-ally`. Keep that guard. [`install/hardware/asus/inputplumber.sh`](../../../install/hardware/asus/inputplumber.sh) installs InputPlumber and enables the greeter unit when `omarchy-hw-rog-ally` succeeds. The profile switch service, its D-Bus policy and its polkit rule are installed only when `omarchy-gaming-session` is present.

`gaming.yaml` ships in this tree. [`bin/omarchy-gaming-input-profile`](../../../bin/omarchy-gaming-input-profile) asks the profile service for the name `gaming` and exits 0 when the machine is not an RC71L or the service is not running.

## 2. Profile schema, and the YAML to write

`DeviceProfile` requires `version`, `kind`, `name`, `mapping`. Each mapping requires `name`, `source_event`, `target_events` (an array). `target_devices` is optional. Its enum includes `ds5-edge`, `deck-uhid`, `xbox-elite`, `mouse` and `keyboard`. `dbus` is a free string. The schema examples are `ui_*` names. The daemon's `Action::from_str` accepts anything else as `Action::Custom` ([`src/input/event/dbus.rs`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/src/input/event/dbus.rs)), so `omarchy_menu`, `omarchy_power`, `omarchy_mode` and `omarchy_overlay` load. Two or more `target_events` are a chord: the first is written immediately, and each further event waits another 80 ms ([`composite_device/mod.rs`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/src/input/composite_device/mod.rs), `handle_event`).

A profile must never emit `KeyLeftCtrl` + `KeyLeftAlt` + `KeyDelete`. The capability map already consumes that chord as `Keyboard` when InputPlumber owns the keys. If the raw chord reaches Hyprland, spec D4 / C9 confirms before anything closes. That confirm is a Hyprland dispatcher, not a profile line.

Userspace does not time a hold of CC or AC (spec §4, D5). Double tap stays unbound (OQ-6). No system action is hold-only.

### `gaming.yaml`

This is the shipped `gamepad.yaml` from `feat/ally-input-20261111` at `95a0992ce5`, with the three changes in spec §12.1: the name, `xbox-elite` → `ds5-edge`, and `omarchy_mode` → `omarchy_overlay`. The Keyboard mapping is the shipped text. Guide, QuickAccess, face buttons, sticks, triggers and paddles stay unmapped, so they pass through (C3). Do not copy `dualsense.yaml`'s `LeftPaddle1` → `LeftPaddle2` remap unless the press test shows the Edge paddles missing (spec §12.1). `deck-uhid` is the one-line fallback if that press test rejects `ds5-edge` (D1). It is not a second profile. Xbox Elite stays `gamepad.yaml`, for Steam in the desktop session (C5).

```yaml
# InputPlumber DeviceProfile v1. Omarchy RC71L mapping.
# Schema: device_profile_v1.json at InputPlumber v0.84.0.
version: 1
kind: "DeviceProfile"
name: "Omarchy Ally gaming"
target_devices:
  - "ds5-edge"
  - "mouse"
  - "keyboard"
mapping:
  - name: "Quick access on Armoury long"
    source_event:
      gamepad:
        button: "QuickAccess2"
    target_events:
      - dbus: "omarchy_overlay"
  - name: "Steam keyboard"
    source_event:
      gamepad:
        button: "Keyboard"
    target_events:
      - gamepad:
          button: "Guide"
      - gamepad:
          button: "West"
```

Every capability name in that file is in the schema enum, and `omarchy_overlay` is a custom D-Bus string the daemon accepts. Spec §12.1 is the diff: profile name, `target_devices`, the `QuickAccess2` target, and that mapping's `name` string. Acceptance 19 lists the first three. A test written only to that sentence would reject the mapping rename §12.1 shows. Allow that one string as well, and fail on any other change. The Keyboard mapping stays byte-for-byte.

Finding, decision unchanged: `ds5-edge` is built as `DualSenseDevice` ([`target/mod.rs`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/src/input/target/mod.rs)). That device's `write_event` turns `QuickAccess` into Guide at 0 ms and South at 80 ms ([`dualsense.rs`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/src/input/target/dualsense.rs)). `deck-uhid` stores `QuickAccess` as its own button ([`steam_deck.rs`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/src/input/target/steam_deck.rs)). D1 already says: if a press test shows the Edge target still delivers QAM as Guide+South, switch the one target line to `deck-uhid`. The gaming profile still does not map `QuickAccess`.

The same 80 ms spacing applies to Guide then West. Spec §5.1 already says Steam may open the menu if it sees Guide first. Confirm on the press test (OQ-1). Do not reorder the mapping ahead of that.

### `desktop.yaml`

Shipped `desktop.yaml` on that same commit, with two edits from spec Appendix A and §5.2:

- Remove `LeftPaddle1` → `KeyLeftShift` and `RightPaddle1` → `KeyLeftCtrl`. No `KeyLeftMeta` target either. After OQ-17 the bridge's uinput keyboard holds Super and Ctrl (§8.1 of the spec). Until then it writes nothing for the grips.
- Add four left-stick mappings, one per direction, to `mouse.button` `WheelUp` / `WheelDown` / `WheelLeft` / `WheelRight`. That is the notched form (D7, OQ-7 closed). The stick deadzone field is omitted, so the schema default and the daemon both use 0.3 ([`value.rs`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/src/input/event/value.rs), `translate_axis_to_button`, `unwrap_or(0.3)`). The spec does not set a stick-scroll deadzone. Do not copy the trigger's 0.25 onto the stick.

The right stick stays the pointer, and the face buttons stay mouse clicks (C2). `target_devices` also lists `xbox-elite`. A mouse and keyboard list stops the gamepad node, and on the #48 deploy that is the state Steam reported as no controller. Right stick `speed_pps: 900` is a schema number; the daemon reads it and otherwise uses 800 (`translate_axis_to_mouse_motion`). The pointer's 0.20 floor is hardcoded in that function, which matches spec §9. Trigger `deadzone: 0.25` is read (`translate_trigger_to_button`). Holding A or RT holds mouse Left, which is the drag.

CC tap is `dbus: omarchy_power` (the power panel now; the quick-access overlay is spec 04, and it does not need a new profile line). CC long is `KeyLeftMeta`, `KeyLeftCtrl`, `KeyY`, the Hyprland bind `SUPER + CTRL + Y` → `omarchy-toggle-desktop-keyboard` in [`default/hypr/bindings/utilities.lua`](../../../default/hypr/bindings/utilities.lua). Steam+X is not a desktop trigger (spec 09 D5). AC tap is `dbus: omarchy_menu`. A second tap closes the menu in Hyprland (spec Δ2), not by a second profile. AC long is `dbus: omarchy_mode`, and the bridge toggles desktop ⇄ `gamepad`.

```yaml
# InputPlumber DeviceProfile v1. Omarchy RC71L mapping.
# Schema: device_profile_v1.json at InputPlumber v0.84.0.
# No grip targets. The bridge owns KeyLeftMeta and KeyLeftCtrl after OQ-17.
version: 1
kind: "DeviceProfile"
name: "Omarchy Ally desktop"
target_devices:
  - "xbox-elite"
  - "mouse"
  - "keyboard"
mapping:
  - name: "Mode switch on Armoury long"
    source_event:
      gamepad:
        button: "QuickAccess2"
    target_events:
      - dbus: "omarchy_mode"
  - name: "Command Centre short"
    source_event:
      gamepad:
        button: "Guide"
    target_events:
      - dbus: "omarchy_power"
  - name: "Command Centre long"
    source_event:
      gamepad:
        button: "Keyboard"
    target_events:
      - keyboard: "KeyLeftMeta"
      - keyboard: "KeyLeftCtrl"
      - keyboard: "KeyY"
  - name: "Armoury short"
    source_event:
      gamepad:
        button: "QuickAccess"
    target_events:
      - dbus: "omarchy_menu"
  - name: "Right stick pointer"
    source_event:
      gamepad:
        axis:
          name: "RightStick"
    target_events:
      - mouse:
          motion:
            speed_pps: 900
  - name: "Left stick scroll up"
    source_event:
      gamepad:
        axis:
          name: "LeftStick"
          direction: "up"
    target_events:
      - mouse:
          button: "WheelUp"
  - name: "Left stick scroll down"
    source_event:
      gamepad:
        axis:
          name: "LeftStick"
          direction: "down"
    target_events:
      - mouse:
          button: "WheelDown"
  - name: "Left stick scroll left"
    source_event:
      gamepad:
        axis:
          name: "LeftStick"
          direction: "left"
    target_events:
      - mouse:
          button: "WheelLeft"
  - name: "Left stick scroll right"
    source_event:
      gamepad:
        axis:
          name: "LeftStick"
          direction: "right"
    target_events:
      - mouse:
          button: "WheelRight"
  - name: "South"
    source_event:
      gamepad:
        button: "South"
    target_events:
      - mouse:
          button: "Left"
  - name: "East"
    source_event:
      gamepad:
        button: "East"
    target_events:
      - mouse:
          button: "Right"
  - name: "West"
    source_event:
      gamepad:
        button: "West"
    target_events:
      - mouse:
          button: "Middle"
  - name: "North"
    source_event:
      gamepad:
        button: "North"
    target_events:
      - keyboard: "KeyEnter"
  - name: "Start"
    source_event:
      gamepad:
        button: "Start"
    target_events:
      - keyboard: "KeyEsc"
  - name: "Select"
    source_event:
      gamepad:
        button: "Select"
    target_events:
      - keyboard: "KeyTab"
  - name: "RightStick"
    source_event:
      gamepad:
        button: "RightStick"
    target_events:
      - mouse:
          button: "Left"
  - name: "DPadUp"
    source_event:
      gamepad:
        button: "DPadUp"
    target_events:
      - keyboard: "KeyUp"
  - name: "DPadDown"
    source_event:
      gamepad:
        button: "DPadDown"
    target_events:
      - keyboard: "KeyDown"
  - name: "DPadLeft"
    source_event:
      gamepad:
        button: "DPadLeft"
    target_events:
      - keyboard: "KeyLeft"
  - name: "DPadRight"
    source_event:
      gamepad:
        button: "DPadRight"
    target_events:
      - keyboard: "KeyRight"
  - name: "RightTrigger"
    source_event:
      gamepad:
        trigger:
          name: "RightTrigger"
          deadzone: 0.25
    target_events:
      - mouse:
          button: "Left"
  - name: "LeftTrigger"
    source_event:
      gamepad:
        trigger:
          name: "LeftTrigger"
          deadzone: 0.25
    target_events:
      - mouse:
          button: "Right"
  - name: "RightBumper"
    source_event:
      gamepad:
        button: "RightBumper"
    target_events:
      - mouse:
          wheel:
            direction: "up"
  - name: "LeftBumper"
    source_event:
      gamepad:
        button: "LeftBumper"
    target_events:
      - mouse:
          wheel:
            direction: "down"
```

Schema check: every mapping except the two bumper lines is valid against `device_profile_v1.json`. `MouseEvent` has `motion` and `button` only (`additionalProperties: false`). There is no `wheel` property. The daemon does implement a button → `mouse.wheel` translation, and it emits `Float(1.0)` for `up`/`right` and `Float(-1.0)` for `down`/`left` (`translate_button_to_wheel`). An axis → `Mouse::Wheel` translation returns `NotImplemented`, which is why the stick uses `mouse.button` and the bumpers keep `mouse.wheel`. Spec §5.2 says keep LB/RB as wheel down/up. yaml-language-server will mark the bumper lines invalid. The daemon accepts them. Do not rewrite the bumpers as `WheelUp` / `WheelDown` buttons to silence the schema: that path holds a mouse button, and the wheel path emits a relative tick.

Finding on the stick: `translate_axis_to_button` returns `Bool(true)` for the whole time the axis is past the threshold. The comment above that match says edge detection is still a TODO. A device test has to show whether a held stick produces repeated wheel ticks or one held `WheelUp`. The mapping stays the notched form either way.

Menu context (Δ5) is a Hyprland layer bind, not a profile. B closes the menu only while that layer exists (spec §6). Do not add a menu profile for it.

### `osk.yaml`

A copy of `desktop.yaml` with the East and West mappings replaced. Do not leave the mouse-button lines beside them.

```yaml
  - name: "East"
    source_event:
      gamepad:
        button: "East"
    target_events:
      - keyboard: "KeyBackspace"
  - name: "West"
    source_event:
      gamepad:
        button: "West"
    target_events:
      - keyboard: "KeySpace"
```

`KeyBackspace` and `KeySpace` are in the keyboard enum. Set this file's `name` to `Omarchy Ally osk`. A copy that keeps `Omarchy Ally desktop` cannot be told apart by `ProfileName`, so the skip in §3 would treat the two files as one profile. The helper loads the name `osk` only from `desktop`, when wvkbd is shown. It remembers the profile that was current and loads that name again when wvkbd hides, when it is stopped, and when the wvkbd process exits for any other reason (spec §6). Watch the process. Do not poll.

### What stays out

`gamepad.yaml` stays the Xbox Elite profile. `dualsense.yaml` stays the manual Edge profile for a desktop-session game (C5). `desktop-swap`, `gaming-swap`, `hand-left` and `hand-right` stay out of `MODES` until a menu row selects one (spec §11, acceptance 20). They are not the profile after boot, unlock, or gaming-session start.

The bridge on `95a0992ce5` has `MODES = ("desktop", "gamepad", "dualsense")`. `omarchy-hw-rog-ally-input gaming` prints `Ally input: unknown action; use --help` and exits non-zero. Add `gaming` and `osk` to `MODES`. `run_gaming` calls `gaming` when the package is installed, and on that unknown-action error calls `gamepad` and still starts Gamescope (spec §12.3). Any other error still aborts.

## 3. Switching: one root helper loads a name

One daemon, the one Arch ships. System bus name `org.shadowblip.InputPlumber` ([`constants.rs`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/src/constants.rs)). Only root may own it ([dbus policy](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/rootfs/usr/share/dbus-1/system.d/org.shadowblip.InputPlumber.conf)). The default policy allows `send_destination` to that name. The unit has no `User=`, so the process is root. Pin for the load path below: tag `v0.84.0`, commit [`117cb04e949f842397b96178bcc0d7fc7ba23acf`](https://github.com/ShadowBlip/InputPlumber/commit/117cb04e949f842397b96178bcc0d7fc7ba23acf).

One Omarchy program talks to that daemon: `/usr/bin/omarchy-inputplumber-profile`, running as root. It accepts a profile name from a fixed allowlist and builds the path itself. The session never receives polkit for `LoadProfilePath`, `LoadProfileFromYaml`, `SetTargetDevices` or `SetInterceptMode`, and it never passes a path. #48's pointer loader and `omarchy-gaming-input-profile` both called `LoadProfilePath`. This tree removes the loader. The pointer unit is a root call of this helper. The gaming oneshot asks it for a name.

Allowlist, and the file each name opens. The prefix is hardcoded to `/usr/share/omarchy/default/inputplumber/profiles`. A name that is not in this table is an error. The file must be a regular file, owned by root, and not a symlink.

| Name | File | `name` in the YAML | When |
|---|---|---|---|
| `pointer` | `omarchy-ally-pointer.yaml` (the #48 file) | `Omarchy Ally pointer` | Before the greeter, and again when the greeter comes back after the 3-in-60 s stop |
| `desktop` | `desktop.yaml` | `Omarchy Ally desktop` | Hyprland active and unlocked |
| `osk` | `osk.yaml` | `Omarchy Ally osk` | wvkbd shown, and only as a change from `desktop` |
| `gamepad` | `gamepad.yaml` | `Omarchy Ally gamepad` | Hyprland locked, inactive, or unknown (C7). Also the desktop-session Steam toggle (C5) |
| `gaming` | `gaming.yaml` | `Omarchy Ally gaming` | `run_gaming`, before Gamescope |
| `dualsense` | `dualsense.yaml` | `Omarchy Ally dualsense` | A menu or CLI choice in the desktop session (C5). Not the boot profile |

`pointer`, `desktop` and `osk` set `target_devices` to `xbox-elite`, `mouse` and `keyboard`. The left stick is a pointer only in `pointer`; the right stick is a pointer only in `desktop` and `osk`. `gaming` sets `ds5-edge`, `mouse` and `keyboard`, and it does not map a stick to the pointer. A profile whose list is only `mouse` and `keyboard` stops the gamepad node. That is what the #48 pointer load left Steam looking at, so none of these files is mouse and keyboard alone. The greeter does not run `desktop.yaml`.

### Which composite

Do not use `CompositeDevice0`. The #48 loader hardcoded that path, and this tree no longer ships it. The old gaming oneshot walked every `CompositeDevice*`. A dock can take index 0, and a USB pad must keep its own profile (acceptance 17).

The helper lists `/org/shadowblip/InputPlumber/CompositeDevice[0-9]*` and reads `org.shadowblip.Input.CompositeDevice.Name`. The Ally composite's name is exactly `ASUS ROG Ally`, from `50-rog_ally.yaml`. `SourceDevicePaths` are devnodes (`/dev/hidraw0`, `/dev/input/event0`), not D-Bus paths. Each devnode is mapped to a source object by hidraw `DevPath` or evdev `DevicePath`. `IdVendor` and `IdProduct` on that object are `format!("{:04x}")`: lowercase, four digits, no `0x` ([`hidraw.rs`](https://github.com/ShadowBlip/InputPlumber/blob/117cb04e949f842397b96178bcc0d7fc7ba23acf/src/dbus/interface/source/hidraw.rs#L48-L75) and the evdev interface). A composite matches when the name is exact and at least one of its sources is vendor `0b05` product `1abe`. `1b4c` is the Ally X and is not a match. Zero matching composites, or more than one: do not load. The greeter oneshot keeps today's bound (40 tries, 0.25 s apart, then exit 0) so a missing daemon does not hold SDDM.

### What a load does to the virtual devices

`LoadProfilePath` replaces the mapping and stores the path ([`load_device_profile`](https://github.com/ShadowBlip/InputPlumber/blob/117cb04e949f842397b96178bcc0d7fc7ba23acf/src/input/composite_device/mod.rs#L1882-L1903)). If the profile has `target_devices`, that function then sends `SetTargetDevices` ([same file, L1931–L1953](https://github.com/ShadowBlip/InputPlumber/blob/117cb04e949f842397b96178bcc0d7fc7ba23acf/src/input/composite_device/mod.rs#L1931-L1956)) and always calls `schedule_clear_state` (L1956), which recenters sticks and releases buttons on every target that is still attached ([`targets.rs` L431–L443](https://github.com/ShadowBlip/InputPlumber/blob/117cb04e949f842397b96178bcc0d7fc7ba23acf/src/input/composite_device/targets.rs#L431-L443)).

The D-Bus comment on `set_target_devices` says the call stops every current virtual device and creates new ones ([`composite_device.rs` L191–L193](https://github.com/ShadowBlip/InputPlumber/blob/117cb04e949f842397b96178bcc0d7fc7ba23acf/src/dbus/interface/composite_device.rs#L191-L194)). The function that runs is [`set_devices`](https://github.com/ShadowBlip/InputPlumber/blob/117cb04e949f842397b96178bcc0d7fc7ba23acf/src/input/composite_device/targets.rs#L128-L183). It asks each running target for its type id and:

- leaves a type that is already running (`Target device {kind} already running, nothing to do.`, L163)
- stops a running type that the new list does not contain (L170–L207)
- creates a type that is not running (L213–L268)

`ds5-edge` and `xbox-elite` are different type ids, so the first gaming load stops the Xbox node and creates the Edge node. `mouse` and `keyboard`, present in both lists, stay up. A second load of the same list does not destroy those nodes. It still clears their state, because `schedule_clear_state` runs on every successful load. C4's "must not reconnect" is the helper skipping that second call, not a comparison the daemon makes.

The `TargetDevices` property is not that type list. It returns `get_target_device_paths()` ([`composite_device.rs` L552–L571](https://github.com/ShadowBlip/InputPlumber/blob/117cb04e949f842397b96178bcc0d7fc7ba23acf/src/dbus/interface/composite_device.rs#L552-L571)), object paths. Comparing those paths to `ds5-edge` never matches. The type string is `org.shadowblip.Input.Target.DeviceType` on each of those paths ([`target/mod.rs` L42–L45](https://github.com/ShadowBlip/InputPlumber/blob/117cb04e949f842397b96178bcc0d7fc7ba23acf/src/dbus/interface/target/mod.rs#L31-L45)), the id the target was created with. `ProfileName` is the loaded profile's `name` field ([`composite_device.rs` L85–L104](https://github.com/ShadowBlip/InputPlumber/blob/117cb04e949f842397b96178bcc0d7fc7ba23acf/src/dbus/interface/composite_device.rs#L85-L104)). It is empty only when the interface has no profile object. Construction loads the packaged `default.yaml` (`name: Default`) before the interface is published, so a composite that was just created reports `Default`, not an empty string. `ProfilePath` is the path string passed to `LoadProfilePath`. `LoadProfileFromYaml` stores no path, so `ProfilePath` stays empty and is not the skip key.

Skip the load only when all of these hold:

1. `ProfileName` equals the `name` field of the allowlisted file.
2. The Ally composite from the lookup above is still that object.
3. If the file sets `target_devices`, every one of those strings is a `DeviceType` on a path in `TargetDevices`. If the file sets none (`pointer`), `TargetDevices` is non-empty.

A composite that was recreated reports `ProfileName` `Default`. That is not one of our names, so the check fails and the helper loads again. Do not treat any non-empty `ProfileName` as already ours. Skipping on a remembered path after the targets are gone would leave the new composite with no profile. Do not call `SetTargetDevices` from Omarchy. The profile's own list is the delta `set_devices` applies. The helper opens the allowlisted file with `O_NOFOLLOW` / `openat` and passes the bytes to `LoadProfileFromYaml`. It does not check the path and then hand that path to `LoadProfilePath`. The name is an exact table key; the opened filename is the table's, never the raw argument joined onto the prefix. The prefix stays `0755` and root-owned.

`InterceptMode` is a `u32` property on the same interface. `0` none, `1` pass except Guide, `2` always, `3` gamepad only. Any other value is stored as none. Spec 04 uses `2` while the overlay is open and `0` on close, crash and session exit (C8). The helper accepts only `0` and `2`. The session does not set the property itself.

### Who calls the helper

The session-facing entry is a root system service on our bus name, method `Load` with a name string and method `SetIntercept` with `0` or `2`. The service checks the allowlist, then the binary does the InputPlumber call as root. Root is the caller InputPlumber's polkit sees. We do not add a YES rule for any `org.shadowblip.Input*` action. Confirm on the device that this root call is authorized without a prompt. If it is not, fix the helper's identity. Still no session grant.

| When | Call | Name |
|---|---|---|
| Boot, before SDDM | [`omarchy-ally-pointer.service`](../../../default/systemd/system/omarchy-ally-pointer.service) stays `Before=display-manager.service` and runs the binary as root | `pointer` |
| Crash-loop stop, greeter shown | [`omarchy-handheld-autologin`](../../../bin/omarchy-handheld-autologin) `fail` already restarts SDDM. After that restart, the same binary runs as root | `pointer`. `graphical.target` is already up, so the oneshot does not run again by itself |
| `run_gaming`, before Gamescope | The gaming oneshot, through the service | `gaming`. On companion 1.0.3-1, which has no `gaming` name, `gamepad`, and Gamescope still starts (§12.3) |
| Gaming session in progress | The service holds it | Lock, unlock, login1 and a bridge restart do not load `desktop`, `gamepad` or `pointer` over it (§12.2). `omarchy_mode` while gaming is ignored |
| Hyprland active and unlocked | The service | `desktop`, or `osk` while wvkbd is shown |
| Hyprland locked, inactive, or unknown | The service | `gamepad` (C7) |
| AC long on the desktop | The profile emits `omarchy_mode`; the service toggles | `desktop` ⇄ `gamepad`, with the notification. Not `gaming` (C5) |
| Leave gaming back to Hyprland | The service, after the §8.1 key-ups | `desktop` if unlocked, otherwise `gamepad` |

[`bin/omarchy-session-start`](../../../bin/omarchy-session-start) `run_gaming` still calls `omarchy-hw-rog-ally-input gamepad` when the package is installed, and aborts on a non-zero status. Spec §12.3 replaces that with `gaming`, then `gamepad` only on the unknown-action error. Key-ups (§8.1) happen before every load, on the device that pressed the key. Grip Super and Ctrl, once OQ-17 is closed, are the bridge uinput keyboard. InputPlumber does not emit those two keys.

### Migration off the #48 loader

1. Add `omarchy-inputplumber-profile` and the system service. The binary is the only caller of `LoadProfileFromYaml`, and it never calls `LoadProfilePath`. Ship a D-Bus system policy: root owns `org.omarchy.InputPlumberProfile`, and method calls are checked by our polkit actions.
2. Change `omarchy-ally-pointer.service` so `ExecStart` is `/usr/bin/omarchy-inputplumber-profile load pointer`. Keep `After=inputplumber.service`, `Before=display-manager.service`, and `WantedBy=graphical.target`. Remove `omarchy-ally-pointer-load`. A migration rewrites the unit on a machine that already enabled it, and leaves a disabled or masked unit disabled. Do not leave a second program calling the daemon.
3. Teach `omarchy-handheld-autologin fail`, after `restart_greeter`, to run the same root `load pointer`. A crash-loop stop onto the greeter must not keep `desktop` loaded.
4. Change `omarchy-gaming-input-profile` to ask the service for `gaming`. It no longer loops `CompositeDevice*`.
5. Add `desktop.yaml`, `gaming.yaml`, `osk.yaml` and, when the companion profiles move, `gamepad.yaml` and `dualsense.yaml` in `default/inputplumber/profiles/`. Leave `omarchy-ally-pointer.yaml` as the `pointer` file.
6. The Hyprland side calls `Load` with a name. It does not call `LoadProfilePath`. Companion 1.0.3-1's bridge still does, and that remains the fallback §12.3 describes until this helper is what `run_gaming` calls.

### Permissions

No `NOPASSWD` sudo, and no YES rule for InputPlumber. [`org.shadowblip.InputPlumber.policy`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/rootfs/usr/share/polkit-1/actions/org.shadowblip.InputPlumber.policy) sets `allow_any` no and `allow_active` `auth_admin` for `LoadProfilePath`, `LoadProfileFromYaml`, `SetTargetDevices`, `SetInterceptMode`, `Stop`, `SendEvent` and `SendButtonChord`. `from_yaml_file` will open any path the caller names, up to 512 KiB. A session grant on `LoadProfilePath` with no path allowlist would let any process in that session, including the SDDM greeter user `sddm`, point the root daemon at `/tmp/evil.yaml`. Do not ship that grant. The shipped [`rules` file](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/rootfs/usr/share/polkit-1/rules.d/org.shadowblip.InputPlumber.rules) returns YES for group `inputplumber` or `wheel` on every `org.shadowblip.Input*` and `Output*` action, including `Stop` and `SendEvent`. Do not add the session user to either group. Whether the Arch package creates the `inputplumber` group was not checked.

The polkit rule we do ship is on our own actions (`Load` and `SetIntercept`), not on InputPlumber's. YES only when `subject.active` and `subject.local` are both true and `subject.user` is the handheld user the installer wrote into `omarchy-handheld-user.conf`. An explicit NO when `subject.user` is `sddm`. The greeter load does not use this rule: the system unit runs the binary as root before `display-manager.service`, and the crash-loop path does the same. Polkit cannot see "this Ally composite". The helper's name lookup is that scope. `SetIntercept` is the same subject check and only accepts `0` and `2`. There is no helper command that accepts YAML from the caller. The helper reads the allowlisted file and calls `LoadProfileFromYaml`.

## 4. Button table

Raw codes are the `aly1` assumption. OQ-1, OQ-2 and OQ-17 are TBC until [`tools/ally-press-test.sh`](tools/ally-press-test.sh) is run on this unit. One firmware event, one action. The profile does not time the hold.

| Control | Capability | Game | Desktop |
|---|---|---|---|
| CC tap. `KeyF16` ⟨TBC, OQ-1⟩ | `Guide`, unmapped in `gaming.yaml` so it passes through | Steam menu | `omarchy_power` (power panel). Spec 04 overlay later, same event |
| CC long. Ctrl+Alt+Delete or `KeyF20` ⟨TBC, OQ-2⟩ | `Keyboard` | Guide then West, the Steam OSK macro | `KeyLeftMeta` + `KeyLeftCtrl` + `KeyY` → `omarchy-toggle-desktop-keyboard`. Never the raw chord |
| AC tap. `KeyProg1`, or `KeyF19` only with `hid-asus-ally` ⟨TBC⟩ | `QuickAccess`, unmapped in gaming | Steam QAM, via the target (see the `ds5-edge` finding) | `omarchy_menu`. Second tap closes it in Hyprland |
| AC long. `KeyF17` ⟨TBC⟩ | `QuickAccess2` | `omarchy_overlay`. QAM until spec 04. Not a screenshot, not a profile change | `omarchy_mode`: desktop ⇄ `gamepad` |
| AC double tap | Unbound | Reserved (OQ-6) | Reserved |
| Right stick | Axis, unmapped in gaming | Game axis | Pointer, 900 px/s |
| Left stick | Axis | Game axis | Notched `WheelUp` / `WheelDown` / `WheelLeft` / `WheelRight` |
| A / RT | South / RightTrigger | Pass through | Left click. Hold is drag. RT deadzone 0.25 |
| B / LT | East / LeftTrigger | Pass through | Right click. LT deadzone 0.25. OSK: B is Backspace |
| X | West | Pass through | Middle click. OSK: Space |
| Y | North | Pass through | Enter |
| LB / RB | Bumpers | Pass through | Scroll down / up (`mouse.wheel`, schema gap) |
| R3 | RightStick button | Pass through | Left click |
| L3 | LeftStick button | Pass through | Unmapped |
| D-pad | DPad* | Pass through | Arrows |
| View | Select | Pass through | Tab |
| Menu | Start | Pass through | Escape |
| M1 / M2 | Whichever capability the press test shows. Do not assume `LeftPaddle1` / `KeyF14` | Pass through. Paddle-2 remap only if the press test shows Edge paddles missing | Unmapped until OQ-17. Then the bridge uinput holds Super (M1) and Ctrl (M2). The profile still has no paddle target |

## 5. Licences

Three statements, left as they are:

- [`Cargo.toml`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/Cargo.toml) at the tag: `license = "GPL-3.0-or-later"`. README at the tag: "InputPlumber is licensed under THE GNU GPLv3+."
- GitHub's licence API, fetched 16 Nov 2026, reports SPDX `GPL-3.0` for [`LICENSE`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/LICENSE) (blob `53d1f3d01864c35841739c55aeba9700657627b7`, same at the tag and at `main`).
- The Arch extra package page for `inputplumber` 0.84.0-1 lists `GPL-3.0-only` ([package JSON](https://archlinux.org/packages/extra/x86_64/inputplumber/json/), `licenses: ["GPL-3.0-only"]`).

Do not collapse those. None of them allows pasting the upstream YAML into this MIT tree. The profiles in §2 are new text written against the schema. The capability names are the schema's vocabulary. They are not a copy of `mouse_keyboard_wasd.yaml` or of `ally_type1.yaml`. They go in `default/inputplumber/profiles/`, beside the #48 pointer profile, which is the same kind of file. The derived composite device stays in the companion package, which already marks `license=('MIT' 'GPL-3.0-or-later')` and installs `LICENSE.inputplumber` beside the MIT licence. Keep that split. A citation of the schema URL in a comment is the notice the new files need.

`hid-asus-ally` is GPL-2.0-or-later and stays out of this tree (OQ-17).

## 6. Test plan and open questions

On the device, after the press test. "TBC" waits on OQ-1, OQ-2 or OQ-17 and is not a failure of the other rows. The checks that belong to this brief are spec 01 acceptance 1–6, 8, 9, 12, 15 and 19, plus the ones below.

1. Run [`tools/ally-press-test.sh`](tools/ally-press-test.sh). Record the code for CC tap, CC long, AC tap, AC long, and each grip. Record which capability is the left grip. Leave OQ-1, OQ-2 and OQ-17 open in the spec until that log exists.
2. `omarchy-inputplumber-profile load gaming` selects the composite named `ASUS ROG Ally` with a `0b05:1abe` source, and no other composite. `ProfileName` is `Omarchy Ally gaming`. `TargetDevices` is a list of object paths; `DeviceType` on those paths includes `ds5-edge`, `mouse` and `keyboard`. A second `load gaming` is skipped. A root `LoadProfilePath` of the same file, issued by hand, leaves the `ds5-edge` node up (`already running, nothing to do`) and still clears target state. The helper skip is what keeps that clear from happening mid-session (C4).
3. With a game running: AC tap opens and closes QAM, CC tap opens the Steam menu, CC long opens the Steam OSK in a search field. If QAM arrives as Guide+South, switch the target line to `deck-uhid` and stop (D1). If Guide+West opens the Steam menu, record it under OQ-1.
4. AC long in game does not change `ProfilePath`, does not screenshot, and opens the overlay when spec 04 is installed, otherwise QAM.
5. Desktop, Steam closed: pointer at a full deflection, A and RT click and drag, B and LT right-click, X middle-clicks, LB/RB scroll a long page, left stick produces wheel ticks and no pointer motion, stick centred for 10 s does not drift.
6. CC long on the desktop shows and hides wvkbd. With it up, B is Backspace and X is Space. Killing wvkbd, and `omarchy-toggle-desktop-keyboard stop`, both restore the previous profile with no further button. B right-clicks again.
7. No profile load emits Ctrl+Alt+Delete. With the companion stopped, the raw chord asks before it closes anything (D4).
8. Paddles absent on this kernel: record against OQ-17. Do not fail the rest of the map. Do not install grip-Super.
9. An external pad keeps its own composite and does not take `gaming.yaml`.
10. Against a stub that prints `Ally input: unknown action; use --help`, `run_gaming` loads `gamepad` and Gamescope still starts.

Open, and left open:

| Id | State |
|---|---|
| OQ-1 | TBC. Press test. Raw codes, which grip is which capability, and whether Guide+West opens the OSK or the Steam menu. |
| OQ-2 | TBC. Press test. Which CC-long code this firmware sends. The profile handles both. |
| OQ-17 | TBC. Press test. Whether M1/M2 arrive on `7.2.15-2-omarchy` without `hid-asus-ally`. Desktop grips stay unmapped until it is confirmed. |
| OQ-6 | Open in the spec. Double tap stays unbound. |
| OQ-8 | Open. Volume keys are not in the composite include list. |

## Findings

Decisions stay as spec 01 wrote them.

1. At v0.84.0, `ds5-edge` turns `QuickAccess` into a Guide+South chord. D1's fallback condition is true in the source. The press test still decides what Steam shows. The target line stays `ds5-edge` until that test.
2. `mouse.wheel` is missing from the published schema and implemented for button sources. Axis → `mouse.wheel` is `NotImplemented`. The stick uses `mouse.button` `Wheel*`. The bumpers keep `mouse.wheel`.
3. Axis → button holds `Bool(true)` while past the threshold. Edge detection is a TODO in `value.rs`. The device test checks tick repeat.
4. The D-Bus comment says `SetTargetDevices` stops and recreates every virtual device. `set_devices` at `117cb04` keeps types that are already running, stops types the new list omits, and creates types that are missing. Every load also clears target state. The helper skips when `ProfileName` matches and each required `DeviceType` is live. `TargetDevices` is object paths, so it is not compared to the YAML type list.
5. Chord events are spaced 80 ms. Guide then West, and Super then Ctrl then Y, both use that path. The device test checks that the Hyprland bind and the Steam OSK still fire.
6. The session gets no polkit for `LoadProfilePath` or `SetInterceptMode`. Both go through the root helper, which allowlists the profile name and accepts intercept values `0` and `2` only. The session rule is on our actions, YES for the installed handheld user when the session is active and local, and NO for `sddm`. The greeter load is the root unit, not that rule. No `NOPASSWD` sudo, and no YES rule for `org.shadowblip.Input*`.
7. #48's pointer loader hardcoded `CompositeDevice0`, and the gaming oneshot loaded every `CompositeDevice*`. The helper replaces both: name `ASUS ROG Ally`, confirmed with vendor `0b05` product `1abe`.
8. The capability-map path comment in `path.rs` disagrees with the vector. `/etc` wins for the same id because the `HashMap` insert is later. Do not add an override on the strength of the comment.
9. Arch's `GPL-3.0-only` and upstream's `GPL-3.0-or-later` disagree. Report both. Do not copy upstream YAML into this tree.
