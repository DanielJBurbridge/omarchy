# 11 · Undocked touch desktop

Status: draft, 16 November 2026. Device: ROG Ally RC71L, 7 inch 1080p, landscape, no dock and no keyboard. Owner: dev-ux. Depends on [01](01-controller-button-map.md) (the desktop map), [02](02-mode-switch-and-dock.md) (dock, session), [06](06-accessibility.md) (scale), [07](07-on-screen-keyboard.md) (wvkbd), [08](08-mode-round-trip.md) (Switch to Desktop). This file is the undocked Hyprland desktop.

Research: [touch-desktop-and-stick-mouse.md](research/touch-desktop-and-stick-mouse.md), [touch-first-boot.md](research/touch-first-boot.md), [prior-art.md](research/prior-art.md), [feature-parity-audit.md](research/feature-parity-audit.md). The desktop profile is `default/inputplumber/profiles/desktop.yaml`, loaded by the helper from [PR #53](https://github.com/DanielJBurbridge/omarchy/pull/53). The [parity checklist](feature-parity.md#controller-touch-and-accessibility) records which parts of this design have passed on the RC71L.

## 0. Decisions

| # | Decision |
|---|---|
| D1 | The button and stick map is spec 01's desktop map. This spec does not replace it. Right stick pointer at 900 px/s, left stick notched scroll, RT left click, LT right click, CC long toggles wvkbd, AC tap opens the Omarchy menu. No system action is hold-only (spec 01 D5). |
| D2 | Docked is the ordinary Hyprland desktop: the machine's saved per-monitor scale, no edge gestures, no OSK auto-show. An external display that spec 02 counts as docked turns the touch profile off. |
| D3 | The touch profile turns on when a touchscreen is present and `omarchy-hw-physical-keyboard` fails, or when the user opts in. The Ally N-KEY `0b05:1abe`, InputPlumber's virtual keyboard and the bridge uinput keyboard do not count as a physical keyboard (spec 09). The gate is the touchscreen, not `omarchy-hw-rog-ally` (L54). |
| D4 | One keyboard on the desktop: wvkbd, via `omarchy-toggle-desktop-keyboard`. Menu search and the network passphrase auto-show it, and only while the session is unlocked. The lock, polkit and the greeter never do. Other clients keep the manual toggle until a show path exists that leaves fcitx5 in the input-method slot (spec 07 D2). |
| D5 | Touch is direct. The stick moves the seat pointer. A finger tap lands on the finger. Steam's Desktop Layout stays unset while `desktop` or `osk` is the loaded profile. |
| D6 | The panel stays landscape. No rotation daemon. |
| D7 | Gestures, the OSK and the touch profile are optional. With all three failed, AC tap, the right stick and RT/LT still work once `desktop` is loaded. The default bar's `omarchy.menu` button opens the menu by finger, and the handheld pin does not remove it. |

## 1. Docked and undocked

| | Undocked, no keyboard | Docked |
|---|---|---|
| Session | Hyprland after Switch to Desktop, a gamescope miss, or Stay on the undock prompt (spec 02, spec 08) | Hyprland. Spec 02 applies the saved external layout |
| Touch profile | On (D3) | Off. Today's desktop |
| Scale | Internal panel 1.5 (spec 06 Normal), unless the user already chose Larger or Largest | Each monitor keeps its saved scale |
| Sticks | `desktop` profile, spec 01 | Same profile while this is an RC71L desktop. The touch profile is the piece that turns off |
| OSK | Auto-show on shell fields. Manual toggle everywhere | Manual toggle only, and only if the user opens it |
| Gestures | Section 4 | None |

A USB keyboard on an undocked Ally turns the touch profile off (D3) and leaves the stick map loaded. Pulling that keyboard out turns the profile on again. The session does not change.

## 2. Entry and exit

| # | Flow | What happens |
|---|---|---|
| F1 | Gaming to desktop | Steam Power → Switch to Desktop (spec 08). The greeter stays down. The session loads `desktop` before the first frame the person uses. ProfileName reads `Omarchy Ally desktop`. |
| F2 | Gamescope miss | `desktop()` in `omarchy-session-start`. Same profile load as F1. The touch profile comes on because the panel is the only display and no physical keyboard is attached. |
| F3 | Back to gaming | AC tap, or the bar menu, then Switch to Gaming (spec 02 D4, spec 08). The launcher already stops wvkbd. Gestures stop with the Hyprland session. |
| F4 | Dock while here | Spec 02. Touch profile off. External scale unchanged. `desktop` stays loaded. |
| F5 | Undock, Stay | Spec 02's Stay. Keyboard gone and no external display: touch profile on. The session stays Hyprland. |

With the optional gaming-session package and its profile service running, the managed login requests `desktop` before starting Hyprland, including after Switch to Desktop. It requests `pointer` again on desktop exit after a successful desktop profile request. A missing service or a refused request still allows Hyprland to start. The failure-limit recovery desktop has its own OSK profile. The automated test covers request ordering. On the physical RC71L the right stick moved the pointer and RT left-clicked after both an ordinary return and a touchscreen password sign-in.

## 3. On-screen keyboard

Manual toggle, all of them the same command:

| Route | Who |
|---|---|
| CC long | `desktop.yaml` emits Super+Ctrl+Y. The bind is `default/hypr/bindings/utilities.lua`, and it exists when `wvkbd-mobintl` is installed and `omarchy-hw-rog-ally` succeeds |
| Bar button | `omarchy.desktop-keyboard` runs `omarchy-toggle-desktop-keyboard`. The bar layer does not take keyboard focus, so the field keeps the caret |
| Menu row | Same command. This is the route that is not a firmware long press (spec 01 D5) |
| `Super+Ctrl+Y` | A docked keyboard. Undocked, CC long is the chord |

Auto-show and hide, touch profile on, unlocked session only. This revises spec 07 D2 and Δ-K2: the gate is D3, not only `omarchy-hw-rog-ally`, and the fields are the named ones below, not every shell field and not menu search alone. `Super+Ctrl+Y` stays the Ally bind. The helper watches the session lock and gates itself. This spec does not edit `shell/plugins/lock` or `LockView.qml`. K07 stays AUTH. wvkbd is not the unlock path (spec 07 K-R2, L44).

| Field | Show | Hide |
|---|---|---|
| Menu search (`omarchy.menu`) and the network passphrase (`shell/plugins/panels/network/Panel.qml`) | On focus, and only while the session is unlocked. The shell owns these surfaces and does not need the input-method slot | On blur. Also when the session locks |
| Lock password (`shell/plugins/lock/LockView.qml`), `omarchy.polkit` (`PolkitAgent.qml`), the greeter | Never | Showing the lock hides wvkbd (`omarchy-toggle-desktop-keyboard hide`), called from the keyboard helper. Unlock does not show it again |
| GTK, Qt, Chromium, a game | Manual toggle until L89. `wvkbd --auto` and squeekboard both ask for the one input-method slot, and fcitx5 holds it (spec 07 D2). fcitx5 stays | A keyboard opened by hand stays until the toggle, and hides when the session locks |

Opening wvkbd currently keeps the desktop controller profile. A proposed `osk` profile gives B Backspace and X Space. Automatic switching needs a clean release when a button is held through the change. The stock daemon can leave B’s original output held. Gaming uses Steam’s keyboard. [Profile transition checks](07-on-screen-keyboard.md)

iPadOS shows the keyboard because the field is focused, and a secure field draws its own keypad. The behaviour is what we copy, for the named shell fields now and for other clients once L89 has a path that leaves fcitx5 alone. Apple's keyboard is not reusable (spec 09). Plasma's lock keyboard is the same idea and stays with K07.

## 4. Gestures

The implemented gesture uses a Quickshell handle. Enable `desktopKeyboard.edgeSwipe` and swipe up from the bottom centre of the undocked Ally desktop. It shows the themed keyboard while keeping the caret in the active app. The bar button still toggles the keyboard, and Apps stays under Menu → Apps. The other gestures below are proposals. [HHD touch recogniser](https://github.com/hhd-dev/hhd/blob/dec62efc3a8a87079d793a6671f3d45b196d633c/src/hhd/plugins/overlay/controllers.py#L375-L456) · [HHD shortcut defaults](https://github.com/hhd-dev/hhd/blob/dec62efc3a8a87079d793a6671f3d45b196d633c/src/hhd/plugins/overlay/shortcuts.yml#L60-L94)

| Gesture | Action | Also reached by | Borrowed |
|---|---|---|---|
| Top edge | Omarchy menu (`omarchy.menu`) | AC tap. Bar `omarchy.menu` | iPad: an edge always reaches a system surface. The action is the Omarchy menu, which is what AC tap already does |
| Swipe up or tap the bottom-centre handle | Show the desktop keyboard in the focused app | Tap **Keyboard** in the bar to show or hide it | HHD’s bottom-up keyboard shortcut |
| Left edge | Previous workspace | Menu. M1+RB once OQ-17 (spec 01) | hyprgrass workspace swipe |
| Right edge | Next workspace | Menu. M1+LB once OQ-17 | hyprgrass workspace swipe |
| Two-finger swipe up | Fullscreen | Menu (spec 01 OQ-13) | hyprgrass multi-finger swipe, bound to `Super+F`'s action |
| Two-finger swipe down | Polite close (`killactive`) | Menu | Same. Spec 01: the app may ask to save |
| Two-finger tap | Right click | B, LT | omarchy-osk's tap, reimplemented. Their MIT notice travels if a file is adapted. The vendored hyprgrass does not |
| Long-press, about 450 ms | Right click | Two-finger tap, B, LT | omarchy-osk's timing. Legal only because the tap routes exist (D5) |

Conflict with Steam and with games:

| Where | Rule |
|---|---|
| Gamescope | Gestures do not run. `--default-touch-mode 4` stays passthrough. Steam owns the finger |
| Fullscreen focused window on the desktop | Edge swipes and the two-finger close / fullscreen gestures do not fire. Touch goes to the client. A Steam game and Big Picture in this session included |
| Swipe that starts inside the window | The app's. A browser's back swipe stays the browser's |
| wvkbd visible | The handle yields the bottom edge so every key can receive a tap |
| Session locked | No gesture fires. Each `hl.plugin.hyprgrass.bind` omits `locked`, so Hyprland does not run it while the session lock is up. The gesture config gates itself. No edit to `shell/plugins/lock` or `LockView.qml` |
| Plugin absent or dead | The table's "also reached by" column is the product |

The other proposed gestures target hyprgrass for edge and multi-finger swipes with one command per gesture ([configuration](https://github.com/horriblename/hyprgrass/blob/main/docs/configuration.md)). SPDX `BSD-3-Clause` (copyright Ching Pei Yang 2023). Some parts follow AOSP (Apache-2.0) and the examples follow Waybar (MIT). It stays a plugin. The BSD notice travels with any example we adapt. A bad load can leave the touch device dead until the plugin unloads, which is why D7 does not use the plugin as the way back. There is no Arch extra package. AUR `hyprgrass-git` depends on `hyprland-git`, so this image does not install it (L92). Install is `hyprpm` against a commit that builds on the extra `hyprland` this tree ships, and a Hyprland update means a rebuild. The plugin is still alpha. [omarchy-tablet](https://github.com/yeutterg/omarchy-tablet) has no licence: ideas only, and we do not copy it.

## 5. Scale and targets

The internal panel at Normal is scale 1.5, 1280×720 logical (spec 06). Larger is 1.75. Largest is 2.0. Hit targets are at least 44 logical px at each of those: shell menu rows, shell bar controls, notification dismiss and notification actions. The floor uses the current theme's colour, type and metrics. There is no second theme and no theme fork.

This branch has no Waybar config and no Walker. The bar is `shell/plugins/bar`. The menu is `shell/plugins/menu` (`omarchy.menu`). The default bar already places `omarchy.menu` on the left (`shell/shell.qml`). Menu `baseRowHeight` is `Style.space(50)`, a layout constant, not a touch profile. Notification dismiss is the close glyph in `Toast.qml` (`Style.space` around the mark), which is the control the 44 px floor has to cover. `default/hypr/monitors.lua` is `scale = "auto"` for every machine. The touch profile sets 1.5 on the internal panel only. A docked output keeps the scale in `monitor-settings.lua`. `omarchy-display-rog-ally touch-preset` is the other branch's name for the 1.5 preset and is not on this tip (L43).

## 6. Sticks

Spec 01 §5.2 and §9. The shipped file matches that map. The speeds and the button targets below are `desktop.yaml`, listed so a device test can use this page. Spec 01 states a fixed 0.20 deadzone on the pointer. The file sets 0.25 on the triggers and does not repeat a deadzone on the right-stick motion.

| Control | Desktop | Optional OSK profile | Gaming |
|---|---|---|---|
| Right stick | Pointer, 900 px/s | Pointer, 900 px/s | Game axis |
| Left stick | Stock InputPlumber 0.84.0 produces no wheel events. A private driver and profile pair scroll in four directions in a guest | Same | Game axis |
| RT / A / R3 | Left click. Hold A or RT drags | Left click, including a key under the pointer | Game |
| LT / B | Right click | B is Backspace | Game |
| X | Middle click | Space | Game |
| Y | Enter | Enter | Game |
| LB / RB | Wheel down / up | Same | Game |
| D-pad | Arrows | Arrows | Game |
| View / Menu | Tab / Escape | Tab / Escape | Game |
| CC tap | Power panel, then the quick-access overlay when spec 04 exists | Same | Steam |
| CC long | Toggle wvkbd | Hide wvkbd | Steam OSK |
| AC tap | Omarchy menu | Omarchy menu, keyboard stays | QAM |
| AC long | Profile toggle, and a menu row does the same | Same | Overlay, or QAM until spec 04 |

`desktop.yaml` and `osk.yaml` also list `xbox-elite` next to `mouse` and `keyboard`. Spec 01 C2 asked for no gamepad target so Steam could not add a second pointer. This spec leaves the file as PR #53 shipped it (OQ-1).

Touch and the stick together:

| | Touch | Stick |
|---|---|---|
| Pointing | The finger, on the panel | The seat cursor, 900 px/s. Triggers use the file's 0.25 deadzone |
| Click | Tap is left click at the finger | RT, A or R3 at the cursor |
| Scroll | The client's own drag, inside the window | Left stick notches, and LB/RB |
| Right click | Two-finger tap | LT or B |
| While the other is active | A finger does not warp the cursor | Stick motion during a finger drag still moves the cursor |

One owner: InputPlumber (spec 01 C1). Firmware stays in gamepad mode (C10). HHD's 0.4 s Armoury hold, which tells the MCU to enter mouse mode, stays out. Bazzite's Ally page still describes that hold; the handheld wiki also says a missing desktop layout is fixed in Steam's controller settings, and that the Deck 44 stack is InputPlumber. We take the second fact. The hold is the HHD path spec 01 already refused. Upstream `mouse_keyboard_wasd.yaml` uses 800 px/s and maps the left stick to WASD. We do not paste it. Our left stick scrolls.

`hand-left` and `hand-right` stay spec 01 §11.2: off until a menu row selects one, then the pointer moves to the stick that preset names. The touch profile stays on, so the other hand can still tap.

## 7. Text and the right click

| Action | Touch | Stick |
|---|---|---|
| Place the caret | Tap the text | A or RT on the cursor |
| Select a word | Double-tap, when the client does that | — |
| Extend a selection | The client's handles, or a drag the client already treats as a selection | Hold A or RT and move the right stick |
| Right click / context menu | Two-finger tap. Long-press is the same action and is a shortcut beside that tap | B or LT |
| Copy, paste | The menu the right click opened | The same menu |

A long-press with no tap route does not ship (D5). We do not draw our own selection handles.

## 8. Rotation

The RC71L panel stays landscape here and in the gaming session. No autorotation, no `iio-hyprland`. That daemon is GPL-3 and stays out of this tree. A transform the display panel already saved is Hyprland's own; this spec adds no sensor and no new transform. SteamOS 3.8's note about rotated handheld panels does not name the Ally, and it is not a reason to rotate this desktop.

## 9. Accessibility

Spec 06 owns the pack. This desktop follows it.

| Need | What the touch profile does |
|---|---|
| Text size | 1.5, 1.75 and 2.0 on the internal panel. The 44 px floor holds at each. Spec 06 AC 6: bar, menu and wvkbd stay usable, and at 2.0 the menu scrolls |
| High contrast | The existing theme. No forked colours |
| Reduce motion | Gestures still complete. No action exists only as an animation |
| Zoom | Spec 06. The right stick moves the pointer while zoomed. The keyboard chord stays `Super+Ctrl+Z`. The menu row is spec 06's |
| One hand | Spec 01 presets, off until chosen. Touch targets stay on both sides of the panel |
| Lock and polkit | K07 and the polkit keypad (L36, L37). wvkbd does not unlock the lock and does not type into `omarchy.polkit` |

## 10. Failure

| Failure | What still works | What the person sees |
|---|---|---|
| wvkbd fails to start | The profile is unchanged (spec 07 D7). Stick, touch and AC tap work | `omarchy-notification-send` says the keyboard did not start. The same toggle retries |
| wvkbd exits | The profile from before `osk` returns. B is right click again (spec 01 §6) | The keyboard is gone. Next CC long starts another |
| Gesture plugin dies | AC tap, bar menu, CC long, right stick, RT/LT | Edge swipes stop. A menu row turns the plugin off |
| Plugin wedges the touch device | The controller, once `desktop` is loaded: AC tap opens the menu, CC long toggles wvkbd, the right stick moves, RT and LT click | The menu row unloads the plugin. A USB keyboard is the rung after that, the same rung as ALPHA.md. The plugin is not the recovery |
| `desktop` did not load (L64) | The default bar's `omarchy.menu` button opens the menu by finger. `pinHandheldTouch` adds Wi-Fi, Bluetooth and the keyboard and leaves that button in place. The session retries the load once | A notification names the profile that is loaded. After a successful retry the right stick moves. AC tap is QAM while the profile is still `gaming`, so the bar button is the touch route on that path |
| Both the touch device and the profile are dead | SSH if sshd was enabled, or a USB keyboard (ALPHA.md) | The controller cannot invent a pointer the profile did not load, and a wedged touch device has no bar to tap |

Gamescope is unchanged through all of these. A gesture crash does not cross into the gaming session.

## 11. Core and the gaming package

Core means Omarchy on any touchscreen, useful on a laptop or a tablet. It ships off unless D3 is true or the user opts in. Gaming means the opt-in handheld package (`omarchy-gaming-session` and the InputPlumber profile helper). Ally buttons and stick maps stay there.

| Feature | Where | Off until |
|---|---|---|
| Gesture config (section 4) | Core | D3, or the menu row. Off while the session is locked. The binds gate themselves |
| OSK manual toggle for a touchscreen that is not an Ally | Core. The package is still optional AUR wvkbd (L61). The binary stays out of the MIT tree | D3, and `wvkbd-mobintl` present |
| OSK auto-show on shell fields | Core | D3, and the session is unlocked. The helper gates itself |
| OSK auto-show on other clients | Core, once L89 exists | D3, and the session is unlocked |
| Touch scale 1.5 and the 44 px floor, current theme | Core | D3. A saved per-monitor scale wins on a docked output |
| Menu row to opt in or out | Core | Always available on a machine with a touchscreen |
| `desktop.yaml` / `osk.yaml`, stick pointer, CC and AC | Gaming | RC71L handheld package. PR #53 |
| Load `desktop` on F1 and F2, load `osk` while wvkbd is up | Gaming | The same package. L64 is the hole |
| Gamescope `--default-touch-mode 4` | Gaming | Already shipped. This spec leaves it |
| One-handed presets | Gaming | A menu row (spec 01 AC 20) |
| Rotation | Neither | Stays off (D6) |

The Ally undocked, with no keyboard, meets D3, so the core profile turns on there without a second Ally-only copy of the gestures or the scale. The gaming package adds the stick map and the button chords on top.

## 12. Shipped and still to build

Read on this tip. "Shipped" means the file or the command is in the tree. It does not mean an RC71L has run it.

| Piece | Tree | This spec |
|---|---|---|
| Right stick 900 px/s, left stick notched wheel, RT/LT, CC long → Super+Ctrl+Y, AC tap → `omarchy_menu` | `default/inputplumber/profiles/desktop.yaml` | Keep |
| OSK face-button swap | `default/inputplumber/profiles/osk.yaml` | Keep. The load on show is to build |
| Greeter left-stick pointer | `omarchy-ally-pointer.yaml`, `omarchy-ally-pointer.service` | Out of scope. Greeter only |
| Profile helper, allowlist, `load pointer` before SDDM | `bin/omarchy-inputplumber-profile` (PR #53) | F1 requests `desktop` via the profile service. Physical acceptance remains open (L64) |
| wvkbd toggle, bar button, Ally bind | `omarchy-toggle-desktop-keyboard`, `DesktopKeyboard.qml`, `utilities.lua` | Manual toggle. Keep |
| Shell menu and bar | `shell/plugins/menu`, `shell/plugins/bar`, `omarchy.menu` on the default bar | 44 px floor to build |
| Notifications | `shell/plugins/notifications` | Dismiss and actions grow to 44 px. To build |
| Monitor scale | `monitors.lua` `scale = "auto"` | 1.5 on the internal panel under D3. To build (L43 for the other branch's helper) |
| Gestures | The keyboard handle is the first trial. The other gestures are proposals for hyprgrass | Check the handle in a focused text field and ordinary app scrolling immediately beside it. Repeat in fullscreen, while locked and after docking |
| Shell-field auto-show | Spec 07 names it. No show-on-focus in the shell fields | To build |
| Other-client auto-show | Blocked by fcitx5 | L89 |
| Gamescope touch passthrough | `omarchy-session-start` mode 4 | Keep |
| Rotation daemon | None | Stays none |
| Steam Desktop Layout forced off | Not enforced | OQ-2 |

## 13. Acceptance

On an RC71L, undocked, no USB keyboard. The N-KEY device does not count. Each one that needs a piece from section 12's "to build" column fails until that piece exists.

1. F1. Steam Power → Switch to Desktop shows Hyprland, the greeter stays down, and ProfileName is `Omarchy Ally desktop`. The right stick moves the pointer. The left stick scrolls a page in notches and does not move the pointer. A centred stick for 10 s does not drift. 5/5.
2. RT and A left-click, LT and B right-click, X middle-clicks, CC long shows and hides wvkbd, AC tap opens and closes the Omarchy menu. No action in section 6 exists only as a hold.
3. Docked, with a keyboard on the external display's desk: no edge swipe runs a section 4 action, wvkbd does not appear on a shell field by itself, and the external monitor keeps its saved scale. Undock, keyboard unplugged, Stay: the touch profile is on and the session is still Hyprland.
4. With the touch profile on and the session unlocked, focusing menu search or the network passphrase shows wvkbd without CC long, and blur hides it. CC long, the bar button and the menu row still toggle it. A browser field does not show it by itself. The lock password field, `omarchy.polkit`, and the greeter do not show it. Showing the lock hides wvkbd, and unlock does not show it again. Killing wvkbd restores B as right click. No file under `shell/plugins/lock` changed for this.
5. Touch profile on, session unlocked, no fullscreen window: the section 4 table, each gesture, 5/5, and the "also reached by" control does the same action. A fullscreen game receives the finger and the edge swipes do not change workspace, close the game, or open the menu. While the session is locked, none of those gestures fire, and AC/CC do not run a desktop action (spec 01 AC 13). After unlock the gestures work again. Gamescope is still touch mode 4, and a finger activates a Steam control.
6. At 1.5, 1.75 and 2.0 the menu row, a bar control, and a notification's dismiss and action are each at least 44 logical px, drawn in the current theme. The docked external monitor is not forced to 1.5.
7. A finger tap clicks where the finger is. The right stick moves the cursor. During a finger drag the cursor stays on the stick's path. Two-finger tap opens a context menu. Long-press does too, and two-finger tap still does it with long-press disabled. Double-tap in a text field selects a word when that client already does.
8. The panel stays landscape across F1 and a reboot into this desktop. No rotation daemon is running.
9. wvkbd missing or crashing: a notification, the stick still clicks, AC tap still opens the menu. The gesture plugin stopped, and again with the touch device wedged: AC tap, CC long and the right stick still work while `desktop` is loaded. The menu row unloads the plugin.
10. Force the profile load to fail once: the notification names the loaded profile, the bar `omarchy.menu` button opens the menu by finger, and the one retry that succeeds leaves the right stick moving. AC tap is not required to succeed while the name is still the gaming profile.
11. A laptop with a keyboard and no opt-in: no gesture config, no 1.5 force, no OSK auto-show. An RC71L without the handheld package: no `desktop.yaml` and no CC/AC chords. With the package, undocked, no keyboard: section 4 and section 5 are on, and section 6 is on as well.

## 14. Open questions

| # | Question | Owner |
|---|---|---|
| OQ-1 | With `xbox-elite` still in `desktop.yaml`, can Steam add a desktop-layout pointer beside the 900 px/s stick while Steam is open? Spec 01 C2 wanted that target gone. This spec does not edit the file. | Hardware |
| OQ-2 | What keeps Steam's Desktop Layout unset for the life of `desktop` and `osk`? Bazzite documents setting that layout by hand. A forced empty layout is unverified here. | input |
| OQ-3 | Do a 24 px edge and an 80 px travel false-trigger on ordinary scrolls at scale 1.5 on this panel? | Hardware |
| OQ-4 | Two-finger swipe up and down against a browser's two-finger scroll, windowed. The fullscreen exception is specified. The windowed boundary needs a pass on the device. | Hardware |
| OQ-5 | L89's show path for clients that are not the shell, leaving fcitx5 in the slot. An Fcitx addon that only signals show and hide is the candidate spec 07 already names. The same unlocked-session gate as the shell fields. | TOUCH |
| OQ-6 | `pinHandheldTouch` adds Wi-Fi, Bluetooth and the keyboard. It does not add `omarchy.menu`. The default layout has that button. A stored layout that dropped it has no finger route to the menu until the top-edge gesture (L88). Should the pin keep the menu button the way it keeps the keyboard? If it does, the pin stays a runtime merge and does not write `~/.config/omarchy/shell.json`. | shell |

## What we borrow

Behaviour only. The link is the upstream for that piece. The Omarchy command or file that already does the job stays the implementation: `omarchy-menu`, `omarchy-toggle-desktop-keyboard`, the shell bar and menu, and `desktop.yaml` on InputPlumber. No second menu, theme, or keyboard. Licences stay with the upstream project. GPL and LGPL stay separate packages. A repository with no licence file contributes no code.

| Upstream | What we take | What we leave |
|---|---|---|
| Apple Human Interface Guidelines, [keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards) and [gestures](https://developer.apple.com/design/human-interface-guidelines/gestures) | The keyboard follows a focused field. An edge swipe reaches a system surface. Double-tap selects a word, and a long-press is a shortcut beside that tap. Spec 09 already uses the lock-screen half of this | Apple's software. Rotation stays off (D6). The top edge opens `omarchy-menu` |
| [hyprgrass](https://github.com/horriblename/hyprgrass), BSD-3-Clause, copyright Ching Pei Yang 2023 | Edge swipe, multi-finger swipe, one command per gesture. The README's warning that a bad load kills touch until unload is why D7 recovers from the controller | Default binds, the AOSP parts, and a vendored copy. AUR `hyprgrass-git` depends on `hyprland-git` (L92). Install stays `hyprpm` against a commit that builds on extra `hyprland`, rebuilt when Hyprland updates |
| [wvkbd](https://github.com/jjsullivan5196/wvkbd) v0.21, [AUR wvkbd](https://aur.archlinux.org/packages/wvkbd), GPL-3 (treat as `GPL-3.0-only`). Omarchy already runs it as `omarchy-toggle-desktop-keyboard`. The package stays separate | Show, hide and toggle signals. Themed from the active Omarchy theme (spec 07 D5) | `--auto`. v0.21's `im_unavailable` is empty, and Hyprland allows one input method. The sources stay out of this MIT tree |
| [squeekboard](https://gitlab.gnome.org/World/Phosh/squeekboard), Arch extra `squeekboard` 1.43.1-6, GPL-3.0-or-later. D-Bus name `sm.puri.OSK0` | Show-on-request via `SetVisible`, if L89 needs a signal that is not the input-method slot | The package as the default. It wants the same slot fcitx5 holds |
| Valve [gamescope](https://github.com/ValveSoftware/gamescope) `--default-touch-mode`, and Steam's Power → Switch to Desktop (spec 08 already wires the shim) | Touch mode 4, so a game keeps the finger. The menu entry the pad already uses | KDE's desktop gestures. The Ally has no trackpad, so the Deck's trackpad mouse is not a model for this panel |
| [Bazzite handheld wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/), Deck 44 on InputPlumber. Ally page: [ASUS ROG Ally](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/ASUS_ROG_Ally/) | One daemon owns the sticks. A Steam Desktop Layout must not be a second pointer | The Ally page's "hold Armoury Crate for mouse mode". That matches HHD's 0.4 s MCU command, which spec 01 refuses. The page says the wiki may be outdated |
| [omarchy-osk](https://github.com/ekollof/omarchy-osk), MIT, copyright 2026 ekollof, if a file is adapted and the notice travels | About 450 ms for the long-press right click, and a second finger as a tap | The vendored hyprgrass tree (BSD-3-Clause, its own notice) and the Quickshell keyboard. The desktop keyboard stays wvkbd |
| InputPlumber [`mouse_keyboard_wasd.yaml`](https://github.com/ShadowBlip/InputPlumber/blob/main/rootfs/usr/share/inputplumber/profiles/mouse_keyboard_wasd.yaml). Our map is `default/inputplumber/profiles/desktop.yaml` | The schema can map a stick to `speed_pps` and a trigger to a click. Their figure is 800 px/s. Ours is 900 px/s, spec 01 | The file itself (GPL daemon; we do not paste it) and left-stick WASD. Our left stick is a notched wheel |

[omarchy-tablet](https://github.com/yeutterg/omarchy-tablet) describes a detached bar, a tray that does not launch the app under it, and a keyboard that shows on text fields. No licence file. Ideas only.

## Sources

- Tree: `default/inputplumber/profiles/desktop.yaml`, `osk.yaml`, `omarchy-ally-pointer.yaml`, `bin/omarchy-inputplumber-profile`, `bin/omarchy-toggle-desktop-keyboard`, `bin/omarchy-session-start`, `default/hypr/bindings/utilities.lua`, `default/hypr/monitors.lua`, `shell/plugins/menu/Menu.qml`, `shell/plugins/menu/BarWidget.qml`, `shell/plugins/bar/widgets/DesktopKeyboard.qml`, `shell/plugins/notifications/Toast.qml`, `shell/shell.qml`. [PR #53](https://github.com/DanielJBurbridge/omarchy/pull/53).
- Specs: [01](01-controller-button-map.md), [02](02-mode-switch-and-dock.md), [06](06-accessibility.md), [07](07-on-screen-keyboard.md), [08](08-mode-round-trip.md), [09](09-keyboard-free-boot.md). Follow-ups L43, L54, L61, L64, L88–L92.
- Borrowed behaviour, with the upstream link on each row: [What we borrow](#what-we-borrow).
