# 04 · Quick-access overlay

Status: draft, 12 Nov 2026 (AWST). Owner: dev-ux. Depends on: [01](01-controller-button-map.md) (Δ1, Δ3, bridge), [02](02-mode-switch-and-dock.md) (session switch, D8 targets), [03](03-first-boot-and-install.md) (packages). Hardware notes: `docs/handheld/research/` on PR #20 (`cursor/handheld-research-docs-4e81`), not on this branch.

**Power (lead ruling, 12 Nov 2026).** On RC71L, `power-profiles-daemon` is **masked** (it is D-Bus-activatable, so disable is not enough). The owner is our capped writer, backlog **#10** (`omarchy-ally-power-helper`: root, fixed verbs, 25 W on battery and 30 W on AC). Its Steam session-bus shim is backlog **#11** (public `com.steampowered.SteamOSManager1` on the session bus: `TdpLimit1` and `PerformanceProfile1`), not `steamos-manager`. Stock and patched `steamos-manager` stay not installed. TDP rows are read-only until #10 lands, and live after it. These backlog numbers are not GitHub pull requests #10 and #11.

## 0. Decisions in one table

| # | Decision | Source |
|---|---|---|
| D1 | One overlay, **two renderers**: on desktop it is an `omarchy-shell` panel (`omarchy.quick`); in gaming it is a small X11 client inside Gamescope tagged `GAMESCOPE_EXTERNAL_OVERLAY`. Both read one backend CLI (`omarchy-quick`, §5), so contents and rules cannot drift. | P2, §6 |
| D2 | Open: **AC long (`F17`, `QuickAccess2`) in gaming**, **CC tap on desktop** (spec 01 Δ1), and an Omarchy menu entry (both modes reach it without a long press). Spec 01 revision 1 already assigns AC long to this overlay (Δ3) and keeps Steam's own screenshot path. Row 14 is this overlay's screenshot control. | Brief; spec 01 Δ3; D9 of spec 02 |
| D3 | Gaming fallback is **Steam QAM**: if the overlay client is missing, crashed, not ready, or a game is starting, AC long sends QAM instead. | Brief, red review |
| D4 | Overlay input arrives through **InputPlumber intercept** (`omarchy-hw-rog-ally-input intercept all`, restore `none` on close), never through X/Wayland focus. The game keeps focus; the overlay never steals it. | Baseline bridge, red review |
| D5 | Prompts and the overlay **ignore controller input for 500 ms** after appearing, and the initial focus is the safe item (Close / no change). | Red review |
| D6 | On RC71L, **power-profiles-daemon is masked** and backlog **#10** owns power. Backlog **#11** is the Steam session-bus shim, not `steamos-manager`. TDP rows go live once #10 lands and are read-only until then. No ryzenadj, no PowerStation, no HHD, and **asusd must not write profile or PPT** while the writer can. Charge limit is not a #10 verb. | TDP decision, 12 Nov 2026; `docs/rog-ally-power.md` |
| D7 | Rows that the device or kernel cannot do (fan curves, RGB, haptics on the stock kernel) are **hidden or read-only with a reason**, never a dead control. | `power.py` `UNAVAILABLE`, parity matrix |
| D8 | Decky is **not** a dependency. Optional later: a Decky plugin that calls the same `omarchy-quick` CLI. | `bin/omarchy-setup-gaming-decky` |

## 1. Baseline: what is already built

Checked on `feat/ally-parity-integration-20261111` (`9f8b3572f`) and the `feat/ally-*-20261111` branch that contains the file.

