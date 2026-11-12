# 07 · On-screen keyboard

Status: draft, revision 3, 12 Nov 2026 (AWST). Owner: dev-ux. Depends on: [01](01-controller-button-map.md) (CC long, Δ6 `osk` profile), [03](03-first-boot-and-install.md) (buffyboard, `tty` profile), [06](06-accessibility.md). Lock-screen keyboard (K07) is AUTH's: **requirements only** here (§7). Rulings applied: `desktop-lock` ships off until K07 lands; no extra Ally binds; `SUPER + CTRL + X` taken. Revision 3 takes the second dev-red review of PR #30. Switching to desktop is spec 02 D12. Before K07, with the effective value `on` and no usable keyboard, the overlay row is shown disabled and reads “Connect a keyboard to unlock” (§4.1). Suspend outcomes are spec 02 §7.7.

## 0. Decisions in one table

| # | Decision | Source |
|---|---|---|
| D1 | One keyboard per context, never two on screen: buffyboard (first boot only, spec 03 §3.1), Qt Virtual Keyboard (SDDM greeter, built), wvkbd (Hyprland), Steam OSK (Gamescope), K07 trusted keyboard (lock, AUTH). | §1 |
| D2 | Desktop summon stays **manual**: CC long, bar button, Apps entry, Omarchy menu, `SUPER + CTRL + Y`. Auto-show on text focus is **not feasible today** (single input-method slot held by Fcitx5). | `docs/rog-ally-touch-keyboard.md` |
| D3 | While wvkbd is visible the controller uses the **`osk` profile** (spec 01 Δ6): desktop + **B = Backspace, X = Space**; plus Y = Enter (baseline), Start = Esc (baseline). Keys are pressed by **pointer (right stick) + A** or touch; no d-pad key-by-key focus (wvkbd has none). | Spec 01 |
| D4 | **Restore the previous profile** when wvkbd hides, crashes or the bridge restarts. Remember the profile that was current when `osk` loaded (spec 01 §6). A gaming session stays on its profile. Locked, inactive or unknown loads `gamepad`. A stale wvkbd exit that does not match the current generation is ignored. | Spec 01 §6, §12, C7 |
| D5 | wvkbd is **themed** from the active Omarchy theme via its colour/font flags at launch and on theme change. | wvkbd 0.21 flags |
| D6 | Gaming: Steam OSK only, via CC long (`Keyboard` → Guide+West macro) or Steam's own text-field prompt. | Baseline |
| D7 | Red-team: every hand-over between keyboards/profiles releases held keys first; a keyboard that fails to appear leaves the previous profile unchanged and says why. | Red review |

## 1. Contexts

| Context | Keyboard | Summon | Controller | Owner |
|---|---|---|---|---|
| ISO installer (TTY) | none (spec 03 §3.1: buffyboard does not run on the live ISO) | Physical keyboard, or the plain form | — | INSTALL |
| First-boot provisioning (tty1) | **buffyboard**, only as a child of that stage | Stage unit starts it for a text field and stops it when the field is left | `tty` profile (spec 03 §3) | INSTALL |
| Polkit and sudo prompts (desktop) | wvkbd, with the `osk` profile | Same summon as the desktop row. Turning `desktop-lock` off is one of these prompts (spec 02: interactive password, no passwordless grant) | `osk` while wvkbd is visible | TOUCH |
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
| M1 | Super (spec 01 Δ7), only after OQ-17 confirms the grip |

Key-by-key d-pad navigation inside wvkbd is out of scope (wvkbd has no focus model; would need a patch, OQ-3).

### 3.3 Profile life cycle (D4)

The restore target is the **previous** profile, never a hard-coded `desktop`. Compute it in this order (spec 01 §6, §12 and C7):

1. A gaming session in progress keeps its profile (`gaming`, or the fallback `gamepad` that spec 01 §12 holds for that session). Lock, unlock and a late wvkbd exit do not replace it.
2. Locked, inactive or unknown loads `gamepad`.
3. Otherwise load the profile remembered when `osk` was loaded. Spec 01 loads `osk` only from `desktop`, so that remembered profile is normally `desktop`.

