# Omarchy Handheld UX specs

Start with the [feature-parity checklist](feature-parity.md) for what works on the original ROG Ally RC71L, which build was tested and what still needs hardware. The physical results are from a Z1 Extreme. The Z1, Ally X and Xbox Ally need their own acceptance runs.

The [alpha guide](ALPHA.md) covers installation and recovery. The [Gaming session reference](../rog-ally-gaming-session.md) covers the optional companion, session preferences and desktop controls. The narrow installer draft detects the RC71L and offers Gaming setup at first login. The full handheld desktop and the touch-driven installer wizard have separate development and test histories.

The specifications below describe the intended experience. The [16 November handoff](HANDOFF-20261116.md) records an earlier deployment.

## Index

| # | Spec | Status |
|---|---|---|
| 01 | [Controller and button map](01-controller-button-map.md) | Draft, revision 4 |
| 02 | [Mode switch (gaming ⇄ desktop) and dock / undock](02-mode-switch-and-dock.md) | Draft, revision 12 |
| 03 | [First boot and install flow (handheld variant)](03-first-boot-and-install.md) | Draft, revision 1 |
| 04 | [Quick-access overlay: TDP, fan, RGB, brightness, performance profile](04-quick-access-overlay.md) | Draft, revision 2 |
| 05 | [Notifications (gaming and desktop)](05-notifications.md) | Draft, revision 3 |
| 06 | [Accessibility: text size, contrast, haptics, one-handed](06-accessibility.md) | Draft, revision 3 |
| 07 | [On-screen keyboard (desktop wvkbd and Steam OSK)](07-on-screen-keyboard.md) | Draft, revision 8 |
| 08 | [Mode round trip (gaming ⇄ desktop)](08-mode-round-trip.md) | Draft, revision 1 |
| 09 | [Keyboard-free boot](09-keyboard-free-boot.md) | Draft, revision 2 |
| 10 | [Disk unlock (installer choice)](tpm-unlock-installer-spec.md) | Proposed TPM2 unlock with a retained recovery passphrase |
| 11 | [Undocked touch desktop](11-undocked-touch-desktop.md) | Draft, 16 Nov 2026. No dock, no keyboard |
| — | [TPM unlock runbook](tpm-unlock.md) | Procedure for an installed machine |

Lock-screen and greeter UI stay with AUTH. Disk unlock for a handheld install is spec 10. Spec 09 states the keyboard-free requirements on the greeter and the lock, and the TPM branch of the boot. The matching research is [research/touch-first-boot.md](research/touch-first-boot.md), which lands via [PR #45](https://github.com/DanielJBurbridge/omarchy/pull/45).

## Principles

| # | Principle | What it means in practice |
|---|---|---|
| P1 | Undocked = gaming, docked = desktop | Default session undocked is Gamescope + Steam; docked is Omarchy Hyprland. Details in spec 02. |
| P2 | Still Omarchy | Controller actions call existing Omarchy entry points (`omarchy-menu`, `omarchy-shell` panels, Hyprland binds in `default/hypr/bindings/*.lua`, `bin/omarchy-*`). No parallel launcher, no second theme system. |
| P3 | One input owner | InputPlumber (lead decision, 12 Nov) owns the physical controller. Steam Input consumes its virtual pad. Nothing else grabs the devices. |
| P4 | Steam owns games | In gamepad mode Omarchy never rebinds face buttons, sticks or triggers; per-game layouts stay in Steam Input. |
| P5 | Build on what ships | Use the controller profiles in `default/inputplumber/profiles/` and existing Omarchy commands and panels. |
| P6 | Fail safe | Unknown/locked/inactive Hyprland session ⇒ gamepad profile, no desktop actions. A gaming session keeps its own profile (spec 01). A broken daemon must leave firmware controls usable. |
| P7 | Verify on hardware | Anything not exercised on the RC71L is an open question, not a feature. Source tests ≠ physical acceptance. |
| P8 | Tables over prose | Australian English, concise, testable acceptance criteria. |

## Glossary

| Term | Meaning |
|---|---|
| AC | Armoury Crate button. **Right** side of the RC71L screen, below Menu. InputPlumber `QuickAccess` (tap) / `QuickAccess2` (long). The long press is a real firmware key (`KEY_F17`). |
| CC | Command Centre button. **Left** side of the RC71L screen, below View. InputPlumber `Guide` (tap) / `Keyboard` (long). The long press is not a separate hold code: firmware sends Ctrl+Alt+Delete, or `KEY_F20` when `hid-asus-ally` is present. |
| View / Menu | Xbox-style Select / Start (`BTN_SELECT` / `BTN_START`). These have a real press and release. CC and AC do not. |
| M2 / M1 | Back grips, left / right. InputPlumber names `LeftPaddle1` / `RightPaddle1` are not yet proven to match those sides (spec 01, OQ-1, OQ-17). On the tested stock kernel, both paddles produced the same F15 event on the ASUS N-KEY interface. |
| N-KEY | ASUS USB HID device `0b05:1abe` (driver `hid-asus`); interface 2 carries the OEM buttons and paddles. |
| Game mode | Gamescope session with Steam (Big Picture / Gaming Mode UI). The gaming service requests the `gaming` InputPlumber profile, which exposes a Steam Deck controller (`deck`, Valve `28de:1205`) to Steam. If `vhci_hcd` is unavailable, that load uses DualSense Edge (`ds5-edge`). |
| Desktop mode | Managed Hyprland session. The `desktop` profile keeps an Xbox Elite target alongside the virtual mouse and keyboard. The right stick moves the pointer, RT left-clicks and LT right-clicks. |
| Controller profile | The integration contains four InputPlumber profiles for the desktop, Gaming, keyboard recovery and greeter pointer. The greeter uses the left stick and A. |
| Profile broker and desktop observer | The system service `omarchy-inputplumber-profile` loads the profiles. The managed desktop starts `default/gaming/input-profile-watch.py` to request its profile and handle OEM button events. |
| QAM | Steam Quick Access Menu (right-hand panel in Gaming Mode). |
| OSK | On-screen keyboard: Steam OSK in game mode, wvkbd (`omarchy-toggle-desktop-keyboard`) in desktop mode. |
| Tap / Long | OEM-button gestures. Armoury long is a firmware key. Command Centre long is a different firmware chord or key. Neither is a userspace hold timer. |
| Omarchy menu | `omarchy-menu` (Super + Space), entries in `default/omarchy/omarchy-menu.jsonc`. |
| Quick-access overlay | Omarchy's own TDP/fan/RGB/brightness/perf overlay (spec 04). Not built yet. |
| Dock | USB-C dock/hub with external display; triggers desktop (spec 02). |
