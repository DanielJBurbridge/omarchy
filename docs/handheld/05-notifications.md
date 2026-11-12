# 05 · Notifications (gaming and desktop)

Status: draft, revision 3, 12 Nov 2026 (AWST). Owner: dev-ux. Depends on: [02](02-mode-switch-and-dock.md) (dock prompt, gaming-fail notice), [03](03-first-boot-and-install.md) (lock migration notice), [04](04-quick-access-overlay.md) (overlay client, intercept rules). Rulings applied: PPD masked on RC71L; backlog #10 (power writer) and backlog #11 (Steam TDP shim) own power (`tdp-decision-review.md`); `desktop-lock` ships off until K07. Revision 3 takes the second dev-red review of PR #30. While `desktop-lock` is off, the quick overlay hides “Switch to Desktop”; that switch is only Steam’s own menu, which honours Steam’s PIN. While it is on and a usable keyboard is attached, or once K07 counts as landed, our switch runs the lock first (spec 02 §7.4, D10). Before K07, with the effective value `on` and no usable keyboard, that row is shown disabled and reads “Connect a keyboard to unlock” (spec 07 §4.1, spec 02 §7.4).

## 0. Decisions in one table

| # | Decision | Source |
|---|---|---|
| D1 | Desktop keeps **Omarchy's own notifier** (`omarchy-shell`, `omarchy.notifications`). It replaced mako in this fork; no mako on the handheld variant. | `docs/notifications.md` |
| D2 | Gaming gets an `org.freedesktop.Notifications` server, `omarchy-gaming-notifier`, as a D-Bus front end only. It does **not** open a Gamescope external-overlay window. Gamescope paints one such window. Spec 04 (`omarchy-quick-overlay`, D9 and §6.1) owns that slot: it takes the slot from mangoapp while its panel is open and gives it back on close or crash. Critical battery and thermal alerts are always sent on Steam’s notification path, which is a hard dependency of the handheld gaming session, and are also offered to the spec 04 slot owner. Delivery does not wait on that owner. Same senders (`omarchy-notification-send`) work in both sessions. | Spec 04 D9, §6.1 |
| D3 | Toasts in gaming are **display-only**. Acting on one means opening the overlay (AC long) → Notifications; the game never loses focus, and controller input reaches a notification only through InputPlumber intercept. | Red review, spec 04 D4 |
| D4 | **Game-running quiet**: while a game runs (gaming scope game process, or a real fullscreen window on desktop) only **P0** shows; P1 shows as a one-line banner; P2/P3 go straight to history and are summarised when the game exits. | Brief |
| D5 | Four priority levels (P0–P3) map onto freedesktop urgency + Omarchy's existing Do Not Disturb bypass rules. No new bypass for third-party apps. | `shell/plugins/notifications/Delivery.js` |
| D6 | **One history**: gaming notifications are appended to the same store the shell reads (`~/.local/state/omarchy/notifications/`), so the desktop history shows what happened in gaming. | `shell/plugins/notifications/Store.js` |
| D7 | Red-team: a toast or prompt that asks for a choice ignores input for **500 ms**, focuses the **safe** choice, and never appears while a game is starting (first 10 s). Only a **new press** after the arm counts. A button already held when the prompt appears is ignored until it is released, and that release does not act. The action is the press edge, not the release. | Red review |

## 1. Baseline: what is already built

