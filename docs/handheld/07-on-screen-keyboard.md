# 07 · On-screen keyboard

Status: draft, 12 Nov 2026 (AWST). Owner: dev-ux. Depends on: [01](01-controller-button-map.md) (CC long, Δ6 `osk` profile), [03](03-first-boot-and-install.md) (buffyboard, `tty` profile), [06](06-accessibility.md). Lock-screen keyboard (K07) is AUTH's: **requirements only** here (§7). Rulings applied: `desktop-lock` ships off until K07 lands; no extra Ally binds; `SUPER + CTRL + X` taken.

## 0. Decisions in one table

| # | Decision | Source |
|---|---|---|
| D1 | One keyboard per context, never two on screen: buffyboard (TTY), Qt Virtual Keyboard (SDDM greeter, built), wvkbd (Hyprland), Steam OSK (Gamescope), K07 trusted keyboard (lock, AUTH). | §1 |
| D2 | Desktop summon stays **manual**: CC long, bar button, Apps entry, Omarchy menu, `SUPER + CTRL + Y`. Auto-show on text focus is **not feasible today** (single input-method slot held by Fcitx5). | `docs/rog-ally-touch-keyboard.md` |
| D3 | While wvkbd is visible the controller uses the **`osk` profile** (spec 01 Δ6): desktop + **B = Backspace, X = Space**; plus Y = Enter (baseline), Start = Esc (baseline). Keys are pressed by **pointer (right stick) + A** or touch; no d-pad key-by-key focus (wvkbd has none). | Spec 01 |
| D4 | **Restore the profile when wvkbd dies**: the bridge watches the keyboard process; on exit it sends key-ups and loads `desktop` atomically. | Brief, red team |
| D5 | wvkbd is **themed** from the active Omarchy theme via its colour/font flags at launch and on theme change. | wvkbd 0.21 flags |
| D6 | Gaming: Steam OSK only, via CC long (`Keyboard` → Guide+West macro) or Steam's own text-field prompt. | Baseline |
| D7 | Red-team: every hand-over between keyboards/profiles releases held keys first; a keyboard that fails to appear leaves the previous profile unchanged and says why. | Red review |

## 1. Contexts

| Context | Keyboard | Summon | Controller | Owner |
|---|---|---|---|---|
| ISO installer (TTY) | **buffyboard** (framebuffer, uinput) | Auto on text fields; View toggles | `tty` profile (spec 03 §3) | INSTALL |
| First-boot provisioning (tty1) | buffyboard | Same | `tty` profile | INSTALL |
| SDDM greeter | Qt Virtual Keyboard, embedded (`default/sddm/omarchy/Main.qml` and `GreeterEnvironment` in `etc/sddm.conf.d/10-wayland.conf`, on `feat/ally-auth-20261111` and `feat/ally-parity-release-20261111`). The integration tip has both files without the virtual keyboard or `GreeterEnvironment`. | Keyboard button on the greeter | Touch; controller TBC (AUTH) | AUTH |
| Hyprland desktop | **wvkbd-mobintl 0.21** via `omarchy-toggle-desktop-keyboard` | CC long, bar, Apps, menu, `SUPER + CTRL + Y` | `osk` profile while visible | TOUCH / INPUT |
| Omarchy menus / Apps grid | wvkbd (stays up) | Before or after opening the menu | `osk` profile | TOUCH (acceptance pending) |
| Gaming (Gamescope + Steam) | **Steam OSK** | CC long (Guide+West), Steam text field | Steam | Steam |
| Lock screen | **K07** trusted keyboard (held) | AUTH | AUTH | AUTH |
| Disk unlock (LUKS) | none today (`unl0kr` candidate, K11) | — | — | AUTH |

## 2. Baseline: what is already built

