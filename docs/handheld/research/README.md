# Handheld research

Research notes for a gaming-first handheld mode on the original ASUS ROG Ally (RC71L). The notes through `ally-hw-dump.md` are dated 12 Nov 2026 (AWST). `touch-first-boot.md`, `prior-art.md`, `feature-parity-audit.md` and `touch-desktop-and-stick-mouse.md` are dated 16 Nov 2026.

**An earlier independent review rejected stock steamos-manager 26.4.1-3 even when inactive.** ~~It was left as a recommendation under re-assessment.~~ That re-assessment is closed by the note below.

**Superseded (12 Nov 2026).** Do not ship stock steamos-manager and do not fork it. Build backlog #10 (a small root writer for the power limits) and #11 (a session-bus shim implementing the public SteamOSManager1 API, so Steam's QAM performance slider works). The stock package enables a root service on install, its root RootManager API lacks Polkit/caller authorisation, its root daemon manages InputPlumber targets, it has a networking-helper dependency, and its root interface is monolithic.

Per-button codes and paddle mapping are pending a device press test.

Omarchy is MIT. InputPlumber files (GPL-3.0-or-later), HHD's MCU bytes (LGPL-2.1-or-later) and the CachyOS handheld configs are not copied into this tree. For each of those, reimplement the behaviour, or vendor the files in a clearly separate path with their own LICENSE and SPDX headers. Checked licence ids are in [`distros.md`](distros.md).

## Index

- [`feature-parity-audit.md`](feature-parity-audit.md) — User-facing features of Bazzite Deck, CachyOS Handheld and SteamOS, plus touch Hyprland setups. Each row has integ status with a file on this branch, the source repo and SPDX licence, effort, and whether it belongs in Omarchy core or an opt-in handheld package. Ranked gaps at the end.
- [`touch-desktop-and-stick-mouse.md`](touch-desktop-and-stick-mouse.md) — An undocked touch desktop on the Ally (gestures, OSK, menu size, scale, rotation), and how Bazzite and InputPlumber turn sticks into a desktop pointer. Idea list and port candidates.
- [`prior-art.md`](prior-art.md) — Pizzarchy, cephalization/omarchy-steam-gaming-mode, DeckShift and deckarchy. What each does, its licence, how it starts gamescope and gets back to the desktop, keyboard-free install and login, and a port list for the files on this branch.
- [`touch-first-boot.md`](touch-first-boot.md) — Power on, log in and get online on the RC71L with the touchscreen and the built-in controller only. Greeter keyboard, Steam OSK, Wi-Fi without the bar module, controller-as-mouse before login, polkit prompts, crash-loop fallback, and the iPadOS patterns worth copying.
- [`buttons-and-input.md`](buttons-and-input.md) — Ally extra buttons, kernel codes, how InputPlumber and HHD map them, and the InputPlumber recommendation. Paddle codes and the M1/M2 side mapping are marked unverified there and still need the press test.
- [`parity-matrix.md`](parity-matrix.md) — Bazzite, CachyOS Handheld, SteamOS and a 10-line recommended Omarchy stack, with the steamos-manager caveat above.
- [`distros.md`](distros.md) — How Bazzite, CachyOS Handheld, SteamOS, ChimeraOS and Nobara install, boot into gaming mode, switch to the desktop and handle docking, plus what Omarchy can reuse and under which licence.
- [`accessibility.md`](accessibility.md) — Handheld accessibility findings for a gamescope + Steam gaming mode and the Hyprland desktop.
- [`gamescope-external-overlay.md`](gamescope-external-overlay.md) — Whether a Gamescope external overlay draws above a fullscreen game without taking focus, and how Decky, mangoapp and the handheld distros actually draw.
- [`ally-hw-dump.md`](ally-hw-dump.md) — Read-only hardware and input dump from a real RC71L running Omarchy dev (kernel `7.2.15-2-omarchy`). The raw captures are kept off-repo and are available on request. The press-test script is [`tools/ally-press-test.sh`](tools/ally-press-test.sh).
- [`tools/ally-press-test.sh`](tools/ally-press-test.sh) — Device-only button press-test script. Not part of the product. It is the pending check for per-button codes and paddle mapping.
