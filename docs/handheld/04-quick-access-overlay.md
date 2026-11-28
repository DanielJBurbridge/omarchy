# 04 · Quick-access overlay

Status: draft, revision 2, 12 Nov 2026 (AWST). Owner: dev-ux. Depends on: [01](01-controller-button-map.md) (Δ1, Δ3, bridge), [02](02-mode-switch-and-dock.md) (session switch, D8 targets), [03](03-first-boot-and-install.md) (packages), spec 07 §3.6 (the Gaming Mode bridge `omarchy-rog-ally-input-gaming.service`; [PR #30](https://github.com/DanielJBurbridge/omarchy/pull/30)). Merge order is [PR #36](https://github.com/DanielJBurbridge/omarchy/pull/36), then PR #30, then this spec. Hardware notes: `docs/handheld/research/` on this branch, including [gamescope-external-overlay.md](research/gamescope-external-overlay.md). The TDP contract is §5.1. [tdp-decision-review.md](tdp-decision-review.md) is the 12 Nov review, kept as history.

**Power.** The writer is `bin/omarchy-ally-tdp-apply`. The session shim is `bin/omarchy-ally-tdp-shim`. It exposes SteamOS Manager’s `TdpLimit1` and `PerformanceProfile1` when the firmware is writable. The interfaces follow evlaV/steamos-manager `85fbd8f` (MIT; `default/ally-tdp/NOTICE.steamos-manager`). Stock `steamos-manager` is not shipped and is not started. `power-profiles-daemon` is D-Bus-activatable, so disable is not enough. `omarchy-ally-tdp-install session` masks it when `omarchy-hw-rog-ally` succeeds, `omarchy-gaming-session` is installed, and the writer is present. It records the previous unit state in `/var/lib/omarchy/handheld/power-profiles-daemon.state`. Hardware install alone does not mask it. `remove-session` restores the recorded state. While that record exists, `bin/omarchy-powerprofiles-set` sends explicit presets to `omarchy-ally-tdp-apply --set-profile`. The wake and power source units reapply the saved request. The apply rules are §5.1. Every written tuple keeps SPL ≤ SPPT ≤ FPPT. Policy ceilings in the writer are battery 20/20/25 (SPL/SPPT/FPPT) and AC SPL 30, then clamped to the live firmware limits. On the stock tables, AC `--set 30` applies 30/43/53.

**Gaming renderer (lead ruling, 12 Nov 2026).** From [research/gamescope-external-overlay.md](research/gamescope-external-overlay.md) on this branch (PR #31, merged). The gaming overlay is an X11 window on Gamescope's root Xwayland, with `GAMESCOPE_EXTERNAL_OVERLAY` set, drawn as an output-sized transparent buffer whose opacity is above 0. It draws above fullscreen games and does not take focus. Input comes only through InputPlumber intercept. The window itself gets no input, and `STEAM_OVERLAY` and `STEAM_INPUT_FOCUS` are never set. Gamescope paints one external overlay, and any client on the root X display can take that slot. On the gaming session path, Gamescope is started with `--xwayland-count 2` and `-e`. That steers well-behaved Steam games onto the second Xwayland. It is not a security boundary. While this panel is open it takes the slot from mangoapp/MangoHud. On close, and if the client dies, it gives the slot back and restores the mangoapp state from before the panel opened. This spec is the only owner of the slot. While the session is locked, desktop lock or Steam lock, or when that state is unknown, the overlay is not drawn. Count 2 and `-e` are required on the gaming session path only. The nested launcher leaves this overlay disabled. The RC71L session has not been run; that check stays on device test T1. Merge order is [PR #36](https://github.com/DanielJBurbridge/omarchy/pull/36), then [PR #30](https://github.com/DanielJBurbridge/omarchy/pull/30), then this spec. The Switch to Desktop row follows spec 02 as PR #36 amends it. The Armoury escape is F17 + 1 s, as spec 07 §3.6 defines it. `InterceptMode` last seen when F17 arrives is non-zero, and if it is still non-zero 1 s later the bridge forces it to 0. `WatchdogSec=1s` is the second route.

## 0. Decisions in one table

| # | Decision | Source |
|---|---|---|
| D1 | One overlay, **two renderers**. On desktop it is an `omarchy-shell` panel (`omarchy.quick`). In gaming it is an X11 window on Gamescope's **root Xwayland** (the exported `DISPLAY`, server 0), with `GAMESCOPE_EXTERNAL_OVERLAY` non-zero, drawn as an **output-sized transparent buffer** whose `_NET_WM_WINDOW_OPACITY` is above 0. It paints above fullscreen games and does not take focus. A window on a later Xwayland is not this overlay. Both renderers read one backend CLI (`omarchy-quick`, §5). | [research/gamescope-external-overlay.md](research/gamescope-external-overlay.md); §6 |
| D2 | Open: **AC long (`F17`, `QuickAccess2`) in gaming**, **CC tap on desktop** (spec 01 Δ1), and an Omarchy menu entry (both modes reach it without a long press). Spec 01 revision 1 already assigns AC long to this overlay (Δ3) and keeps Steam's own screenshot path. Row 14 is this overlay's screenshot control. | Brief; spec 01 Δ3; D9 of spec 02 |
| D3 | Gaming fallback is **Steam QAM**: if the overlay client is missing, crashed, not ready, or a game is starting, AC long sends QAM instead. | Brief, red review |
| D4 | Gaming input comes **only** through InputPlumber intercept (`omarchy-hw-rog-ally-input intercept all`, restore `none` on close, crash and session exit). The overlay window gets no keyboard, pointer or touch. Never set `STEAM_OVERLAY` or `STEAM_INPUT_FOCUS`. The game keeps focus. | [research/gamescope-external-overlay.md](research/gamescope-external-overlay.md); spec 01 C8 |
| D5 | Prompts and the overlay **ignore controller input for 500 ms** after appearing, and the initial focus is the safe item (Close / no change). | Red review |
| D6 | **power-profiles-daemon is masked by `omarchy-ally-tdp-install session`.** That runs when `omarchy-hw-rog-ally` succeeds and `omarchy-gaming-session` is installed. Not on every RC71L, and not from the hardware install alone. The previous unit state is recorded and restored by `remove-session`. While the record exists, `omarchy-powerprofiles-set` sends the preset to `omarchy-ally-tdp-apply --set-profile` and does not call `powerprofilesctl`. The shim is `omarchy-ally-tdp-shim`, not `steamos-manager`. No ryzenadj, no PowerStation, no HHD. **Omarchy skips asusd installation on RC71L. If an existing asusd service is running, it keeps ownership of tuning.** Charge limit is not a writer verb. The apply rules are §5.1. SPL ≤ SPPT ≤ FPPT always. Battery policy is 20/20/25. AC SPL policy is 30 W, then the live firmware clamp. | §5.1; `bin/omarchy-ally-tdp-apply`; `bin/omarchy-ally-tdp-install` |
| D7 | Rows that the device or kernel cannot do (fan curves, RGB, haptics on the stock kernel) are **hidden or read-only with a reason**, never a dead control. | [parity-matrix.md](research/parity-matrix.md) |
| D8 | Decky is **not** a dependency. Optional later: a Decky plugin that calls the same `omarchy-quick` CLI. | `bin/omarchy-setup-gaming-decky` |
| D9 | Gamescope paints **one** external overlay, and **this spec owns that slot** for the gaming session. `--xwayland-count 2` plus `-e` on that path (`bin/omarchy-session-start` at `c52affb7b`) steers well-behaved Steam games onto the second Xwayland. It is not a security boundary: root Xwayland has no `-auth` (wlroots 0.20), so any same-UID process can open `:0` and claim or fake the overlay. The client self-checks and, if that fails, does not map and never sets the atom. The nested launcher is out of scope: the overlay stays disabled there. While the panel is open it **takes that slot from mangoapp/MangoHud**. On close it gives the slot back. The overlay never hosts auth, password, PIN or unlock UI. | [research/gamescope-external-overlay.md](research/gamescope-external-overlay.md); [PR #35](https://github.com/DanielJBurbridge/omarchy/pull/35); §6.1 |
| D10 | While the session is locked (desktop lock or Steam lock), or the lock state is unknown, this overlay **hides and refuses to open**. On `PrepareForSleep(true)` this overlay closes fully, as its own behaviour: atom 0, `intercept none`, mangoapp restored. On `PrepareForSleep(false)`, before any paint, it re-checks the lock state. If that state is not game-focused and the overlay is still open, it closes fully (atom 0, `intercept none`, mangoapp restored) before any paint. If this overlay is the suspend source, it closes fully before it calls `omarchy-handheld-suspend-request` (`org.omarchy.Handheld.Suspend1`, spec 02 AC 41). Ordering against sleep is spec 02 §7.7. This spec does not add a sleep inhibitor. While `desktop-lock` is `default-off` or `explicit-off`, **Switch to Desktop is hidden**. While it is `on` and a usable keyboard exists, or after K07, the row runs spec 02's lock command before any desktop frame. Before K07, with `on` and no usable keyboard, the row is shown disabled, reading “Connect a keyboard to unlock”, and activating it does nothing beyond that hint. | Lead ruling, 12 Nov 2026; [PR #36](https://github.com/DanielJBurbridge/omarchy/pull/36) |

## 1. Baseline: what is already built

Checked on `feat/ally-parity-integration-20261111` (`bbc819047`) and the `feat/ally-*-20261111` branch that contains the file.

| Piece | Path (branch) | Use here |
|---|---|---|
| TDP writer | `bin/omarchy-ally-tdp-apply` (this branch). Verbs `--show`, `--snapshot`, `--set WATTS`, `--reassert`. Writes `ppt_pl1_spl`, `ppt_pl2_sppt`, `ppt_pl3_fppt` `current_value` in that order. Refuses while a competing unit is active. | The owner §5.1 names. The overlay does not write sysfs and does not install steamos-manager. |
| TDP shim | `bin/omarchy-ally-tdp-shim` and `default/systemd/user/omarchy-ally-tdp-shim.service` (this branch). Session bus `com.steampowered.SteamOSManager1`, interface `TdpLimit1`. | Steam's slider. The shim uses pkexec to call the writer for `--set`. |
| Profile helpers | `bin/omarchy-powerprofiles-list` and `bin/omarchy-powerprofiles-set` (this branch). Set arguments are `autodetect`, `ac` or `battery`, then `power-saver`, `balanced` or `performance`. With the recorded mask still in place, list reads availability and active state from `omarchy-ally-tdp-apply --show` and set submits a named preset through `--set-profile`. | A desktop-only RC71L keeps `powerprofilesctl`. The Ally session install is the mask in D6. |
| Install | `install/hardware/asus/ally-tdp.sh` runs `omarchy-ally-tdp-install` `hardware`, and `session` when `omarchy-gaming-session` is installed. | Resume unit, source unit, udev rule, shim, polkit, PPD mask. |
| Input bridge | `bin/omarchy-hw-rog-ally-input` (`feat/ally-input-20261111`): `status`, `desktop`, `gamepad`, `dualsense`, `toggle`, `capabilities`, `intercept none` or `intercept all`, `watch`. Help: “Profiles clear held target inputs on change. Switching target disconnects it.” Status JSON `InterceptMode` is `0` for `none` and `2` for `all`. | Overlay input + controller rows. |
| Gaming session | `bin/omarchy-setup-gaming-session` (`feat/ally-session-20261111`): `display` takes `native`, `720p`, `900p` or `1080p`, then an optional fps (`0`, `30`, `40`, `45`, `60`, `90`, `120`) and filter (`linear`, `nearest`, `fsr`, `nis`). `overlay on` or `overlay off` is mangoapp for the **next** gaming session and takes no preset. `docs/rog-ally-gaming-session.md` on this branch: no layer-shell panels in gaming. `gamescope-args` from `omarchy-display-rog-ally` still supplies only `--prefer-output`. The DRM launch itself, `bin/omarchy-session-start` at `c52affb7b`, is `gamescope --backend drm -e --xwayland-count 2 --default-touch-mode 4`. Gamescope package cited there is 3.17.0-1. | FPS/render rows. The gaming session path keeps `-e` and `--xwayland-count 2`. The nested `--gamescope` launcher does not, and this overlay is disabled there (§6.1). |
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

Take: everyone uses Steam QAM in gaming and one power owner. Omarchy adds a themed overlay with the same one-owner rule. The owner is `omarchy-ally-tdp-apply`, not `steamos-manager`. QAM stays the fallback, through `omarchy-ally-tdp-shim`.

## 3. Opening and closing

| Trigger | Mode | Action | Fallback |
|---|---|---|---|
| AC long (`F17` → `QuickAccess2`) | Gaming | Open overlay client | Steam QAM (InputPlumber emits `QuickAccess` / Guide+South on the Xbox target) when D3 applies |
| CC tap (`Guide`) | Desktop | `omarchy-shell shell toggle omarchy.quick` (Δ1) | Power panel `omarchy.power` (baseline) if `omarchy.quick` is absent |
| Omarchy menu → **Quick settings** | Desktop | Same as CC tap | — |
| Steam → Non-Steam shortcut “Omarchy Quick Settings” | Gaming | Opens the overlay client (menu path; no long press) | — |
| Same trigger again, **B**, or **CC tap** (gaming) | Both | Close | — |
| Game launch begins / Steam overlay opens | Gaming | Overlay closes itself (no prompt) | — |
| Steam lock screen up | Gaming | Overlay stays hidden (atom 0). AC long does not open it | Steam's own lock. No panel over the PIN |

**D3 “game is starting”** = a new game process appeared in the gaming scope within the last 10 s (spec 02 OQ-9 detector). During that window AC long goes straight to QAM.

## 4. Contents

Order is fixed (most-used first). **RC71L today** = this tree: Omarchy kernel, no `hid-asus-ally`, the TDP writer and shim installed with the gaming session, `steamos-manager` not installed. `omarchy-quick` is not in this tree. Until that client exists, Steam's QAM is the TDP control.

| # | Row | Control | Backend | Gaming | Desktop | RC71L today |
|---|---|---|---|---|---|---|
| 1 | Performance profile | Quiet · Balanced · Performance | While the PPD record exists, `omarchy-powerprofiles-set` sends the preset to `omarchy-ally-tdp-apply --set-profile`. Otherwise it calls `powerprofilesctl`. A desktop-only RC71L stays on PPD. | ✓ | ✓ | ✓ via PPD until the session install masks it |
| 2 | TDP (sustained W) | Whole watts. Battery policy 20/20/25. AC SPL policy 30 W, then the live firmware clamp. SPL ≤ SPPT ≤ FPPT. | `omarchy-ally-tdp-apply --set WATTS` (§5.1). Root derives SPPT and FPPT, then clamps. Steam's slider uses the shim. | ✓ | ✓ | The writer is in the tree. On-device slider check is still open |
| 3 | Fan | Read-only: “Firmware (follows profile)” | `asus-wmi` platform profile | ✓ | ✓ | Read-only (custom curves fail, -19) |
| 4 | Brightness | Slider, 5 % steps | `omarchy-brightness-display` (backlight via logind in gaming) | ✓ | ✓ | ✓ |
| 5 | Volume / mute | Slider + mute | `omarchy-audio-output-volume` (wpctl) | ✓ | ✓ | ✓ |
| 6 | Frame limit | Off · 30 · 40 · 45 · 60 · 90 · 120 | Gaming: Steam QAM's own limiter (link) plus `omarchy-setup-gaming-session display` fps for the **next** session (`0` is off). Desktop: n/a | ✓ (labelled “next session”) | — | ✓ |
| 7 | Refresh rate | 60 · 120 Hz | Desktop: `omarchy-display-rog-ally native 60` or `native 120`. Gaming: Steam QAM | link | ✓ | ✓ desktop |
| 8 | Performance HUD | Off · Compact · Detailed | Next gaming session: `omarchy-setup-gaming-session overlay on` or `off` (no preset argument). Presets: `omarchy-launch-gaming-overlay --preset compact` or `detailed`. | ✓ next session | per-game (`omarchy-launch-gaming-overlay`) | ✓ if MangoHud is installed |
| 9 | Battery charge limit | Off · 80 % | Not a verb of `omarchy-ally-tdp-apply`. `BatteryChargeLimit1` is not in the shim. Stays read-only until OQ-5's later owner. Not `steamos-manager`. | ✓ once that owner exists | ✓ once that owner exists | **Read-only**: “Charge limit is not in the writer yet” |
| 10 | Wi-Fi | On/off + current SSID | NetworkManager (`nmcli radio wifi`) | ✓ | ✓ + “More…” → `omarchy.network` | ✓ |
| 11 | Bluetooth | On/off + connected count | On/off: `omarchy-bluetooth-power`. Count from BlueZ. | ✓ | ✓ + “More…” → `omarchy.bluetooth` | ✓ |
| 12 | Controller | Desktop/gamepad/DualSense (desktop only); presets: Standard · One-handed L · One-handed R · Paddles = A/B | `omarchy-hw-rog-ally-input` + preset profiles (Δ-Q2) | presets only, §7 | ✓ | Presets need the companion; paddles need `hid-asus-ally` |
| 13 | RGB | Off · Colour · Brightness | `/sys/class/leds/*` (driver) | hidden | hidden | **Hidden** (no `hid-asus-ally`; brightness firmware-locked) |
| 14 | Screenshot | Button | Gaming: Steam screenshot (InputPlumber `Screenshot`); desktop: `omarchy-capture-screenshot` | ✓ | ✓ | ✓ (spec 01 already left AC long on this overlay; this row is the control) |
| 15 | Switch mode | “Switch to Desktop” is **hidden** while `desktop-lock` is `default-off` or `explicit-off`. While it is `on` and a usable keyboard is present, or after K07, the row runs spec 02's lock command before any desktop frame. Before K07, with `on` and no usable keyboard, the row is shown **disabled** and reads “Connect a keyboard to unlock”. Activating it does nothing beyond that hint. “Switch to Gaming” stays. | `omarchy-launch-gaming-desktop` / `omarchy-launch-gaming-session` (no arguments today; `--confirm` is spec 02 §4). Hidden or disabled means the overlay does not call the desktop launcher. A usable keyboard is the one [spec 02 on PR #36](https://github.com/DanielJBurbridge/omarchy/pull/36) counts. | hidden while lock is off; disabled before K07 with no keyboard; ✓ otherwise while `on` | ✓ | follows the stored value |
| 16 | Accessibility | Toggles (§4.1) | various | some | ✓ | partial |

Each row shows: label, current value, unit, and on failure a reason. Writes show “Applying…” until readback matches. A timeout (3 s) restores the displayed value and shows the error.

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
| `omarchy-quick status --json` | One JSON object: per row `available`, `value`, `choices` / `min` / `max`, `reason`, `mode` (`gaming` or `desktop`). TDP comes from `omarchy-ally-tdp-apply --show`, plus wpctl, NetworkManager, BlueZ and bridge status. `omarchy-quick` is not in this tree yet. Event-driven refresh (D-Bus signals); no polling loop. |
| `omarchy-quick set <row> <value>` | Validates against the last status, calls the owning CLI, waits for readback (≤ 3 s), exits non-zero with `reason` on mismatch. Never writes sysfs itself. Never calls `steamos-manager`. |
| Unknown row/value | Error, no change (red team: unknown ⇒ safe). |
| Conflicts | If any competing writer is active, rows 1, 2 and 9 are read-only with “Competing power writer: …”. The writer's list is `power-profiles-daemon` (masked by the TDP session install; left running on a desktop-only RC71L), `powerstation`, `hhd`, `adjustor`, `asusd`, `tlp`, `auto-cpufreq`, `tuned`, and `gamemoded`. Explicit writes and snapshots fail while a competing owner is active. Background reapply skips the write and exits successfully. |
| Caps | Slider max is 20 W on battery and 30 W on AC. A canonical request above the cap is **clamped**, not rejected: on battery `--set 21` and `--set 25` apply 20/20/25. A canonical request below 7 W clamps up to 7 W. A non-canonical watt string, a set while a conflict is active, or a tuple that would break SPL ≤ SPPT ≤ FPPT writes nothing. |

### 5.1 Power authority

This section is the TDP contract. The writer is `bin/omarchy-ally-tdp-apply`. The shim is `bin/omarchy-ally-tdp-shim`. [tdp-decision-review.md](tdp-decision-review.md) is the 12 Nov review and is not a second contract. Stock `steamos-manager` is not shipped.

The shim owns `com.steampowered.SteamOSManager1` on the session bus and loads `TdpLimit1` from `default/ally-tdp/com.steampowered.SteamOSManager1.TdpLimit1.xml`. That interface, and the SPL then SPPT then FPPT write, are from evlaV/steamos-manager `85fbd8f` (MIT; `default/ally-tdp/NOTICE.steamos-manager`). The shim does not write sysfs. It uses pkexec to call the writer for `--set`.

The shim exposes `TdpLimit1` only while the writer reports a writable slider. It keeps `Manager2` available and signals `InterfacesAdded` or `InterfacesRemoved` when a writer update or a competing system service changes that capability. A writable slider reports changes to its limit and bounds through `PropertiesChanged`.

`install/hardware/asus/ally-tdp.sh` runs `omarchy-ally-tdp-install hardware`, and `session` when `omarchy-gaming-session` is installed. Session install enables the shim, writes the polkit rule, and masks `power-profiles-daemon` after recording its previous state.

- One polkit action, `org.omarchy.ally.set-tdp`. The policy defaults are `allow_any=no`, `allow_inactive=no`, `allow_active=yes` (`default/polkit/org.omarchy.ally.set-tdp.policy`). The exec path is `/usr/bin/omarchy-ally-tdp-apply`. The generated rule returns YES only for the user in `omarchy-handheld-user.conf`, and only while that session is active and local. `sddm` is NO. There is no `wheel` grant. D1's sign-off of `allow_active=yes` is still open. The caller does not pass SPPT or FPPT.
- Verbs are `--show`, `--snapshot`, `--set WATTS`, and `--reassert`. Watts are a canonical whole number (`15` is accepted; `15.5`, `1e1`, `+15`, and `015` are not). Anything else writes nothing. `--show` is unprivileged. `--snapshot`, `--set` and `--reassert` re-exec through pkexec unless the process is already root.
- `--set` and `--reassert` take an exclusive flock on `/run/omarchy-ally-tdp.lock`, with a 5 s acquire wait. A timeout writes nothing.
- SPL ≤ SPPT ≤ FPPT on every write, on AC and on battery, for every SPL from 7 W through the cap, and after `--reassert`. A result that would break that order writes nothing.
- The writer reads live `min_value`, `max_value` and `default_value` and clamps to them, to the boot-captured max, and to the policy ceiling. The ratio anchor is the boot-captured `default_value` when that is greater than zero, otherwise `max_value`. Policy constants in the script are battery 20/20/25 and AC SPL 30. On AC, SPPT and FPPT ceilings are the boot-captured max. The stock AC table is SPL 30, SPPT 43, FPPT 53, so `--set 30` applies 30/43/53. The stock DC table is min/def/max SPL 7/15/25, SPPT 15/20/30, FPPT 15/25/35. The applied battery ceiling is 20/20/25, not that DC max. The slider max is also bounded by the live SPL max.
- Root derives SPPT and FPPT, then clamps. On battery, SPPT = clamp(derived, max(SPL, sppt_min), 20) and FPPT = clamp(derived, max(SPPT, fppt_min), 25). A request above the cap clamps: `--set 21` and `--set 25` on battery apply 20/20/25. `--set` stores the number the user asked for. A canonical value below 7 W clamps up to 7 W on apply, on AC and on battery. `--set 5` stores 5 and writes SPL 7, then the same derive-and-clamp. It is not rejected.
- `--reassert` clamps the stored request into the current source and does not change the stored number. After a 30 W AC set, unplug applies 20/20/25 and keeps 30 stored, so plugging back in restores 30/43/53.
- Resume is `--reassert` from `omarchy-ally-tdp-resume.service` `ExecStop` after wake (`WantedBy=sleep.target`). That unit is the only wake path, including on the desktop. The shim does not subscribe to logind `PrepareForSleep`. A mains supply whose `POWER_SUPPLY_ONLINE` is 0 or 1 starts `omarchy-ally-tdp-source.service`, which runs the same verb. A USB supply does not start that oneshot. The writer still treats a USB supply with `online` 1 as AC.
- While `power-profiles-daemon`, `powerstation`, `hhd`, `adjustor`, `asusd`, `tlp`, `auto-cpufreq`, `tuned` or `gamemoded` is active, `--set` and `--snapshot` report the conflict and exit with an error. `--reassert` logs the conflict and exits successfully without changing the firmware or the saved request.
- Any battery tuple above 20/20/25 needs measured data and dev-red sign-off before it ships. Until that sign-off, the clamp is the rule. `BatteryChargeLimit1` is not in the shim.

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

1. If a mangoapp record already exists, restore it and delete it before writing a new one. Then record whether mangoapp is visible (its process is running and its `GAMESCOPE_EXTERNAL_OVERLAY` cardinal is non-zero). Write that record only when none exists. It lives outside the client. `ExecStopPost` restores from it and then deletes it.
2. Hide mangoapp by setting that atom to 0. Leave the process running. Do not change the session preference (`omarchy-setup-gaming-session overlay on` or `overlay off`).
3. Map our window on the root Xwayland: output-sized, cleared transparent, panel in one corner. Set `GAMESCOPE_EXTERNAL_OVERLAY` to 1 and `_NET_WM_WINDOW_OPACITY` above 0.

On close:

1. Set our overlay atom to 0 and unmap. That releases the slot.
2. Write mangoapp's atom back to the recorded value. A HUD that was visible is visible again. One that was hidden stays hidden.
3. Restore intercept `none` (§7).

If the client dies, including `SIGKILL`, the window is gone and Gamescope drops our slot. `ExecStopPost` still runs: it sets `intercept none` and restores the recorded mangoapp state. A HUD that was visible before open is visible again, and the pad is not left captured.

`--xwayland-count 2` plus `-e` is required on the gaming session path. `bin/omarchy-session-start` at `c52affb7b` on `feat/ally-session-20261111` already runs `gamescope --backend drm -e --xwayland-count 2 --default-touch-mode 4`. `docs/rog-ally-gaming-session.md` on this branch still describes `gamescope-args` as `--prefer-output` only; that is the display helper, not the session argv. The same DRM line is in `bin/omarchy-session-start` on `feat/ally-recovery-20261111`, and recovery keeps it. The flag steers well-behaved Steam games onto the second Xwayland (`STEAM_GAME_DISPLAY_*`). This client and mangoapp stay on the root `DISPLAY`. It is not a security boundary. Root Xwayland has no `-auth` (wlroots 0.20), so any process of the same user can open `:0` and claim the slot or draw a fake overlay.

At start the client runs one self-check, and all three parts must hold. The X display it is connected to is the `DISPLAY` Gamescope exported, and that display is server 0, the root Xwayland. `STEAM_MULTIPLE_XWAYLANDS` is `1`. `STEAM_GAME_DISPLAY_0` is set and names a different display from `DISPLAY`. Gamescope exports those: `DISPLAY` stays server 0, and with `-e` and `--xwayland-count 2` the extra server is `STEAM_GAME_DISPLAY_0` ([research/gamescope-external-overlay.md](research/gamescope-external-overlay.md)). If any value is missing, equal, or unreadable, the check fails: the client does not map, never sets `GAMESCOPE_EXTERNAL_OVERLAY`, and AC long opens Steam QAM.

The nested launcher `bin/omarchy-launch-gaming-overlay --gamescope` on `feat/ally-games-performance-20261111` is out of scope for this overlay. It does not pass `--xwayland-count 2`. The overlay is disabled there: the self-check fails and AC long goes to QAM. This spec does not require that launcher to grow the flag.

The unit restarts at most 3 times in 60 s. After that, AC long opens QAM for the rest of the session and hub Status says why.

**Residual risk.** Any same-UID process can draw a fake overlay or a fake toast. That is the same class of problem as squatting the notifier name. This overlay is never trusted for, and never hosts, auth, a password, a PIN or an unlock UI.

While the session is locked, desktop lock or Steam lock, the client hides and refuses to open. If the lock state is unknown, it fails closed the same way. The overlay paints above the base window (zpos 2), so an open panel would cover a lock that is that window. On `PrepareForSleep(true)` the overlay closes fully, as its own behaviour: atom 0, `intercept none`, mangoapp restored. On `PrepareForSleep(false)`, before any paint, it runs the lock check again. If the state is not game-focused and the overlay is still open, it closes fully (atom 0, `intercept none`, mangoapp restored) before any paint. If this overlay is the suspend source, it closes fully before it calls `omarchy-handheld-suspend-request` (`org.omarchy.Handheld.Suspend1`, spec 02 AC 41). Ordering of that close against sleep is spec 02 §7.7. This spec does not add a sleep inhibitor. AC long does not open the overlay while the session is locked. Whether Steam's own Switch to Desktop asks for the PIN inside this Gamescope session is unverified until device test T3 passes.

The Steam-lock check reads four properties on the root window of that same `DISPLAY`, on every paint and on `PropertyNotify`. It does not cache them. They are `GAMESCOPE_FOCUSED_WINDOW`, `GAMESCOPE_FOCUSED_APP`, `GAMESCOPE_FOCUSED_APP_GFX`, and `GAMESCOPE_FOCUS_DISPLAY`. Gamescope writes them on the root window during the focus pass, and the app properties are written only when `-e` is on. Gamescope 3.17.0 publishes no lock or PIN property. The only unlocked state is game-focused: `GAMESCOPE_FOCUS_DISPLAY` is the game Xwayland (`STEAM_GAME_DISPLAY_0`, not root `DISPLAY`), and `GAMESCOPE_FOCUSED_APP` is not 0 and is not Steam's app id. Steam's app id is the `GAMESCOPE_FOCUSED_APP` value device test T2 records on Steam's library window. App ids vary by game, so game-focused is this rule, not one recorded number. Library-focused is not unlocked. T2 records the library tuple and the PIN tuple and shows whether they differ. They are the same Steam window until that record says otherwise, so the library is not on the allowlist. Anything else is locked, including a failed read, a `PropertyNotify` that leaves the rule, and a PIN. The overlay closes fully and does not paint. It does not match a window title. A same-UID client can write these root properties (`DISPLAY` has no `-auth`, D9). That is the same residual as a fake overlay. Desktop lock is spec 02's lock, not these properties.

### 6.2 Who may ask the slot owner

This spec is the only owner. Spec 05 (PR #30) does not open its own `GAMESCOPE_EXTERNAL_OVERLAY` window. It asks `omarchy-quick`:

| Request | What the owner does |
|---|---|
| `omarchy-quick slot preempt battery` | Hide mangoapp (record its state) and hold the slot so a critical battery alert can be shown. |
| `omarchy-quick slot preempt thermal` | Same, for a critical thermal alert. |
| `omarchy-quick slot release` | Restore the recorded mangoapp state, unless Steam is locked or another preempt is still active. |

Critical battery and thermal alerts **never depend on this slot**. If the owner is not running, or preempt fails, the caller uses a notification drawn by the Steam client. How a non-Steam process asks Steam to draw that notice inside this Gamescope session is **unverified**. UPower's critical battery action does not use this overlay or that Steam path. A failed preempt does not drop the alert. The overlay still never hosts the alert's auth or unlock UI.

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
| Intercept on | The overlay unit has `BindsTo=` and `After=` on `omarchy-rog-ally-input-gaming.service`, and `BindsTo=` and `After=` on `omarchy-gaming-session.target`. That target is a user target from [PR #34](https://github.com/DanielJBurbridge/omarchy/pull/34). It takes intercept only when the bridge's `ActiveState` is `active`. `activating`, auto-restart and `failed` refuse, and AC long opens QAM. Any non-zero `InterceptMode` counts as on. When the unit is `active`: 1) send key/button-up for everything held on the current target, 2) `intercept all`, 3) wait until `omarchy-hw-rog-ally-input status` reports a non-zero `InterceptMode` (≤ 500 ms), 4) show. Failure ⇒ don't show; send QAM instead. The client watches `InterceptMode` `PropertiesChanged`. A 0 it did not set closes the overlay fully (atom 0, mangoapp restored) and it does not take intercept again until the next AC long. |
| Intercept off | On close, crash, or 30 s idle: send ups, `intercept none`, confirm `InterceptMode` `0`, and restore the recorded mangoapp state (§6.1). The overlay unit has `WatchdogSec=1s` and `TimeoutStopSec=1s`, and the client sends `sd_notify` `WATCHDOG=1`. A missed ping stops the unit. That is the second route when the client does not answer. `ExecStopPost` sets `intercept none`. If the gaming bridge stops or fails, or `omarchy-gaming-session.target` stops, `BindsTo=` stops this unit and the same `ExecStopPost` sets `intercept none`. |
| Armoury escape | The trigger is F17 + 1 s, as spec 07 §3.6 defines it ([PR #30](https://github.com/DanielJBurbridge/omarchy/pull/30)). `InterceptMode` last seen when F17 arrives is non-zero, and if it is still non-zero 1 s later the bridge forces it to 0. The bridge does nothing else. It does not open QAM. The overlay closes on that external 0. The controller returns to the game or to Steam. QAM opens only on a later AC long, by the normal path, once this overlay is gone. `WatchdogSec=1s` is the second route. |
| IP killed while open | Overlay closes; firmware pad returns to Steam (spec 02 §8). |
| Profile change (row 12) | Same target only (presets): ups → load profile → wait ready → done; on failure **atomic fallback** to `gamepad` (gaming) / `desktop` (desktop). Target change (desktop, gamepad or DualSense) is **desktop only** and refused in gaming while a game runs (“switching target disconnects the controller”). |
| Session switch (row 15) | While `desktop-lock` is `default-off` or `explicit-off`, Switch to Desktop is not in the overlay. Steam's own menu is the switch. Whether that menu asks for the PIN in this session is unverified until T3. While it is `on` and a usable keyboard is present, or after K07, the row is shown: confirmation sheet (spec 02 §4), Cancel focused, 500 ms arm delay, then spec 02's lock command runs before any desktop frame. Before K07, with `on` and no usable keyboard, the row is shown disabled and reads “Connect a keyboard to unlock”. Activating it does nothing beyond that hint, and `desktop()` returns to gaming instead of a lock screen. |
| No hold-only action | Every row is tap-driven; long press not used inside the overlay. |
| Lock | Desktop locked ⇒ CC tap does nothing (bridge already fails closed, spec 01 P6). While spec 03 ships handheld `default-off`, the desktop is not locked, so CC tap still opens the overlay. |

## 8. User flows

| # | Flow | Steps |
|---|---|---|
| F1 | Drop power mid-game | AC long → (500 ms) → Performance profile → left to Quiet → A → readback → B. Game never lost focus. With the session install, PPD is masked and the TDP reassert is `omarchy-ally-tdp-apply`. |
| F2 | Client crashed | Overlay dies while mangoapp had been visible → slot released, intercept back to `none`, mangoapp visible again → next AC long → QAM opens (fallback) → hub Status later shows the crash. |
| F3 | Desktop brightness | CC tap → Display → right → A → CC tap closes. |
| F4 | One-handed preset in game | AC long → Controller → One-handed L → A → key-ups, profile loads → B. |
| F5 | TDP | AC long → TDP row. Battery policy 20/20/25. AC SPL policy 30 W, then the live firmware clamp. A battery request above 20 W clamps to 20/20/25. Steam's QAM uses the shim. Whether that slider is drawn on this RC71L is still unverified. |
| F6 | Switch to desktop | While `desktop-lock` is `default-off` or `explicit-off`: the row is absent. While it is `on` with a usable keyboard, or after K07: AC long → Switch to Desktop → sheet (Cancel focused) → Switch → A → spec 02's lock command runs before any desktop frame. Before K07, with `on` and no usable keyboard: the row reads “Connect a keyboard to unlock”, and activating it only shows that hint. |
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
10. Rows 1, 2 and 9 are read-only, and name the writer, whenever `power-profiles-daemon`, `powerstation`, `hhd`, `adjustor`, `asusd`, `tlp`, `auto-cpufreq`, `tuned` or `gamemoded` is active. `power-profiles-daemon` is masked by `omarchy-ally-tdp-install session`. A desktop-only RC71L is not masked. Hardware install alone does not mask it.
11. Every write shows “Applying…” and is reported done only after readback; a forced mismatch shows the error and the old value within 3 s.
12. Unsupported rows on the stock RC71L kernel (RGB, haptics) are hidden. The TDP row calls `omarchy-ally-tdp-apply`. It does not name `steamos-manager`. Charge limit stays read-only, and says it is not in the writer, until OQ-5's later owner exists. Installing the TDP writer does not by itself enable the charge row.
13. A preset change in gaming sends key-ups first (held-A test: no stuck A after the change) and falls back to `gamepad` on load failure.
14. A target change is refused in gaming while a game runs, with the reason shown.
15. While `desktop-lock` is `on` and a usable keyboard is present, or after K07, “Switch to Desktop” goes through spec 02's confirmation and runs the lock command before any desktop frame. While it is `default-off` or `explicit-off`, that row is not shown (AC 31). Before K07, with `on` and no usable keyboard, the row is disabled (AC 32).
16. No row writes sysfs directly; `omarchy-quick` calls only the owning CLIs (code review + strace). TDP goes to `omarchy-ally-tdp-apply`. It does not exec `steamos-manager`.
17. Colours and fonts match the active theme under `~/.local/state/omarchy/current/theme` in both renderers (theme switch reflected on next open).
18. Boot race: AC long before the client is up (first 10 s of gaming) opens QAM, not nothing.
19. A canonical TDP set at or below the slider max completes on readback with SPL ≤ SPPT ≤ FPPT. Battery policy is 20/20/25. AC SPL policy is 30 W, then the live firmware clamp. A request above the cap clamps. A canonical `--set` below the live SPL min, such as `--set 5` on the stock tables, stores 5 and writes SPL 7, then the same derive-and-clamp runs. A non-canonical watt string, or a set while a conflict is active, is rejected and writes nothing.
20. With mangoapp visible, opening the overlay hides mangoapp and paints this panel in the single external-overlay slot, above the fullscreen game, with no focus change. `InterceptMode` is `2`. The overlay window receives no keyboard, pointer or touch, and neither `STEAM_OVERLAY` nor `STEAM_INPUT_FOCUS` is set.
21. Closing the overlay releases the slot and restores mangoapp to the visibility it had before open. `InterceptMode` is `0`. The session's `overlay on` or `overlay off` preference is unchanged.
22. `SIGKILL` of the client, when mangoapp was visible before open, releases the slot, restores `InterceptMode` `0` within 1 s, and mangoapp is visible again.
23. A desktop-only RC71L does not mask `power-profiles-daemon`. `powerprofilesctl` works, and so do the Omarchy power menu and waybar. Hardware install without the session install does not mask it either.
24. PPD is masked by `omarchy-ally-tdp-install session`, and the previous unit state is recorded. `remove-session` unmasks PPD and restores that recorded state.
25. While that record exists, `omarchy-powerprofiles-set` sends the preset to `omarchy-ally-tdp-apply --set-profile`, not `powerprofilesctl`.
26. The only `allow_active=yes` action is `org.omarchy.ally.set-tdp` on `/usr/bin/omarchy-ally-tdp-apply`. `--set` takes watts and does not take SPPT or FPPT. A non-canonical watt string, or a set while PPD is active, is rejected and writes nothing. A canonical value above the source cap clamps (AC 27). A canonical value below 7 W clamps up to 7 W (AC 19).
27. On battery, `--set 20` applies 20/20/25. `--set 25` clamps and applies 20/20/25. Readback matches. SPPT does not exceed 20 W and FPPT does not exceed 25 W.
28. The resume unit calls `--reassert` after wake. The shim does not. After a 30 W AC set, unplug clamps the applied tuple to 20/20/25, keeps the stored request at 30, and plugging back in restores 30/43/53.
29. A Steam-launched game on the second Xwayland does not take the external-overlay slot. This is not a claim that no process can. A same-UID process on the root Xwayland still can.
30. While the session is locked (desktop lock or Steam lock), or the lock state is unknown, this overlay is not painted and AC long does not open it. On `PrepareForSleep(true)` the overlay closes fully, as its own behaviour: atom 0, `intercept none`, mangoapp restored. Ordering against sleep is spec 02 §7.7. This spec does not add a sleep inhibitor. On `PrepareForSleep(false)`, before any paint, the lock check runs again. If the state is not game-focused and the overlay is still open, it closes fully (atom 0, `intercept none`, mangoapp restored) before any paint, and `InterceptMode` is `0` (T2). If this overlay is the suspend source, that same full close happens before it calls `omarchy-handheld-suspend-request` (`org.omarchy.Handheld.Suspend1`, spec 02 AC 41).
31. While `desktop-lock` is `default-off` or `explicit-off`, Switch to Desktop is not in the overlay, and the overlay does not start the desktop. Steam's own menu is the remaining switch. That it asks for the PIN in this Gamescope session is unverified until device test T3 passes.
32. While `desktop-lock` is `on` and a usable keyboard is present, or after K07, Switch to Desktop is shown and runs spec 02's lock command before any desktop frame. Before K07, with `on` and no usable keyboard, the row is shown disabled, reads “Connect a keyboard to unlock”, and activating it does nothing beyond that hint. `desktop()` returns to gaming instead of a lock screen.
33. A critical battery alert and a critical thermal alert are still shown when the overlay client is not running, and when mangoapp holds the slot. `omarchy-quick slot preempt` hides mangoapp when the owner is up. When preempt cannot run, a Steam-client notice is the fallback. How a non-Steam process posts that notice is unverified. UPower's critical action does not depend on this path. The alert is not dropped.
34. Every tuple written, on AC and on battery, for every SPL from 7 W through the cap, and after `--reassert`, satisfies SPL ≤ SPPT ≤ FPPT. A canonical set below 7 W clamps up to 7 W before that check. A write that would break the order writes nothing.
35. Under `bin/omarchy-launch-gaming-overlay --gamescope` without `--xwayland-count 2`, the overlay does not paint and AC long opens QAM.
36. `SIGSTOP` of the client while it is open is recovered by `WatchdogSec=1s` and `TimeoutStopSec=1s`: `InterceptMode` returns to `0`, mangoapp is restored, and the game receives input. A default stop timeout does not. This is the second route. It is not the Armoury escape.
37. Crashing the client 3 times in a row, with mangoapp visible beforehand, leaves the HUD visible. The next AC long opens QAM, and hub Status says the restart limit was hit. Separately, the escape uses spec 07 AC 18's rig: a test drop-in sets this unit's `WatchdogSec=0` and an empty `ExecStopPost=`, or a scratch process sets `InterceptMode` to 2 with `busctl` and is then stopped. On the overlay path the client is `SIGSTOP`ped, or a test hook ignores AC long, so the overlay does not close itself before the bridge's deadline. F17 arrives with `InterceptMode` still non-zero. About 1.2 s later `InterceptMode` is 0, `busctl monitor` shows that Set from the gaming bridge's unique name, and QAM does not open. After `SIGCONT` the client sees that external 0 and closes fully (atom 0, mangoapp restored), which is AC 41. A later AC long, once the overlay is gone, opens QAM by the normal path.
38. On that escape, InputPlumber reports `InterceptMode` `0`. The read is `omarchy-hw-rog-ally-input status`, from InputPlumber's D-Bus property. It is not a reply from the overlay client. Any non-zero value before that 0 counts as intercepted.
39. The overlay does not take intercept unless `omarchy-rog-ally-input-gaming.service` has `ActiveState=active`. `activating`, auto-restart and `failed` refuse. AC long opens QAM and `InterceptMode` stays `0`.
40. The overlay unit has `BindsTo=` and `After=` on `omarchy-rog-ally-input-gaming.service`, and `BindsTo=` and `After=` on `omarchy-gaming-session.target` (the user target from [PR #34](https://github.com/DanielJBurbridge/omarchy/pull/34)). Stopping or failing the bridge, or stopping that target, while the overlay is open stops the overlay unit. Within 1 s, `ExecStopPost` has set `intercept none`, `InterceptMode` is `0`, and the overlay is closed.
41. A `PropertiesChanged` to `InterceptMode` `0` that this client did not set closes the overlay fully (atom 0, mangoapp restored). It does not take intercept again until the next AC long.

## Device tests

The shim is in the tree. The check still to run is that Steam's QAM shows a TDP slider when `omarchy-ally-tdp-shim` holds `com.steampowered.SteamOSManager1` on the session bus inside this Gamescope session. The 12 Nov review is [tdp-decision-review.md](tdp-decision-review.md).

| # | Test | Pass |
|---|---|---|
| T1 | On the RC71L, in a Gamescope 3.17.0 DRM session launched with `--xwayland-count 2` and `-e`, an output-sized `GAMESCOPE_EXTERNAL_OVERLAY` window on the root Xwayland draws above a fullscreen Steam game and above Steam's library, with opacity above 0 and no focus change, on the internal panel and on an external display. That Steam-launched game does not take the slot. Repeat with mangoapp visible beforehand: open takes the slot, close and a killed client give it back. | The game keeps input focus. The overlay is visible on both outputs. Mangoapp returns to the state it had. **Not yet run on the RC71L.** |
| T2 | With the overlay open, suspend and resume to Steam's PIN. The overlay's own close is on `PrepareForSleep(true)`. Ordering is spec 02 §7.7. | Before any paint on resume the lock check runs again. If the overlay is still open and the state is not game-focused, it closes fully before any paint. The PIN is visible, it takes controller input, and the overlay does not paint. `InterceptMode` is `0`. T2 records `GAMESCOPE_FOCUSED_APP` on the library and on the PIN, and whether those tuples differ. Until they differ, the overlay opens over a game only. Game-focused uses `GAMESCOPE_FOCUS_DISPLAY` on `STEAM_GAME_DISPLAY_0` and a `GAMESCOPE_FOCUSED_APP` that is not 0 and not that Steam id. **Not yet run.** |
| T3 | In this Gamescope session, use Steam's own Switch to Desktop while Steam is locked. | Record whether Steam asks for the PIN. AC 31 stays unverified until this passes. **Not yet run.** |
| T4 | On the RC71L: `power1_input` under load on battery at `--set` 15, 20 and 25. | 15 W and 20 W settle near those limits. 25 W clamps, and measured power stays at the 20/20/25 tuple. **Not yet run.** |

## 10. Open questions

OQ-1 moved to device test T1.

| # | Question | Owner |
|---|---|---|
| OQ-2 | v1 is settled by [research/gamescope-external-overlay.md](research/gamescope-external-overlay.md): the overlay window gets no touch, and input is InputPlumber only. A later pointer path would set Steam's focus atoms and would be a focus change. Is that path ever wanted? | dev-research |
| OQ-3 | Overlay client toolkit inside Gamescope (Quickshell under Xwayland vs a small Qt/QML X11 app)? | dev-lead |
| OQ-4 | Brightness in gaming: does Steam's own slider fight `omarchy-brightness-display` on RC71L? | Hardware test |
| OQ-5 | Charge limit is not a verb of `omarchy-ally-tdp-apply`, and `BatteryChargeLimit1` is not in the shim. Later owner: that interface, or a small polkit-gated helper for `charge_control_end_threshold`? The row stays read-only until that choice ships. Not `steamos-manager`. | POWER |
| OQ-6 | Should AC long in gaming be configurable (overlay vs QAM vs screenshot)? Spec 01 revision 1 already points AC long at this overlay. | Daniel |
| OQ-7 | Live frame limit in gaming without steamos-manager: does Steam's QAM limiter work under Omarchy's Gamescope session? | Hardware test |
| OQ-8 | Decky plugin calling `omarchy-quick` (D8): worth maintaining given root plugins? | dev-lead |
| OQ-9 | Fan “mode” (asus-wmi throttle policy) as a separate row, or always tied to profile? | POWER |

## 11. Branch conflicts

| Conflict | Where | Resolution proposed |
|---|---|---|
| AC long = screenshot | Spec 01 first draft | Spec 01 revision 1 already superseded that: AC long is this overlay. Row 14 is the overlay's screenshot control. Steam's QAM and Edge shortcut remain the path spec 01 names. |
| “Armoury short invokes Steam QAM. Long switches mode only in Hyprland.” | `bin/omarchy-hw-rog-ally-input --help` on `feat/ally-input-20261111` | Gaming long now opens the overlay (needs the `gaming` profile, spec 01). |
| Old Manager client | Those files are not on this branch. | D6: do not install Manager. The session install masks PPD, records the previous state, and `remove-session` restores it. The shim is `omarchy-ally-tdp-shim`. The writer is in the tree. |
| `asusd` running on Daniel's unit | `docs/handheld/research/ally-hw-dump.md` (this branch) | asusd stays off on RC71L. If it is running, power rows are read-only. Spec 03 W7 focuses Disable asusd; declining stays in hub Status. |
| Desktop CC tap = power panel | spec 01 baseline | Δ1 moves it to `omarchy.quick`; `omarchy.power` is the fallback. |
| GameMode | `bin/omarchy-ally-tdp-apply` refuses `--set` and skips background reapply while `gamemoded.service` is active | Performance rows read-only while GameMode is active. |
| Profile switch while PPD is masked | `bin/omarchy-powerprofiles-set` when `/var/lib/omarchy/handheld/power-profiles-daemon.state` exists | It sends the preset to `omarchy-ally-tdp-apply --set-profile`. |
| Switch to Desktop, the disabled keyboard row, and the pre-K07 return to gaming | [PR #36](https://github.com/DanielJBurbridge/omarchy/pull/36) (`cursor/spec-02-suspend-lock-ruling-29cd`), still open | Merge order is #36, then [PR #30](https://github.com/DanielJBurbridge/omarchy/pull/30), then this PR. Spec 04 cites spec 02 as PR #36 amends it, including §7.7 for closing on suspend, and does not restate that design. |
| Armoury escape while the overlay is open | Spec 01's Hyprland bridge, `omarchy-rog-ally-input.service`, does not run in Gaming Mode and does not clear an overlay intercept | The owner is `omarchy-rog-ally-input-gaming.service`. The trigger is F17 + 1 s (spec 07 §3.6, [PR #30](https://github.com/DanielJBurbridge/omarchy/pull/30)): `InterceptMode` last seen when F17 arrives is non-zero, and if it is still non-zero 1 s later the bridge forces it to 0. The bridge does not open QAM. The overlay unit `BindsTo=` that service and `omarchy-gaming-session.target` ([PR #34](https://github.com/DanielJBurbridge/omarchy/pull/34)). `ActiveState` must be `active` (AC 39, AC 40). `WatchdogSec=1s` is the second route. |

## Sources

- This branch: `bin/omarchy-powerprofiles-list`, `bin/omarchy-powerprofiles-set` (PPD path), `default/hypr/bindings/media.lua`, `bin/omarchy-audio-output-volume`, `bin/omarchy-brightness-display`, `bin/omarchy-bluetooth-power`, `bin/omarchy-capture-screenshot`, `shell/plugins/panels/{audio,bluetooth,network,monitor,power}/manifest.json`, `docs/omarchy-shell.md`, `docs/theming.md` (`~/.local/state/omarchy/current/theme`).
- This branch: `bin/omarchy-ally-tdp-apply`, `bin/omarchy-ally-tdp-shim`, `bin/omarchy-ally-tdp-install`, `bin/omarchy-powerprofiles-set`, `default/polkit/org.omarchy.ally.set-tdp.policy`, `default/ally-tdp/NOTICE.steamos-manager`, `default/systemd/system/omarchy-ally-tdp-resume.service`, `default/systemd/system/omarchy-ally-tdp-source.service`, `default/udev/99-omarchy-ally-tdp.rules`, `install/hardware/asus/ally-tdp.sh`.
- `feat/ally-input-20261111`: `bin/omarchy-hw-rog-ally-input`, `default/rog-ally-input/bridge.py`, `default/rog-ally-input/omarchy-rog-ally-input.service` (Hyprland only). The Armoury escape is F17 + 1 s (spec 07 §3.6, [PR #30](https://github.com/DanielJBurbridge/omarchy/pull/30), `docs/handheld/07-on-screen-keyboard.md`). `InterceptMode` last seen when F17 arrives is non-zero, and if it is still non-zero 1 s later the bridge forces it to 0. `WatchdogSec=1s` is the second route. The overlay unit `BindsTo=` and `After=` `omarchy-rog-ally-input-gaming.service`, and `BindsTo=` and `After=` `omarchy-gaming-session.target`, the user target from [PR #34](https://github.com/DanielJBurbridge/omarchy/pull/34).
- `feat/ally-session-20261111`: `bin/omarchy-setup-gaming-session`, `bin/omarchy-launch-gaming-session`, `bin/omarchy-launch-gaming-desktop`, `docs/rog-ally-gaming-session.md`.
- `feat/ally-games-performance-20261111`: `bin/omarchy-launch-gaming-overlay`, `bin/omarchy-setup-gaming-decky`.
- `feat/ally-display-20261111`: `bin/omarchy-display-rog-ally`.
- `feat/ally-recovery-20261111` and `feat/ally-parity-release-20261111`: `bin/omarchy-setup-rog-ally`.
- This branch: `docs/handheld/research/accessibility.md`, `docs/handheld/research/parity-matrix.md`, `docs/handheld/research/ally-hw-dump.md`.
- [tdp-decision-review.md](tdp-decision-review.md) is the 12 Nov review. The contract on this tip is §5.1. The writer and the shim are in the tree. Stock steamos-manager stays out.
- Lead ruling, 12 Nov 2026, from [research/gamescope-external-overlay.md](research/gamescope-external-overlay.md) on this branch (PR #31, merged, with the PR #35 follow-ups). It reads Gamescope tag 3.17.0 (`e6674a98118ca7b098b98a3874b8f195ae1bf750`). The self-check uses `DISPLAY` (server 0), `STEAM_MULTIPLE_XWAYLANDS`, and `STEAM_GAME_DISPLAY_0`. The Steam-lock check re-reads those four properties on every paint and on `PropertyNotify`. Game-focused is the only unlocked state. Closing on `PrepareForSleep(true)` is this overlay's own behaviour. If it is still open on resume and the state is not game-focused, it closes fully before any paint. If this overlay is the suspend source, it closes fully before `omarchy-handheld-suspend-request`. Ordering is spec 02 §7.7 on [PR #36](https://github.com/DanielJBurbridge/omarchy/pull/36). The RC71L session in that note was not run. Device test T1 is still outstanding.
- External: [gamescope #288 external overlay](https://github.com/ValveSoftware/gamescope/issues/288); [steamcompmgr z-order](https://deepwiki.com/bazzite-org/gamescope/2.2-x11-window-manager-(steamcompmgr)); [loadout Gamescope overlay notes](https://github.com/srsholmes/loadout/blob/main/docs/overlay-gamescope-integration.md); [OpenGamepadUI InputPlumber PR #332](https://github.com/ShadowBlip/OpenGamepadUI/pull/332); [steamos-manager RC71L TOML](https://gitlab.steamos.cloud/holo/steamos-manager/-/blob/master/data/devices/rog-ally-series.toml); [Bazzite handheld wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/); [GoL Bazzite 44](https://www.gamingonlinux.com/2026/08/bazzite-linux-44-for-handhelds-finally-launches-with-some-massive-upgrades/); [CachyOS steamos-manager PKGBUILD](https://github.com/CachyOS/CachyOS-PKGBUILDS/tree/master/handheld/steamos-manager).