Restores run through one serial queue. A second restore whose target is already loaded is a no-op, so hide followed by process exit is one load. The bridge arms a generation from the helper state file: PID, start time and executable. An exit applies only when it matches that generation. A stale exit (the previous process, a reused PID, or a generation the bridge did not arm) is ignored. Once the session is gaming or locked, a pidfd event does not load another profile.

The remembered profile and the armed generation are written under `$XDG_RUNTIME_DIR`, not kept only in the bridge process. `ExecStopPost` and a bridge that has just started read that file. If the file, the profile or the generation is missing or unreadable, the restore is `gamepad` (rule 2), unless a gaming session is in progress (rule 1). Rule 1 comes from the session, not from the file.

| Event | Bridge action |
|---|---|
| Helper `show` succeeded | Send key-ups. If the current profile is `desktop`, remember it and load `osk`, then confirm within 500 ms. Any other current profile stays as it is. Failure leaves the previous profile and notifies once. |
| Helper `hide` / `stop` | Key-ups, then one restore of the target above. |
| **wvkbd exits unexpectedly** (crash, `kill -9`, OOM) | If the exit matches the armed generation: key-ups on the InputPlumber target, one restore, clear the state. A mismatched generation is ignored. The next CC long starts a new wvkbd. |
| Bridge dies while `osk` | The bridge unit's `ExecStopPost` reads the runtime file and loads the safe profile from the order above, including when `Restart=on-failure` has hit its start limit. A missing or unreadable file loads `gamepad` unless a gaming session is in progress. `osk` must not survive the bridge. |
| Bridge starts | Re-read the helper state and the runtime file. Verify PID, start time and executable, and only then open the pidfd (a reused PID must not win). Keep `osk` only when that wvkbd is live and visible. Otherwise one restore. |
| InputPlumber dies | Firmware pad; wvkbd stays usable by touch. |
| Lock / session inactive | Load `gamepad` (C7) and `hide`. The hide restore must not land `desktop` after that `gamepad`. |
| Leaving desktop for gaming | Session calls `stop` (baseline) then the gaming hand-over (spec 02 §8). A delayed wvkbd exit does not load the remembered desktop profile over `gaming`. |

Hyprland does not release a closed virtual keyboard's keys unless told to. `input:virtualkeyboard:release_pressed_on_close` defaults to false. The handheld variant sets it to **true** in `default/hypr/input.lua`, gated by `omarchy-hw-rog-ally`, so other machines keep the default. The bridge cannot send those key-ups itself: spec 01 §8.1 requires the release from the device that pressed the key. If a latched Shift or Ctrl still sticks after that setting, force a keyboard focus leave and enter once wvkbd has gone. This closes OQ-2.

### 3.4 Auto-show feasibility

