# InputPlumber profiles: implementation brief

16 Nov 2026. For dev-blue. Docs only: the YAML below is the file to put in the companion package, not a file this MIT tree ships.

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

Profiles are not picked up from a directory. `LoadProfilePath` takes an absolute path (§3). Put ours in the companion at `/usr/share/omarchy-rog-ally-input/profiles/`, which is where `bridge.py` on that branch already looks (`PROFILE_DIR`). Do not drop them into `/usr/share/inputplumber/profiles/`.

Upstream udev hwdb [`60-inputplumber-autostart.hwdb`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/rootfs/usr/lib/udev/hwdb.d/60-inputplumber-autostart.hwdb) sets `USE_INPUTPLUMBER=1` for `dmi:*svnASUSTeKCOMPUTERINC.:*rnRC71L:*`. The unit is `WantedBy=multi-user.target`, so it can be up before SDDM. The companion drop-in `90-omarchy-rc71l.conf` adds `ConditionPathExists=/etc/omarchy/rog-ally-input-enabled` and `ExecCondition=/usr/bin/omarchy-hw-rog-ally`. Keep that guard.

`gaming.yaml` is not in this tree. [`bin/omarchy-gaming-input-profile`](../../../bin/omarchy-gaming-input-profile) looks for `$OMARCHY_PATH/default/rog-ally-input/profiles/gaming.yaml` and exits 0 when the file or the daemon is missing. Point that oneshot at the companion path when the file exists. Until then the exit 0 is the right behaviour.

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

Targets stay `mouse` and `keyboard` only (C2). Right stick `speed_pps: 900` is a schema number; the daemon reads it and otherwise uses 800 (`translate_axis_to_mouse_motion`). The pointer's 0.20 floor is hardcoded in that function, which matches spec §9. Trigger `deadzone: 0.25` is read (`translate_trigger_to_button`). Holding A or RT holds mouse Left, which is the drag.

CC tap is `dbus: omarchy_power` (the power panel now; the quick-access overlay is spec 04, and it does not need a new profile line). CC long is `KeyLeftMeta`, `KeyLeftCtrl`, `KeyY`, the Hyprland bind `SUPER + CTRL + Y` → `omarchy-toggle-desktop-keyboard` in [`default/hypr/bindings/utilities.lua`](../../../default/hypr/bindings/utilities.lua). Steam+X is not a desktop trigger (spec 09 D5). AC tap is `dbus: omarchy_menu`. A second tap closes the menu in Hyprland (spec Δ2), not by a second profile. AC long is `dbus: omarchy_mode`, and the bridge toggles desktop ⇄ `gamepad`.

```yaml
# InputPlumber DeviceProfile v1. Omarchy RC71L mapping.
# Schema: device_profile_v1.json at InputPlumber v0.84.0.
# No grip targets. The bridge owns KeyLeftMeta and KeyLeftCtrl after OQ-17.
version: 1
kind: "DeviceProfile"
name: "Omarchy Ally desktop"
target_devices:
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

`KeyBackspace` and `KeySpace` are in the keyboard enum. The bridge loads `osk` only from `desktop`, when wvkbd is shown. It remembers the profile that was current and loads that profile again when the helper hides, when it is stopped, and when the wvkbd process exits for any other reason (spec §6). Watch the process. Do not poll.

### What stays out

`gamepad.yaml` stays the Xbox Elite profile. `dualsense.yaml` stays the manual Edge profile for a desktop-session game (C5). `desktop-swap`, `gaming-swap`, `hand-left` and `hand-right` stay out of `MODES` until a menu row selects one (spec §11, acceptance 20). They are not the profile after boot, unlock, or gaming-session start.

The bridge on `95a0992ce5` has `MODES = ("desktop", "gamepad", "dualsense")`. `omarchy-hw-rog-ally-input gaming` prints `Ally input: unknown action; use --help` and exits non-zero. Add `gaming` and `osk` to `MODES`. `run_gaming` calls `gaming` when the package is installed, and on that unknown-action error calls `gamepad` and still starts Gamescope (spec §12.3). Any other error still aborts.

## 3. Switching: the bridge loads the profile

One daemon, the one Arch ships. System bus name `org.shadowblip.InputPlumber` ([`constants.rs`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/src/constants.rs)). Only root may own it ([dbus policy](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/rootfs/usr/share/dbus-1/system.d/org.shadowblip.InputPlumber.conf)). The default policy allows `send_destination` to that name. The unit has no `User=`, so the process is root.

Composite object paths are assigned at runtime (`/org/shadowblip/InputPlumber/CompositeDevice0` is the example in the manager comments, not a promise). A dock or a USB pad can take a lower index. Discover the path. Interface `org.shadowblip.Input.CompositeDevice` ([`composite_device.rs`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/src/dbus/interface/composite_device.rs)). Manager object: `/org/shadowblip/InputPlumber/Manager`, interface `org.shadowblip.InputManager`.

`busctl` talks to the system bus by default.

```bash
busctl tree org.shadowblip.InputPlumber
# Replace the path. Do not hardcode CompositeDevice0.
busctl get-property org.shadowblip.InputPlumber \
  /org/shadowblip/InputPlumber/CompositeDevice0 \
  org.shadowblip.Input.CompositeDevice Name
