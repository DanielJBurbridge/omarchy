# Omarchy Handheld

**Status as of 26 November 2026 (AWST).** The first target is the original ASUS ROG Ally RC71L. The goal is to match Bazzite and CachyOS Handheld for boot and sign-in with handheld controls, Steam launch, suspend and resume of the same game, and deliberate switching to a usable Hyprland desktop. The physical receipts are from a Z1 Extreme. The Z1, Ally X and Xbox Ally each need their own acceptance run. [Feature parity and hardware receipts](feature-parity.md)

## Architecture

| Layer | Responsibility |
|---|---|
| Stock Omarchy core | Keep the stock installer, SDDM/PAM, Hyprland and native menus. Add small, reviewable hardware fixes for the RC71L and use stock InputPlumber as the controller owner. Desktop Steam Big Picture works independently of dedicated Gaming Mode. |
| `omacom/omarchy-pkgs` | Build and distribute optional dependencies such as output-aware `wvkbd` and the Gaming Mode power-button helper. Review package changes independently of desktop and session policy. |
| Opt-in `omarchy-gaming-session` | Register the dedicated Gamescope/Steam session and managed Desktop entry. Keep preference, controller profile, authenticated return and optional gaming integrations with their session lifecycle. The ordinary Hyprland entry remains the recovery path. |

