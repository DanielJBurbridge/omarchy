# ROG Ally RC71L: hardware and input dump (read-only)

Captured 12 Nov 2026 13:27 AWST over `ssh <ally>` from `<workstation>`. Nothing installed or changed. Raw captures (`ally-hw-dump-raw.txt`, `ally-hw-dump-raw-2.txt`, `ally-omarchy-files.txt`) are kept off-repo and are available on request. They hold device identifiers and are not in this repository.

## System
- ASUSTeK ROG Ally RC71L_RC71L, board RC71L, BIOS RC71L.339 (2024-07-02), Ryzen Z1 Extreme.
- Kernel 7.2.15-2-omarchy (BORE), Omarchy 4.0.0.r7695.g7a9a1e9. Sleep: `s2idle` only.
- Running: `asusd` (asusctl 6.5.0), `power-profiles-daemon` (omarchy-power-profiles-daemon 0.30). Platform profile: quiet / balanced / performance.
- Not installed: InputPlumber, HHD, steamos-manager, evtest. User `<user>` is not in `input` group, so no live event capture was possible.

## Kernel modules loaded
`hid_asus`, `asus_wmi`, `asus_nb_wmi`, `asus_armoury` (firmware-attributes: `ppt_pl1_spl`, `ppt_pl2_sppt`, `ppt_pl3_fppt`, `apu_mem`, `mcu_powersave`, `charge_mode`, ...), `xpad`, `hid_multitouch`, `i2c_hid_acpi`, `sparse_keymap`. No separate Ally gamepad driver; the gamepad comes through `xpad`.

## Input devices
| evdev | Name | IDs | Driver / path | Role |
|---|---|---|---|---|
| event7, js0 | Microsoft X-Box 360 pad | 045e:028e | xpad, usb 1-2 if0 | Built-in gamepad (MCU in XInput mode). 11 buttons: A/B/X/Y, LB/RB, Select, Start, Guide (BTN_MODE), L3/R3; sticks, triggers, d-pad as ABS. **No paddle codes exposed.** |
| event4 | N-KEY Device (kbd) | 0b05:1abe | hid-asus, usb 1-3 if0, hidraw0 | Keyboard interface (incl. F13–F24) |
| event5 | N-KEY Device (mouse) | 0b05:1abe | hid-asus, if1, hidraw1 | Mouse (L/R/M, REL) |
| event6 | N-KEY Device | 0b05:1abe | hid-asus, if2, hidraw2 (+hiddev96) | Vendor/consumer keys: KEY_PROG1–4, F13–F18, F21, volume, etc. **Armoury Crate / Command Centre / paddle events arrive on this interface** (InputPlumber reads hidraw if2 + these keys). |
| event13 | Asus WMI hotkeys | platform asus-nb-wmi | asus_nb_wmi | WMI hotkeys |
| event11 | NVTK0603:00 touchscreen | 0603:f200 | hid-multitouch, i2c | Touchscreen 160x90 mm |
| event0/1 | Power / Sleep Button | ACPI | | Power key (Omarchy tags it `STEAMOS_POWER_BUTTON`) |

## Kernel log notes
- `asus 0003:0B05:1ABE.0003: The MCU firmware version must be 319 or greater to avoid issues with suspend.` printed every boot. In mainline `hid-asus.c` (`validate_mcu_fw_version`, `ROG_ALLY_MIN_MCU 319`) this warning only prints when the version read is **below 319**, and the ≥319 path sets `mcu_powersave` on. Here `mcu_powersave`=0, which is consistent. So this unit's MCU firmware is <319 (exact number not logged; it updates via Armoury Crate on Windows / MyASUS). Assumes the Omarchy kernel carries mainline logic.
- `asus_wmi: fan_curve_get_factory_default (0x00110032) failed: -19`: no fan-curve control via asus-wmi on this unit.
- `xpad 1-2:1.0: timed out waiting for output URB to complete` (12:18): controller hiccup, possibly rumble or LED write.
- `Unmapped Asus vendor usagepage code 0xa2` (13:11, twice): vendor usage 0xa2 isn't in mainline hid-asus's keymap (it maps 0x38→PROG1 ROG key, 0xa5→F15 left back, 0xa6→F16 QAM, 0xa7/0xa8→F17/F18 ROG long press/release). It also isn't handled in HHD `rog_ally/base.py` (0xA6, 0x38/0x93/0xA0, 0xA7/0xA4, 0xA8) or InputPlumber `ally_type1.yaml`. Source is still unknown; the press test captures raw hidraw to pin it down.
- Mapping conflict to check: kernel comment says 0xa5/F15 = left back, while InputPlumber aly1 maps F14 = left paddle and F15 = right paddle.
- `asus_wmi` warns that `/sys/bus/platform/asus_wmi` attributes are deprecated; use `/sys/class/firmware-attributes`.

