# 04 · Quick-access overlay

Status: draft, revision 2, 12 Nov 2026 (AWST). Owner: dev-ux. Depends on: [01](01-controller-button-map.md) (Δ1, Δ3, bridge), [02](02-mode-switch-and-dock.md) (session switch, D8 targets), [03](03-first-boot-and-install.md) (packages). Hardware notes: `docs/handheld/research/` on this branch. Power ownership: [tdp-decision-review.md](tdp-decision-review.md). Gaming renderer: [PR #31](https://github.com/DanielJBurbridge/omarchy/pull/31).

**Power (lead ruling, 12 Nov 2026).** `power-profiles-daemon` is D-Bus-activatable, so disable is not enough. It is **masked** only when the handheld variant (`omarchy-hw-rog-ally` and `omarchy-gaming-session`) and backlog **#10 (power writer)** are both installed. Not on every RC71L, and not on the handheld pair alone. The same gate is [PR #33](https://github.com/DanielJBurbridge/omarchy/pull/33). The writer's setup records that it masked PPD and the unit state it replaced. It unmasks and restores that state when either the variant or the writer is removed, or when the device goes desktop-only. While that mask is on, Desktop Mode's profile switch calls backlog #10 (power writer), not `powerprofilesctl`. The capped TDP write is the single action in `docs/handheld/tdp-spike-findings.md` on that PR (`cursor/ally-tdp-spike-1843`, §5.1), not the `apply(profile, spl)` verb in the decision review. The Steam session-bus shim is backlog **#11 (Steam TDP shim)**, not `steamos-manager`. Stock and patched `steamos-manager` stay not installed. TDP rows are read-only until backlog #10 (power writer) lands, and live after it. See [tdp-decision-review.md](tdp-decision-review.md). No pull request or branch exists yet for backlog #10 (power writer) or backlog #11 (Steam TDP shim). PR #33 is the spike, not those tasks.

**Gaming renderer (lead ruling, 12 Nov 2026).** From [PR #31](https://github.com/DanielJBurbridge/omarchy/pull/31) (`docs/handheld/research/gamescope-external-overlay.md` on `cursor/gamescope-external-overlay-6671`). The gaming overlay is an X11 window on Gamescope's root Xwayland, with `GAMESCOPE_EXTERNAL_OVERLAY` set, drawn as an output-sized transparent buffer whose opacity is above 0. It draws above fullscreen games and does not take focus. Input comes only through InputPlumber intercept. The window itself gets no input, and `STEAM_OVERLAY` and `STEAM_INPUT_FOCUS` are never set. Gamescope paints one external overlay. While this panel is open it takes that slot from mangoapp/MangoHud. On close, and if the client dies, it gives the slot back and restores the mangoapp state from before the panel opened. The RC71L session has not been run; that check stays on device test T1.

## 0. Decisions in one table

| # | Decision | Source |
|---|---|---|
| D1 | One overlay, **two renderers**. On desktop it is an `omarchy-shell` panel (`omarchy.quick`). In gaming it is an X11 window on Gamescope's **root Xwayland** (the exported `DISPLAY`, server 0), with `GAMESCOPE_EXTERNAL_OVERLAY` non-zero, drawn as an **output-sized transparent buffer** whose `_NET_WM_WINDOW_OPACITY` is above 0. It paints above fullscreen games and does not take focus. A window on a later Xwayland is not this overlay. Both renderers read one backend CLI (`omarchy-quick`, §5). | [PR #31](https://github.com/DanielJBurbridge/omarchy/pull/31); §6 |
| D2 | Open: **AC long (`F17`, `QuickAccess2`) in gaming**, **CC tap on desktop** (spec 01 Δ1), and an Omarchy menu entry (both modes reach it without a long press). Spec 01 revision 1 already assigns AC long to this overlay (Δ3) and keeps Steam's own screenshot path. Row 14 is this overlay's screenshot control. | Brief; spec 01 Δ3; D9 of spec 02 |
| D3 | Gaming fallback is **Steam QAM**: if the overlay client is missing, crashed, not ready, or a game is starting, AC long sends QAM instead. | Brief, red review |
| D4 | Gaming input comes **only** through InputPlumber intercept (`omarchy-hw-rog-ally-input intercept all`, restore `none` on close, crash and session exit). The overlay window gets no keyboard, pointer or touch. Never set `STEAM_OVERLAY` or `STEAM_INPUT_FOCUS`. The game keeps focus. | [PR #31](https://github.com/DanielJBurbridge/omarchy/pull/31); spec 01 C8 |
| D5 | Prompts and the overlay **ignore controller input for 500 ms** after appearing, and the initial focus is the safe item (Close / no change). | Red review |
| D6 | **power-profiles-daemon is masked only when the handheld variant and backlog #10 (power writer) are both installed.** Not on every RC71L, and not on the handheld pair alone. The mask is recorded and undone when either is removed or the device goes desktop-only. While it is on, Desktop Mode's profile switch calls backlog #10 (power writer). Backlog **#11 (Steam TDP shim)** is the Steam session-bus shim, not `steamos-manager`. TDP rows go live once backlog #10 (power writer) lands and are read-only until then. No ryzenadj, no PowerStation, no HHD. **asusd stays off on RC71L; if it is running, power rows are read-only.** Charge limit is not a backlog #10 (power writer) verb. The single capped action and the burst, resume and unplug rules are §5.1, from [PR #33](https://github.com/DanielJBurbridge/omarchy/pull/33). On battery the derived SPPT stays at or below 20 W and the derived FPPT at or below 25 W. | [PR #33](https://github.com/DanielJBurbridge/omarchy/pull/33); [tdp-decision-review.md](tdp-decision-review.md) |
| D7 | Rows that the device or kernel cannot do (fan curves, RGB, haptics on the stock kernel) are **hidden or read-only with a reason**, never a dead control. | `power.py` `UNAVAILABLE`, parity matrix |
| D8 | Decky is **not** a dependency. Optional later: a Decky plugin that calls the same `omarchy-quick` CLI. | `bin/omarchy-setup-gaming-decky` |
| D9 | Gamescope paints **one** external overlay. While the panel is open it **takes that slot from mangoapp/MangoHud**. On close it gives the slot back and restores the previous mangoapp state. If the client dies, the slot and the intercept are released and mangoapp comes back. The session's `overlay on` or `overlay off` preference is not changed. | [PR #31](https://github.com/DanielJBurbridge/omarchy/pull/31); §6.1 |

## 1. Baseline: what is already built

Checked on `feat/ally-parity-integration-20261111` (`32ea89dc3`) and the `feat/ally-*-20261111` branch that contains the file.

| Piece | Path (branch) | Use here |
|---|---|---|
| Handheld power panel | `shell/plugins/panels/power/Handheld.qml`, `Panel.qml` (`feat/ally-power-20261111`): controller-navigable (d-pad up/down selects the control, left/right changes the action, A applies), rows profile / tdp / boost / governor / gpu-level / gpu-clock / charge, “Applying; waiting for readback…”, conflict line. The footer still says “SteamOS Manager”. | **Navigation model reused** for every row. The source line changes when backlog #10 (power writer) is the owner; it does not keep naming SteamOS Manager. |
| Power client | `default/handheld/power.py`, `bin/omarchy-power-ally status` (`feat/ally-power-20261111`). JSON keys: `controls`, `unavailable`, `conflicts`, `source`, and `backend` (`"SteamOS Manager"`). `CONFLICTS` is `power-profiles-daemon`, `powerstation`, `hhd*`, `adjustor`, `asusd`, `tlp`, `auto-cpufreq`, `tuned`, plus GameMode (`gamemoded` when session-bus name `com.feralinteractive.GameMode` has an owner). Activation of unchanged `steamos-manager` is refused. | Today's client. backlog #10 (power writer) replaces it as the writer. The overlay does not call Manager and does not install it. |
| Profile helpers | `bin/omarchy-powerprofiles-list` and `bin/omarchy-powerprofiles-set` (this branch, with the Ally opt-in on `feat/ally-power-20261111`). Arguments: `autodetect`, `ac` or `battery`, then `power-saver`, `balanced` or `performance`. If `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/ally-power/enabled` exists on RC71L, `power-saver` maps to `quiet` and the command calls `omarchy-power-ally`. Otherwise it calls `powerprofilesctl`. | Until the handheld variant and backlog #10 (power writer) are both installed, the profile row uses this PPD path, including a handheld pair with no writer. Once that gate masks PPD, Desktop Mode and gaming call backlog #10 (power writer), not `powerprofilesctl` and not Manager. A desktop-only RC71L keeps `powerprofilesctl`. |
| Power hold | `docs/rog-ally-power.md` (`feat/ally-power-20261111`): “Do not install unchanged `steamos-manager 26.4.1-3`”. Ordinary machines keep PPD. `docs/rog-ally-power-authority.md` recommends keeping that denial and generic PPD for now. | Superseded by D6 when the handheld variant and backlog #10 (power writer) are both installed. The pair alone keeps PPD. A desktop-only RC71L keeps PPD. backlog #11 (Steam TDP shim) is the shim. The do-not-install line for `steamos-manager` stays. |
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

Take: everyone uses Steam QAM in gaming and one power owner. Omarchy adds a themed overlay with the same one-owner rule. The owner for the handheld pair is backlog #10 (power writer), not `steamos-manager`. QAM stays the fallback.

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

Order is fixed (most-used first). **RC71L today** = this tree plus the Ally branches as they are: Omarchy kernel, no `hid-asus-ally`, PPD still the running profile owner, backlog #10 (power writer) not installed, `steamos-manager` not installed.

| # | Row | Control | Backend | Gaming | Desktop | RC71L today |
|---|---|---|---|---|---|---|
| 1 | Performance profile | Quiet · Balanced · Performance | When the mask gate is on, Desktop Mode and gaming call backlog #10 (power writer). Until then, `omarchy-powerprofiles-set` while PPD is running. The handheld pair alone, and a desktop-only RC71L, stay on PPD. | ✓ | ✓ | ✓ via PPD, until the variant and the writer are both installed |
| 2 | TDP (sustained W) | Whole watts. SPL cap 25 W battery / 30 W AC. Derived bursts stay within the firmware defaults for the source (on DC: SPPT 20 W, FPPT 25 W). | backlog #10 (power writer) `--set WATTS` (§5.1). Root derives SPPT and FPPT. Not `omarchy-power-ally` against Manager. | ✓ after backlog #10 (power writer) | ✓ after backlog #10 (power writer) | **Read-only** until backlog #10 (power writer): “TDP waits for the capped power writer” |
| 3 | Fan | Read-only: “Firmware (follows profile)” | `asus-wmi` platform profile | ✓ | ✓ | Read-only (custom curves fail, -19) |
| 4 | Brightness | Slider, 5 % steps | `omarchy-brightness-display` (backlight via logind in gaming) | ✓ | ✓ | ✓ |
| 5 | Volume / mute | Slider + mute | `omarchy-audio-output-volume` (wpctl) | ✓ | ✓ | ✓ |
| 6 | Frame limit | Off · 30 · 40 · 45 · 60 · 90 · 120 | Gaming: Steam QAM's own limiter (link) plus `omarchy-setup-gaming-session display` fps for the **next** session (`0` is off). Desktop: n/a | ✓ (labelled “next session”) | — | ✓ |
| 7 | Refresh rate | 60 · 120 Hz | Desktop: `omarchy-display-rog-ally native 60` or `native 120`. Gaming: Steam QAM | link | ✓ | ✓ desktop |
| 8 | Performance HUD | Off · Compact · Detailed | Next gaming session: `omarchy-setup-gaming-session overlay on` or `off` (no preset argument). Presets: `omarchy-launch-gaming-overlay --preset compact` or `detailed`. | ✓ next session | per-game (`omarchy-launch-gaming-overlay`) | ✓ if MangoHud is installed |
| 9 | Battery charge limit | Off · 80 % | Not a backlog #10 (power writer) verb. Stays read-only until OQ-5's later owner (a backlog #11 (Steam TDP shim) `BatteryChargeLimit1` slice, or POWER's polkit helper). Not `steamos-manager`. | ✓ once that owner exists | ✓ once that owner exists | **Read-only**: “Charge limit is not in the capped writer yet” |
| 10 | Wi-Fi | On/off + current SSID | NetworkManager (`nmcli radio wifi`) | ✓ | ✓ + “More…” → `omarchy.network` | ✓ |
| 11 | Bluetooth | On/off + connected count | On/off: `omarchy-bluetooth-power`. Count from BlueZ. | ✓ | ✓ + “More…” → `omarchy.bluetooth` | ✓ |
| 12 | Controller | Desktop/gamepad/DualSense (desktop only); presets: Standard · One-handed L · One-handed R · Paddles = A/B | `omarchy-hw-rog-ally-input` + preset profiles (Δ-Q2) | presets only, §7 | ✓ | Presets need the companion; paddles need `hid-asus-ally` |
| 13 | RGB | Off · Colour · Brightness | `/sys/class/leds/*` (driver) | hidden | hidden | **Hidden** (no `hid-asus-ally`; brightness firmware-locked) |
| 14 | Screenshot | Button | Gaming: Steam screenshot (InputPlumber `Screenshot`); desktop: `omarchy-capture-screenshot` | ✓ | ✓ | ✓ (spec 01 already left AC long on this overlay; this row is the control) |
| 15 | Switch mode | “Switch to Desktop” / “Switch to Gaming” | `omarchy-launch-gaming-desktop` / `omarchy-launch-gaming-session` (no arguments today; `--confirm` is spec 02 §4) | ✓ | ✓ | ✓ |
| 16 | Accessibility | Toggles (§4.1) | various | some | ✓ | partial |

Each row shows: label, current value, unit, and on failure the backend's `reason` text (the same idea as `power.py` `UNAVAILABLE`). Writes show “Applying…” until readback matches (Handheld.qml); a timeout (3 s) restores the displayed value and shows the error.

### 4.1 Accessibility quick toggles (from `docs/handheld/research/accessibility.md` on this branch)

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
| `omarchy-quick status --json` | One JSON object: per row `available`, `value`, `choices` / `min` / `max`, `reason`, `mode` (`gaming` or `desktop`). Aggregates backlog #10 (power writer) status once it exists, plus wpctl, NetworkManager, BlueZ and bridge status. Until backlog #10 (power writer) exists, profile may still come from PPD and TDP/charge report unavailable. Event-driven refresh (D-Bus signals); no polling loop. |
| `omarchy-quick set <row> <value>` | Validates against the last status, calls the owning CLI, waits for readback (≤ 3 s), exits non-zero with `reason` on mismatch. Never writes sysfs itself. Never calls `steamos-manager`. |
| Unknown row/value | Error, no change (red team: unknown ⇒ safe). |
| Conflicts | If any competing writer is active, rows 1, 2 and 9 are read-only with “Competing power writer: …”. The set matches `power.py`: `power-profiles-daemon` (masked only when the handheld variant and backlog #10 (power writer) are both installed; left running on a desktop-only RC71L and on the pair alone), `powerstation`, `hhd*`, `adjustor`, `asusd`, `tlp`, `auto-cpufreq`, `tuned`, and GameMode (`gamemoded`). backlog #10 (power writer) refuses `--set` and `--reassert` while PPD is active. asusd stays off on RC71L; if it is running, these rows are read-only. |
| Caps | backlog #10 (power writer) rejects a TDP above 25 W on battery or 30 W on AC, a non-canonical watt string, and a plan whose derived SPPT or FPPT would exceed the firmware default for the current source. Nothing is written. The row shows the refusal. |

### 5.1 Power authority (backlog #10 (power writer))

The capped-apply rules are [PR #33](https://github.com/DanielJBurbridge/omarchy/pull/33), `docs/handheld/tdp-spike-findings.md` on `cursor/ally-tdp-spike-1843`. That file is not on this branch. Where it differs from [tdp-decision-review.md](tdp-decision-review.md), the spike is the rule, except the battery burst ceiling in the last bullet, which is the later lead ruling.

- One polkit action, `org.omarchy.ally.set-tdp`. `allow_any=no`, `allow_inactive=no`, `allow_active=yes`. The exec path is `/usr/bin/omarchy-ally-tdp-apply` and nothing else. The caller does not pass SPPT or FPPT.
- Verbs are `--show`, `--snapshot`, `--set WATTS`, and `--reassert`. Watts are a canonical whole number (`15` is accepted; `15.5`, `1e1`, `+15`, and `015` are not). Anything else writes nothing. `--show` is unprivileged. `--set` and `--reassert` go through pkexec.
- SPL caps are 30 W on AC and 25 W on battery, also bounded by the live max and the boot-captured max. The ratio anchor for each limit is its boot-captured `default_value` when that is greater than zero, otherwise `max_value`. The stock AC table is SPL 30, SPPT 43, FPPT 53. The stock DC table is min/def/max SPL 7/15/25, SPPT 15/20/30, FPPT 15/25/35.
- `--set` rejects out of range and does not clamp. It stores the requested SPL. `--reassert` clamps that stored request into the current source and does not change the stored request.
- Resume is `--reassert`. The shim calls it on logind `PrepareForSleep(false)`, and `omarchy-ally-tdp-resume.service` calls the same verb after suspend, hibernate, hybrid-sleep, and suspend-then-hibernate. A double run is idempotent.
- Unplug is the same `--reassert`. After a 30 W AC set, the stored request stays 30 so plugging back in can restore 30/43/53.
- On battery the derived SPPT must not exceed the DC firmware default of 20 W, and the derived FPPT must not exceed 25 W. A `--set` whose plan would exceed either default is rejected and writes nothing. The spike's 25/30/35 battery tuple is not applied. `--reassert` after an unplug clamps inside those defaults and still keeps the stored AC request.

## 6. Rendering

| | Desktop (Hyprland) | Gaming (Gamescope) |
|---|---|---|
| Host | `omarchy-shell` panel `omarchy.quick` (layer-shell, right edge, full height, 420 px at scale 1.5). Toggle is `omarchy-shell shell toggle <id>`, the same form as `omarchy.menu` and `omarchy.power`. | `omarchy-quick-overlay`: X11 client on Gamescope's root Xwayland, started by the gaming scope (owned PID, like the power-button helper). Output-sized transparent buffer. The panel is drawn in one corner of that buffer. |
| Stacking | Normal Omarchy panel | `GAMESCOPE_EXTERNAL_OVERLAY` non-zero and `_NET_WM_WINDOW_OPACITY` above 0. Gamescope paints that layer above the focused game and below the Steam overlay. One slot only (D9, §6.1). The on-RC71L check of this paint path is device test T1. It has not been run. |
| Focus | Panel keyboard focus (Hyprland) | **None.** Gamescope's focus picker skips this window and does not call `XSetInputFocus` on it. The window gets no keyboard, pointer or touch. Never set `STEAM_OVERLAY` or `STEAM_INPUT_FOCUS`. Do not set `GAMESCOPE_NO_FOCUS` and expect it to be read: Gamescope 3.17.0 does not. Input is InputPlumber intercept only (D4). |
| Touch | Yes | No (v1). Touch keeps going to the game/Steam (OQ-2). |
| Theme | Omarchy `Style` (current theme colours, font, icons) | Same theme files (`~/.local/state/omarchy/current/theme`) rendered by the client; same layout grid |
| Not running | CC tap opens `omarchy.power` | AC long ⇒ Steam QAM |

Why not `STEAM_OVERLAY` + `STEAM_INPUT_FOCUS`: that path is Steam's QAM and OpenGamepadUI's overlay mode. It moves pointer and keyboard onto the overlay window, which is a focus change. Do not mix those atoms with `GAMESCOPE_EXTERNAL_OVERLAY` on this window. The two X properties are written here. Do not copy MangoHud or `gamescope-x11-client`.

### 6.1 The one external-overlay slot

Gamescope 3.17.0 paints one external overlay. A visible mangoapp holds that slot. A per-connector mangoapp is preferred over an untagged window, so a higher opacity on our window does not take the slot away from it. Hide mangoapp first.

Before the panel is shown:

1. Record whether mangoapp is visible (its process is running and its `GAMESCOPE_EXTERNAL_OVERLAY` cardinal is non-zero). The record lives outside the client, where the unit's `ExecStopPost` can read it after a kill.
2. Hide mangoapp by setting that atom to 0. Leave the process running. Do not change the session preference (`omarchy-setup-gaming-session overlay on` or `overlay off`).
3. Map our window on the root Xwayland: output-sized, cleared transparent, panel in one corner. Set `GAMESCOPE_EXTERNAL_OVERLAY` to 1 and `_NET_WM_WINDOW_OPACITY` above 0.

On close:

1. Set our overlay atom to 0 and unmap. That releases the slot.
2. Write mangoapp's atom back to the recorded value. A HUD that was visible is visible again. One that was hidden stays hidden.
3. Restore intercept `none` (§7).

If the client dies, including `SIGKILL`, the window is gone and Gamescope drops our slot. `ExecStopPost` still runs: it sets `intercept none` and restores the recorded mangoapp state. A HUD that was visible before open is visible again, and the pad is not left captured.

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
| Intercept off | On close, crash, or 30 s idle: send ups, `intercept none`, confirm `InterceptMode` `0`, and restore the recorded mangoapp state (§6.1). The client's systemd unit `ExecStopPost` does both the intercept release and the mangoapp restore, so a killed client never leaves the pad captured and never leaves a previously visible HUD hidden. |
| IP killed while open | Overlay closes; firmware pad returns to Steam (spec 02 §8). |
| Profile change (row 12) | Same target only (presets): ups → load profile → wait ready → done; on failure **atomic fallback** to `gamepad` (gaming) / `desktop` (desktop). Target change (desktop, gamepad or DualSense) is **desktop only** and refused in gaming while a game runs (“switching target disconnects the controller”). |
| Session switch (row 15) | Confirmation sheet (spec 02 §4), Cancel focused, 500 ms arm delay. Gaming → Desktop also warns “Your game will close” when a game is running. |
| No hold-only action | Every row is tap-driven; long press not used inside the overlay. |
| Lock | Desktop locked ⇒ CC tap does nothing (bridge already fails closed, spec 01 P6). While spec 03 ships handheld `default-off`, the desktop is not locked, so CC tap still opens the overlay. |

## 8. User flows

| # | Flow | Steps |
|---|---|---|
| F1 | Drop power mid-game | AC long → (500 ms) → Performance profile → left to Quiet → A → readback → B. Game never lost focus. After backlog #10 (power writer), this write goes to the capped writer with PPD masked. |
| F2 | Client crashed | Overlay dies while mangoapp had been visible → slot released, intercept back to `none`, mangoapp visible again → next AC long → QAM opens (fallback) → hub Status later shows the crash. |
| F3 | Desktop brightness | CC tap → Display → right → A → CC tap closes. |
| F4 | One-handed preset in game | AC long → Controller → One-handed L → A → key-ups, profile loads → B. |
| F5 | TDP before backlog #10 (power writer) | AC long → TDP row shows “Unavailable — TDP waits for the capped power writer” → Y not offered in gaming. After backlog #10 (power writer), the same row sets watts inside the 25 W / 30 W cap. |
| F6 | Switch to desktop | AC long → Switch to Desktop → sheet (Cancel focused) → Switch → A → spec 02 flow, then spec 03's lock choke point (skipped while the effective value is `default-off` or `explicit-off`). |
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
10. Rows 1, 2 and 9 are read-only, and name the writer, whenever `power-profiles-daemon`, `powerstation`, `hhd`, `adjustor`, `asusd`, `tlp`, `auto-cpufreq`, `tuned` or GameMode (`gamemoded`) is active. `power-profiles-daemon` is masked only when the handheld variant and backlog #10 (power writer) are both installed. A desktop-only RC71L is not masked. The handheld pair without the writer is not masked.
11. Every write shows “Applying…” and is reported done only after readback; a forced mismatch shows the error and the old value within 3 s.
12. Unsupported rows on the stock RC71L kernel (RGB, haptics) are hidden. Until backlog #10 (power writer) is installed, the TDP row is read-only and its reason names that writer, not `steamos-manager`. Charge limit stays read-only, and says it is not in the capped writer, until OQ-5's later owner exists. Installing backlog #10 (power writer) does not by itself enable the charge row.
13. A preset change in gaming sends key-ups first (held-A test: no stuck A after the change) and falls back to `gamepad` on load failure.
14. A target change is refused in gaming while a game runs, with the reason shown.
15. “Switch to Desktop” from the overlay goes through spec 02's confirmation and spec 03's lock choke point (the choke point skips the lock while handheld `desktop-lock` is off).
16. No row writes sysfs directly; `omarchy-quick` calls only the owning CLIs (code review + strace). It does not exec `steamos-manager` or `omarchy-power-ally` against that daemon.
17. Colours and fonts match the active theme under `~/.local/state/omarchy/current/theme` in both renderers (theme switch reflected on next open).
18. Boot race: AC long before the client is up (first 10 s of gaming) opens QAM, not nothing.
19. After backlog #10 (power writer) lands, a canonical TDP set inside the source cap completes on readback when the derived bursts also stay within the firmware defaults. A value above 25 W on battery or 30 W on AC, a non-canonical watt string, or a set while a conflict is active is rejected and nothing is written.
20. With mangoapp visible, opening the overlay hides mangoapp and paints this panel in the single external-overlay slot, above the fullscreen game, with no focus change. `InterceptMode` is `2`. The overlay window receives no keyboard, pointer or touch, and neither `STEAM_OVERLAY` nor `STEAM_INPUT_FOCUS` is set.
21. Closing the overlay releases the slot and restores mangoapp to the visibility it had before open. `InterceptMode` is `0`. The session's `overlay on` or `overlay off` preference is unchanged.
22. `SIGKILL` of the client, when mangoapp was visible before open, releases the slot, restores `InterceptMode` `0` within 1 s, and mangoapp is visible again.
23. A desktop-only RC71L does not mask `power-profiles-daemon`. `powerprofilesctl` works, and so do the Omarchy power menu and waybar. The handheld pair without backlog #10 (power writer) does not mask it either.
24. PPD is masked only when the handheld variant and backlog #10 (power writer) are both installed, and the previous unit state is recorded. Removing the writer, removing the variant (`omarchy-gaming-session` gone, or the device no longer `omarchy-hw-rog-ally`), or switching to desktop-only unmasks PPD and restores that recorded state.
25. While that mask is on, the Desktop Mode profile switch (`omarchy-powerprofiles-set` and the power menu) calls backlog #10 (power writer), not `powerprofilesctl`.
26. The only `allow_active=yes` action is `org.omarchy.ally.set-tdp` on `/usr/bin/omarchy-ally-tdp-apply`. `--set` takes watts and does not take SPPT or FPPT. A non-canonical watt string, a value outside the source cap, or a set while PPD is active is rejected and writes nothing.
27. On battery, the derived SPPT does not exceed 20 W and the derived FPPT does not exceed 25 W. A `--set` of 25 W on battery, which the spike would plan as 25/30/35, is rejected and writes nothing.
28. `PrepareForSleep(false)` and the resume unit both call `--reassert`. After a 30 W AC set, unplugging keeps the stored request at 30, applies a battery tuple whose SPPT is at most 20 W and whose FPPT is at most 25 W, and plugging back in restores 30/43/53.

## Device tests

Scheduled with the backlog #11 (Steam TDP shim) deploy (the check that Steam's QAM shows a TDP slider when a non-Valve owner holds `com.steampowered.SteamOSManager1` on the session bus inside our Gamescope session). See [tdp-decision-review.md](tdp-decision-review.md).

| # | Test | Pass |
|---|---|---|
| T1 | On the RC71L, in a Gamescope 3.17.0 DRM session, an output-sized `GAMESCOPE_EXTERNAL_OVERLAY` window on the root Xwayland draws above a fullscreen game and above Steam's library, with opacity above 0 and no focus change, on the internal panel and on an external display. Repeat with mangoapp visible beforehand: open takes the slot, close and a killed client give it back. | The game keeps input focus. The overlay is visible on both outputs. Mangoapp returns to the state it had. **Not yet run on the RC71L.** The design is the PR #31 source review. This row is the on-device check, not an open design question. |

## 10. Open questions

OQ-1 moved to device test T1.

| # | Question | Owner |
|---|---|---|
| OQ-2 | v1 is settled by the PR #31 ruling: the overlay window gets no touch, and input is InputPlumber only. A later pointer path would set Steam's focus atoms and would be a focus change. Is that path ever wanted? | dev-research |
| OQ-3 | Overlay client toolkit inside Gamescope (Quickshell under Xwayland vs small Qt/QML X11 app reusing `Handheld.qml`)? | dev-lead |
| OQ-4 | Brightness in gaming: does Steam's own slider fight `omarchy-brightness-display` on RC71L? | Hardware test |
| OQ-5 | Charge limit is not in backlog #10 (power writer) (`apply` is profile + SPL, plus `restore`). Later owner: a backlog #11 (Steam TDP shim) `BatteryChargeLimit1` slice, or a small polkit-gated helper for `charge_control_end_threshold`? The row stays read-only until that choice ships. Not `steamos-manager`. | POWER |
| OQ-6 | Should AC long in gaming be configurable (overlay vs QAM vs screenshot)? Spec 01 revision 1 already points AC long at this overlay. | Daniel |
| OQ-7 | Live frame limit in gaming without steamos-manager: does Steam's QAM limiter work under Omarchy's Gamescope session? | Hardware test |
| OQ-8 | Decky plugin calling `omarchy-quick` (D8): worth maintaining given root plugins? | dev-lead |
| OQ-9 | Fan “mode” (asus-wmi throttle policy) as a separate row, or always tied to profile? | POWER |

## 11. Branch conflicts

| Conflict | Where | Resolution proposed |
|---|---|---|
| AC long = screenshot | Spec 01 first draft | Spec 01 revision 1 already superseded that: AC long is this overlay. Row 14 is the overlay's screenshot control. Steam's QAM and Edge shortcut remain the path spec 01 names. |
| “Armoury short invokes Steam QAM. Long switches mode only in Hyprland.” | `bin/omarchy-hw-rog-ally-input --help` on `feat/ally-input-20261111` | Gaming long now opens the overlay (needs the `gaming` profile, spec 01). |
| Experimental client targets SteamOS Manager; “retain generic PPD” | `docs/rog-ally-power.md`, `docs/rog-ally-power-authority.md`, `default/handheld/power.py` on `feat/ally-power-20261111` | D6: do not install Manager. Mask PPD only when the handheld variant and backlog #10 (power writer) are both installed, record it, and restore it when either is removed or the device goes desktop-only. While the mask is on, Desktop Mode's profile switch calls backlog #10 (power writer). backlog #11 (Steam TDP shim) is the session-bus shim. TDP stays read-only until backlog #10 (power writer) lands. |
| `asusd` running on Daniel's unit | `docs/handheld/research/ally-hw-dump.md` (this branch) | asusd stays off on RC71L. If it is running, power rows are read-only. Spec 03 W7 focuses Disable asusd; declining stays in hub Status. |
| Desktop CC tap = power panel | spec 01 baseline | Δ1 moves it to `omarchy.quick`; `omarchy.power` is the fallback. |
| GameMode is reported beside `power.py` `CONFLICTS` | `default/handheld/power.py` (`gamemoded` via the GameMode bus name) | Performance rows read-only while GameMode is active. |
| Ally profile opt-in calls `omarchy-power-ally` | `bin/omarchy-powerprofiles-set` when `omarchy/ally-power/enabled` exists | That opt-in is the experimental Manager path. After D6, and only while the mask gate is on, the owner is backlog #10 (power writer), in Desktop Mode as well as gaming. |

## Sources

- This branch: `bin/omarchy-powerprofiles-list`, `bin/omarchy-powerprofiles-set` (PPD path), `default/hypr/bindings/media.lua`, `bin/omarchy-audio-output-volume`, `bin/omarchy-brightness-display`, `bin/omarchy-bluetooth-power`, `bin/omarchy-capture-screenshot`, `shell/plugins/panels/{audio,bluetooth,network,monitor,power}/manifest.json`, `docs/omarchy-shell.md`, `docs/theming.md` (`~/.local/state/omarchy/current/theme`).
- `feat/ally-power-20261111`: `shell/plugins/panels/power/Handheld.qml`, `default/handheld/power.py`, `bin/omarchy-power-ally`, the Ally opt-in in `bin/omarchy-powerprofiles-set`, `docs/rog-ally-power.md`, `docs/rog-ally-power-authority.md`.
- `feat/ally-input-20261111`: `bin/omarchy-hw-rog-ally-input`, `default/rog-ally-input/bridge.py`.
- `feat/ally-session-20261111`: `bin/omarchy-setup-gaming-session`, `bin/omarchy-launch-gaming-session`, `bin/omarchy-launch-gaming-desktop`, `docs/rog-ally-gaming-session.md`.
- `feat/ally-games-performance-20261111`: `bin/omarchy-launch-gaming-overlay`, `bin/omarchy-setup-gaming-decky`.
- `feat/ally-display-20261111`: `bin/omarchy-display-rog-ally`.
- `feat/ally-recovery-20261111` and `feat/ally-parity-release-20261111`: `bin/omarchy-setup-rog-ally`.
- This branch: `docs/handheld/research/accessibility.md`, `docs/handheld/research/parity-matrix.md`, `docs/handheld/research/ally-hw-dump.md`.
- Lead ruling, 12 Nov 2026, recorded in [tdp-decision-review.md](tdp-decision-review.md): backlog #10 (power writer) owns power; backlog #11 (Steam TDP shim) is the session-bus shim. Neither task has a branch. The capped-apply rules are [PR #33](https://github.com/DanielJBurbridge/omarchy/pull/33) (`cursor/ally-tdp-spike-1843`, `docs/handheld/tdp-spike-findings.md`), which is the spike, not those backlog tasks.
- Lead ruling, 12 Nov 2026, from [PR #31](https://github.com/DanielJBurbridge/omarchy/pull/31) (`cursor/gamescope-external-overlay-6671`): `docs/handheld/research/gamescope-external-overlay.md`. That file is on that branch, not on this one. It reads Gamescope tag 3.17.0 (`e6674a98118ca7b098b98a3874b8f195ae1bf750`). The RC71L session in that note was not run. Device test T1 is still outstanding.
- External: [gamescope #288 external overlay](https://github.com/ValveSoftware/gamescope/issues/288); [steamcompmgr z-order](https://deepwiki.com/bazzite-org/gamescope/2.2-x11-window-manager-(steamcompmgr)); [loadout Gamescope overlay notes](https://github.com/srsholmes/loadout/blob/main/docs/overlay-gamescope-integration.md); [OpenGamepadUI InputPlumber PR #332](https://github.com/ShadowBlip/OpenGamepadUI/pull/332); [steamos-manager RC71L TOML](https://gitlab.steamos.cloud/holo/steamos-manager/-/blob/master/data/devices/rog-ally-series.toml); [Bazzite handheld wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/); [GoL Bazzite 44](https://www.gamingonlinux.com/2026/08/bazzite-linux-44-for-handhelds-finally-launches-with-some-massive-upgrades/); [CachyOS steamos-manager PKGBUILD](https://github.com/CachyOS/CachyOS-PKGBUILDS/tree/master/handheld/steamos-manager).