The unified baseline, `work/ally-unified-quattro` at `191329fee`, combined upstream Quattro `a3bad0b1b`, the managed desktop (Track B, `5f7d0775b`), the session work (Track A, `c53706bfa`, through fork #92), the RC71L i8042 exclusion from fork #39 and the power-button follow-ups from fork #76. The current in-place candidate is integration revision `7d87d9ef` with companion `1.0.0-18`. Its corrected package trio passed an isolated upgrade and rollback rehearsal and awaits an attended desktop reload. The physical Z1 Extreme still runs `918cd56c` with companion `1.0.0-15`, and the fresh-install run is deferred. [Fork #92](https://github.com/DanielJBurbridge/omarchy/pull/92) · [Fork #39](https://github.com/DanielJBurbridge/omarchy/pull/39) · [Fork #76](https://github.com/DanielJBurbridge/omarchy/pull/76) · [Candidate and evidence](feature-parity.md#unified-integration-baseline)

## Ordered upstream PR stack

The four live PRs were rebased cleanly on 25 November and had zero conflicts or unresolved review threads. The Omarchy PRs share the `upstream/quattro` base `a3bad0b1b`. Land the package before relying on output-aware keyboard behaviour.

| Order | Slice | Target and status | Review or acceptance gate |
|---|---|---|---|
| 1 | Skip ASUS ROG laptop setup on the original RC71L | [omacom/omarchy#18022](https://github.com/omacom/omarchy/pull/18022) · Live · `0a2d371ba` | Hardware predicate and laptop regression coverage in `test/shell.d/hw-rog-ally-test.sh`. |
| 2 | Steam Big Picture in Trigger | [omacom/omarchy#18432](https://github.com/omacom/omarchy/pull/18432) · Live · `6cc07ca1d` | Steam-installed guard and `uwsm-app -- gtk-launch steam steam://open/bigpicture`. Verify signed-in launch and exit on the Ally. |
| 3 | Output-aware `wvkbd` | [omacom/omarchy-pkgs#3114](https://github.com/omacom/omarchy-pkgs/pull/3114) · Live · `7aac5cbaf` | Package `0.21-2` with `--output` for x86_64 and aarch64. Complete package CI and signing. |
| 4 | Offer the touch keyboard on the original RC71L | [omacom/omarchy#18433](https://github.com/omacom/omarchy/pull/18433) · Live · `50fb72050` | Builds on #18022. Greptile quoting thread resolved. Verify the exact keyboard and package pair on eDP with touch and dock hotplug. |
| 5 | SDDM touch keyboard | Omarchy · Staged · `work/upstream-sddm-touch-keyboard` at `7eb22923f` | Optional lazy-loaded Qt Virtual Keyboard (+215/−11). Greeter is pixel-identical without `qt6-virtualkeyboard`. Verify physical touch sign-in and the USB keyboard fallback before opening. |
| 6 | RC71L boot pointer | Omarchy · Staged · `work/upstream-rc71l-pointer` at `b06a07774` | 187 implementation lines atop #18022. Stock InputPlumber, exact `0b05:1abe` match, external-pad guard and opt-out lifecycle. Verify an offline boot and first login on hardware before opening. |
| 7 | Trusted lock keyboard (K07) | Omarchy · Next | Qualify the lock-owner archive and verify wrong and correct passwords, wake, keyboard access and safe recovery on the actual candidate. |
| 8 | `steamos-powerbuttond` | Packages · Next | Package the scoped helper and verify short suspend and long Steam power-menu presses. Cover the install retry and package skew from L192–L193. |
| 9 | Authenticated Gamescope session companion | Companion · Next | Review the opt-in session registration and lifecycle. Prove authenticated SDDM return, cold-boot handoff, bounded recovery and removal. |
| 10 | Companion discovery in the menu | Omarchy · Next | Offer native Setup and launch actions with hardware and package guards once the companion is available. |
| 11 | Steam TDP control | Companion · Next | Review the narrowly authorised power writer and Steam shim. Verify AC/battery clamp, wake readback and exclusive ownership. |
| 12 | Removable Steam library | Companion · Next | Verify the remembered library on physical microSD through cold boot, suspend, safe removal and reinsertion. |

Fork [#39](https://github.com/DanielJBurbridge/omarchy/pull/39) (K07/lock host, failing CI) and draft [#43](https://github.com/DanielJBurbridge/omarchy/pull/43) (auth rollout and cold-boot handoff) can be superseded once their remaining pieces are accounted for. Carry forward or replace the lock-host archive verification at `4fa2e7ed7` / `a7194f15a`, resolve the K07 suspend finding (`InhibitDelayMaxSec=15s)) and account for the held cold-boot patches. [Active blockers and priority follow-ups](alpha-followups.md#active-open-blockers--priority-follow-ups)

## Index

### Active docs

- [Feature parity](feature-parity.md) records the Bazzite comparison, the evidence by build and the [next RC71L acceptance runs](feature-parity.md#next-rc71l-acceptance-runs).
- [Alpha follow-ups](alpha-followups.md) tracks the live blockers and keeps the original L-number log.
- [Alpha install and recovery](ALPHA.md) gives operator steps for the trial builds. [Companion reference](../rog-ally-gaming-session.md) covers the session entries, preferences, packaging and rollback. Use the current baseline above and the [parity checklist](feature-parity.md) when older build or policy details differ.

### Archived and historical reference

- Earlier handoffs and plans. [16 November](HANDOFF-20261116.md) · [12 November](HANDOVER.md) · [Original parity inventory](../../plans/rog-ally-parity.md) · [Original work threads](../../plans/rog-ally-threads.md)
- Design drafts capture target behaviour and earlier decisions. [01 Controller map](01-controller-button-map.md) · [02 Mode switch and dock](02-mode-switch-and-dock.md) · [03 First boot](03-first-boot-and-install.md) · [04 Quick access](04-quick-access-overlay.md) · [05 Notifications](05-notifications.md) · [06 Accessibility](06-accessibility.md) · [07 On-screen keyboard](07-on-screen-keyboard.md) · [08 Mode round trip](08-mode-round-trip.md) · [09 Keyboard-free boot](09-keyboard-free-boot.md) · [10 Disk unlock](tpm-unlock-installer-spec.md) · [11 Undocked desktop](11-undocked-touch-desktop.md)
- Supporting material. [Prior-art research](research/README.md) · [TPM unlock runbook](tpm-unlock.md) · [Lock review](review/lock-findings.md) · [TDP decision review](tdp-decision-review.md)

## Decisions needed

| Decision | What is open |
|---|---|
| Boot and desktop authentication · L129/L131 | Decide the boot and desktop sign-in policy for no-input TPM unlock and unencrypted installs. The unified build can require SDDM sign-in on return when `desktop-lock` is on. |
| Disk unlock · L68–L70 | Choose the TPM+PIN and Secure Boot path. Retain passphrase recovery and keep the installer on the current unlock path until rekey preserves the TPM token and recovery slot. |
| Stock vs Deckify kernel | Keep stock as the acceptance baseline. Decide whether distinct paddle events and the alternate lighting path justify an optional Deckify kernel after cold boot, unlock and rollback are verified. |
| TDP, charge and lighting ownership | Choose a single writer for power and charge. Resolve how `asusd` retains ring lighting without competing writes or overwriting the saved charge threshold. |
| Companion package ownership | Decide where its recipe and release ownership live and how it tracks the compatible Omarchy runtime before opening the Gamescope and discovery slices. |