busctl call org.shadowblip.InputPlumber \
  /org/shadowblip/InputPlumber/CompositeDevice0 \
  org.shadowblip.Input.CompositeDevice \
  LoadProfilePath s \
  /usr/share/omarchy-rog-ally-input/profiles/gaming.yaml
busctl get-property org.shadowblip.InputPlumber \
  /org/shadowblip/InputPlumber/CompositeDevice0 \
  org.shadowblip.Input.CompositeDevice ProfilePath
busctl get-property org.shadowblip.InputPlumber \
  /org/shadowblip/InputPlumber/CompositeDevice0 \
  org.shadowblip.Input.CompositeDevice TargetDevices
```

`LoadProfilePath` is the switch. When the profile sets `target_devices`, the load path sends `SetTargetDevices` ([`mod.rs` around the profile apply](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/src/input/composite_device/mod.rs)). The D-Bus method's contract is to stop the current virtual devices and create new ones. There is no equality check on that send. C4 still stands: the first load, from Xbox Elite to `ds5-edge`, happens in `run_gaming` before Gamescope, and a later reload with the same target list must not reconnect the pad. Implement that in the bridge: if `ProfilePath` and `TargetDevices` already match the file, do not call `LoadProfilePath` again. A direct `SetTargetDevices` is the same reconnect. Signature `as`:

```bash
busctl call org.shadowblip.InputPlumber \
  /org/shadowblip/InputPlumber/CompositeDevice0 \
  org.shadowblip.Input.CompositeDevice \
  SetTargetDevices as 3 ds5-edge mouse keyboard
```

Do not call it from session scripts. The profile's `target_devices` is the list.

`InterceptMode` is a `u32` property. `0` none (pass everything), `1` pass except Guide, `2` always (send nothing to the targets), `3` gamepad only (gamepad events go out over D-Bus). Any other value is stored as none. Spec 04 sets `2` while the overlay is open and restores `0` on close, crash and session exit (C8). That is not part of a profile load.

```bash
busctl set-property org.shadowblip.InputPlumber \
  /org/shadowblip/InputPlumber/CompositeDevice0 \
  org.shadowblip.Input.CompositeDevice InterceptMode u 2
busctl set-property org.shadowblip.InputPlumber \
  /org/shadowblip/InputPlumber/CompositeDevice0 \
  org.shadowblip.Input.CompositeDevice InterceptMode u 0
