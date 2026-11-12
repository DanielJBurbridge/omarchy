# Handheld research

Research notes for a gaming-first handheld mode on the original ASUS ROG Ally (RC71L). Each file below is a research record dated 12 Nov 2026 (AWST).

**steamos-manager is a recommendation, not a decision. An earlier independent review rejected stock steamos-manager 26.4.1-3 even when inactive, and it is being re-assessed.**

Per-button codes and paddle mapping are pending a device press test.

Omarchy is MIT. GPL and LGPL material in these notes (CachyOS-Handheld configs, HHD MCU init bytes, and the InputPlumber-derived Ally config) stays under its own licence. Reimplement from behaviour, or vendor it as separately-licensed files with LICENSE and SPDX headers. That is a decision for Daniel.

## Index

- [`buttons-and-input.md`](buttons-and-input.md) — Ally extra buttons, kernel codes, how InputPlumber and HHD map them, and the InputPlumber recommendation. Paddle codes and the M1/M2 side mapping are marked unverified there and still need the press test.
- [`parity-matrix.md`](parity-matrix.md) — Bazzite, CachyOS Handheld, SteamOS and a 10-line recommended Omarchy stack, with the steamos-manager caveat above.
- [`distros.md`](distros.md) — How Bazzite, CachyOS Handheld, SteamOS, ChimeraOS and Nobara install, boot into gaming mode, switch to the desktop and handle docking, plus what Omarchy can reuse and under which licence.
- [`accessibility.md`](accessibility.md) — Handheld accessibility findings for a gamescope + Steam gaming mode and the Hyprland desktop.
- [`ally-hw-dump.md`](ally-hw-dump.md) — Read-only hardware and input dump from a real RC71L running Omarchy dev (kernel `7.2.15-2-omarchy`). Raw captures named in the note (`ally-hw-dump-raw.txt`, `ally-hw-dump-raw-2.txt`, `ally-omarchy-files.txt`) are not committed. The press-test script is [`tools/ally-press-test.sh`](tools/ally-press-test.sh).
- [`tools/ally-press-test.sh`](tools/ally-press-test.sh) — Device-only button press-test script. Not part of the product. It is the pending check for per-button codes and paddle mapping.