| Piece | Path (branch) | Fact |
|---|---|---|
| Helper | `bin/omarchy-toggle-desktop-keyboard` (`feat/ally-touch-20261111`; same flags on `feat/ally-parity-release-20261111`) | `toggle|show|hide|stop`; PID + start-time + executable identity; signals `SIGRTMIN`/`USR2`/`USR1`; `stop` = hide (releases keys in 0.21) then TERM; launch flags `-H 264 -L 264 --non-exclusive --wayland-layer overlay -l full,special --landscape-layers full,special --no-popup`; refuses Gamescope. The integration tip, `feat/ally-input-20261111` and `feat/ally-session-20261111` have this command with `-H 180 -L 180`. |
| Docs | `docs/rog-ally-touch-keyboard.md` | “No swipe-up gesture or automatic text-field activation”; `--auto` off because Hyprland permits a single input method and Fcitx5 holds it; covered fields at the bottom; bar summon. |
| Bind | `default/hypr/bindings/utilities.lua` (touch branch): `SUPER + CTRL + Y` on RC71L with wvkbd | CC long maps to it (INPUT). |
| Bar widget | `shell/plugins/bar/widgets/DesktopKeyboard.qml` and `shell/plugins/bar/widgets/DesktopKeyboard.manifest.json` (`feat/ally-touch-20261111`, also `feat/ally-parity-release-20261111`; not on the integration tip, `feat/ally-input-20261111` or `feat/ally-session-20261111`). Documented in `docs/rog-ally-touch-keyboard.md`. | Left tap toggles; right tap hides. |
| Setup | `bin/omarchy-setup-rog-ally-keyboard` | Requires reviewed `wvkbd 0.21-1`. |
| Session | `bin/omarchy-launch-gaming-session` calls `omarchy-toggle-desktop-keyboard stop` (`feat/ally-session-20261111` and `feat/ally-parity-release-20261111`; that launcher is not on the integration tip). `docs/rog-ally-gaming-session.md` (integration tip, session branch and release branch) says the launcher stops wvkbd. | No wvkbd in gaming. |
| Bridge | `default/rog-ally-input/bridge.py` (`feat/ally-input-20261111` and `feat/ally-parity-release-20261111`; not on the integration tip or `feat/ally-session-20261111`) | Needs show/hide signal to load `osk` (spec 01 OQ-10). Shipped `MODES` are `desktop`, `gamepad`, `dualsense`. |

## 3. Desktop: wvkbd

### 3.1 Layout and size

| Item | Spec |
|---|---|
| Layers | `full` (letters, numbers, Shift, Ctrl, Esc, Tab, arrows, Backspace) ↔ `special` (Alt, Super, AltGr, symbols, Delete, Home/End, PgUp/PgDn) — baseline. `Cmp` + letter for accents; `Cmp` + Space for the layout index. |
| Height | 264 logical units (baseline), = 396 px at scale 1.5. “Larger text” (spec 06) keeps 264 units. |
| Modifiers | One-shot (baseline), which already serves sticky-key users. |
| Position | Bottom overlay, non-exclusive (does not resize windows). Fields under it: scroll or move the window (baseline). |
| Physical layout | wvkbd's own keymap; physical layout and Fcitx untouched (baseline). |

### 3.2 Controller while visible (`osk` profile, Δ6)

| Button | Action |
|---|---|
| Right stick | Pointer (baseline) |
| A / RT | Press key under pointer (left click) |
| **B** | **Backspace** |
| **X** | **Space** |
| Y | Enter (baseline) |
| Start (Menu) | Esc (baseline) |
| D-pad | Arrows into the focused app (baseline) |
| LB / RB | Scroll (baseline) |
| CC long | Hide keyboard (toggle) |
| M1 | Super (spec 01 Δ7) |

Key-by-key d-pad navigation inside wvkbd is out of scope (wvkbd has no focus model; would need a patch, OQ-3).

### 3.3 Profile life cycle (D4)

| Event | Bridge action |
|---|---|
| Helper `show` succeeded | Send key-ups, load `osk` if current is `desktop`, confirm loaded (≤ 500 ms); failure ⇒ stay `desktop`, notify once. |
| Helper `hide` / `stop` | Key-ups, load `desktop`. |
| **wvkbd exits unexpectedly** (crash, `kill -9`, OOM) | Bridge holds a `pidfd` for the PID in the helper's state file; on exit: key-ups on the InputPlumber target, load `desktop`, remove stale state (helper already treats a dead PID as stopped). Next CC long starts a new wvkbd. |
| Bridge dies while `osk` | Systemd restarts bridge (3 s); on start, if no live wvkbd ⇒ `desktop`. |
| InputPlumber dies | Firmware pad; wvkbd stays usable by touch. |
| Lock / session inactive | Bridge already ⇒ `gamepad` (fail closed); helper `hide`. |
| Leaving desktop for gaming | Session calls `stop` (baseline) then the gaming hand-over (spec 02 §8). |

Stuck keys inside the compositor from wvkbd's virtual keyboard after a crash: Hyprland should release them when the virtual-keyboard client disconnects (**verify**, OQ-2).

### 3.4 Auto-show feasibility