```

Select the RC71L composite (name `ASUS ROG Ally`, or the object whose sources are the `0b05:1abe` nodes). The oneshot in this tree calls `LoadProfilePath` on every `CompositeDevice*` it finds. A dock or a USB pad on that list would take the Ally profile (acceptance 17). The bridge should load the Ally object only.

### Who calls it

| When | Who | Profile |
|---|---|---|
| `run_gaming`, before Gamescope | `omarchy-hw-rog-ally-input gaming`, and the oneshot [`omarchy-gaming-input-profile.service`](../../../default/systemd/user/omarchy-gaming-input-profile.service) which `omarchy-gaming-session.target` already `Wants=` | `gaming.yaml`. On companion 1.0.3-1, `gamepad.yaml`, and Gamescope still starts (§12.3). |
| Gaming session in progress | The bridge holds it | Lock, unlock, login1 and a bridge restart do not load `desktop` or `gamepad` over it (§12.2). `omarchy_mode` while gaming is ignored. |
| Hyprland active and unlocked | The bridge | `desktop.yaml`, or `osk.yaml` while wvkbd is shown. |
| Hyprland locked, inactive, or unknown | The bridge | `gamepad.yaml` (C7). |
| AC long on the desktop | The profile emits `omarchy_mode`; the bridge toggles | `desktop` ⇄ `gamepad`, with the notification. Not `gaming` (C5). |
| Leave gaming back to Hyprland | The bridge, after the §8.1 key-ups | `desktop` if unlocked, otherwise `gamepad`. |

[`bin/omarchy-session-start`](../../../bin/omarchy-session-start) `run_gaming` still calls `omarchy-hw-rog-ally-input gamepad` when the package is installed, and aborts on a non-zero status. Spec §12.3 replaces that with `gaming`, then `gamepad` only on the unknown-action error. Key-ups (§8.1) happen before every load, on the device that pressed the key. Grip Super and Ctrl, once OQ-17 is closed, are the bridge uinput keyboard. InputPlumber does not emit those two keys.

### Permissions

No `NOPASSWD` sudo. Polkit is the gate. [`org.shadowblip.InputPlumber.policy`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/rootfs/usr/share/polkit-1/actions/org.shadowblip.InputPlumber.policy) sets `allow_any` no, `allow_inactive` `auth_admin`, and `allow_active` `auth_admin` for `LoadProfilePath`, `LoadProfileFromYaml`, `SetTargetDevices`, `SetInterceptMode`, `Stop`, `SendEvent` and `SendButtonChord`. A session `busctl` today asks for an admin password or fails. The shipped [`rules` file](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/rootfs/usr/share/polkit-1/rules.d/org.shadowblip.InputPlumber.rules) returns `YES` for a subject in group `inputplumber` or `wheel`, for every `org.shadowblip.Input*` and `org.shadowblip.Output*` action, including `Stop` and `SendEvent`. The companion PKGBUILD does not install a rule. Whether the Arch package creates the `inputplumber` group was not checked.

Ship a narrow rule with the companion: `YES` for the active local session, and only for `LoadProfilePath` and `SetInterceptMode` on this Ally. Do not add the session user to `wheel`. Do not grant `Stop` or `SendEvent`. Installing the rule is the package's root action. The running session does not call sudo.

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

Do not collapse those. None of them allows pasting the upstream YAML into this MIT tree. The profiles in §2 are new text written against the schema. The capability names are the schema's vocabulary. They are not a copy of `mouse_keyboard_wasd.yaml` or of `ally_type1.yaml`. Ship them in the companion, next to the derived composite, which that package already marks `license=('MIT' 'GPL-3.0-or-later')` and installs `LICENSE.inputplumber` beside the MIT licence. Keep that split. A citation of the schema URL in a comment is the notice the new files need.

`hid-asus-ally` is GPL-2.0-or-later and stays out of this tree (OQ-17).

## 6. Test plan and open questions

On the device, after the press test. "TBC" waits on OQ-1, OQ-2 or OQ-17 and is not a failure of the other rows. The checks that belong to this brief are spec 01 acceptance 1–6, 8, 9, 12, 15 and 19, plus the ones below.

1. Run [`tools/ally-press-test.sh`](tools/ally-press-test.sh). Record the code for CC tap, CC long, AC tap, AC long, and each grip. Record which capability is the left grip. Leave OQ-1, OQ-2 and OQ-17 open in the spec until that log exists.
2. Load `gaming.yaml` on the Ally composite only. `TargetDevices` contains `ds5-edge`. A second load, or a load when the path and the target list already match, does not disconnect the pad (C4).
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
4. `LoadProfilePath` always sends `SetTargetDevices` when the profile lists targets, and that D-Bus method stops and recreates virtual devices. The bridge skips the call when path and targets already match, so C4 holds even if the daemon does not compare the list.
5. Chord events are spaced 80 ms. Guide then West, and Super then Ctrl then Y, both use that path. The device test checks that the Hyprland bind and the Steam OSK still fire.
6. Polkit for `LoadProfilePath` and `SetInterceptMode` is `auth_admin` for the active session. The shipped group rule is wider than this session needs (`Stop`, `SendEvent`). A narrow active-session rule ships with the companion. No `NOPASSWD` sudo.
7. The oneshot loads every `CompositeDevice*`. The bridge must select the Ally object.
8. The capability-map path comment in `path.rs` disagrees with the vector. `/etc` wins for the same id because the `HashMap` insert is later. Do not add an override on the strength of the comment.
9. Arch's `GPL-3.0-only` and upstream's `GPL-3.0-or-later` disagree. Report both. Do not copy upstream YAML into this tree.
