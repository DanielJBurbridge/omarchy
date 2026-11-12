# 01 · Controller and button map

Status: draft for dev-lead review, revision 1, 12 Nov 2026. Device: ROG Ally RC71L. Input daemon: **InputPlumber** (lead decision; HHD only as an alternatives note in Appendix B).
Related: [README](README.md) · 02 mode switch + dock (TODO) · 04 quick-access overlay (TODO) · 07 OSK (TODO). No lock-screen design here.

Revision 1 incorporates the dev-red review and the 12 Nov hardware research. The decisions are in §2. They replace the first draft's "Armoury long takes a screenshot" proposal.

## 1. Baseline: what is already built

This spec builds on `feat/ally-input-20261111` (head `95a0992ce5`, companion `omarchy-rog-ally-input 1.0.3-1`). That mapping is the **baseline** in every table below. Columns marked **Δ** are proposed changes. Hyprland line numbers are from `feat/ally-parity-integration-20261111` at `3f800d118` (`default/hypr/bindings/`). The same mouse, Super and close-all binds are on the fork default branch `quattro`.

| Piece | Path | What it does |
|---|---|---|
| Composite device | `default/rog-ally-input/50-rog_ally.yaml` on `feat/ally-input-20261111` | Derived from InputPlumber 0.84.0. Sources: hidraw `0b05:1abe` if2, xpad pad `045e:028e`, N-KEY keys `KeyProg1` / `KeyF14`–`KeyF17` / `KeyF19` / `KeyF20` / `KeyLeftCtrl` / `KeyLeftAlt` / `KeyDelete`, `bmi323-imu`. Targets `xbox-elite`, `mouse`, `keyboard`; capability map `aly1`. LED source omitted (firmware keeps RGB). The evdev include list has no volume key (OQ-8). |
| Profiles | `default/rog-ally-input/profiles/{desktop,gamepad,dualsense}.yaml` | DeviceProfile v1. Names: `Omarchy Ally desktop`, `Omarchy Ally gamepad`, `Omarchy Ally dualsense`. Installed to `/usr/share/omarchy-rog-ally-input/profiles/`. `gamepad` targets `xbox-elite`. `dualsense` targets `ds5-edge` and remaps `LeftPaddle1`→`LeftPaddle2`, `RightPaddle1`→`RightPaddle2`. |
| Bridge | `default/rog-ally-input/bridge.py`, `default/rog-ally-input/omarchy-rog-ally-input.service` | `MODES` is `desktop`, `gamepad`, `dualsense`. Loads `desktop` only in an active, unlocked Hyprland session, else `gamepad`. Handles D-Bus `omarchy_mode`, `omarchy_menu`, `omarchy_power`. An unknown action exits `Ally input: unknown action; use --help`. Never touches an overlay's interception or a custom profile. |
| CLI | `bin/omarchy-hw-rog-ally-input`, `bin/omarchy-setup-rog-ally-input` | `status / desktop / gamepad / dualsense / toggle / capabilities / intercept / watch`. Enable refuses unit and process names matching `hhd`, `handheld-daemon`, `input-remapper`, `xboxdrv`, `chimera`, `opengamepadui`. |
| Detection | `bin/omarchy-hw-rog-ally` (also PR #3, `cursor/rog-ally-rc71l-3178`) | DMI: `ASUSTeK COMPUTER INC.` + product `ROG Ally RC71L*` or board `RC71L`. Excludes Ally X / Xbox Ally. |
| OSK | `bin/omarchy-toggle-desktop-keyboard`; bind `SUPER + CTRL + Y` on `feat/ally-touch-20261111` in `default/hypr/bindings/utilities.lua` | wvkbd toggle, only when `wvkbd-mobintl` is present and `omarchy-hw-rog-ally` succeeds. Not on the parity or input branch yet. |
| Docs | `docs/rog-ally-input.md`, `plans/rog-ally-parity.md` on the input branch | Control table, session contract, acceptance list I01–I13. |
| Gaming session | `feat/ally-session-20261111` | `bin/omarchy-launch-gaming-session` leaves the desktop (it stops wvkbd, writes the switch marker, and logs out). `bin/omarchy-session-start` `run_gaming` calls `omarchy-hw-rog-ally-input gamepad` before Gamescope when `omarchy-pkg-present omarchy-rog-ally-input`, and a non-zero status aborts the session (`return 1`). State lives in `default/gaming/session.sh` (`~/.local/state/omarchy/gaming-session`, choice `desktop` or `gaming`). Docs: `docs/rog-ally-gaming-session.md`. Steam owns Guide+South (QAM on an Xbox target) and Guide+West (OSK). |

Hardware facts (read-only dump, 12 Nov 2026, Daniel's RC71L; the dump is not a file in this repo): kernel `7.2.15-2-omarchy`, BIOS RC71L.339; pad is **xpad** (11 buttons, **no paddle codes**); OEM buttons arrive on **N-KEY if2** (`hid-asus`). `Unmapped Asus vendor usagepage code 0xa2` was logged twice. The kernel printed `The MCU firmware version must be 319 or greater` and `mcu_powersave` was 0, so this unit's MCU firmware is below 319. InputPlumber, HHD and the companion are **not installed**. `asusd` 6.5.0 is running next to `power-profiles-daemon`. The power key is tagged `STEAMOS_POWER_BUTTON`. There is no `omarchy-system-power-button` command on this branch or on `feat/ally-input-20261111`. logind ignores the key (`etc/systemd/logind.conf.d/10-ignore-power-button.conf`, `HandlePowerKey=ignore`). Short-press suspend stays with RELIABILITY (parity plan row R01) and spec 02.

Omarchy binds driven by this spec (`default/hypr/bindings/` at `3f800d118`):

| Bind | Action | File |
|---|---|---|
| `SUPER + SPACE` | Omarchy menu | `utilities.lua:1` |
| `SUPER + ALT + SPACE` | Apps | `utilities.lua:2` |
| `SUPER + ESCAPE` | System menu | `utilities.lua:8` |
| `SUPER + CTRL + P` | Power panel (`omarchy.power`) | `utilities.lua:119` |
| `SUPER + LEFT/RIGHT/UP/DOWN` | Focus window | `tiling.lua:18-21` |
| `SUPER + SHIFT + arrows` | Swap window | `tiling.lua:51-54` |
| `SUPER + mouse:272` / `mouse:273` | Drag move / resize | `tiling.lua:84-85` |
| `SUPER + mouse_down` | Next workspace (forward) | `tiling.lua:81` |
| `SUPER + mouse_up` | Previous workspace (backward) | `tiling.lua:82` |
| `SUPER + TAB` | Next workspace | `tiling.lua:37` |
| `SUPER + W` / `SUPER + Q` | Close window (`hl.dsp.window.close()`, dispatcher `killactive`) | `tiling.lua:1-2` |
| `SUPER + F` | Full screen | `tiling.lua:8` |
| `SUPER + RETURN` | Terminal | `applications.lua:2` |
| `CTRL + ALT + DELETE` | Close all windows (`omarchy-hyprland-window-close-all`) | `tiling.lua:3` |
| `PRINT` | Screenshot (`omarchy-capture-screenshot`) | `utilities.lua:40` |
| `XF86AudioRaise/LowerVolume`, `XF86MonBrightnessUp/Down` | Volume / brightness (OSD) | `media.lua:2-3`, `media.lua:6-7` |

`SUPER` alone is unbound. No `o.bind`, `o.bind_toggle` or `o.bind_hold` in `default/hypr/bindings/` uses the chord `SUPER` with no other key. A bare Super tap does nothing. `mouse:274` (middle click) is also unbound. Left is `mouse:272`, right is `mouse:273`.

`hl.dsp.window.close()` is a polite close. The keybindings fixture records its dispatcher as `killactive` (`test/shell.d/keybindings-menu-test.sh`). Hyprland asks the client to close. It does not send SIGKILL. The app may show a save prompt, or it may drop unsaved work. There is no confirmation in the bind.

## 2. Decisions (revision 1)

| # | Decision |
|---|---|
| D1 | **Gaming-session target is `ds5-edge` (DualSense Edge).** Upstream `deck-uhid` (Steam Deck) is the accepted alternative if a press test shows the Edge target still delivers QAM as a Guide+South macro, or if gyro is flaky. Xbox Elite stays the shipped `gamepad` profile and is not the gaming-session target: it has no motion, and it fakes QAM as a Guide+face chord (Guide+South in InputPlumber, Guide+A in HHD). |
| D2 | **Δ3 is the quick-access overlay, not a screenshot.** Armoury long (`KEY_F17` / `QuickAccess2`) in the gaming session opens the Omarchy quick-access overlay (spec 04). Until that overlay exists, the same action falls back to Steam's QAM. It does not change profile and it does not take a screenshot. Screenshot in a game stays on Steam's own path (the QAM menu, or Steam's screenshot shortcut on the Edge target). |
| D3 | **The overlay has a route that is not a long press.** Spec 04 adds an Omarchy menu row and a QAM entry that run the same action. Until spec 04, Armoury tap (QAM) is that route. |
| D4 | **On RC71L, `CTRL + ALT + DELETE` always asks before it closes windows.** The confirm is keyed only on `omarchy-hw-rog-ally`. InputPlumber being up, down, killed, or not yet started does not matter. Raw Ctrl+Alt+Delete is always possible on this device. |
| D5 | **No system action is hold-only.** Steam Input hold-chords are unreliable on the Ally (firmware does not give CC or AC a press/release pair). A firmware-distinct key (Armoury `KEY_F17`, Command Centre Ctrl+Alt+Delete or `KEY_F20`) may be a shortcut. It is never the only route. |
| D6 | **Keep asusctl off the RC71L.** `asusd` fights `power-profiles-daemon` for the platform profile. The skip in `install/hardware/asus/rog-ally.sh` does not stop a copy that is already installed. |
| D7 | **Left-stick scroll is notched, not analogue.** Gyro's source exists; Steam only sees it through a `ds5-edge` or Steam Deck target. Both are untested on this unit. |

## 3. Physical layout

Confirmed from the ASUS RC71L manual (items 6 and 7) and the 12 Nov research. OQ-5 is closed.

| Control | Where it is | Hold? |
|---|---|---|
| Command Centre (CC) | **Left** of the screen, below View | No press/release. Tap and long are different firmware events. |
| Armoury Crate (AC) | **Right** of the screen, below Menu | Long press is a real firmware key (`0xa7` → `KEY_F17`). `KEY_F18` is the release. This is the only OEM long-press key. |
| View / Menu | Above CC / above AC | Real press and release. Can be a modifier. |
| M1 / M2 | **Back grips**, left / right | Real press and release. Can be a modifier. |
| Face, sticks, shoulders, triggers | Standard Xbox layout | Real press and release. Passed through in the gaming session (P4). |

Do not swap CC and AC in tables, diagrams or profile comments. Windows uses the same sides: Command Centre tap opens Command Centre, Armoury tap opens Armoury Crate SE.

## 4. Gesture model for OEM buttons (CC, AC)

RC71L Command Centre has **no MCU long-press code of its own**. A long press sends **Ctrl+Alt+Delete** on the keyboard interface (ASUS manual; InputPlumber `aly1` matches `KeyLeftCtrl`+`KeyLeftAlt`+`KeyDelete`). With the out-of-tree `hid-asus-ally` driver it can send `KEY_F20` instead. **Design for both.** Do not rely on `KEY_F20` or `KEY_F19`: those exist with `hid-asus-ally`, which the stock Omarchy kernel does not have. Armoury long is `KEY_F17` on mainline `hid-asus`.

Userspace must not time a hold of CC or AC. The baseline rule in `docs/rog-ally-input.md` stands. Steam's "hold Guide + X" chords cannot be performed on CC or AC. Each system action has a single-event route and a menu route (§7).

| Gesture | Source | Rule |
|---|---|---|
| Tap | Firmware key on release | Fires on release. Desktop action starts within 100 ms of release. Virtual-pad event within 50 ms. |
| Armoury long | `KEY_F17` once | Must never also fire the tap action. Threshold is firmware (reported ≈ 1 s; measure, OQ-3). |
| Command Centre long | Ctrl+Alt+Delete **or** `KEY_F20` | Both map to the InputPlumber `Keyboard` capability when InputPlumber owns the device. If the raw chord reaches Hyprland, Δ9 confirms before any close. Never emit Ctrl+Alt+Delete from a profile. |
| Double tap | Userspace only | **Not bound by default.** It would delay every tap. Reserved for spec 02 (OQ-6). |
| Hold-as-modifier on CC or AC | Not possible | No press/release pair. |

Paddles and View/Menu have real press/release, so they can be modifiers. A system action still needs a route that does not require holding them (§7, D5).

Upstream key map, used as the design assumption until the press test (OQ-1). Mainline `hid-asus`: `0x38`→`KEY_PROG1` (Armoury tap), `0xa6`→`KEY_F16` (Command Centre tap), `0xa7`→`KEY_F17` (Armoury long), `0xa8`→`KEY_F18` (Armoury long release). `0xa5`→`KEY_F15` is commented "left back" in the kernel, while `aly1` labels `KEY_F15` as the right paddle and `KEY_F14` as the left. **Do not treat those names as the physical sides.**

## 5. Button map: actions per button per mode

Modes: **Game** = gaming session (Gamescope + Steam, `gaming` profile; see §12). **Desktop** = Hyprland, `desktop` profile. **Menu** = an Omarchy menu or panel is open on the desktop. **OSK** = wvkbd visible on the desktop.
Raw codes are the upstream assumption. **This unit is untested (OQ-1).** OQ-2 stays open for which Command Centre long code this firmware sends; the design does not wait on it.

### 5.1 OEM buttons

| Button | Raw code (TBC) | IP event | Game | Desktop | Menu | OSK | Δ vs baseline |
|---|---|---|---|---|---|---|---|
| CC tap | `KEY_F16` ⟨TBC⟩ | `Guide` | Steam button (Steam menu) | Power panel (`omarchy-shell shell toggle omarchy.power`) → **Quick-access overlay** (spec 04) when it ships | Close menu, then same as Desktop | Same as Desktop | **Δ1** Desktop target moves to the quick-access overlay once spec 04 lands; power panel stays the fallback. |
| CC long | Ctrl+Alt+Delete **or** `KEY_F20` ⟨TBC⟩ | `Keyboard` | Steam OSK (Guide+West macro, emitted by the profile, not held by the user) | Toggle wvkbd (`Super+Ctrl+Y` → `omarchy-toggle-desktop-keyboard`). Menu row does the same, so this is not the only route. | Toggle wvkbd | Hide wvkbd | Keep the shortcut. **Δ9** if the raw chord hits Hyprland, it confirms; it never closes windows on its own. |
| AC tap | `KEY_PROG1` (or `KEY_F19` only with `hid-asus-ally`) ⟨TBC⟩ | `QuickAccess` | Steam QAM (a real button on the gaming target; see D1) | Omarchy menu (`omarchy-menu`) | Close menu (toggle) | Omarchy menu (wvkbd stays) | Keep. Δ2: in Menu, second tap closes (toggle, as `Super+Space`). |
| AC long | `KEY_F17` ⟨TBC⟩ | `QuickAccess2` | **Quick-access overlay** (spec 04). Until it exists, **Steam QAM**. Not a screenshot. Not a profile change. | Toggle controller profile desktop ⇄ gamepad, with notification. Menu row does the same. | Same as Desktop | Same as Desktop | **Δ3** in Game only. Matches the community InputPlumber default (Armoury long opens an overlay) instead of the first draft's screenshot. |
| AC double tap | — | (bridge timer) | — | **Reserved: switch gaming ⇄ desktop** → spec 02 | — | — | New, off by default (OQ-6). Not a system action's only route. |

Rationale: on Windows, Command Centre is the quick-settings panel and Armoury is the launcher. Desktop mapping mirrors that (CC → quick settings/power, AC → Omarchy menu). Game mapping matches SteamOS / Bazzite / InputPlumber (CC = Steam, AC tap = QAM, AC long = an overlay). The first draft sent Armoury long to Screenshot because a profile toggle is meaningless in Gamescope. Revision 1 keeps that reason for not toggling, and uses the overlay the community already uses. Screenshot does not need this button: Steam already has it on the QAM and on the Edge target's screenshot shortcut.

Guide+West is the shipped OSK macro (`gamepad.yaml`, `dualsense.yaml`). If Steam sees Guide before West it can open the Steam menu instead of the keyboard. That is baseline behaviour. Confirm it on the press test. It does not block this spec.

### 5.2 Face, shoulder, stick and system buttons

| Button | Game | Desktop (baseline) | Menu | OSK | Δ vs baseline |
|---|---|---|---|---|---|
| Right stick | Game axis | Pointer, 900 px/s (logical, pre-scale) | Pointer | Pointer (tap keys with A) | Keep. Speed setting → spec 06. |
| Left stick | Game axis | **Unmapped** in the shipped profile | Unmapped | Unmapped | **Δ4** Notched scroll only: `WheelUp` / `WheelDown` (and the horizontal pair) from an axis direction. Not an analogue wheel. IP 0.84 can do the notched form; `mouse: wheel:` is not in the 0.84 schema but upstream `mouse_keyboard_wasd.yaml` uses a wheel. OQ-7 closed. |
| A (South) | A | Left click / drag (hold) | Left click (select under pointer) | Left click (press key) | Keep. |
| B (East) | B | Right click | **Δ5 Close/back** (Escape, via a layer-scoped bind) | **Δ6 Backspace** | Δ5, Δ6 (§6). |
| X (West) | X | Middle click | Middle click | **Δ6 Space** | Δ6. |
| Y (North) | Y | Enter | Enter (activate highlighted) | Enter | Keep. |
| LB / RB | LB / RB | Scroll down / up (`LeftBumper` wheel down, `RightBumper` wheel up) | Scroll | Scroll | Keep. |
| LT / RT | LT / RT | Right / left click (deadzone 0.25) | Same | Same | Keep. |
| L3 | L3 | Unmapped | Unmapped | Unmapped | Keep. `Super+Ctrl+Z` zoom (`utilities.lua:134`) stays a keyboard chord, not a paddle chord. |
| R3 | R3 | Left click | Left click | Left click | Keep. Same Hyprland event as A (`mouse:272`). |
| D-pad | D-pad | Arrow keys | Move highlight | Arrow keys | Keep. |
| View (Select) | View | Tab | Tab | Tab | Keep. |
| Menu (Start) | Menu | Escape | Escape (close) | Escape | Keep. |
| Volume rocker | System volume | `XF86AudioRaise/LowerVolume` → Omarchy OSD (`media.lua:2-3`) | Same | Same | Keep. The shipped composite include list does not name the volume keys, so an InputPlumber grab may swallow them (OQ-8). |
| Power button | Short press: suspend, owned by spec 02 / RELIABILITY (R01). Not `omarchy-system-power-button`. | Same | Same | Same | Out of scope here. |

### 5.3 Rear paddles (back grips)

| Paddle | Raw (TBC) | Game default | Game suggested | Desktop baseline | Desktop proposed | Δ |
|---|---|---|---|---|---|---|
| M1 (left grip) | Whichever capability the press test shows is the left grip. Do not assume `LeftPaddle1` or `KEY_F14`. | Xbox Elite passthrough on the shipped `gamepad` profile. On `ds5-edge`, passthrough unless the press test shows the `dualsense.yaml` paddle-2 remap is required. | Unbound in Steam Input until a game layout uses it | `LeftPaddle1` → Left Shift, **if** that capability is this grip | **Left Super (held)** on the capability that is this grip | **Δ7** |
| M2 (right grip) | The other paddle capability. `aly1`'s F14/F15 labels may be swapped relative to the kernel comment. | Same, other side | Same | `RightPaddle1` → Left Ctrl, if that capability is this grip | Left Ctrl (held) | Keep. |

Δ7 rationale: Omarchy is driven by Super. Shift-as-paddle only helps Shift+click (A-drag already selects). Super on the left grip unlocks existing Hyprland binds (§8). Shift remains on the OSK (one-shot). Steam Deck precedent: L5 = Super in desktop. A bare tap is Super down and Super up, and Super alone is unbound, so a tap does nothing.

**Dependency (OQ-17).** InputPlumber programs Ally paddles through the out-of-tree `hid-asus-ally` driver (`asus_rog_ally` / `asus_ally_hid`). That driver is not in mainline and not in kernel `7.2.15-2-omarchy`. HHD can program paddles over hidraw without it. Until the press test, treat "M1 is Super" as the design and treat "the event arrives" as unproven. Do not ship Δ7 as working on the stock kernel without that test.

### 5.4 Community comparison

| | Community InputPlumber default | HHD | Omarchy (this spec) |
|---|---|---|---|
| AC tap | QAM | QAM | Game: QAM. Desktop: Omarchy menu. |
| AC long / hold | Overlay (`QuickAccess2`, OGUI on Bazzite/Chimera) | Double tap opens the HHD overlay (0.2 s window). Hold 0.4 s toggles MCU mouse mode. | Game: quick-access overlay, Steam QAM until spec 04 (**Δ3**). Desktop: profile toggle. Firmware key, not a userspace 0.4 s timer. |
| CC tap | Steam menu | Guide (Steam menu) | Game: Steam menu. Desktop: power panel, then the quick-access overlay (Δ1). |
| CC long | OSK (`Keyboard`) | Not handled in HHD's Ally code (unverified) | OSK, plus a menu row so it is not hold-only. Raw Ctrl+Alt+Delete confirms (Δ9). |

Omarchy does not copy HHD's 0.4 s mouse-mode hold or its double tap. Those need a userspace timer, and CC cannot be held.

## 6. Proposed context profiles (Menu, OSK)

DeviceProfile v1 takes **one `source_event` per mapping**, so a context change is a profile swap or a Hyprland layer-scoped bind.

| Context | Mechanism | Changes | Why this mechanism |
|---|---|---|---|
| Menu (Δ5) | Hyprland, enabled only while an Omarchy menu layer is open (same pattern as the `selection` binds in `utilities.lua:54-98`, namespace `selection`): `mouse:273` → close menu | B = back/close | No daemon change. Cannot leak: enabled only while the layer exists. Menu namespaces are still TBC (OQ-9). The `selection` namespace is the slurp picker, not the Omarchy menu. |
| OSK (Δ6) | Bridge loads `osk.yaml` (desktop, plus B→Backspace, X→Space) when wvkbd is shown, and restores the **previous** profile when it hides | B = Backspace, X = Space | wvkbd is pointer/touch only. |

**wvkbd death.** Remember the profile that was current when `osk` was loaded (normally `desktop`). Restore that profile on the helper's hide/stop **and** when the wvkbd process exits for any other reason (crash, kill, Wayland disconnect). Watch the process; do not poll, and do not wait for a hide signal that will not come. A dead keyboard must not leave B as Backspace.

OSK changes which Hyprland chords X and B produce. See the OSK rows in §8.

## 7. Chords and system actions

No CC/AC chords (§4). No system action is reachable only by holding a button or by a Steam Input hold-chord (D5). Paddles may be modifiers for Hyprland chords that already exist; each action below also has a menu or single-event route.

| Action | Game | Desktop | Notes |
|---|---|---|---|
| Quick-access overlay | AC long (Δ3). Also a QAM entry once spec 04 adds it. Until then, AC tap opens QAM, which is the no-hold route. | CC tap (Δ1). Also an Omarchy menu row. | Spec 04. AC long is a shortcut, not the only way in. |
| Screenshot | QAM menu, or Steam's screenshot shortcut on the `ds5-edge` target. **Not AC long.** | Omarchy menu → Capture (`omarchy-capture-screenshot`). `PRINT` is `utilities.lua:40` and is not on the pad. | If Steam's shortcut is a hold-chord, it is unreliable here. The QAM entry is the route that does not need a hold. Optional pad shortcut remains OQ-11. |
| OSK | CC long emits Guide+West. Also Steam menu → keyboard. | CC long toggles wvkbd. Also an Omarchy menu row. | Baseline shortcut, plus a non-hold route. |
| Volume | Volume rocker | Volume rocker | Hardware. OQ-8. |
| Brightness | QAM slider, and the overlay once spec 04 exists | Quick-access overlay / Omarchy OSD. `XF86MonBrightness*` is not on the pad (`media.lua:6-7`). | Do not require Steam's Guide+stick hold. |
| Perf profile | QAM performance tab, then the overlay (POWER owns the single writer) | Quick-access overlay (spec 04) | `plans/rog-ally-parity.md`. asusctl stays off the device (D6). |
| Close a game | CC tap → Steam menu → Exit game | — | Polite exit. Not a kill. Steam's Guide+B hold is not a route (D5). A force-close macro waits on OQ-12. |
| Close a window | — (Hyprland is not running) | M1 + X once Δ8 exists (`Super + mouse:274`) | **Polite close** (`killactive`), no confirmation. See §8. Not a kill. |
| Open QAM | AC tap | — | Baseline, on a target that has a real QAM button (D1). |
| Omarchy menu | — | AC tap | Baseline. |
| Switch gaming ⇄ desktop | Steam Power → Switch to Desktop; reserved AC double tap | Omarchy menu → Gaming; reserved AC double tap | **Flow belongs to spec 02.** Ends running games; needs confirmation. |
| Controller profile toggle | — (would disconnect the pad mid-session; C4) | AC long, and an Omarchy menu row | Baseline on the desktop. Notification "Controller mode: Desktop/Gamepad". |

## 8. Driving Hyprland from the controller (desktop, with Δ7)

### 8.1 Releasing held modifiers

Δ7 makes the left grip a held Super. If that grip is down across a profile switch, the virtual keyboard can leave Super latched. The next A or RT is then `Super + mouse:272` (window move), and the next X is the Δ8 close.

The bridge emits a synthetic key-up for every modifier and mouse button it has put down and not yet released, including `KeyLeftMeta` and `KeyLeftCtrl`, **before** it loads another profile. InputPlumber's virtual keyboard can send that key-up over D-Bus. Do it on all of these, not only on Armoury long:

- every profile load (`desktop`, `gamepad`, `dualsense`, `gaming`, `osk`, and the optional presets)
- lock, and unlock
- suspend (`PrepareForSleep`) and the matching resume
- bridge SIGTERM / SIGINT, before the process exits
- InputPlumber restart: if the composite device disappears, the virtual device goes with it and the kernel drops its keys; when the device returns, do not restore a latched modifier

A userspace injector such as `wtype` is the wrong tool. `default/hypr/bindings/clipboard.lua` already notes that a physically held Super merges into an injected chord.

### 8.2 Intended desktop chords

| Task | Controller input | Emits | Omarchy bind |
|---|---|---|---|
| Move pointer | Right stick | mouse motion | — |
| Focus window | Hold M1 + D-pad | `Super + arrows` | `tiling.lua:18-21` |
| Swap window | No paddle route | — | `tiling.lua:51-54` needs Shift. Δ7 removed Shift from the grip. M1+M2+D-pad is `Super+Ctrl+arrows`, and that bind exists only for left/right, where it is group focus (`tiling.lua:98-99`), not swap. Up/down have no `SUPER + CTRL` bind. OQ-13. |
| Move window (drag) | Hold M1 + hold A, right stick | `Super + mouse:272` | `tiling.lua:84`. RT and R3 emit the same button, so they drag too. |
| Resize window | Hold M1 + hold B or LT, right stick | `Super + mouse:273` | `tiling.lua:85` |
| Next workspace | Hold M1 + LB | `Super + mouse_down` | `tiling.lua:81` (forward) |
| Previous workspace | Hold M1 + RB | `Super + mouse_up` | `tiling.lua:82` (backward) |
| Next workspace (alt) | Hold M1 + View | `Super + Tab` | `tiling.lua:37` |
| Close window | Hold M1 + X | `Super + mouse:274` | **Δ8, new.** Unbound today (no `mouse:274` in `default/hypr/bindings/`). Same dispatcher as `tiling.lua:1-2`: `hl.dsp.window.close()` / `killactive`. Polite close, **no confirmation**. An app may prompt to save, or it may discard the document. Easy to hit: M1 held for a drag, X brushed. Accepted, and called a close, not a force-close or a kill. |
| Full screen | Omarchy menu | — | `Super + F` is `tiling.lua:8`. The pad has no F. M1+Y is Terminal. OQ-13. |
| Terminal | Hold M1 + Y | `Super + Return` | `applications.lua:2` |
| System menu | Hold M1 + Menu | `Super + Escape` | `utilities.lua:8`. Opens the menu. Does not log out, reboot or shut down by itself. |
| Launcher (Apps) | AC tap → Omarchy menu → Apps | — | `utilities.lua:2` is `Super+Alt+Space`, which the pad cannot emit (no Alt). Use the menu. |
| Omarchy menu | AC tap | D-Bus `omarchy_menu` | baseline bridge → `omarchy-menu` |

OEM taps are D-Bus actions. They do not include the paddle modifiers. Super stays down until the grip is released, so the next pad key is still a Super chord.

### 8.3 Paddle × pad matrix

Checked against every bind in `default/hypr/bindings/` at `3f800d118`. Desktop profile emissions after Δ7: M1 = Super, M2 = Left Ctrl, M1+M2 = Super+Ctrl. Neither paddle emits Alt or Shift, and no pad key emits Alt, Shift or a letter. **Every `SUPER + ALT` and `SUPER + SHIFT` bind is unreachable from the pad**, including swap (`tiling.lua:51-54`) and move-to-monitor (`tiling.lua:46-49`).

A, RT and R3 are one row: they all emit `mouse:272`. B and LT both emit `mouse:273`. "No bind" means no Omarchy bind. The focused app can still see Ctrl+click or Ctrl+Tab.

| Pad control | Emits | M1 (Super) | M2 (Ctrl) | M1+M2 (Super+Ctrl) |
|---|---|---|---|---|
| A / RT / R3 | `mouse:272` | **Move window** `tiling.lua:84`. Intended for A. RT and R3 are the same drag. | No bind | No bind |
| B / LT | `mouse:273` | **Resize** `tiling.lua:85`. Intended. | No bind | No bind |
| X | `mouse:274` | **No bind today.** Δ8 adds polite close, no confirmation. | No bind | No bind |
| Y | Return | **Terminal** `applications.lua:2`. Intended. | No bind | **Collision: Herdr** `applications.lua:13`. Not a power, logout, close-all or kill bind. Unintended. |
| View | Tab | **Next workspace** `tiling.lua:37`. Intended. | No bind (`CTRL + ALT + TAB` at `tiling.lua:63` needs Alt) | **Collision: former workspace** `tiling.lua:39`. Unintended. |
| Menu | Escape | **System menu** `utilities.lua:8`. Intended. Does not log out. | No bind | No bind. There is no `SUPER + CTRL + ESCAPE`. |
| D-pad left | Left | **Focus left** `tiling.lua:18` | No bind | **Collision: group focus left** `tiling.lua:98` |
| D-pad right | Right | **Focus right** `tiling.lua:19` | No bind | **Collision: group focus right** `tiling.lua:99` |
| D-pad up | Up | **Focus up** `tiling.lua:20` | No bind | No bind. Not group focus. |
| D-pad down | Down | **Focus down** `tiling.lua:21` | No bind | No bind. Not group focus. |
| RB | `mouse_up` | **Previous workspace** `tiling.lua:82` | No bind | No bind. `SUPER + ALT + mouse_up` (`tiling.lua:102`) needs Alt. |
| LB | `mouse_down` | **Next workspace** `tiling.lua:81` | No bind | No bind |
| L3 | nothing | Bare Super, unbound | No bind | No bind. Does not zoom (`utilities.lua:134` needs Z). |
| Left stick | none, or notched wheel (Δ4) | Not a Super chord | Not a Ctrl chord | Not a Super+Ctrl chord |
| CC / AC | D-Bus, not a key | The D-Bus action runs; Super stays down if M1 is held | Ctrl stays down if M2 is held | Both stay down |

`SUPER + CTRL` binds that the pad cannot hit, including the dangerous ones: tiled full screen (`tiling.lua:9`, F), power (`utilities.lua:119`, P), lock (`utilities.lua:143`, L), emojis (`utilities.lua:3`), capture menu (`utilities.lua:4`), display toggle (`utilities.lua:32`, Delete, not the close-all chord), zoom (`utilities.lua:134`, Z), and the bar-panel number keys (`utilities.lua:126-131`). `CTRL + ALT + DELETE` (`tiling.lua:3`) needs Alt as well as Delete. Paddles cannot produce it. The firmware Command Centre long can, which is Δ9, not a paddle chord.

Close-window letters `SUPER + W` and `SUPER + Q` (`tiling.lua:1-2`) are unreachable. The only pad route to `killactive` is the new Δ8 bind. There is no SIGKILL bind in `default/hypr/bindings/`.

OSK profile only (Δ6). X is Space and B is Backspace, so the desktop row above does not apply to those two buttons while `osk` is loaded:

| Pad control | M1 | M2 | M1+M2 |
|---|---|---|---|
| X (Space) | **Omarchy menu** `utilities.lua:1` (`SUPER + SPACE`). Not the Δ8 close. | **Direct input** `input-method.lua:24` (`CTRL + SPACE`), and only in a terminal. `non_consuming`. | **Background switcher** `utilities.lua:14` |
| B (Backspace) | **Toggle window transparency** `utilities.lua:18` | No bind | **Single-window square aspect** `utilities.lua:20` |

## 9. Controller-as-mouse (desktop)

| Item | Decision | Baseline/Δ |
|---|---|---|
| Pointer | Right stick, 900 px/s, IP fixed 0.20 deadzone | Baseline |
| Clicks | A/RT left (hold = drag), B/LT right, X middle, R3 left | Baseline |
| Scroll | LB/RB vertical. Left stick: notched wheel only (Δ4, OQ-7 closed). | Baseline + Δ4 |
| Trackpad emulation | None (RC71L has no trackpad). Touchscreen stays direct touch. The pattern file is `default/hypr/rog-ally-touch.lua` on `feat/ally-display-20261111` (early-return unless `omarchy-hw-rog-ally` succeeds). It is not on the parity or input branch. DS5 touchpad is not synthesised. | Statement |
| Gyro mouse | Optional, **off by default**, desktop only, enabled from the quick-access overlay (spec 04). `bmi323-imu` is on the composite and IP 0.84 accepts a gyro source. OQ-14 closed for capability. Still untested on this unit. | D7 |
| Gyro in Steam | The gaming target is `ds5-edge` so Steam can see motion. Xbox Elite cannot. Inferred from InputPlumber's targets, not from a test on this Ally. `deck-uhid` is the fallback target if Edge gyro is flaky. | D1, D7 |
| Steam closed | Pointer, clicks and scroll work with Steam not running | Baseline acceptance |

## 10. Conflict rules with Steam Input

| # | Rule |
|---|---|
| C1 | Exactly one input owner: InputPlumber. Setup refuses `hhd`, `handheld-daemon`, `input-remapper`, `xboxdrv`, `chimera`, `opengamepadui` (`bin/omarchy-setup-rog-ally-input`). |
| C2 | `desktop` has **no gamepad target**, so Steam's Desktop Configuration cannot add a second pointer. |
| C3 | The gaming profile exposes one virtual pad (`ds5-edge`). Omarchy maps OEM buttons and Armoury long (Δ3) only. Face, sticks, triggers and paddles pass through to Steam Input. |
| C4 | Choose the target before Gamescope starts. Loading `gaming` (`ds5-edge`) over `gamepad` (`xbox-elite`) reconnects the pad, so session start does it before Gamescope. A later reload with the same `target_devices` must not reconnect. Switching mid-game disconnects the pad. |
| C5 | Steam game in the **desktop** session: AC long still toggles to the shipped `gamepad` profile (Xbox Elite), not to `gaming`. The `dualsense` CLI profile remains the manual Edge profile for that session. Auto-switch on a focused fullscreen game → spec 02. |
| C6 | Never bind raw OEM keys (`F13–F24`, `PROG1–4`) globally in Hyprland. |
| C7 | Locked / inactive / unknown **Hyprland** session ⇒ `gamepad`, no desktop actions. This rule does not demote an active gaming session (§12). |
| C8 | Omarchy overlay (spec 04) uses `intercept all` while open and restores `none` on close, crash and session exit. |
| C9 | **Δ9.** On RC71L, `CTRL + ALT + DELETE` never runs `omarchy-hyprland-window-close-all` until a second, distinct accept (A, Y or Return). B, Menu (Escape) or dismissing the prompt does nothing. There is no timeout that means yes. The prompt is an Omarchy menu or notification action, not a new toolkit. Install this dispatcher whenever `omarchy-hw-rog-ally` succeeds, at Hyprland start, and do not also register the direct bind from `tiling.lua:3`. Do not consult InputPlumber. The confirm stays in place if InputPlumber is stopped, killed, not yet started, or disabled with `omarchy-setup-rog-ally-input disable`. Inside Gamescope the chord is the `Keyboard` capability (OSK macro), not this Hyprland bind, and no profile re-emits Ctrl+Alt+Delete. |
| C10 | Firmware stays in gamepad mode. Do not use `hid-asus` `gamepad_mode=desktop` as a second mouse path. |
| C11 | **asusctl stays off the RC71L (D6).** It was installed on this unit before the image's handheld setup, and its udev rule starts `asusd` on ROG DMI, so `install/hardware/asus/rog-ally.sh` skipping the laptop path does not stop it. `asusd` writes the platform profile and fights the power daemon. Do not add it for RGB or fans. |

## 11. Optional parity profiles

Off by default. Not loaded in `MODES` until the user turns them on from a menu row (not a hold). They are extra DeviceProfiles under `default/rog-ally-input/profiles/`. Default `desktop` and `gaming` stay as specified above.

### 11.1 Swap Armoury/CC with View/Menu

HHD's `swap_armory`. Bazzite users ask for it because View and Menu have a real hold, so Steam chords work when Guide and QAM sit on those buttons.

| Physical | Default game | `gaming-swap` |
|---|---|---|
| CC tap | Guide (Steam) | Select (View's action) |
| AC tap | QuickAccess (QAM) | Start (Menu's action) |
| View | Select | Guide |
| Menu | Start | QuickAccess |
| CC long | `Keyboard` (stays: the firmware chord does not move) | same |
| AC long | `omarchy_overlay` (stays on F17) | same |

`desktop-swap` is the same exchange on the desktop actions (CC tap ↔ View's Tab, AC tap ↔ Menu's Escape). View hold is a real modifier in the swap profile, which is the point of the option. Firmware long-press keys cannot be moved to View/Menu.

### 11.2 One-handed presets (desktop only)

Game face buttons stay with Steam (P4). One-handed play in a game is a Steam Input layout, not an Omarchy profile. These two profiles are desktop-only. The unused side is unmapped so a lap does not click it. Leave the preset from the Omarchy menu, which is on the side that preset can open.

| | `hand-left` (right side unmapped) | `hand-right` (left side unmapped) |
|---|---|---|
| Pointer | Left stick | Right stick |
| Arrows / d-pad | D-pad | Unmapped |
| Left click | View | A and RT |
| Right click | LT | B |
| Menu | CC tap → Omarchy menu | AC tap → Omarchy menu |
| Scroll | LB down | RB up |
| Modifier | M1 = Super | M2 = Ctrl |
| Unmapped | Right stick, A/B/X/Y, RB, RT, R3, Menu, AC tap | Left stick, d-pad, View, CC, LB, LT, L3, M1 |

Spec 06 can replace these with a fuller accessibility pass. The names and the "off unless chosen" rule are the parity requirement.

## 12. Gaming profile, watcher and old companions

### 12.1 What `gaming` is

`gaming.yaml` is `gamepad.yaml` plus the target decision (D1) and the Δ3 mapping. Nothing else. Profile name `Omarchy Ally gaming`. Session start loads it instead of `gamepad`, before Gamescope.

The shipped file's `QuickAccess2` target is `dbus: omarchy_mode`. The gaming file changes that one target to `dbus: omarchy_overlay`. Guide, QuickAccess and the paddles stay unmapped, as they are in `gamepad.yaml` (passthrough). The Keyboard → Guide+West mapping is copied unchanged.

`dualsense.yaml`'s paddle remap (`LeftPaddle1`→`LeftPaddle2`, `RightPaddle1`→`RightPaddle2`) is **not** in this delta. If the press test shows Edge paddles missing, add those two lines as part of D1, and do not add anything else.

Diff against `default/rog-ally-input/profiles/gamepad.yaml`:

```diff
--- profiles/gamepad.yaml
+++ profiles/gaming.yaml
   kind: "DeviceProfile"
-  name: "Omarchy Ally gamepad"
+  name: "Omarchy Ally gaming"
   target_devices:
-    - "xbox-elite"
+    - "ds5-edge"
     - "mouse"
     - "keyboard"
   mapping:
-    - name: "Mode switch on Armoury long"
+    - name: "Quick access on Armoury long"
       source_event:
         gamepad:
           button: "QuickAccess2"
       target_events:
-        - dbus: "omarchy_mode"
+        - dbus: "omarchy_overlay"
     - name: "Steam keyboard"
```

A source test asserts that those are the only differences, and that the Keyboard mapping is byte-for-byte the same. Loading this file when the composite is already on `ds5-edge` with the same target list must not reconnect the pad (C4). The first load, from Xbox Elite to Edge, happens only in `run_gaming` before Gamescope.

`deck-uhid` is the alternative target if D1's press test rejects `ds5-edge`. It is an upstream name. Omarchy does not ship it today. Switching to it is a one-line target change, not a new button map.

### 12.2 Bridge watcher

Baseline: desktop only while Hyprland is active and unlocked, otherwise `gamepad`. `omarchy_mode` sets the preferred mode to `gamepad` when the current mode is `desktop`, and to `desktop` otherwise. Applied blindly, a lock or a session signal inside Gamescope would replace `gaming` with `gamepad` and drop Δ3, or the two loads would fight.

| State | Profile |
|---|---|
| Gaming session in progress (`gaming_selection` / the session state is `gaming`, or the Gamescope session `run_gaming` started) | Hold `gaming` for the life of that session. Lock, unlock, login1 signals and bridge restart do not load `gamepad` or `desktop` over it. |
| Same session, companion has no `gaming` mode | Hold the fallback `gamepad` the same way. Do not "upgrade" it later. |
| Hyprland, active, unlocked, not the gaming session | `desktop`, or `osk` while that keyboard is up |
| Hyprland locked, inactive, or unknown | `gamepad`, no desktop actions (C7) |
| `omarchy_overlay` while mode is `gaming` | If spec 04's entry point is installed, toggle the overlay. If it is not, emit the target's QAM control (a button event the daemon sends, not a chord the user holds). Do not load another profile. Do not screenshot. |
| `omarchy_mode` while mode is `gaming` | Ignore. Armoury long no longer sends it. A stale event must not toggle to desktop. |
| Leave the gaming session back to Hyprland | Existing rule: `desktop` if unlocked, else `gamepad`. Key-ups first (§8.1). |

### 12.3 Companion 1.0.3-1

That package's `MODES` has no `gaming`. `omarchy-hw-rog-ally-input gaming` exits with `Ally input: unknown action; use --help`.

`run_gaming` tries `gaming` only when `omarchy-rog-ally-input` is installed. On that unknown-action error it calls `gamepad` and **still starts Gamescope**. Δ3 is absent on the fallback (Armoury long remains the shipped `omarchy_mode`). Any other error still aborts the session, as today's `gamepad || return 1` does. A missing package skips the call, as today, and Gamescope still starts.

## 13. User flows

| # | Flow | Steps | Expected |
|---|---|---|---|
| F1 | Undocked game | Boot → Gaming Mode (`gaming` profile before Gamescope) → launch game → AC tap → QAM → AC long → overlay or, until spec 04, QAM again → CC long → type → CC long | QAM opens from a real button. AC long does not change profile and does not take a screenshot. Steam OSK types. |
| F2 | Screenshot in game | AC tap → QAM → screenshot (or Steam's Edge shortcut) | Steam screenshot notification. AC long is not the gesture. |
| F3 | Exit stuck game | CC tap → Steam menu → Exit game | Polite exit. Library shown. Not a kill. |
| F4 | Desktop window work | Right stick + A to click → M1 + D-pad focus → M1 + LB next workspace → M1 + A drag → M1 + X close | Close is `killactive` with no prompt from Omarchy. The app may ask to save, or the work may be gone. |
| F5 | Launch app | AC tap → D-pad to Apps → Y → D-pad → Y | App opens; menu closes. |
| F6 | Type on desktop | Select field with A → CC long, or the menu row → B/X/Y → CC long | Backspace and Space work (Δ6). Keyboard hides. |
| F7 | Play Steam in the desktop session | AC long (→ `gamepad`, Xbox Elite) → play → AC long (→ desktop) | Not the `gaming` profile. Notification each way. No stuck Super or click (§8.1). |
| F8 | Lock while desktop | Lock | Profile → `gamepad` after key-ups. AC/CC do nothing desktop-side. Unlock restores `desktop`. |
| F9 | CC long with InputPlumber absent | Hyprland up, companion not grabbed, press Command Centre long | Confirmation. Windows stay until accept. |

## 14. Acceptance criteria

Each is testable on the RC71L. "TBC" items wait on the open questions.

1. Each OEM gesture (CC tap, CC long, AC tap, AC long) triggers exactly one action per §5.1 in each mode, 20/20 presses, never the tap action on a long press. Both Command Centre long codes (`Ctrl+Alt+Delete` and `KEY_F20`) count as the one long gesture.
2. Desktop OEM tap actions start within 100 ms of button release (journal timestamps).
3. In Game, AC tap opens and closes Steam QAM and CC tap opens the Steam menu, with a game running. QAM is a button event on the gaming target, not a chord the user holds.
4. In Game, CC long opens Steam OSK in a Steam search field and an in-game text field. The menu route opens it too.
5. In Game, AC long opens the quick-access overlay when spec 04 is installed, and Steam QAM when it is not. It does not change profile and it does not take a screenshot by itself.
6. In Desktop with Steam **closed**: pointer moves, A/RT left click and drag, B/LT right click, X middle click, LB/RB scroll a long page; stick centred for 10 s produces no pointer drift. With Δ4 on, the left stick produces notched wheel ticks and no pointer motion.
7. In Desktop, AC tap opens the Omarchy menu; D-pad moves the highlight, Y activates, Menu (Start) closes; B closes it (Δ5).
8. In Desktop, CC tap opens the power panel (later: quick-access overlay, Δ1).
9. In Desktop, CC long shows and hides wvkbd; with it visible B = Backspace and X = Space (Δ6). Killing wvkbd, and `omarchy-toggle-desktop-keyboard stop`, both restore the profile from before OSK without a further button press. B right-clicks again.
10. In Desktop with Δ7, once the paddle events arrive: M1 + D-pad focuses windows; M1 + LB/RB changes workspace in the §8.2 direction; M1 + A drags; M1 + X polite-closes the focused window (Δ8) with no Omarchy confirmation; M1 + Y opens a terminal. A bare M1 tap does nothing.
11. Releasing a held grip, trigger or mouse button across a transition leaves no stuck Super, Ctrl or click. Cover: AC long, lock, unlock, suspend, resume, OSK show, OSK hide, wvkbd killed, InputPlumber restarted, bridge restarted. After each, A is left click, not a window move, and X is not a close.
12. `omarchy-hw-rog-ally-input status` shows exactly one virtual gamepad in `gaming` / `gamepad` and none in `desktop`. The gaming target is `ds5-edge` (or `deck-uhid` if D1 was switched).
13. Locking a Hyprland session moves the profile to `gamepad` within 1 s after the key-ups; no Omarchy action fires from AC/CC while locked; unlock restores the previous profile. Locking during a gaming session does **not** replace `gaming` with `gamepad`.
14. On RC71L a Command Centre long that arrives as Ctrl+Alt+Delete does not close windows unless the confirmation is accepted. Cover all of: InputPlumber never enabled; `omarchy-setup-rog-ally-input disable` then the chord; InputPlumber killed mid-session; boot race (Hyprland up, N-KEY not yet grabbed). Dismissing the prompt closes nothing. This holds whether or not the companion is installed.
15. Paddles, **if the press test shows they arrive**: Steam Input sees them on the gaming target and can bind them per game. If they do not arrive on the stock kernel, record that against OQ-17 instead of failing the rest of the map.
16. Volume rocker changes volume with the Omarchy OSD in Desktop and Steam's in Game, including while InputPlumber has grabbed N-KEY (OQ-8).
17. An external controller on USB or Bluetooth keeps its own index and is not affected by the RC71L profile.
18. Against companion 1.0.3-1 (no `gaming` mode), `run_gaming` falls back to `gamepad` and Gamescope still starts. A different input error still aborts. A test with a stub that prints `Ally input: unknown action; use --help` is the source check.
19. A test diffs `gaming.yaml` to `gamepad.yaml` and fails if anything other than the name, `target_devices`, and the `QuickAccess2` target events changed.
20. `desktop-swap`, `gaming-swap`, `hand-left` and `hand-right` are not the profile after boot, after unlock, or at gaming-session start, until a menu row selects one.

## 15. Open questions

| # | Question | Blocks | Owner | Status |
|---|---|---|---|---|
| OQ-1 | Exact raw codes on this BIOS/MCU for CC tap, CC long, AC tap, AC long, and each grip. Which event is `0xa2`? Which InputPlumber paddle name is the left grip? `evtest` needs the `input` group or sudo. Script on the device: `~/ally-press-test.sh`. Also confirm whether Guide+West opens the OSK or the Steam menu. | Raw-code column, Δ7 wiring, Appendix A | Daniel + dev-research | Open. Press test. |
| OQ-2 | Does **this** unit's CC long send `KEY_F20` or Ctrl+Alt+Delete? Both are handled. The answer does not gate Δ9. | Which source event to expect in the log | dev-research | Open. Press test. Design already covers both. |
| OQ-3 | Firmware long-press threshold (ms), and whether a long press also emits a tap on some firmware. | §4, AC 1 | Press test | Open |
| OQ-4 | Is MCU firmware below 319? | Suspend | dev-research | **Resolved.** The kernel warning is printed only below 319, and `mcu_powersave` was 0. Exact integer was not logged. Button codes are not shown to depend on it. Suspend stays with RELIABILITY. Update via Armoury Crate / MyASUS on Windows before chasing suspend bugs. |
| OQ-5 | Physical placement | Docs | Daniel | **Resolved.** CC left, AC right, M1/M2 back grips. ASUS RC71L manual. |
| OQ-6 | Is AC double tap acceptable for session switch (adds 250 ms to every AC tap), or menu only? | Spec 02 | dev-lead | Open |
| OQ-7 | Axis → mouse wheel in IP 0.84? | Δ4 | dev-research | **Resolved.** Notched `WheelUp`/`WheelDown` only, via an axis direction. Not analogue. `mouse: wheel:` is used upstream but is not in the 0.84 schema. |
| OQ-8 | Volume rocker while InputPlumber grabs N-KEY. It is not in the `50-rog_ally.yaml` include list. | AC 16 | Press test | Open |
| OQ-9 | Layer namespaces of Omarchy menus for the layer-scoped B bind. | Δ5 | dev-lead | Open |
| OQ-10 | Show/hide signal from `omarchy-toggle-desktop-keyboard` without polling. | Δ6 show path | TOUCH owner | Open for the show signal. The **exit** path is specified (§6): watch the process. |
| OQ-11 | A desktop screenshot chord on the pad, or menu only? | §7 | dev-ux/dev-lead | Open. Not a hold-only route either way. |
| OQ-12 | Is Steam menu → Exit game enough for a frozen game? | §7 | Hardware test | Open. A kill macro is not in this spec. |
| OQ-13 | Swap and full screen have no paddle route. Menu only, or extra Ally binds? | §8.2 | dev-lead | Open |
| OQ-14 | Gyro source and Steam visibility? | §9 | dev-research | **Resolved for capability.** `bmi323-imu` is present and is a legal IP 0.84 source. Steam sees motion only on `ds5-edge` / DualSense / `deck-uhid`, not on Xbox Elite. Mount matrix and a real Steam client are untested. |
| OQ-15 | Why is `asusd` running? | Power ownership | dev-research | **Resolved.** asusctl was installed on this unit; its udev rule starts `asusd` on ROG DMI. The `rog-ally.sh` skip does not stop that. It writes the platform profile. Recommendation: keep asusctl off the RC71L (D6, C11). |
| OQ-16 | Ally X / Legion Go / Deck / Claw role mapping | Secondary devices | Later | Open |
| OQ-17 | Do M1/M2 events arrive on kernel `7.2.15-2-omarchy` without `hid-asus-ally`? | Δ7, AC 15 | Press test | Open. Dependency, not a chosen kernel. Options if they do not arrive: an opt-in handheld kernel that already carries the driver, a DKMS package of `hid-asus-ally` (GPL-2.0-or-later), or a small hidraw remap of the MCU paddle slots. HHD does not need the driver; InputPlumber's Ally driver does. |

## Appendix A · Profile sketch

Shipped files stay as they are, except the new `gaming.yaml` in §12.1. Desktop Δ7, once the press test names the left grip:

```yaml
# desktop.yaml — Δ7. Bind the capability the press test shows is the left grip.
  - name: Left grip Super
    source_event: { gamepad: { button: LeftPaddle1 } }   # replace LeftPaddle1 if OQ-1 says the left grip is the other name
    target_events: [ { keyboard: KeyLeftMeta } ]          # was KeyLeftShift on LeftPaddle1
# Δ4 notched scroll — one mapping per direction, WheelUp/WheelDown, not an analogue axis
```

```yaml
# profiles/osk.yaml — Δ6, copy of desktop.yaml with:
  - name: East
    source_event: { gamepad: { button: East } }
    target_events: [ { keyboard: KeyBackspace } ]
  - name: West
    source_event: { gamepad: { button: West } }
    target_events: [ { keyboard: KeySpace } ]
```

| Bridge change | Detail |
|---|---|
| `MODES` | Add `gaming` and `osk`. Optional presets stay out of `MODES` until a menu row selects one. Unknown `gaming` on an old binary is §12.3, not a hard dependency on a new package. |
| Key-ups | §8.1, before every load, lock, suspend and restart. |
| Gaming entry | `run_gaming` calls `omarchy-hw-rog-ally-input gaming` instead of `gamepad`, with the 1.0.3-1 fallback. |
| Overlay | `omarchy_overlay`: spec 04 entry point, else the target QAM event. |
| OSK | On show, remember the current profile and load `osk` only from `desktop`. On hide, stop, or process death, restore the remembered profile. |
| AC double tap | Only if OQ-6 is approved. Not the only session-switch route. |

Hyprland, RC71L-gated, same early-return as `default/hypr/rog-ally-touch.lua` (`if not o.shell_succeeds("omarchy-hw-rog-ally") then return end`). Proposed file `default/hypr/rog-ally-input.lua`. The touch shortcut itself lives in `utilities.lua` on `feat/ally-touch-20261111`, not in that display file.

```lua
if not o.shell_succeeds("omarchy-hw-rog-ally") then return end
-- Δ8. Polite close, no confirmation. Unbound on every other machine.
o.bind("SUPER + mouse:274", "Close window", hl.dsp.window.close())
-- Δ9. Owns CTRL+ALT+DELETE on RC71L. tiling.lua must not also bind it here.
-- Dispatcher confirms, then runs omarchy-hyprland-window-close-all.
-- No InputPlumber check: the confirm is installed for the whole session.
-- Δ5. mouse:273 closes the menu only while an Omarchy menu layer is open.
```

## Appendix B · Alternatives note (HHD)

[HHD](https://github.com/hhd-dev/hhd) supports the RC71L (hidraw `0b05:1abe`, Xbox pad `045e:028e`): QAM tap → Steam QAM, double tap → HHD overlay, AC hold 0.4 s → MCU mouse mode, `QAM_MULTI_PRESS_DELAY` 0.2 s. It also does TDP/fan/RGB in its overlay, and it programs paddles over hidraw without `hid-asus-ally`. Not chosen: it overlaps POWER's single writer, and the shipped branch already integrates InputPlumber (also Bazzite 44+, CachyOS Handheld, SteamOS, ChimeraOS). Do not run both. They grab the same evdev nodes.

Mainline `hid-asus` Ally support beyond the key map (remap, `gamepad_mode`, deadzones) is still a patch set. Revisit paddle remap when it merges, or via OQ-17 if the press test shows no paddle events.

The comparison table is §5.4.

## Appendix C · Other handhelds (role mapping, unverified)

| Role | RC71L | Ally X / Xbox Ally | Legion Go | Steam Deck | MSI Claw |
|---|---|---|---|---|---|
| Home (CC role) | CC, **left** | CC / Xbox | Legion L | Steam | (TBC) |
| Quick (AC role) | AC, **right** | AC | Legion R | QAM (…) | (TBC) |
| Real firmware long on the quick button | Yes (F17) | TBC | TBC | Yes (native chords) | TBC |
| Rear grips | 2 | 2 | 2 + extra | 4 | 2 |
| Trackpad | No | No | Yes | 2 | No |

Detection today is RC71L-only (`omarchy-hw-rog-ally`). Do not broaden it to other models.

## Sources

Repo: [`feat/ally-input-20261111`](https://github.com/DanielJBurbridge/omarchy/tree/feat/ally-input-20261111) at `95a0992ce5`, [`feat/ally-parity-integration-20261111`](https://github.com/DanielJBurbridge/omarchy/tree/feat/ally-parity-integration-20261111) at `3f800d118`, PR #3 [`cursor/rog-ally-rc71l-3178`](https://github.com/DanielJBurbridge/omarchy/pull/3), [`feat/ally-touch-20261111`](https://github.com/DanielJBurbridge/omarchy/tree/feat/ally-touch-20261111), [`feat/ally-session-20261111`](https://github.com/DanielJBurbridge/omarchy/tree/feat/ally-session-20261111), [`feat/ally-display-20261111`](https://github.com/DanielJBurbridge/omarchy/tree/feat/ally-display-20261111) (`default/hypr/rog-ally-touch.lua`).
External: [InputPlumber](https://github.com/ShadowBlip/InputPlumber) `aly1` and `50-rog_ally.yaml` · [Arch inputplumber 0.84.0](https://archlinux.org/packages/extra/x86_64/inputplumber/) · [ASUS RC71L manual](https://dlcdnets.asus.com/pub/ASUS/IOTHMD/RC71L/0421_ID25271_NR2301L_V5_A.pdf?model=ROG+Ally+%282023%29) · [SteamOS #2853](https://github.com/ValveSoftware/SteamOS/issues/2853) · [Bazzite ASUS wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/ASUS_ROG_Ally/) · [HHD](https://github.com/hhd-dev/hhd) · [Steam Deck shortcuts](https://www.pcgamingwiki.com/wiki/Steam_Deck) · [mainline hid-asus Ally key map](https://github.com/torvalds/linux/blob/master/drivers/hid/hid-asus.c).