| Piece | Path (default branch unless noted) | Note |
|---|---|---|
| Notifier | `shell/plugins/notifications/Service.qml` (Quickshell `NotificationServer`, claims `org.freedesktop.Notifications`); `shell/plugins/notifications/Toast.qml`, `shell/plugins/notifications/Store.js`, `shell/plugins/notifications/Delivery.js`; `docs/notifications.md` | Grouped decks top-right, inline actions, DND, history (100 rows / 24 h), steps aside under a real fullscreen window when idle. |
| Timing | `shell/plugins/notifications/Service.qml` `durationFor`: low ≥ 5 s, normal ≥ 8 s, **critical waits until dismissed**. | Reused. |
| DND bypass | `shell/plugins/notifications/Delivery.js` `bypassesQuiet`: `app_name = omarchy-action`, or `notify-send` + critical; verification codes always pass. | P0/P1 senders use `omarchy-action`. |
| Sender | `bin/omarchy-notification-send` (`-u`, `-g`, `--transient`, `--exec`, `--action`, `-r`) | Single sender CLI for every event below. |
| Binds | `default/hypr/bindings/utilities.lua`: `SUPER + comma` act/dismiss, `SUPER + SHIFT + comma` dismiss all, `SUPER + CTRL + comma` keyboard mode, `SUPER + ALT + comma` dismiss last, `SUPER + SHIFT + ALT + comma` history, `SUPER + CTRL + ALT + comma` toggle silencing. | Controller reaches them via spec 01 M1 = Super only with a comma key, so §5 adds overlay routes, **no new Ally binds**. |
| Battery low | `shell/plugins/services/battery/Service.qml` (threshold 10 %, UPower) → `bin/omarchy-battery-low` (normal urgency, 30 s) + `config/omarchy/hooks/battery-low.d`. | Shell-only: **nothing warns in gaming today**. |
| Update | `install/user/first-run/wifi.sh` `notify_update` (first-run toast); `bin/omarchy-update-available` (checker; bar widget `shell/plugins/bar/widgets/SystemUpdate.qml`). | Reused for P2. `bin/omarchy-update-user-notify` is a hidden wrapper for `omarchy-migrate-notify`, not this toast (`docs/update-process.md`). |
| Gaming fail | spec 02 §7.2 notice (critical, “Try Gaming again”). | Shown on desktop. |
| Gaming session | `docs/rog-ally-gaming-session.md` (`feat/ally-parity-integration-20261111`): gaming does not start `graphical-session.target`, so **the shell notifier is absent in gaming**. | Why D2 is needed. |

## 2. How others do it