## Already in Omarchy dev on the device (not enabled)
- `omarchy-hw-rog-ally`: detection by DMI (`ASUSTeK COMPUTER INC.` + product `ROG Ally RC71L*` or board `RC71L`). It deliberately excludes the Ally X and Xbox Ally.
- `/usr/share/omarchy/default/rog-ally-input/50-rog_ally.yaml`: InputPlumber composite-device config, derived from InputPlumber 0.84.0 (GPL-3.0-or-later; upstream README says "GNU GPLv3+"). Sources are hidraw 0b05:1abe if2, the xpad pad, and N-KEY keys PROG1/F14–F17/F19/F20. It also uses the bmi323 IMU. Targets are xbox-elite, mouse and keyboard; capability map `aly1`. Omarchy is MIT. Reimplement that config, or vendor it in a clearly separate path with its own LICENSE and SPDX headers.
- Profiles `desktop.yaml`, `gamepad.yaml` and `dualsense.yaml`, switched by `bridge.py` over InputPlumber D-Bus according to session and lock state.
  - Armoury short (`QuickAccess`) opens the Omarchy menu. Armoury long (`QuickAccess2`) switches mode.
  - Command Centre short (`Guide`) is the power action. Command Centre long (`Keyboard`) does Super+Ctrl+Y on the desktop (wvkbd keyboard), or Guide+West in gamepad mode (Steam OSK).
  - On the desktop the paddles (`LeftPaddle1`/`RightPaddle1`) act as Shift/Ctrl. In DualSense mode they're remapped to paddle 2.
  - In the desktop profile, the right stick moves the pointer, A/B/X are left/right/middle click, the triggers click, and the bumpers scroll.
- `omarchy-ally-power.service` + `power.py`: TDP and profile control through the SteamOS Manager session D-Bus. It treats ppd, PowerStation, HHD, asusd, tlp and tuned as conflicts, and has no fan-curve API.
- Touchscreen-to-panel binding (`rog-ally-touch.lua`), power-button udev/hwdb rule, and a first-run "Gaming Setup" invitation.
- Services `omarchy-rog-ally-input`, `omarchy-ally-power` and `inputplumber` are not installed or active. Note that `asusd` is running even though `rog-ally.sh` says RC71L skips asusctl, and `power.py` lists asusd as a conflict.

## Still needed (needs Daniel at the device)
A per-button press test is needed to pin each extra button to its exact code and confirm 0xa2. It covers Armoury Crate short/long, Command Centre short/long and the M1/M2 paddles, plus combos. It needs `evtest` and either sudo or the `input` group, so it's an install or change and is waiting on Daniel.

## Press test
On the device the script is `~/ally-press-test.sh`. The repo copy is [`tools/ally-press-test.sh`](tools/ally-press-test.sh) (`docs/handheld/research/tools/ally-press-test.sh`). It is a device-only research tool and not part of the product.
- It installs evtest via one-off sudo and logs that to `~/omarchy-handheld-deploy.log`.
- It takes 17 prompted steps of 5 s each (`SECS` defaults to 5). The steps are `armoury_short`, `armoury_long`, `cc_short`, `cc_long`, `cc_hold_0.5s`, `cc_hold_1s`, `armoury_hold_0.5s`, `armoury_hold_1s`, `vol_up`, `vol_down`, `paddle_left`, `paddle_right`, `paddle_left_plus_A`, `paddle_right_plus_A`, `armoury_plus_A`, `cc_plus_A` and `idle`. Each step records evtest on all N-KEY interfaces, WMI and the pad, plus raw hidraw and dmesg.
- Output goes to `~/ally-press-test/<timestamp>.tar.gz`.

## Open questions from dev-ux's button map (12 Nov, 13:37 AWST)
- **OQ-2:** does CC long send F20 or Ctrl+Alt+Del? It's in the press test (`cc_long`; N-KEY devices grabbed). Upstream InputPlumber `ally_type1` accepts both F20 and Ctrl+Alt+Del as CC long.
- **OQ-3:** what's the long-press threshold? The press test has 0.5 s and 1 s holds for CC and Armoury. It brackets the value; it may not give exact milliseconds.
- **OQ-8:** volume rocker. The press test has volume up and down steps.
- **OQ-7/14:** stick-scroll and gyro in InputPlumber v0.84.0.
  - Gyro: bmi323 IIO is present (`iio:device0 bmi323-imu`) and in the composite config, and profiles accept a `GyroEvent` source. The xbox-elite target has no motion, so gyro into Steam would go via `ds5-edge` (inferred).
  - Stick-scroll: the mouse target has REL_WHEEL plus WheelUp/WheelDown, and `AxisEvent.direction` converts an axis to a button. Notched scrolling is possible; smooth scrolling is unconfirmed.
  - `mouse: wheel:` isn't in the v0.84.0 schema but is used by upstream `mouse_keyboard_wasd.yaml`.
- **OQ-15:** why is asusd running?
  - asusctl was explicitly installed on 2026-11-11 at 11:51, before omarchy-dev at 12:02.
  - `asusd.service` is static. asusctl's own udev rule (asus-nb-wmi + DMI family `*ROG*`) starts it, so the skip in `rog-ally.sh` doesn't stop it.
  - It actively changes platform_profile and EPP.