| Option | Feasible now? | Why |
|---|---|---|
| wvkbd `--auto` (`zwp_input_method_v2`) | No | Hyprland allows one input method; Fcitx5 holds it; wvkbd 0.21 ignores `im_unavailable` ([main.c](https://github.com/jjsullivan5196/wvkbd/blob/v0.21/main.c)) |
| Fcitx5 front-end that signals show/hide to wvkbd on focus | Maybe | Needs an Fcitx5 addon or D-Bus hook (OQ-1) |
| Drop Fcitx5 on handheld | No | Breaks CJK input methods for users who need them |
| Shell-level heuristic (focus a known text widget) | Partial | Only for Omarchy's own QML fields (menu search): shell can call `show` itself (Δ-K2) |

Decision: manual summon; Δ-K2 auto-show only for Omarchy shell search fields when no physical keyboard is attached.

### 3.5 Theming (D5)

| wvkbd flag (0.21) | Omarchy theme value |
|---|---|
| `--bg` | `background` in `themes/*/colors.toml` |
| `--fg` / `--fg-sp` | Key / special-key surface (no separate palette key; text colour is `foreground`) |
| `--press` / `--press-sp` | `accent` in `themes/*/colors.toml` |
| `--text` / `--text-sp` | `foreground` in `themes/*/colors.toml` |
| `--fn` | Omarchy UI font; size is `[font] base-size` in `default/themed/shell.toml.tpl` |
| `--corner-radius` | Hyprland `decoration:rounding`, mirrored by `cornerRadius` in `shell/Commons/Style.qml`. `colors.toml` has no radius key. |

Applied by the helper at launch; a `theme-set` hook restarts a **hidden** keyboard only (never a visible one mid-typing; visible ⇒ restyle on next hide). `bin/omarchy-theme-set` runs `omarchy-hook theme-set` after retint (`docs/theming.md`). `bin/omarchy-hook` runs `~/.config/omarchy/hooks/theme-set` and every file in `~/.config/omarchy/hooks/theme-set.d/` except `*.sample`. The shipped sample is `config/omarchy/hooks/theme-set.d/show-theme-notification.sample`. There is no wvkbd hook yet. `bin/omarchy-theme-set-keyboard` retints keyboard backlight, not wvkbd. Flags verified in [wvkbd v0.21 `main.c`](https://github.com/jjsullivan5196/wvkbd/blob/v0.21/main.c).

## 4. Installer and first boot: buffyboard

From spec 03 §3: framebuffer touch keyboard ([README](https://gitlab.com/postmarketOS/buffybox/-/raw/master/buffyboard/README.md)), keys via uinput, VT resized so the form stays visible. View toggles; theme via buffyboard config (`/etc/buffyboard.conf.d/`) with Omarchy colours. Keymap must match the console keymap (buffyboard README); handheld forces US for the form (spec 03 W1).

## 5. Gaming: Steam OSK

| Item | Spec |
|---|---|
| Summon | CC long → InputPlumber `Keyboard` → Guide+West macro (baseline); Steam's text fields open it themselves. Deck/DS5 Edge targets (spec 02 D8): same macro (verify, OQ-4). |
| Desktop Steam (Big Picture in Hyprland) | wvkbd, not Steam's (Steam's desktop layout is off while the `desktop` profile is active, spec 01). |
| Never | wvkbd in Gamescope (helper refuses). |

## 6. Flows

| # | Flow | Steps |
|---|---|---|
| F1 | Type a URL on desktop | A focuses the address bar → CC long → wvkbd shows, `osk` loads → stick + A keys, X space, B backspace → Y Enter → CC long hides → `desktop`. |
| F2 | wvkbd crash | wvkbd killed mid-typing → bridge sees pidfd exit → key-ups → `desktop` → B is right-click again. |
| F3 | Menu search | AC tap → Omarchy menu → (Δ-K2) keyboard auto-shows when no physical keyboard → type → A selects → keyboard hides. |
| F4 | Steam search in gaming | CC long → Steam OSK → type → B (Steam) closes. |
| F5 | Install | buffyboard shows on the username field; View hides it for lists. |

## 7. Requirements on AUTH (lock screen, K07) — no UI design here

| # | Requirement |
|---|---|
| K-R1 | A trusted touch keyboard on the lock surface (K07), isolated from shell plugins (as in `docs/rog-ally-authentication.md`); its release triggers the `desktop-lock` `default-off` → `on` migration (spec 03 §7). |
| K-R2 | wvkbd must never be the unlock path; showing the lock hides wvkbd (`hide`) and the bridge leaves `osk`. |
| K-R3 | Controller can reach the lock keyboard's keys and Unlock/Cancel without a long press. |
| K-R4 | Held keys are released when the lock appears and when it closes. |
| K-R5 | Layout parity with the user's password characters (non-US) as for the SDDM keyboard. |

## 8. Acceptance criteria

1. Only one keyboard is ever visible: wvkbd never in Gamescope, buffyboard never after SDDM, Steam OSK never in Hyprland via CC long.
2. CC long, bar button, Apps entry, menu entry and `SUPER + CTRL + Y` all toggle wvkbd on RC71L; no new bind is added.
3. With wvkbd visible, B types Backspace and X types Space; hidden, B is right-click and X is middle-click.
4. Killing wvkbd with SIGKILL while visible returns the controller to `desktop` within 1 s with no stuck key (held-A and held-B tests).
5. Killing the bridge while `osk` is loaded and wvkbd is gone results in `desktop` after restart.
6. A failed `osk` load leaves `desktop` loaded and shows one notice.
7. Locking hides wvkbd and moves the controller to `gamepad`; unlock does not reshow wvkbd.
8. wvkbd colours and font match the active theme at launch; a theme change restyles a hidden keyboard and never restarts a visible one.
9. Menu search auto-show (Δ-K2) happens only when no physical keyboard is attached and never steals focus from the search field.
10. Steam OSK opens with CC long in Steam search and in one game's text field on the gaming target in use.
11. buffyboard appears on text fields in the installer and first boot and types the expected characters with the US console keymap.
12. Entering gaming from a desktop with wvkbd visible stops it before Gamescope starts (no orphan process).

## 9. Open questions

| # | Question | Owner |
|---|---|---|
| OQ-1 | Fcitx5 hook to show/hide wvkbd on text focus without taking the input-method slot? | dev-research |
| OQ-2 | Does Hyprland release keys held by a crashed virtual-keyboard client? | Hardware test |
| OQ-3 | Patch wvkbd for d-pad key focus, or accept pointer + A? | dev-lead |
| OQ-4 | Does the Guide+West macro open Steam OSK on the `deck-uhid` and `ds5-edge` targets? | Hardware test |
| OQ-5 | Is `deskintl` (larger desktop layout) better than `mobintl` at 1280×720 logical? | Daniel |
| OQ-6 | Show/hide signal from the helper to the bridge: D-Bus signal vs inotify on the state file (spec 01 OQ-10). | dev-lead |
| OQ-7 | SDDM greeter controller navigation for the Qt keyboard. | AUTH |

## 10. Branch conflicts

| Conflict | Where | Resolution proposed |
|---|---|---|
| Helper says “no automatic text-field activation” | `bin/omarchy-toggle-desktop-keyboard`, `docs/rog-ally-touch-keyboard.md` | Kept for apps; Δ-K2 limited to Omarchy shell fields. |
| Bridge has no `osk` mode | `default/rog-ally-input/bridge.py` (`feat/ally-input-20261111`) | Spec 01 Appendix A `MODES += osk`; plus pidfd watch (D4). |
| wvkbd launched with fixed flags, no colours | `bin/omarchy-toggle-desktop-keyboard` | Add theme flags (D5) via the `theme-set` hook above. |
| Helper height 180 on the integration tip | `bin/omarchy-toggle-desktop-keyboard` | Touch and release branches launch `-H 264 -L 264`. Integration, input and session still launch `-H 180 -L 180`. This spec follows 264. |
| Lock keyboard held (K07) | `feat/ally-auth-20261111` | Requirements §7; `desktop-lock` ships off until it lands. |

## Sources

- Fork: `bin/omarchy-toggle-desktop-keyboard`, `docs/rog-ally-touch-keyboard.md`, `shell/plugins/bar/widgets/DesktopKeyboard.qml`, `default/hypr/bindings/utilities.lua` (`SUPER + CTRL + Y` on `feat/ally-touch-20261111`; the same bind, widget and 264-unit helper are on `feat/ally-parity-release-20261111`); `bin/omarchy-launch-gaming-session` (`feat/ally-session-20261111` and the release branch; not on the integration tip); `docs/rog-ally-gaming-session.md` (integration tip, session branch and release branch); `default/rog-ally-input/bridge.py` (`feat/ally-input-20261111` and the release branch; not on the integration tip or the session branch); `docs/rog-ally-authentication.md`, `default/sddm/omarchy/Main.qml`, `etc/sddm.conf.d/10-wayland.conf` (`GreeterEnvironment` on `feat/ally-auth-20261111` and the release branch). Theme hook: `bin/omarchy-theme-set`, `bin/omarchy-hook`, `config/omarchy/hooks/theme-set.d/`, `docs/theming.md`, `themes/*/colors.toml`, `default/themed/shell.toml.tpl`, `shell/Commons/Style.qml`.
- External: [wvkbd README](https://raw.githubusercontent.com/jjsullivan5196/wvkbd/v0.21/README.md), [wvkbd v0.21 main.c](https://github.com/jjsullivan5196/wvkbd/blob/v0.21/main.c); [buffyboard README](https://gitlab.com/postmarketOS/buffybox/-/raw/master/buffyboard/README.md); [Hyprland InputMethodRelay](https://github.com/hyprwm/Hyprland/blob/main/src/managers/input/InputMethodRelay.cpp); [Steam controller shortcuts](https://help.steampowered.com/en/faqs/view/69e3-14af-9764-4c28).