| | SteamOS | Bazzite / ChimeraOS | CachyOS Handheld | Omarchy (this spec) |
|---|---|---|---|---|
| Gaming notifications | `steam_notif_daemon` started by the Game Mode session forwards freedesktop notifications into Steam toasts ([ChimeraOS session script](https://github.com/ChimeraOS/gamescope-session-steam/blob/main/usr/share/gamescope-session-plus/sessions.d/steam), [Jovian mirror](https://github.com/Jovian-Experiments/steam_notif_daemon), [SteamOS unit](https://gitlab.com/evlaV/jupiter-PKGBUILD/-/blob/4d9e68d8e5a7d2c902d42df6a51e50a2af79155b/gamescope/steam-notif-daemon.service)) | Same session scripts start it **if present** | gamescope-session-cachyos (not checked) | D-Bus front end (D2). `steam_notif_daemon` is a hard dependency. Critical battery and thermal always use it, and are also offered to the spec 04 slot owner (OQ-1 closed) |
| Without a daemon | `notify-send` goes nowhere in Game Mode ([SteamOS #813](https://github.com/ValveSoftware/SteamOS/issues/813)) | — | — | — |
| Desktop | KDE Plasma | KDE / GNOME | KDE | omarchy-shell |
| Mid-game DND | Steam's own “Do not disturb” for Steam toasts | Steam | Steam | D4 game-running quiet |

Why not mako in Gamescope: mako is a `wlr-layer-shell` client. Gamescope treats a layer-shell surface as its one external overlay, and only when the session was started with `--expose-wayland` (PR #31). That is the same slot spec 04 already owns, so a second layer-shell client does not get its own surface. OQ-2 is closed. The overlay client still solves stacking without focus (spec 04 §6).

## 3. Where each priority appears

| Level | Meaning | Urgency / sender | Desktop | Desktop, fullscreen game | Gaming, no game | Gaming, game running |
|---|---|---|---|---|---|---|
| **P0** | Act now or lose data/hardware | critical, `omarchy-action` | Toast, waits; DND bypass | Toast over game | Toast, waits | Critical battery and thermal: Steam’s toast always, and the spec 04 owner as well when it confirms within 1 s. Other P0: the slot owner when it already holds the slot; otherwise history. Repeats once after 60 s if still true |
| **P1** | Needs a decision soon | normal, `omarchy-action` | Toast 8 s | Toast | Toast | **One-line banner** 4 s, no buttons; full card in overlay |
| **P2** | Good to know | low | Toast 5 s | History only | Toast 5 s | History; summary on game exit |
| **P3** | Background | low, `--transient` or history-only | History | History | History | History |
| Third-party apps | Any | as sent | Baseline rules | Baseline (steps aside) | Toast if ≤ normal | History only (D4) |

Silencing (user DND, `SUPER + CTRL + ALT + comma` or overlay toggle) keeps baseline semantics on the desktop: only `omarchy-action` and verification codes pass, so P0/P1 still show. In gaming, D4 overrides that bypass. A non-Omarchy sender draws its title only, never a verification-code body, and a code does not bypass quiet. Nothing from this notifier draws above Steam’s lock screen, or above hyprlock on the desktop.

## 4. Events

| Event | Level | Detected by | Text (title · body) | Action | Notes |
|---|---|---|---|---|---|
| Battery low (≤ 15 %) | P1 | UPower `Percentage` + discharging (shell service on desktop; gaming notifier in gaming) | Battery low · “15 % left, about 40 min.” | Overlay → Performance (Quiet) | Desktop threshold 10 % today; handheld raises to 15 % (OQ-5). Fires once per discharge. |
| Battery critical | P0 | UPower `Percentage` at the configured `PercentageAction` | Battery critical · “Plug in now.” plus the configured action | — | The notifier does not suspend. UPower `CriticalPowerAction` and `PercentageAction` do. The upstream default is HybridSleep at 2 %. The toast names the action and percentage that are configured, not a fixed 3 %. |
| Charge complete / limit reached | P2 | UPower `State = fully-charged`, or level ≥ writer's charge limit | Charged · “Battery at 80 % (limit).” | — | Once per plug-in. |
| Thermal throttle / cap | P1 | backlog #10 (power writer) event on its own read-only interface: cap reduced for temperature | Running hot · “Power limited to 15 W to cool down.” | Overlay → Performance | Event name TBC from backlog #10 (OQ-3). Not carried on backlog #11. See `tdp-decision-review.md`. |
| Thermal critical | P0 | Writer or `thermal_zone` trip `critical` | Too hot · “Shutting down to protect the device.” | — | Only if a shutdown is actually scheduled. |
| Competing power writer | P1 | Writer reports `asusd`/`hhd`/`powerstation`/unmasked PPD | Power controls paused · “asusd is changing power settings.” | Hub → Status | Once per boot. |
| Dock detected (prompt) | P1 | spec 02 §5 | Docked · “Switch to Desktop?” | **Stay** (focused) / Switch | Never while a game is starting; game running ⇒ deferred until exit (spec 02 D5). 500 ms arm, new presses only (D7). While `desktop-lock` is off there is no Switch action: the overlay hides it, and the user uses Steam’s own menu (Steam’s PIN). While it is on and a usable keyboard is attached, or once K07 has landed, Switch runs the lock first (spec 02 §7.4). Before K07, with the effective value `on` and no usable keyboard, that row is shown disabled and reads “Connect a keyboard to unlock” (spec 07 §4.1). In gaming the prompt is inside the spec 04 overlay client: key-ups, `intercept all` confirmed, and `ExecStopPost` restores `intercept none`. If that client is unavailable, defer the prompt to the desktop. |
| Undock in desktop (prompt) | P1 | spec 02 §5 | Undocked · “Switch to Gaming?” | **Stay** / Switch | As above. |
| Gaming failed, desktop fallback | P0 | spec 02 §7.2 | Gaming Mode didn't start · reason + log path | Try Gaming again | Shown after desktop start (after unlock if lock `on`). |
| Desktop lock now on (K07 migration) | P1 | spec 03 §7 migration | Desktop Mode now asks for your password | Settings | Once. |
| Update available | P2 | `omarchy-update-available` (baseline) | Updates available | Open update (desktop) | Gaming: history + overlay badge; never starts an update in gaming. |
| Controller disconnected | P0 in game, P1 otherwise | InputPlumber composite/target removed **not** during a planned swap (bridge marks swaps); BlueZ device disconnect | Controller disconnected · “Built-in controller stopped responding.” / “<name> disconnected.” | Reconnect help (overlay) | Planned swaps (spec 02 D8, spec 04 row 12) are silent. |
| Controller reconnected | P3 | same | — | — | History only. |
| Steam / third-party | as sent | freedesktop | — | — | D4 applies. |

## 5. Controller actions on notifications

| Where | Dismiss newest | Act (primary) | All / history | Notes |
|---|---|---|---|---|
| Desktop | Overlay → Notifications → B on a card; pointer (right stick + A) on the toast's close mark | Pointer + A on the card (baseline click routing) or overlay → card → A | Overlay → Notifications → LB/RB page, “Clear all” | Overlay calls the existing IPC (`notifications.dismissOne`, `act`, `dismissAll`, `showHistory`). No new Ally binds. |
| Gaming, no game | Overlay → Notifications | Overlay → card → A | Overlay | Toast itself is not interactive. |
| Gaming, game running | Toast times out | AC long → overlay (intercept on) → card → A | Overlay | Game keeps focus; intercept rules from spec 04 §7 (ups, confirm, `ExecStopPost` restore). |
| Prompt cards (dock) | B = Stay | A on focused button (Stay first), only a press that begins after the 500 ms arm | — | A hold that started before the prompt, released at 600 ms or later, does not act. In gaming, input is the spec 04 §7 intercept path, not the toast. |

## 6. Gaming notifier (Δ-N1)

| Item | Spec |
|---|---|
| Process | `omarchy-gaming-notifier`, started in the gaming scope after Gamescope provides DISPLAY (same ownership pattern as the power-button helper); claims `org.freedesktop.Notifications` on the session bus **only if unowned**. A same-user process can take that name first and spoof the `omarchy-action` bypass. That squat is a baseline gap; this spec does not close it. |
| Rendering | Does not create an overlay window. Non-critical cards are drawn by the spec 04 client when that client already holds the slot. Critical battery and thermal alerts are sent on the Steam path every time (`steam_notif_daemon`, required), and are also offered to the spec 04 slot owner so it can hide mangoapp and show them. If the owner does not confirm within 1 s, including when it is dead or stopped, nothing waits. The Steam toast is the delivery. |
| Game detection | Same detector as spec 04 D3 / spec 02 OQ-9. Unknown ⇒ treat as **game running** (quieter is safer). |
| History | Appends rows to `~/.local/state/omarchy/notifications/history.json` using `shell/plugins/notifications/Store.js` row rules (redaction, caps), via a lock shared with the shell; the shell picks them up at next start (OQ-4). |
| Steam toasts | Untouched; Steam keeps its own. |
| Crash / killed | systemd restarts once (`Restart=on-failure`); senders time out and fall back to history-only (`omarchy-notification-send` must not block > 1 s). Never leaves intercept on (it never sets it). |
| Session end | Stops with the scope; un-shown rows already in history. |

## 7. User flows

| # | Flow | Steps |
|---|---|---|
| F1 | Battery low mid-game | Banner “Battery low” 4 s → AC long → Notifications/Performance → Quiet → A → B. |
| F2 | Critical battery mid-game | Steam’s toast appears with the Performance HUD up, with the overlay client killed, and with that client stopped (`SIGSTOP`). The spec 04 owner is also asked; a missing confirmation within 1 s does not delay the Steam toast. Repeats once after 60 s → plug in → P2 history “Charging”. |
| F3 | Dock during a game | Nothing on screen; after game exit, prompt with Stay focused. While `desktop-lock` is off the prompt has no Switch action. While it is on and a keyboard is usable, Switch runs the lock first. Before K07 with no usable keyboard, the row is shown disabled and reads “Connect a keyboard to unlock” (spec 07 §4.1). |
| F4 | Update during play | History only; on desktop next time, history shows “Updates available”. |
| F5 | Built-in pad drops | P0 “Controller disconnected” (touch still works). The gaming overlay is controller-only (v1), so the toast says “Use the touchscreen: Steam ▸ Settings ▸ Controller” (OQ-6). |
| F6 | Desktop, act on a notification | CC tap → Notifications → card → A → baseline click routing runs. |

## 8. Acceptance criteria

1. In gaming, `omarchy-notification-send "x"` is accepted within 500 ms and the focused game window keeps Gamescope focus. The notifier process does not map a `GAMESCOPE_EXTERNAL_OVERLAY` window.
2. In gaming with no notifier running, `omarchy-notification-send` returns within 1 s and the row appears in desktop history later.
3. While a game runs, a P2 notification never draws; it is in history and in the exit summary.
4. While a game runs, P0 draws even with user DND on; third-party critical (non-`notify-send`) does not.
5. Planned InputPlumber profile/target swaps produce no “Controller disconnected”; killing InputPlumber mid-game produces exactly one.
6. Battery low fires once per discharge at the handheld threshold in **both** sessions; battery critical repeats at most once.
7. Thermal and competing-writer notices come from the capped writer's events, not from polling the notifier (code review).
8. Dock prompts never appear within 10 s of a game process starting, focus Stay, and ignore input for 500 ms. Holding A from the moment the prompt appears until 700 ms, then releasing, does not act. Only a press that starts after the arm acts.
9. Overlay Notifications section can dismiss, act on and clear all cards using only the controller, via the existing IPC.
10. The gaming-fail notice (spec 02) and K07 migration notice (spec 03) are delivered with `omarchy-action` and survive user DND.
11. Notifier killed with SIGKILL in gaming restarts once; a second kill leaves the session running with history-only delivery.
12. History entries from gaming carry the same redaction as desktop (verification code stored as placeholder).
13. No new Hyprland or Ally binds are added (diff check); `SUPER + CTRL + X` stays unused by this spec.
14. With the Performance HUD holding the external-overlay slot, a critical battery alert and a thermal alert each still draw on Steam’s path within 1 s, and the spec 04 owner is also asked to preempt mangoapp. Repeating each with the overlay client killed, and again with that client `SIGSTOP`ped, still draws on Steam within 1 s. `steam_notif_daemon` is running; the handheld gaming session does not treat it as optional.
15. A verification code sent in gaming does not draw its body and does not bypass quiet. No toast from this notifier draws above Steam’s lock screen or above hyprlock.
16. A gaming dock prompt with the overlay client up receives A and B only after intercept is confirmed. If the client cannot take intercept, the prompt waits for the desktop. While `desktop-lock` is off the prompt has no Switch action. While it is on and a usable keyboard is attached, or once K07 has landed, Switch runs the lock first (spec 02 §7.4). Before K07, with the effective value `on` and no usable keyboard, the row is shown disabled and reads “Connect a keyboard to unlock” (spec 07 §4.1).

## 9. Open questions

| # | Question | Owner |
|---|---|---|
| OQ-1 | **Closed.** `steam_notif_daemon` is a hard dependency of the handheld gaming session. Critical battery and thermal alerts always use it (D2, §6). The Jovian tree is a mirror until upstream is public; that does not make the dependency optional. | dev-lead |
| OQ-2 | **Closed.** PR #31: Gamescope treats a layer-shell surface as the external overlay, and only with `--expose-wayland`. Mako would take the slot spec 04 owns, so it is not used (§2). | dev-research |
| OQ-3 | backlog #10 (power writer) event names for thermal cap and competing owner, on backlog #10’s own read-only interface. Backlog #11 stays the public SteamOSManager1 surface and does not carry those events. See `tdp-decision-review.md`. | POWER |
| OQ-4 | `shell/plugins/notifications/Store.js` reads history once at start: safe concurrent append from the gaming notifier, or a separate `gaming.json` merged at start? | dev-lead |
| OQ-5 | Handheld low-battery threshold 15 % vs baseline 10 % (`shell/plugins/services/battery/Service.qml` `batteryThreshold`); does `shell/plugins/services/battery/BatteryModel.js` accept a per-device threshold? | dev-lead |
| OQ-6 | Touch on the gaming overlay (spec 04 OQ-2) — needed for “controller disconnected” recovery. | dev-research |
| OQ-7 | Does Steam show its own low-battery warning on non-Deck hardware under Omarchy's Gamescope session? If yes, avoid duplicates. | Hardware test |

## 10. Branch conflicts

| Conflict | Where | Resolution proposed |
|---|---|---|
| Battery service “follows power-profiles-daemon's change signals” | `shell/plugins/services/battery/Service.qml` | PPD is masked on RC71L (ruling): profile display must follow the capped writer; battery % still from UPower. |
| Shell notifier absent in gaming | `docs/rog-ally-gaming-session.md` | Δ-N1 is a D-Bus front end. It does not take Gamescope’s one external-overlay slot; spec 04 does. |
| Power notices referenced steamos-manager in earlier drafts | specs 02–04 | Now backlog #10 (power writer) and backlog #11 (Steam TDP shim). See `tdp-decision-review.md`. No pull request or branch exists for either task. |

## Sources

- Fork: `docs/notifications.md`, `shell/plugins/notifications/{Service.qml,Toast.qml,Delivery.js,Store.js}`, `shell/plugins/services/battery/{Service.qml,BatteryModel.js}`, `bin/omarchy-notification-send`, `bin/omarchy-battery-low`, `bin/omarchy-update-available`, `shell/plugins/bar/widgets/SystemUpdate.qml`, `config/omarchy/hooks/battery-low.d`, `default/hypr/bindings/utilities.lua`, `install/user/first-run/wifi.sh`, `docs/update-process.md` (default branch and this integration tip); `docs/rog-ally-gaming-session.md` (`feat/ally-parity-integration-20261111`, also `feat/ally-session-20261111` and `feat/ally-parity-release-20261111`).
- Power ownership: `tdp-decision-review.md` (team-box TDP decision review; not a file in this repo). backlog #10 is the power writer and backlog #11 is the Steam TDP shim. Neither is a pull request.
- External: [SteamOS #813](https://github.com/ValveSoftware/SteamOS/issues/813); [ChimeraOS gamescope-session-steam](https://github.com/ChimeraOS/gamescope-session-steam/blob/main/usr/share/gamescope-session-plus/sessions.d/steam); [steam_notif_daemon mirror](https://github.com/Jovian-Experiments/steam_notif_daemon); [SteamOS steam-notif-daemon.service](https://gitlab.com/evlaV/jupiter-PKGBUILD/-/blob/4d9e68d8e5a7d2c902d42df6a51e50a2af79155b/gamescope/steam-notif-daemon.service); [gamescope #288](https://github.com/ValveSoftware/gamescope/issues/288); [ArchWiki Desktop notifications](https://wiki.archlinux.org/title/Desktop_notifications).
