# Handheld research

Research notes for a gaming-first handheld mode on the original ASUS ROG Ally (RC71L). The notes through `ally-hw-dump.md` are dated 12 Nov 2026 (AWST). `touch-first-boot.md`, `prior-art.md`, `feature-parity-audit.md`, `parity-gaps-ranked.md`, `touch-desktop-and-stick-mouse.md`, `inputplumber-profiles-brief.md`, `brief-speaker-dsp.md`, `brief-power-button.md`, `brief-tdp-limits.md` and `build-tdp-slider.md` are dated 16 Nov 2026.

**An earlier independent review rejected stock steamos-manager 26.4.1-3 even when inactive.** ~~It was left as a recommendation under re-assessment.~~ That re-assessment is closed by the note below.

**Superseded (12 Nov 2026), and landed on this tip.** Do not ship stock steamos-manager and do not fork it. The writer is `bin/omarchy-ally-tdp-apply`. The session shim is `bin/omarchy-ally-tdp-shim` (`TdpLimit1`, MIT interface from evlaV/steamos-manager `85fbd8f`). The stock package enables a root service on install, its root RootManager API lacks Polkit/caller authorisation, its root daemon manages InputPlumber targets, it has a networking-helper dependency, and its root interface is monolithic. The current contract is [spec 04 §5.1](../04-quick-access-overlay.md).

Per-button codes and paddle mapping are pending a device press test.

Omarchy is MIT. InputPlumber files (GPL-3.0-or-later), HHD's MCU bytes (LGPL-2.1-or-later) and the CachyOS handheld configs are not copied into this tree. For each of those, reimplement the behaviour, or vendor the files in a clearly separate path with their own LICENSE and SPDX headers. Checked licence ids are in [`distros.md`](distros.md).

## Index

- [`parity-gaps-ranked.md`](parity-gaps-ranked.md) — The current ranked list of what Bazzite, CachyOS Handheld and SteamOS do on the RC71L that this branch still does not. Read at integ `5534cf292`.
- [`feature-parity-audit.md`](feature-parity-audit.md) — Pointer. The 16 Nov matrix is retired. Status lives in the gaps file.
- [`brief-speaker-dsp.md`](brief-speaker-dsp.md) — Implementation brief for ranked gap 2, Ally speaker DSP. What CachyOS and Bazzite ship, why those files stay out, the two-volume sink against the CS35L41 pair, and an opt-in tuning under `default/audio/tunings/` that reuses the existing speaker host.
- [`touch-desktop-and-stick-mouse.md`](touch-desktop-and-stick-mouse.md) — An undocked touch desktop on the Ally (gestures, OSK, menu size, scale, rotation), and how Bazzite and InputPlumber turn sticks into a desktop pointer. Idea list and port candidates.
- [`prior-art.md`](prior-art.md) — Pizzarchy, cephalization/omarchy-steam-gaming-mode, DeckShift and deckarchy. What each does, its licence, how it starts gamescope and gets back to the desktop, keyboard-free install and login, and a port list for the files on this branch.
- [`touch-first-boot.md`](touch-first-boot.md) — Power on, log in and get online on the RC71L with the touchscreen and the built-in controller only. Greeter keyboard, Steam OSK, Wi-Fi without the bar module, controller-as-mouse before login, polkit prompts, crash-loop fallback, and the iPadOS patterns worth copying.
- [`buttons-and-input.md`](buttons-and-input.md) — Ally extra buttons, kernel codes, how InputPlumber and HHD map them, and the InputPlumber recommendation. M2 is the left back paddle and M1 is the right. The 17 Nov codes (M2 sent F15, M1 sent nothing, inputplumber stopped) are pending a re-run.
- [`inputplumber-profiles-brief.md`](inputplumber-profiles-brief.md) — Implementation brief for the RC71L profiles in [spec 01](../01-controller-button-map.md): the upstream composite device, the `gaming`, `desktop` and `osk` YAML against the InputPlumber 0.84 schema, D-Bus profile loads, and the licence split. OQ-1, OQ-2 and OQ-17 stay TBC.
- [`brief-power-button.md`](brief-power-button.md) — Implementation brief for ranked gap 3: the RC71L power button in the gamescope session. Short press suspends, a one-second hold opens Steam's power menu, and the desktop path stays lock-then-suspend until K07. Names the upstream files to vendor and the core-fit split.
- [`brief-tdp-limits.md`](brief-tdp-limits.md) — Research for the RC71L PPT limits. Implemented. The contract is spec 04 §5.1. Keeps the kernel tables, the licence notes and the evlaV `85fbd8f` citation.
- [`build-tdp-slider.md`](build-tdp-slider.md) — Build comparison for the TDP slider. Implemented. The contract is spec 04 §5.1. Keeps the licence table and the evlaV citation. On-device slider check stays open.
- [`parity-matrix.md`](parity-matrix.md) — Bazzite, CachyOS Handheld, SteamOS and the Omarchy stack. Leads with the landed writer and shim. The stock steamos-manager rejection stays as history.
- [`distros.md`](distros.md) — How Bazzite, CachyOS Handheld, SteamOS, ChimeraOS and Nobara install, boot into gaming mode, switch to the desktop and handle docking, plus what Omarchy can reuse and under which licence.
- [`accessibility.md`](accessibility.md) — Handheld accessibility findings for a gamescope + Steam gaming mode and the Hyprland desktop.
- [`gamescope-external-overlay.md`](gamescope-external-overlay.md) — Whether a Gamescope external overlay draws above a fullscreen game without taking focus, and how Decky, mangoapp and the handheld distros actually draw.
- [`ally-hw-dump.md`](ally-hw-dump.md) — Read-only hardware and input dump from a real RC71L running Omarchy dev (kernel `7.2.15-2-omarchy`). The raw captures are kept off-repo and are available on request. The press-test script is [`tools/ally-press-test.sh`](tools/ally-press-test.sh).
- [`tools/ally-press-test.sh`](tools/ally-press-test.sh) — Device-only button press-test script. Not part of the product. It is the pending check for per-button codes and paddle mapping.