| Piece | Path (branch) | Use here |
|---|---|---|
| Handheld power panel | `shell/plugins/panels/power/Handheld.qml`, `Panel.qml` (`feat/ally-power-20261111`): controller-navigable (d-pad up/down selects the control, left/right changes the action, A applies), rows profile / tdp / boost / governor / gpu-level / gpu-clock / charge, “Applying; waiting for readback…”, conflict line. The footer still says “SteamOS Manager”. | **Navigation model reused** for every row. The source line changes when #10 is the owner; it does not keep naming SteamOS Manager. |
| Power client | `default/handheld/power.py`, `bin/omarchy-power-ally status` (`feat/ally-power-20261111`). JSON keys: `controls`, `unavailable`, `conflicts`, `source`, and `backend` (`"SteamOS Manager"`). `CONFLICTS` is `power-profiles-daemon`, `powerstation`, `hhd*`, `adjustor`, `asusd`, `tlp`, `auto-cpufreq`, `tuned`, plus GameMode (`gamemoded` when session-bus name `com.feralinteractive.GameMode` has an owner). Activation of unchanged `steamos-manager` is refused. | Today's client. #10 replaces it as the writer. The overlay does not call Manager and does not install it. |
| Profile helpers | `bin/omarchy-powerprofiles-list` and `bin/omarchy-powerprofiles-set` (this branch, with the Ally opt-in on `feat/ally-power-20261111`). Arguments: `autodetect`, `ac` or `battery`, then `power-saver`, `balanced` or `performance`. If `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/ally-power/enabled` exists on RC71L, `power-saver` maps to `quiet` and the command calls `omarchy-power-ally`. Otherwise it calls `powerprofilesctl`. | Until #10 lands and masks PPD, the profile row can still show this PPD path. After the mask, the row calls #10, not PPD and not Manager. |
| Power hold | `docs/rog-ally-power.md` (`feat/ally-power-20261111`): “Do not install unchanged `steamos-manager 26.4.1-3`”. Ordinary machines keep PPD. `docs/rog-ally-power-authority.md` recommends keeping that denial and generic PPD for now. | Superseded on RC71L by D6: PPD is masked, #10 owns power, #11 is the shim. The do-not-install line for `steamos-manager` stays. |
| Input bridge | `bin/omarchy-hw-rog-ally-input` (`feat/ally-input-20261111`): `status`, `desktop`, `gamepad`, `dualsense`, `toggle`, `capabilities`, `intercept none` or `intercept all`, `watch`. Help: “Profiles clear held target inputs on change. Switching target disconnects it.” Status JSON `InterceptMode` is `0` for `none` and `2` for `all`. | Overlay input + controller rows. |
| Gaming session | `bin/omarchy-setup-gaming-session` (`feat/ally-session-20261111`): `display` takes `native`, `720p`, `900p` or `1080p`, then an optional fps (`0`, `30`, `40`, `45`, `60`, `90`, `120`) and filter (`linear`, `nearest`, `fsr`, `nis`). `overlay on` or `overlay off` is mangoapp for the **next** gaming session and takes no preset. `docs/rog-ally-gaming-session.md`: no layer-shell panels in gaming. Gamescope package cited there is 3.17.0-1. | FPS/render rows; why the shell can't render in gaming. |
| Performance HUD | `bin/omarchy-launch-gaming-overlay` (`feat/ally-games-performance-20261111`): `--preset compact` or `detailed`, `--fps` of `0`, `30`, `40`, `60`, `90` or `120` (no 45), and `--gamescope`, which runs mangoapp. There is no `--mangoapp` flag. | “Performance HUD” toggle. Presets live here, not on `overlay on`. |
| Display | `bin/omarchy-display-rog-ally` (`feat/ally-display-20261111`): `native [RATE]`, dock profiles, Hyprland monitor modes. | Desktop refresh row (`native 60`, `native 120`). |
| Desktop panels | `shell/plugins/panels/audio` (`omarchy.audio`), `bluetooth` (`omarchy.bluetooth`), `network` (`omarchy.network`), `monitor` (`omarchy.monitor`), `power` (`omarchy.power`) on this branch. | Deep links (“More…”). |
| Media keys | `default/hypr/bindings/media.lua`: `omarchy-audio-output-volume`, `omarchy-brightness-display`. | Volume / brightness rows (desktop). |
| Bluetooth power | `bin/omarchy-bluetooth-power` (this branch): `on`, `off`, `toggle`, `is-on`. A plain `bluetoothctl power on` fails while the rfkill soft block is set; every Omarchy path goes through this command. | Bluetooth row. |
| Decky | `bin/omarchy-setup-gaming-decky` (`feat/ally-games-performance-20261111`): explicit `--allow-root-plugins`, “Keep plugin power/input writers disabled”. | D8. |
| Session switch | `bin/omarchy-launch-gaming-desktop` and `bin/omarchy-launch-gaming-session` (`feat/ally-session-20261111`). The launcher takes no arguments today. `--confirm` is spec 02 §4's proposal. | Row 15. |

