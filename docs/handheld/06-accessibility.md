# 06 · Accessibility

Status: draft, 12 Nov 2026 (AWST). Owner: dev-ux. Source research: [`docs/handheld/research/accessibility.md`](research/accessibility.md). Depends on: [01](01-controller-button-map.md) (profiles), [03](03-first-boot-and-install.md) (first boot), [04](04-quick-access-overlay.md) §4.1 (quick toggles), [07](07-on-screen-keyboard.md) (OSK). Rulings applied: no extra Ally binds (swap/fullscreen are menu/overlay only); `SUPER + CTRL + X` is taken (Agents); Steam accessibility via steamos-manager stays an unverified OQ.

## 0. Decisions in one table

| # | Decision | Source |
|---|---|---|
| D1 | **No hold-only system action** anywhere; every hold has a menu or overlay route. | Research rec. 2, red team |
| D2 | One **Accessibility** page in the Omarchy menu (desktop) and an Accessibility section in the overlay (both sessions); each toggle persists and is reversible from the same place. | P2 |
| D3 | Desktop pack: magnifier (existing zoom), colour filters (Hyprland `screen_shader`), reduce motion, sticky keys (`keyd`), mono audio (PipeWire), OSK (wvkbd), haptics slider (when the driver exists). | Research |
| D4 | Default text size on the 7" 1080p panel = **scale 1.5** (1280×720 logical, existing touch preset); “Larger” = 1.75, “Largest” = 2.0. | `docs/rog-ally-display.md`, research |
| D5 | Contrast is a **theme**, not a shader: ship “High Contrast Dark/Light” Omarchy themes that meet WCAG 7:1 for text. | Research rec. 6 |
| D6 | One-handed presets are InputPlumber profiles, selectable from the overlay (spec 04 row 12). | Research, spec 04 |
| D7 | Gaming mode relies on Steam's own settings; the Steam screen reader and colour filters are **unverified** without steamos-manager (OQ-1). Omarchy does not claim them. | Ruling 12 Nov |
| D8 | Orca on Hyprland is documented **honestly** as partial (§6). | Research |
| D9 | First boot offers an accessibility entry before any typing (spec 03 ISO step 2 and W1). | Brief |

## 1. Baseline: what is already built

| Piece | Path (branch) | Note |
|---|---|---|
| Magnifier | `default/hypr/bindings/utilities.lua`: `SUPER + CTRL + Z` zoom in (`cursor.zoom_factor + 1`), `SUPER + CTRL + ALT + Z` reset | Keyboard only; controller route needed. |
| Scaling / touch preset | `bin/omarchy-display-rog-ally touch-preset` (`feat/ally-display-20261111`): internal 1.5×, bar ≥ 44 logical units | Text size base. |
| Themes | Omarchy theme system (`omarchy-menu` theme, `SUPER + CTRL + T`) | Contrast themes slot in here. |
| OSK | `bin/omarchy-toggle-desktop-keyboard`, `docs/rog-ally-touch-keyboard.md` (`feat/ally-touch-20261111`) | Spec 07. |
| Input profiles | `default/rog-ally-input/profiles/*.yaml`, `default/rog-ally-input/bridge.py` (`feat/ally-input-20261111`; also `feat/ally-parity-release-20261111`, not the integration tip) | Presets build on these. |
| SDDM touch keyboard | `default/sddm/omarchy/Main.qml` (Qt VK) and `etc/sddm.conf.d/10-wayland.conf` (`GreeterEnvironment`) on `feat/ally-auth-20261111` (also `feat/ally-parity-release-20261111`). The integration tip's copies have neither the Qt keyboard nor `GreeterEnvironment`. | Greeter is usable by touch. |
| Lock touch keyboard | K07 **held** (`docs/rog-ally-authentication.md` on `feat/ally-auth-20261111`; also the release branch, not the integration tip) | Why `desktop-lock` ships off. |

## 2. How others do it (from research)

