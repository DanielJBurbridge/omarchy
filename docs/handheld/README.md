# Omarchy Handheld UX specs

Status: draft, 12 Nov 2026. Owner: dev-ux. Hand-off: dev-lead. Target branch for PRs: `feat/ally-parity-integration-20261111`. Spec 01 is at revision 2 (OQ-13 closed; matrix re-checked after the quattro sync).

Primary device: original 2023 ASUS ROG Ally **RC71L** (Z1 / Z1 Extreme). Secondary (design for, verify later): Ally X (RC72LA), Xbox Ally (RC73X/Y), Lenovo Legion Go, Steam Deck, MSI Claw.

## Index

| # | Spec | Status |
|---|---|---|
| 01 | [Controller and button map](01-controller-button-map.md) | Draft, revision 2 |
| 02 | [Mode switch (gaming ⇄ desktop) and dock / undock](02-mode-switch-and-dock.md) | Draft, revision 2 |
| 03 | First boot and install flow (handheld variant) | TODO |
| 04 | Quick-access overlay: TDP, fan, RGB, brightness, performance profile | TODO |
| 05 | Notifications (gaming and desktop) | TODO |
| 06 | Accessibility: text size, contrast, haptics, one-handed | TODO |
| 07 | On-screen keyboard (desktop wvkbd and Steam OSK) | TODO |

Out of scope for now: lock screen, greeter and disk-unlock design (AUTH owns those surfaces).

## Principles

| # | Principle | What it means in practice |
|---|---|---|
| P1 | Undocked = gaming, docked = desktop | Default session undocked is Gamescope + Steam; docked is Omarchy Hyprland. Details in spec 02. |
| P2 | Still Omarchy | Controller actions call existing Omarchy entry points (`omarchy-menu`, `omarchy-shell` panels, Hyprland binds in `default/hypr/bindings/*.lua`, `bin/omarchy-*`). No parallel launcher, no second theme system. |
| P3 | One input owner | InputPlumber (lead decision, 12 Nov) owns the physical controller. Steam Input consumes its virtual pad. Nothing else grabs the devices. |
| P4 | Steam owns games | In gamepad mode Omarchy never rebinds face buttons, sticks or triggers; per-game layouts stay in Steam Input. |
| P5 | Build on what ships | `feat/ally-input-20261111` (InputPlumber profiles + bridge) is the baseline. Specs list each change against it with rationale. |
| P6 | Fail safe | Unknown/locked/inactive Hyprland session ⇒ gamepad profile, no desktop actions. A gaming session keeps its own profile (spec 01). A broken daemon must leave firmware controls usable. |
| P7 | Verify on hardware | Anything not exercised on the RC71L is an open question, not a feature. Source tests ≠ physical acceptance. |
| P8 | Tables over prose | Australian English, concise, testable acceptance criteria. |

## Glossary

| Term | Meaning |
|---|---|
| AC | Armoury Crate button. **Right** side of the RC71L screen, below Menu. InputPlumber `QuickAccess` (tap) / `QuickAccess2` (long). The long press is a real firmware key (`KEY_F17`). |
| CC | Command Centre button. **Left** side of the RC71L screen, below View. InputPlumber `Guide` (tap) / `Keyboard` (long). The long press is not a separate hold code: firmware sends Ctrl+Alt+Delete, or `KEY_F20` when `hid-asus-ally` is present. |
| View / Menu | Xbox-style Select / Start (`BTN_SELECT` / `BTN_START`). These have a real press and release. CC and AC do not. |
| M1 / M2 | Back grips, left / right. InputPlumber names `LeftPaddle1` / `RightPaddle1` are not yet proven to match those sides (spec 01, OQ-1, OQ-17). Not on the xpad pad; they arrive via the ASUS N-KEY HID interface, and on the stock Omarchy kernel they may not arrive at all. |
| N-KEY | ASUS USB HID device `0b05:1abe` (driver `hid-asus`); interface 2 carries the OEM buttons and paddles. |
| Game mode | Gamescope session with Steam (Big Picture / Gaming Mode UI). Controller in the `gaming` profile (DualSense Edge target; spec 01). `gamepad` (Xbox Elite) remains the shipped fallback. |
| Desktop mode | Omarchy Hyprland session. Controller in `desktop` profile (mouse + keyboard targets only). |
| Controller profile | InputPlumber DeviceProfile loaded on the composite device: `desktop`, `gamepad`, `dualsense` (shipped), `gaming` / `osk` / `swap` / `hand-left` / `hand-right` (proposed). |
| Bridge | `default/rog-ally-input/bridge.py`: user service that switches profiles on session/lock state and runs desktop actions from D-Bus events. |
| QAM | Steam Quick Access Menu (right-hand panel in Gaming Mode). |
| OSK | On-screen keyboard: Steam OSK in game mode, wvkbd (`omarchy-toggle-desktop-keyboard`) in desktop mode. |
| Tap / Long | OEM-button gestures. Armoury long is a firmware key. Command Centre long is a different firmware chord or key. Neither is a userspace hold timer. |
| Omarchy menu | `omarchy-menu` (Super + Space), entries in `default/omarchy/omarchy-menu.jsonc`. |
| Quick-access overlay | Omarchy's own TDP/fan/RGB/brightness/perf overlay (spec 04). Not built yet. |
| Dock | USB-C dock/hub with external display; triggers desktop (spec 02). |