## 2. How others do it

| | Bazzite 44 | CachyOS Handheld | SteamOS 3.8 | ChimeraOS |
|---|---|---|---|---|
| Overlay | Steam QAM; OGUI on Armoury hold | Steam QAM + Decky | Steam QAM | Steam QAM + OGUI (`steam-plus`) |
| TDP | steamos-manager in QAM (Ally listed) / PowerStation elsewhere ([GoL](https://www.gamingonlinux.com/2026/08/bazzite-linux-44-for-handhelds-finally-launches-with-some-massive-upgrades/)) | steamos-manager ([PKGBUILD](https://github.com/CachyOS/CachyOS-PKGBUILDS/tree/master/handheld/steamos-manager)) | steamos-manager, RC71L `tdp_limit.method="firmware_attribute"` ([rog-ally-series.toml](https://gitlab.steamos.cloud/holo/steamos-manager/-/blob/master/data/devices/rog-ally-series.toml)) | PowerStation / Decky |
| Rule | “Run only one TDP controller” ([wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/)) | — | Steam hides unsupported settings | — |
| Fan | Some devices lost control in 44 | Deck only | Deck only (`jupiter-fan-control`) | none |
| RGB | Steam QAM RGB (OGC kernel `hid-asus-ally`) | LED udev rule | needs driver | Decky |
| Overlay over game | Steam overlay / OGUI via Gamescope atoms | Decky inside Steam | Steam | OGUI via InputPlumber intercept ([OGUI #332](https://github.com/ShadowBlip/OpenGamepadUI/pull/332)) |

Take: everyone uses Steam QAM in gaming and one power owner. Omarchy adds a themed overlay with the same one-owner rule. The owner on RC71L is backlog #10, not `steamos-manager`. QAM stays the fallback.

## 3. Opening and closing

| Trigger | Mode | Action | Fallback |
|---|---|---|---|
| AC long (`F17` → `QuickAccess2`) | Gaming | Open overlay client | Steam QAM (InputPlumber emits `QuickAccess` / Guide+South on the Xbox target) when D3 applies |
| CC tap (`Guide`) | Desktop | `omarchy-shell shell toggle omarchy.quick` (Δ1) | Power panel `omarchy.power` (baseline) if `omarchy.quick` is absent |
| Omarchy menu → **Quick settings** | Desktop | Same as CC tap | — |
| Steam → Non-Steam shortcut “Omarchy Quick Settings” | Gaming | Opens the overlay client (menu path; no long press) | — |
| Same trigger again, **B**, or **CC tap** (gaming) | Both | Close | — |
| Game launch begins / Steam overlay opens | Gaming | Overlay closes itself (no prompt) | — |

**D3 “game is starting”** = a new game process appeared in the gaming scope within the last 10 s (spec 02 OQ-9 detector). During that window AC long goes straight to QAM.

## 4. Contents

Order is fixed (most-used first). **RC71L today** = this tree plus the Ally branches as they are: Omarchy kernel, no `hid-asus-ally`, PPD still the running profile owner, #10 not installed, `steamos-manager` not installed.

| # | Row | Control | Backend | Gaming | Desktop | RC71L today |
|---|---|---|---|---|---|---|
| 1 | Performance profile | Quiet · Balanced · Performance | #10 once it lands (PPD masked). Until then, `omarchy-powerprofiles-set` while PPD is still running. | ✓ | ✓ | ✓ via PPD, until #10 masks it |
| 2 | TDP (sustained W) | Steps from firmware min/max, capped 25 W battery / 30 W AC | #10 `apply` (SPL; root derives SPPT/FPPT). Not `omarchy-power-ally` against Manager. | ✓ after #10 | ✓ after #10 | **Read-only** until #10: “TDP waits for the capped power writer” |
| 3 | Fan | Read-only: “Firmware (follows profile)” | `asus-wmi` platform profile | ✓ | ✓ | Read-only (custom curves fail, -19) |
| 4 | Brightness | Slider, 5 % steps | `omarchy-brightness-display` (backlight via logind in gaming) | ✓ | ✓ | ✓ |
| 5 | Volume / mute | Slider + mute | `omarchy-audio-output-volume` (wpctl) | ✓ | ✓ | ✓ |
| 6 | Frame limit | Off · 30 · 40 · 45 · 60 · 90 · 120 | Gaming: Steam QAM's own limiter (link) plus `omarchy-setup-gaming-session display` fps for the **next** session (`0` is off). Desktop: n/a | ✓ (labelled “next session”) | — | ✓ |
| 7 | Refresh rate | 60 · 120 Hz | Desktop: `omarchy-display-rog-ally native 60` or `native 120`. Gaming: Steam QAM | link | ✓ | ✓ desktop |
| 8 | Performance HUD | Off · Compact · Detailed | Next gaming session: `omarchy-setup-gaming-session overlay on` or `off` (no preset argument). Presets: `omarchy-launch-gaming-overlay --preset compact` or `detailed`. | ✓ next session | per-game (`omarchy-launch-gaming-overlay`) | ✓ if MangoHud is installed |
| 9 | Battery charge limit | Off · 80 % | Not a #10 verb. Stays read-only until OQ-5's later owner (a #11 `BatteryChargeLimit1` slice, or POWER's polkit helper). Not `steamos-manager`. | ✓ once that owner exists | ✓ once that owner exists | **Read-only**: “Charge limit is not in the capped writer yet” |
| 10 | Wi-Fi | On/off + current SSID | NetworkManager (`nmcli radio wifi`) | ✓ | ✓ + “More…” → `omarchy.network` | ✓ |
| 11 | Bluetooth | On/off + connected count | On/off: `omarchy-bluetooth-power`. Count from BlueZ. | ✓ | ✓ + “More…” → `omarchy.bluetooth` | ✓ |
| 12 | Controller | Desktop/gamepad/DualSense (desktop only); presets: Standard · One-handed L · One-handed R · Paddles = A/B | `omarchy-hw-rog-ally-input` + preset profiles (Δ-Q2) | presets only, §7 | ✓ | Presets need the companion; paddles need `hid-asus-ally` |
| 13 | RGB | Off · Colour · Brightness | `/sys/class/leds/*` (driver) | hidden | hidden | **Hidden** (no `hid-asus-ally`; brightness firmware-locked) |
| 14 | Screenshot | Button | Gaming: Steam screenshot (InputPlumber `Screenshot`); desktop: `omarchy-capture-screenshot` | ✓ | ✓ | ✓ (spec 01 already left AC long on this overlay; this row is the control) |
| 15 | Switch mode | “Switch to Desktop” / “Switch to Gaming” | `omarchy-launch-gaming-desktop` / `omarchy-launch-gaming-session` (no arguments today; `--confirm` is spec 02 §4) | ✓ | ✓ | ✓ |
| 16 | Accessibility | Toggles (§4.1) | various | some | ✓ | partial |

Each row shows: label, current value, unit, and on failure the backend's `reason` text (the same idea as `power.py` `UNAVAILABLE`). Writes show “Applying…” until readback matches (Handheld.qml); a timeout (3 s) restores the displayed value and shows the error.

### 4.1 Accessibility quick toggles (from `docs/handheld/research/accessibility.md`, PR #20)

| Toggle | Desktop backend | Gaming | Persist |
|---|---|---|---|
| Reduce motion | Hyprland `animations:enabled = false` | Link: Steam → Accessibility (manual) | Yes |
| Colour filter: Off · Greyscale · Invert · Deuteranopia · Protanopia · Tritanopia | Hyprland `decoration:screen_shader` | Not available (Hyprland shaders don't reach Gamescope) — row shows why | Yes |
| Mono audio | PipeWire `filter.smart` loopback `audio.position=[MONO]` | ✓ (PipeWire is shared) | Yes |
| Text size | Omarchy scaling (one knob) | Link: Steam UI scale | Yes |
| High contrast | Switch to the high-contrast Omarchy theme (when it exists) | Link: Steam high contrast | Yes |
| Screen reader | Start/stop Orca (desktop limits documented) | Steam reader if present with steamos-manager (unverified) | No |
| Haptics strength | `gamepad_vibration_intensity` (`hid-asus-ally`) | same | hidden on stock kernel |

## 5. Backend contract (`omarchy-quick`, Δ-Q1)

| Command | Behaviour |
|---|---|
| `omarchy-quick status --json` | One JSON object: per row `available`, `value`, `choices` / `min` / `max`, `reason`, `mode` (`gaming` or `desktop`). Aggregates #10 status once it exists, plus wpctl, NetworkManager, BlueZ and bridge status. Until #10 exists, profile may still come from PPD and TDP/charge report unavailable. Event-driven refresh (D-Bus signals); no polling loop. |
| `omarchy-quick set <row> <value>` | Validates against the last status, calls the owning CLI, waits for readback (≤ 3 s), exits non-zero with `reason` on mismatch. Never writes sysfs itself. Never calls `steamos-manager`. |
| Unknown row/value | Error, no change (red team: unknown ⇒ safe). |
| Conflicts | If any competing writer is active, rows 1, 2 and 9 are read-only with “Competing power writer: …”. The set matches `power.py`: `power-profiles-daemon` (must be masked on RC71L), `powerstation`, `hhd*`, `adjustor`, `asusd`, `tlp`, `auto-cpufreq`, `tuned`, and GameMode (`gamemoded`). #10 refuses to write in that case. |
| Caps | #10 rejects a TDP above 25 W on battery or 30 W on AC, and writes nothing. The row shows the refusal. |

## 6. Rendering

| | Desktop (Hyprland) | Gaming (Gamescope) |
|---|---|---|
| Host | `omarchy-shell` panel `omarchy.quick` (layer-shell, right edge, full height, 420 px at scale 1.5). Toggle is `omarchy-shell shell toggle <id>`, the same form as `omarchy.menu` and `omarchy.power`. | `omarchy-quick-overlay`: small X11 client started by the gaming scope (owned PID, like the power-button helper) |
| Stacking | Normal Omarchy panel | `GAMESCOPE_EXTERNAL_OVERLAY` atom, z-position above game, below Steam overlay ([gamescope #288](https://github.com/ValveSoftware/gamescope/issues/288), [steamcompmgr z-order](https://deepwiki.com/bazzite-org/gamescope/2.2-x11-window-manager-(steamcompmgr))). Whether this draws above a fullscreen game with no focus change is device test T1, not an open question. |
| Focus | Panel keyboard focus (Hyprland) | **None**. Does not set `STEAM_OVERLAY` or `STEAM_INPUT_FOCUS`; input via InputPlumber intercept (D4). Game keeps X focus. |
| Touch | Yes | No (v1). Touch keeps going to the game/Steam (OQ-2). |
| Theme | Omarchy `Style` (current theme colours, font, icons) | Same theme files (`~/.local/state/omarchy/current/theme`) rendered by the client; same layout grid |
| Not running | CC tap opens `omarchy.power` | AC long ⇒ Steam QAM |

Why not `STEAM_OVERLAY` + `STEAM_INPUT_FOCUS`: it competes with Steam's own overlay and needs Steam-QAM dismissal tricks (see [loadout notes](https://github.com/srsholmes/loadout/blob/main/docs/overlay-gamescope-integration.md)); it would steal focus from the game. External overlay + intercept avoids both.

## 7. Controller navigation and input rules

| Input (overlay open) | Action |
|---|---|
| D-pad up/down / left stick | Move between rows |
| D-pad left/right | Change value (sliders step; choices cycle) — **applies on A**, not on move, for rows 1, 2, 9, 12, 15 |
| A | Apply / toggle |
| B | Close (or back from a sub-page) |
| X | Reset row to its value when the overlay opened |
| LB / RB | Previous / next section (Performance · Display · Audio · Connections · Controller · Accessibility) |
| Y | “More…” deep link (desktop only) |

| Rule | Spec |
|---|---|
| Arm delay | Ignore all controller input for **500 ms** after the overlay or any prompt appears (the AC long release must not select anything). |
| Safe focus | Opens on row 1 with no pending change; prompts focus **Cancel**. |
| Intercept on | 1) send key/button-up for everything held on the current target, 2) `intercept all`, 3) wait until `omarchy-hw-rog-ally-input status` reports `InterceptMode` `2` (≤ 500 ms), 4) show. Failure ⇒ don't show; send QAM instead. |
| Intercept off | On close, crash, or 30 s idle: send ups, `intercept none`, confirm `InterceptMode` `0`. The client's systemd unit has `ExecStopPost=omarchy-hw-rog-ally-input intercept none` so a killed client never leaves the pad captured. |
| IP killed while open | Overlay closes; firmware pad returns to Steam (spec 02 §8). |
| Profile change (row 12) | Same target only (presets): ups → load profile → wait ready → done; on failure **atomic fallback** to `gamepad` (gaming) / `desktop` (desktop). Target change (desktop, gamepad or DualSense) is **desktop only** and refused in gaming while a game runs (“switching target disconnects the controller”). |
| Session switch (row 15) | Confirmation sheet (spec 02 §4), Cancel focused, 500 ms arm delay. Gaming → Desktop also warns “Your game will close” when a game is running. |
| No hold-only action | Every row is tap-driven; long press not used inside the overlay. |
| Lock | Desktop locked ⇒ CC tap does nothing (bridge already fails closed, spec 01 P6). While spec 03 ships handheld `desktop-lock` off, the desktop is not locked, so CC tap still opens the overlay. |

## 8. User flows

| # | Flow | Steps |
|---|---|---|
| F1 | Drop power mid-game | AC long → (500 ms) → Performance profile → left to Quiet → A → readback → B. Game never lost focus. After #10, this write goes to the capped writer with PPD masked. |
| F2 | Client crashed | AC long → QAM opens (fallback) → hub Status later shows the crash. |
| F3 | Desktop brightness | CC tap → Display → right → A → CC tap closes. |
| F4 | One-handed preset in game | AC long → Controller → One-handed L → A → key-ups, profile loads → B. |
| F5 | TDP before #10 | AC long → TDP row shows “Unavailable — TDP waits for the capped power writer” → Y not offered in gaming. After #10, the same row sets watts inside the 25 W / 30 W cap. |
| F6 | Switch to desktop | AC long → Switch to Desktop → sheet (Cancel focused) → Switch → A → spec 02 flow, then spec 03's lock choke point (skipped while handheld `desktop-lock` is off). |
| F7 | asusd or PPD running | Overlay opens with Performance rows read-only: “Competing power writer: asusd” (or `power-profiles-daemon` if it was not masked). |

## 9. Acceptance criteria

1. AC long in gaming opens the overlay within 300 ms when the client is ready; otherwise Steam QAM opens within 300 ms.
2. CC tap on desktop toggles `omarchy.quick`; with `omarchy.quick` absent it opens `omarchy.power`.
3. Both modes reach the overlay from a menu path without any long press.
4. Input arriving within 500 ms of the overlay or a prompt appearing has no effect (scripted press at 100 ms and 600 ms).
5. The overlay opens with no pending change and prompts open with Cancel focused.
6. While open in gaming, the game window keeps Gamescope input focus (`xprop` / gamescope debug) and receives no controller events; after close it receives them again with no stuck button.
7. Killing the overlay client with SIGKILL while open restores `InterceptMode` `0` within 1 s (`omarchy-hw-rog-ally-input status`).
8. Killing InputPlumber while open closes the overlay and Steam sees the firmware pad.
9. If AC long is pressed within 10 s of a game process starting, QAM opens instead of the overlay.
10. Rows 1, 2 and 9 are read-only, and name the writer, whenever `power-profiles-daemon`, `powerstation`, `hhd`, `adjustor`, `asusd`, `tlp`, `auto-cpufreq`, `tuned` or GameMode (`gamemoded`) is active. On RC71L, once #10 is set up, `power-profiles-daemon` is masked.
11. Every write shows “Applying…” and is reported done only after readback; a forced mismatch shows the error and the old value within 3 s.
12. Unsupported rows on the stock RC71L kernel (RGB, haptics) are hidden. Until #10 is installed, the TDP row is read-only and its reason names that writer, not `steamos-manager`. Charge limit stays read-only, and says it is not in the capped writer, until OQ-5's later owner exists. Installing #10 does not by itself enable the charge row.
13. A preset change in gaming sends key-ups first (held-A test: no stuck A after the change) and falls back to `gamepad` on load failure.
14. A target change is refused in gaming while a game runs, with the reason shown.
15. “Switch to Desktop” from the overlay goes through spec 02's confirmation and spec 03's lock choke point (the choke point skips the lock while handheld `desktop-lock` is off).
16. No row writes sysfs directly; `omarchy-quick` calls only the owning CLIs (code review + strace). It does not exec `steamos-manager` or `omarchy-power-ally` against that daemon.
17. Colours and fonts match the active theme under `~/.local/state/omarchy/current/theme` in both renderers (theme switch reflected on next open).
18. Boot race: AC long before the client is up (first 10 s of gaming) opens QAM, not nothing.
19. After #10 lands, a TDP set inside 25 W on battery and 30 W on AC completes on readback. A value above the cap, a non-integer, or a set while a conflict is active is rejected and nothing is written.

## Device tests

Scheduled with the backlog #11 TDP spike deploy (the deploy that checks whether Steam's QAM shows a TDP slider when a non-Valve owner holds `com.steampowered.SteamOSManager1` on the session bus inside our Gamescope session).

| # | Test | Pass |
|---|---|---|
| T1 | A `GAMESCOPE_EXTERNAL_OVERLAY` window draws above fullscreen games and above Steam's library on Gamescope 3.17.0, with no focus change, on the internal panel and on an external display. | The game keeps input focus. The overlay is visible on both outputs. This was OQ-1; it is not an open design question. |

## 10. Open questions

OQ-1 moved to device test T1.

| # | Question | Owner |
|---|---|---|
| OQ-2 | Touch in the gaming overlay: `STEAM_TOUCH_CLICK_MODE` passthrough vs none. Worth it in v1? | dev-research |
| OQ-3 | Overlay client toolkit inside Gamescope (Quickshell under Xwayland vs small Qt/QML X11 app reusing `Handheld.qml`)? | dev-lead |
| OQ-4 | Brightness in gaming: does Steam's own slider fight `omarchy-brightness-display` on RC71L? | Hardware test |
| OQ-5 | Charge limit is not in #10 (`apply` is profile + SPL, plus `restore`). Later owner: a #11 `BatteryChargeLimit1` slice, or a small polkit-gated helper for `charge_control_end_threshold`? The row stays read-only until that choice ships. Not `steamos-manager`. | POWER |
| OQ-6 | Should AC long in gaming be configurable (overlay vs QAM vs screenshot)? Spec 01 revision 1 already points AC long at this overlay. | Daniel |
| OQ-7 | Live frame limit in gaming without steamos-manager: does Steam's QAM limiter work under Omarchy's Gamescope session? | Hardware test |
| OQ-8 | Decky plugin calling `omarchy-quick` (D8): worth maintaining given root plugins? | dev-lead |
| OQ-9 | Fan “mode” (asus-wmi throttle policy) as a separate row, or always tied to profile? | POWER |

## 11. Branch conflicts

| Conflict | Where | Resolution proposed |
|---|---|---|
| AC long = screenshot | Spec 01 first draft | Spec 01 revision 1 already superseded that: AC long is this overlay. Row 14 is the overlay's screenshot control. Steam's QAM and Edge shortcut remain the path spec 01 names. |
| “Armoury short invokes Steam QAM. Long switches mode only in Hyprland.” | `bin/omarchy-hw-rog-ally-input --help` on `feat/ally-input-20261111` | Gaming long now opens the overlay (needs the `gaming` profile, spec 01). |
| Experimental client targets SteamOS Manager; “retain generic PPD” | `docs/rog-ally-power.md`, `docs/rog-ally-power-authority.md`, `default/handheld/power.py` on `feat/ally-power-20261111` | D6: do not install Manager. Mask PPD on RC71L. #10 owns profile and TDP. #11 is the session-bus shim. TDP stays read-only until #10 lands. |
| `asusd` running on Daniel's unit | `docs/handheld/research/ally-hw-dump.md` (PR #20) | Conflict detection makes power rows read-only; spec 03 W7 offers to disable it. |
| Desktop CC tap = power panel | spec 01 baseline | Δ1 moves it to `omarchy.quick`; `omarchy.power` is the fallback. |
| GameMode is reported beside `power.py` `CONFLICTS` | `default/handheld/power.py` (`gamemoded` via the GameMode bus name) | Performance rows read-only while GameMode is active. |
| Ally profile opt-in calls `omarchy-power-ally` | `bin/omarchy-powerprofiles-set` when `omarchy/ally-power/enabled` exists | That opt-in is the experimental Manager path. After D6 it is not the RC71L owner; #10 is. |

## Sources

- This branch: `bin/omarchy-powerprofiles-list`, `bin/omarchy-powerprofiles-set` (PPD path), `default/hypr/bindings/media.lua`, `bin/omarchy-audio-output-volume`, `bin/omarchy-brightness-display`, `bin/omarchy-bluetooth-power`, `bin/omarchy-capture-screenshot`, `shell/plugins/panels/{audio,bluetooth,network,monitor,power}/manifest.json`, `docs/omarchy-shell.md`, `docs/theming.md` (`~/.local/state/omarchy/current/theme`).
- `feat/ally-power-20261111`: `shell/plugins/panels/power/Handheld.qml`, `default/handheld/power.py`, `bin/omarchy-power-ally`, the Ally opt-in in `bin/omarchy-powerprofiles-set`, `docs/rog-ally-power.md`, `docs/rog-ally-power-authority.md`.
- `feat/ally-input-20261111`: `bin/omarchy-hw-rog-ally-input`, `default/rog-ally-input/bridge.py`.
- `feat/ally-session-20261111`: `bin/omarchy-setup-gaming-session`, `bin/omarchy-launch-gaming-session`, `bin/omarchy-launch-gaming-desktop`, `docs/rog-ally-gaming-session.md`.
- `feat/ally-games-performance-20261111`: `bin/omarchy-launch-gaming-overlay`, `bin/omarchy-setup-gaming-decky`.
- `feat/ally-display-20261111`: `bin/omarchy-display-rog-ally`.
- `feat/ally-recovery-20261111` and `feat/ally-parity-release-20261111`: `bin/omarchy-setup-rog-ally`.
- PR #20: `docs/handheld/research/accessibility.md`, `docs/handheld/research/parity-matrix.md`, `docs/handheld/research/ally-hw-dump.md`.
- Lead ruling, 12 Nov 2026: backlog #10 `omarchy-ally-power-helper`, backlog #11 session-bus shim. Neither name is a file in this repo yet.
- External: [gamescope #288 external overlay](https://github.com/ValveSoftware/gamescope/issues/288); [steamcompmgr z-order](https://deepwiki.com/bazzite-org/gamescope/2.2-x11-window-manager-(steamcompmgr)); [loadout Gamescope overlay notes](https://github.com/srsholmes/loadout/blob/main/docs/overlay-gamescope-integration.md); [OpenGamepadUI InputPlumber PR #332](https://github.com/ShadowBlip/OpenGamepadUI/pull/332); [steamos-manager RC71L TOML](https://gitlab.steamos.cloud/holo/steamos-manager/-/blob/master/data/devices/rog-ally-series.toml); [Bazzite handheld wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/); [GoL Bazzite 44](https://www.gamingonlinux.com/2026/08/bazzite-linux-44-for-handhelds-finally-launches-with-some-massive-upgrades/); [CachyOS steamos-manager PKGBUILD](https://github.com/CachyOS/CachyOS-PKGBUILDS/tree/master/handheld/steamos-manager).