| Need | Steam / SteamOS | Hyprland today | Gap |
|---|---|---|---|
| Screen reader | SteamOS-only built-in reader (Orca-based) | Orca for AT-SPI apps; no global key grabs (no KeyboardMonitor) | High |
| Text size | Steam UI scale | Monitor + GTK/Qt scale | Low |
| Colour filters | SteamOS greyscale/invert ([Verge](https://www.theverge.com/games/689922/steam-is-adding-screen-reader-support-and-other-accessibility-tools)) | `decoration:screen_shader` | Medium |
| High contrast | Steam toggle | Theme only | Medium |
| Reduce motion | Steam toggle | `animations:enabled = false` | Low |
| Mono audio | SteamOS 3.8 option | PipeWire loopback ([docs](https://docs.pipewire.org/page_module_loopback.html)) | Low |
| Remapping / one-handed | Steam Input layouts | InputPlumber profiles ([usage](https://github.com/ShadowBlip/InputPlumber/blob/main/docs/usage.md)) | Medium |
| Sticky keys | — | `keyd` oneshot ([ArchWiki Accessibility](https://wiki.archlinux.org/title/Accessibility)) | Medium |

## 3. Desktop pack

| Feature | Control | Backend | Controller route | Persist |
|---|---|---|---|---|
| Magnifier | Off · 2× · 3× · 4×; follows pointer | Hyprland `cursor:zoom_factor` (existing binds) | Overlay → Accessibility → Zoom; while zoomed, right stick moves the pointer (desktop profile) | No (session) |
| Colour filter | Off · Greyscale · Invert · Deuteranopia · Protanopia · Tritanopia | `decoration:screen_shader` with proposed GLSL in `default/hypr/shaders/` (Δ-A1). That directory is absent on the integration tip, `feat/ally-input-20261111`, `feat/ally-session-20261111` and `feat/ally-parity-release-20261111`. | Overlay | Yes |
| Reduce motion | On/off | `animations:enabled` + shell animation scale 0 | Overlay | Yes |
| Sticky keys | On/off | `keyd` (`extra`) config with `oneshot` modifiers for physical keyboards; wvkbd modifiers are already one-shot | Menu | Yes |
| Mono audio | On/off | `~/.config/pipewire/pipewire.conf.d/omarchy-mono.conf` (`filter.smart` loopback, `audio.position=[MONO]`), PipeWire restart | Overlay (both sessions) | Yes |
| On-screen keyboard | Show/hide, size | wvkbd (spec 07) | CC long / menu / bar | — |
| Haptics strength | 0–100 % | `gamepad_vibration_intensity` (`hid-asus-ally`, out of tree) or InputPlumber force-feedback D-Bus | Overlay | Yes; **hidden on stock kernel** |
| Key repeat | Delay/rate | Hyprland `input:repeat_*` | Menu | Yes |
| Text size | Normal (1.5) · Larger (1.75) · Largest (2.0) | Monitor scale on the internal panel + Omarchy font scale | Overlay / menu | Yes |
| Contrast theme | High Contrast Dark / Light | Omarchy theme | Menu → Theme | Yes |
| Screen reader | Start/stop Orca | `orca`, `speech-dispatcher`, `espeak-ng` | Menu (no bind) | No |

Red-team rules for toggles:

| Rule | Spec |
|---|---|
| Revert | Colour filter, text size and contrast changes show a 15 s “Keep this?” card; **Revert** is focused; no answer ⇒ revert. Input ignored for 500 ms. |
| Unknown value | Unreadable setting ⇒ default (off / scale 1.5), never a partial state. |
| Daemon death | PipeWire restart failure ⇒ remove the mono file and restart again (stereo). keyd crash ⇒ keyboard works unmodified. |

## 4. Text size on a 7" 1080p panel

| Option | Scale | Logical desktop | Notes |
|---|---|---|---|
| Normal | 1.5 | 1280×720 | Existing touch preset; touch targets ≥ 44 logical units |
| Larger | 1.75 | ≈1097×617 | Check bar, overlay (420 px) and wvkbd (264 units) still fit (AC 6) |
| Largest | 2.0 | 960×540 | wvkbd covers half the height; Omarchy menu must scroll |
| Docked | per monitor | — | External monitor keeps its own scale (`omarchy-display-rog-ally` dock profiles) |

Gaming: Steam's UI scale only; Omarchy overlay text follows the desktop choice.

## 5. One-handed and motor presets

Spec 01 has no §11.2; presets live in spec 04 row 12 and Appendix A profiles. Defined here:

| Preset | Gaming (same target, profile only) | Desktop |
|---|---|---|
| Standard | Baseline `gaming` | Baseline `desktop` |
| One-handed left | M1 = A, View = B, LB = Menu; d-pad + left stick unchanged | Left stick = pointer, LB/LT = clicks, M1 = Enter |
| One-handed right | M2 = d-pad up/down toggle layer (TBC), right stick unchanged, RB = View | Right stick = pointer (baseline), RB/RT = clicks |
| Paddles = A/B | M1 = A, M2 = B | M1 = left click, M2 = right click |
| Sticky triggers | Not in gaming (Steam Input owns per-game toggles) | LT/RT click latches drag |

| Rule | Spec |
|---|---|
| Switch | Key-ups first, load, wait ready; failure ⇒ atomic fallback to Standard (spec 04 §7). |
| Paddles | Need `hid-asus-ally`; presets that use paddles are hidden without it. |
| Per-game | Steam Input per-game layouts stay Steam's (P4). |

## 6. Screen reader: what works, honestly

| Context | State | Limits |
|---|---|---|
| Hyprland apps (GTK, Qt with `QT_ACCESSIBILITY=1`, Chromium with accessibility on) | Orca reads focused AT-SPI content | Orca's own key commands (Insert/CapsLock modifier) do **not** work: Hyprland has no KeyboardMonitor-style global key access, by design (keylogging concern). Use menu entries to start/stop. |
| Omarchy shell (Quickshell) | Partial; depends on QML accessible names (OQ-3) | Not audited. |
| Terminal (Ghostty/Alacritty) | Limited | Terminal text is not exposed through AT-SPI. |
| Gaming (Steam) | **Unverified**: Steam's reader appeared on SteamOS; may need steamos-manager (OQ-1) | Omarchy ships no gaming screen reader claim. |
| Installer / first boot (TTY) | Not available; `espeakup` speech in TTY is a candidate (OQ-4) | Say so on the ISO accessibility screen. |
| SDDM greeter / lock | AUTH | Requirement only: accessible names on fields and buttons. |

## 7. Gaming mode

| Feature | Route | State |
|---|---|---|
| UI scale, high contrast, reduce motion | Steam ▸ Settings ▸ Accessibility | Steam-owned |
| Screen reader, colour filters | Steam ▸ Settings ▸ Accessibility | **Unverified** without steamos-manager (OQ-1); backlog #10 (power writer) and backlog #11 (Steam TDP shim) do not provide these interfaces (`tdp-decision-review.md`) |
| Mono audio | Overlay (PipeWire, shared) | Omarchy |
| One-handed presets | Overlay | Omarchy |
| Colour filter | Not available (Hyprland shaders don't reach Gamescope); overlay row says so | Gap (OQ-2) |

## 8. First-boot accessibility entry (spec 03)

| Where | Offer | Backend |
|---|---|---|
| ISO step 2 (Language) | “Accessibility” item: Larger text, High contrast | TTY: larger console font (`setfont`, e.g. Terminus 32), inverted palette; carried to first boot |
| First boot W1 | Same item at the top of the form | Same; choices written to the new user's settings at W9 (scale 1.75/2.0, contrast theme, reduce motion) |
| W4 controller test | “Use one-handed controls” | Applies a preset from §5 |
| After W9 | First desktop entry opens nothing extra; Accessibility page reachable from overlay | — |

## 9. User flows

| # | Flow | Steps |
|---|---|---|
| F1 | Low vision first boot | ISO Accessibility → Larger text + High contrast → install → first boot form in large font → desktop/overlay at scale 1.75 with High Contrast Dark. |
| F2 | Colour filter | CC tap → Accessibility → Colour filter → Deuteranopia → A → “Keep this?” (Revert focused) → → Keep → A. |
| F3 | One-handed play | AC long → Controller → One-handed left → A. |
| F4 | Mono audio in game | AC long → Accessibility → Mono → A (PipeWire restarts; brief audio gap). |
| F5 | Magnify | CC tap → Accessibility → Zoom 2× → right stick pans → Zoom off. |

## 10. Acceptance criteria

1. Every accessibility toggle is reachable by controller without a long press, from the overlay or Omarchy menu.
2. Colour filter, text size and contrast changes revert after 15 s without confirmation; Revert is focused and input is ignored for the first 500 ms.
3. Each colour filter applies on the internal and an external monitor on desktop; in gaming the row is disabled with its reason.
4. Mono toggle produces identical L/R output (loopback measurement) in both sessions and restores stereo when off; a failed PipeWire restart ends in stereo.
5. Sticky keys via keyd: Ctrl tap then C copies in a GTK app; disabling restores normal modifiers.
6. At scale 1.75 and 2.0 the bar, overlay, Omarchy menu and wvkbd are fully usable (no clipped controls) on the 1080p panel.
7. High Contrast themes meet 7:1 for body text (automated contrast check of theme colours).
8. One-handed presets load with key-ups first and fall back to Standard on failure; paddle presets are hidden without `hid-asus-ally`.
9. Haptics row is hidden on the stock Omarchy kernel and present when the attribute exists.
10. Orca starts from the menu and reads a GTK app's focused button; the docs state the key-command limit.
11. ISO/first-boot accessibility choices carry into the installed user's desktop.
12. No new Hyprland/Ally binds are added (zoom keeps its existing binds; `SUPER + CTRL + X` untouched).

## 11. Open questions

| # | Question | Owner |
|---|---|---|
| OQ-1 | Does Steam expose its screen reader and colour filters on Omarchy's Gamescope session, and do they require steamos-manager interfaces that backlog #10 (power writer) and backlog #11 (Steam TDP shim) do not provide (`tdp-decision-review.md`)? | dev-research / hardware test |
| OQ-2 | Gamescope-level colour filter (e.g. `--lut` / colour management options) for gaming CVD support? | dev-research |
| OQ-3 | Quickshell/QML accessibility audit of Omarchy shell surfaces (menu, overlay, notifications). | dev-lead |
| OQ-4 | `espeakup` (TTY speech) on the ISO and first boot: package availability and buffyboard interplay. | dev-research |
| OQ-5 | Licence and adoption of the community “Beacon” accessibility plugin mentioned in research. | dev-lead |
| OQ-6 | One-handed right layout: which button carries the missing d-pad (layer toggle vs paddle)? | Daniel (press test) |
| OQ-7 | Hyprland KeyboardMonitor-equivalent upstream (permission-gated) for Orca. | upstream |

## 12. Branch conflicts

| Conflict | Where | Resolution proposed |
|---|---|---|
| Zoom is keyboard-only | `default/hypr/bindings/utilities.lua` | Add overlay route; no new binds. |
| Paddle presets vs stock kernel | `docs/handheld/research/ally-hw-dump.md` (xpad, no paddles) | Hidden until `hid-asus-ally`. |
| Lock has no touch keyboard | `feat/ally-auth-20261111` K07 | `desktop-lock` ships off (ruling); AUTH requirement in spec 07. |
| Scale 1.75/2.0 vs touch preset 1.5 | `feat/ally-display-20261111` | Text size is a separate setting layered on the preset. |

## Sources

- Research: `docs/handheld/research/accessibility.md`, `docs/handheld/research/parity-matrix.md`, `docs/handheld/research/ally-hw-dump.md`.
- Power ownership: `tdp-decision-review.md` (team-box TDP decision review; not a file in this repo). backlog #10 is the power writer and backlog #11 is the Steam TDP shim. Neither is a pull request.
- Fork: `default/hypr/bindings/utilities.lua` (default branch); `docs/rog-ally-display.md` (`feat/ally-display-20261111`); `docs/rog-ally-touch-keyboard.md` (`feat/ally-touch-20261111`); `docs/rog-ally-authentication.md` (`feat/ally-auth-20261111`); `default/rog-ally-input/` (`feat/ally-input-20261111`).
- External: [Steam accessibility (The Verge)](https://www.theverge.com/games/689922/steam-is-adding-screen-reader-support-and-other-accessibility-tools); [PipeWire loopback](https://docs.pipewire.org/page_module_loopback.html); [ArchWiki Accessibility](https://wiki.archlinux.org/title/Accessibility); [InputPlumber usage](https://github.com/ShadowBlip/InputPlumber/blob/main/docs/usage.md); [CachyOS handheld kernel patch (`hid-asus-ally`)](https://raw.githubusercontent.com/cachyos/kernel-patches/master/6.19/misc/0001-handheld.patch).