| Option | Feasible now? | Why |
|---|---|---|
| wvkbd `--auto` (`zwp_input_method_v2`) | No | Hyprland allows one input method; Fcitx5 holds it; wvkbd 0.21 ignores `im_unavailable` ([main.c](https://github.com/jjsullivan5196/wvkbd/blob/v0.21/main.c)) |
| Fcitx5 front-end that signals show/hide to wvkbd on focus | Maybe | Needs an Fcitx5 addon or D-Bus hook (OQ-1) |
| Drop Fcitx5 on handheld | No | Breaks CJK input methods for users who need them |
| Shell-level heuristic (focus a known text widget) | Partial | Only for Omarchy's own QML fields (menu search): shell can call `show` itself (Δ-K2) |

Decision: manual summon; Δ-K2 auto-show only for Omarchy shell search fields when no physical keyboard is attached. “No physical keyboard” reuses the PR #24 keyboard gate (`test/handheld/hw-keyboard-gate-test.sh`): the check runs only where `omarchy-hw-rog-ally` succeeds, so a laptop or 2-in-1 is unchanged. The Ally’s own Asus Keyboard HID, InputPlumber’s virtual keyboard and the bridge’s uinput keyboard do not count as a physical keyboard.

### 3.5 Theming (D5)

| wvkbd flag (0.21) | Omarchy theme value |
|---|---|
| `--bg` | `background` in `themes/*/colors.toml` |
| `--fg` / `--fg-sp` | Key / special-key surface (no separate palette key; text colour is `foreground`) |
| `--press` / `--press-sp` | `accent` in `themes/*/colors.toml` |
| `--text` / `--text-sp` | `foreground` in `themes/*/colors.toml` |
| `--fn` | Omarchy UI font; size is `[font] base-size` in `default/themed/shell.toml.tpl` |
| `--corner-radius` | Hyprland `decoration:rounding`, mirrored by `cornerRadius` in `shell/Commons/Style.qml`. `colors.toml` has no radius key. |

Applied by the helper at launch; a `theme-set` hook restarts a **hidden** keyboard only (never a visible one mid-typing; visible ⇒ restyle on next hide). That restart is a planned generation change: the bridge re-arms the new PID, start time and executable and does not treat it as a crash. `bin/omarchy-theme-set` runs `omarchy-hook theme-set` after retint (`docs/theming.md`). `bin/omarchy-hook` runs `~/.config/omarchy/hooks/theme-set` and every file in `~/.config/omarchy/hooks/theme-set.d/` except `*.sample`. The shipped sample is `config/omarchy/hooks/theme-set.d/show-theme-notification.sample`. There is no wvkbd hook yet. `bin/omarchy-theme-set-keyboard` retints keyboard backlight, not wvkbd. Flags verified in [wvkbd v0.21 `main.c`](https://github.com/jjsullivan5196/wvkbd/blob/v0.21/main.c).

## 4. First boot only: buffyboard

Same bar as spec 03 §3.1. Buffyboard is not on the live ISO and not on the installed desktop. It runs only as a child of first-boot provisioning (`BindsTo` and `PartOf` the provision unit), started for a text field and stopped when that field is left. It is stopped before `display-manager.service`. The upstream `buffyboard.service` (`WantedBy=multi-user.target`) and its getty drop-in are not enabled. It runs as root. uinput, input and tty access are not granted to a user or to the `input` group. Keys go through its own uinput; the VT is resized so the form stays visible. Theme via buffyboard config (`/etc/buffyboard.conf.d/`) with Omarchy colours. The handheld forces the US console keymap for the form (spec 03). Upstream: [buffyboard README](https://gitlab.com/postmarketOS/buffybox/-/raw/master/buffyboard/README.md).

## 4.1 Suspend before K07

Who locks, who returns to gaming, and who stays on the unlocked desktop are spec 02 §7.7 (D11) and its AC 35–38. The marker `/var/lib/omarchy/handheld/k07-landed`, ENOENT versus any other read, and the laptop exception are spec 02 §7.4. This section does not restate those tables. It is lock-on-suspend only. Desktop entry stays spec 02 §7.4 and D10, and this section does not let `desktop()` start an unlocked Hyprland.

When spec 02 §7.7 ends the desktop session instead of locking, hold a logind `delay` sleep inhibitor for the teardown. On `PrepareForSleep`, blank every output and cut input first (InputPlumber intercept or disable), then end the session. If it has not exited before `InhibitDelayMaxSec` (default 5 s), run `loginctl terminate-session`. Do not release the inhibitor while the desktop is visible or receiving input. The triggers are the power button, idle, low battery, Steam suspend and `systemctl suspend`. The RC71L has no lid, so there is no lid trigger. No desktop frame is shown on wake.

Before K07, with the effective value `on` and no usable keyboard, the overlay row is shown disabled and its label is “Connect a keyboard to unlock”. `desktop()` returns to gaming (spec 02 §7.4). The user does not reach a lock screen. With a usable keyboard, or once the marker is present, the row and the lock are spec 02 D12 and §7.4.

If the lock is up at resume and the keyboard is gone (§3.4, the same keyboard spec 02 §7.7 counts), end the session back to gaming. Never auto-unlock. The next entry is spec 02 §7.4.

## 5. Gaming: Steam OSK

| Item | Spec |
|---|---|
| Summon | CC long → InputPlumber `Keyboard` → Guide+West macro (baseline); Steam's text fields open it themselves. Deck/DS5 Edge targets (spec 02 D8): same macro (verify, OQ-4). |
| Desktop Steam (Big Picture in Hyprland) | wvkbd, not Steam's (Steam's desktop layout is off while the `desktop` profile is active, spec 01). |
| Never | wvkbd in Gamescope (helper refuses). |

## 6. Flows

| # | Flow | Steps |
|---|---|---|
| F1 | Type a URL on desktop | A focuses the address bar → CC long → wvkbd shows, `osk` loads from `desktop` → stick + A keys, X space, B backspace → Y Enter → CC long hides → the remembered profile (normally `desktop`). |
| F2 | wvkbd crash | wvkbd killed mid-typing, including with a key held → matching generation → key-ups → previous profile → B is right-click again. A stale exit from an older generation changes nothing. |
| F3 | Menu search | AC tap → Omarchy menu → (Δ-K2) keyboard auto-shows only under the PR #24 gate with no physical keyboard → type → A selects → keyboard hides. |
| F4 | Steam search in gaming | CC long → Steam OSK → type → B (Steam) closes. |
| F5 | First boot | buffyboard shows on the username field and is gone before SDDM. The ISO does not start it. |

## 7. Requirements on AUTH (lock screen, K07) — no UI design here

| # | Requirement |
|---|---|
| K-R1 | A trusted touch keyboard on the lock surface (K07), isolated from shell plugins (as in `docs/rog-ally-authentication.md`); its release triggers the `desktop-lock` `default-off` → `on` migration (spec 03 §7). |
| K-R2 | wvkbd must never be the unlock path; showing the lock hides wvkbd (`hide`) and the bridge restores per §3.3 (`gamepad` while locked, not `osk` and not `desktop` over that `gamepad`). |
| K-R3 | Controller can reach the lock keyboard's keys and Unlock/Cancel without a long press. |
| K-R4 | Held keys are released when the lock appears and when it closes. |
| K-R5 | Layout parity with the user's password characters (non-US) as for the SDDM keyboard. |

## 8. Acceptance criteria

1. Only one keyboard is ever visible: wvkbd never in Gamescope, buffyboard never after SDDM, Steam OSK never in Hyprland via CC long.
2. CC long, bar button, Apps entry, menu entry and `SUPER + CTRL + Y` all toggle wvkbd on RC71L; no new bind is added.
3. With wvkbd visible, B types Backspace and X types Space; hidden, B is right-click and X is middle-click.
4. Killing wvkbd with SIGKILL while visible restores the previous profile within 1 s, not a hard-coded `desktop`. A key held on the keyboard at the signal, and a latched Shift or Ctrl, is released: `wev` shows the release and the focused client does not autorepeat. `input:virtualkeyboard:release_pressed_on_close` is true on the handheld variant.
5. Killing the bridge while `osk` is loaded restores the §3.3 target from the `$XDG_RUNTIME_DIR` file, not from process memory. If that file is missing or unreadable, the profile is `gamepad` unless a gaming session is in progress. If wvkbd is still live and the restarted bridge verifies its PID, start time and executable, `osk` stays. If the start limit is hit, `osk` does not remain.
6. A failed `osk` load leaves the previous profile loaded and shows one notice.
7. Locking with wvkbd visible hides it and ends on `gamepad`, even if the hide restore races the lock. Unlock does not reshow wvkbd. Entering gaming with wvkbd visible, then a delayed wvkbd exit, leaves the gaming profile in place. Hide followed by process exit is one load. An exit whose generation does not match is ignored.
8. wvkbd colours and font match the active theme at launch; a theme change restyles a hidden keyboard and never restarts a visible one.
9. Menu search auto-show (Δ-K2) happens only when `omarchy-hw-rog-ally` succeeds and no physical keyboard (PR #24 gate, §3.4) is attached, and it never steals focus from the search field. The Ally HID, InputPlumber’s virtual keyboard and the bridge uinput keyboard do not count as attached.
10. Steam OSK opens with CC long in Steam search and in one game's text field on the gaming target in use.
11. buffyboard appears on text fields in first boot only, types the expected characters with the US console keymap, and is stopped before SDDM. After SDDM starts there is no buffyboard uinput device in `/proc/bus/input/devices`, and touch on Hyprland or Steam types nothing through it. No user and no `input` group holds uinput, input or tty access for it. It does not run on the live ISO.
12. Entering gaming from a desktop with wvkbd visible stops it before Gamescope starts (no orphan process). A delayed exit does not replace the gaming profile.
13. Suspend from the desktop follows spec 02 §7.7 and AC 35–38, and the marker rule in spec 02 §7.4. The triggers are the power button, idle, low battery, Steam suspend and `systemctl suspend`. The RC71L has no lid trigger. On the row that returns to gaming, no desktop frame is shown on wake. This criterion does not change desktop entry.
14. Before K07, effective value `on`, no usable keyboard: the overlay row is shown disabled and reads “Connect a keyboard to unlock”. Steam → Switch to Desktop, and any other call into `desktop()`, returns to gaming. There is no unlocked Hyprland frame and no lock screen.
15. A desktop process that ignores SIGTERM for 10 s is running. Suspend from the power button, from idle, from low battery, from Steam, and from `systemctl suspend`. The device never sleeps with the desktop visible or interactive: outputs are blank and input is cut before the session ends, and `loginctl terminate-session` has run if the session is still up at the inhibitor timeout. No desktop frame is shown on wake.
16. Resume after a lock-on-suspend whose keyboard is no longer attached: the session is back in gaming, the lock is not left up, and nothing auto-unlocked. No desktop frame is shown on wake. The next desktop entry is spec 02 §7.4, and criterion 14 while K07 has not landed.

## 9. Open questions

| # | Question | Owner |
|---|---|---|
| OQ-1 | Fcitx5 hook to show/hide wvkbd on text focus without taking the input-method slot? | dev-research |
| OQ-2 | **Closed.** Hyprland releases those keys only when `input:virtualkeyboard:release_pressed_on_close` is true. The handheld variant sets it (§3.3). AC 4 checks a held key and a latched modifier. | dev-lead |
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
| Lock keyboard held (K07) | `feat/ally-auth-20261111` | Requirements §7; `desktop-lock` ships off until it lands. Before K07, suspend follows §4.1. |
| `release_pressed_on_close` unset | `default/hypr/input.lua` | Handheld variant sets it true, gated by `omarchy-hw-rog-ally`. |

## Sources

- Fork: `bin/omarchy-toggle-desktop-keyboard`, `docs/rog-ally-touch-keyboard.md`, `shell/plugins/bar/widgets/DesktopKeyboard.qml`, `default/hypr/bindings/utilities.lua` (`SUPER + CTRL + Y` on `feat/ally-touch-20261111`; the same bind, widget and 264-unit helper are on `feat/ally-parity-release-20261111`); `bin/omarchy-launch-gaming-session` (`feat/ally-session-20261111` and the release branch; not on the integration tip); `docs/rog-ally-gaming-session.md` (integration tip, session branch and release branch); `default/rog-ally-input/bridge.py` (`feat/ally-input-20261111` and the release branch; not on the integration tip or the session branch); `docs/rog-ally-authentication.md`, `default/sddm/omarchy/Main.qml`, `etc/sddm.conf.d/10-wayland.conf` (`GreeterEnvironment` on `feat/ally-auth-20261111` and the release branch). Theme hook: `bin/omarchy-theme-set`, `bin/omarchy-hook`, `config/omarchy/hooks/theme-set.d/`, `docs/theming.md`, `themes/*/colors.toml`, `default/themed/shell.toml.tpl`, `shell/Commons/Style.qml`.
- External: [wvkbd README](https://raw.githubusercontent.com/jjsullivan5196/wvkbd/v0.21/README.md), [wvkbd v0.21 main.c](https://github.com/jjsullivan5196/wvkbd/blob/v0.21/main.c); [buffyboard README](https://gitlab.com/postmarketOS/buffybox/-/raw/master/buffyboard/README.md); [Hyprland InputMethodRelay](https://github.com/hyprwm/Hyprland/blob/main/src/managers/input/InputMethodRelay.cpp); [Steam controller shortcuts](https://help.steampowered.com/en/faqs/view/69e3-14af-9764-4c28).
