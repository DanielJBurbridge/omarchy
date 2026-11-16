# 08 · Mode round trip

Status: draft, 12 Nov 2026. Device: ROG Ally RC71L. This is only the missing round trip on top of the session that already ships. It adds no overlay, input map, TDP, or dock behaviour.

Today `bin/omarchy-launch-gaming-session` can leave Hyprland for gaming, and Steam's Switch to Desktop can ask the same `bin/omarchy-session-start` process to start Hyprland. There is no menu row and no binding, and a later SDDM relogin ignores that choice.

## 1. Desktop → gaming

Add **Switch to Gaming** and `Super + Ctrl + G`. `Super + Ctrl + G` is free. `Super + Shift + Ctrl + G` stays Google Messages (`default/hypr/bindings/applications.lua`).

| Piece | File | Change |
|---|---|---|
| Menu row | `default/omarchy/omarchy-menu.jsonc` | `system.switch-gaming`, under System, label "Switch to Gaming", action `omarchy-launch-gaming-session`. The shell reads this file (`shell/plugins/menu/MenuModel.js`). No new menu script. No `aliases`. |
| Binding | `default/hypr/bindings/utilities.lua` | `o.bind("SUPER + CTRL + G", "Switch to Gaming", "omarchy-launch-gaming-session")`, gated like the existing Ally `Super + Ctrl + Y` check. |
| Catalog line | `default/i18n/en/keybindings.json` | The bind's description string, same as "Desktop keyboard". |

The command is `omarchy-launch-gaming-session`, not `omarchy-gaming-session.target`. The launcher logs the desktop out. `default/gaming/switch.sh` writes `gaming` into the runtime switch file and runs `omarchy-system logout --execute`. After that logout, `bin/omarchy-session-start` sees the switch and `run_gaming` starts the target.

Guards, using what the command already does:

- The row's `when` is `omarchy-hw-rog-ally && omarchy-pkg-present omarchy-gaming-session`. Hidden when this is not an RC71L, or the gaming session package is not installed. The binding uses that same predicate.
- The command exits 1 when `omarchy-hw-rog-ally` fails, when this login is not the managed preference session (`active` is not `desktop`), when Steam is still running, or when `gamescope` or `steam` is missing. It accepts `--confirm` and does not prompt again.
- No new unsaved-work or open-apps prompt. The user saves work and exits Steam first. The command already refuses while Steam is running, then logs out.
- Controller-only: nothing in this tree opens the menu from the pad. With a keyboard the row is `Super + Space` then the row, or `Super + Ctrl + G`. Reaching it from the pad alone is out of scope until the input map exists.

## 2. Gaming → desktop, and Relogin

Steam's Power → Switch to Desktop runs `default/gaming/bin/steamos-session-select` with `plasma`, which execs `omarchy-launch-gaming-desktop`. That writes `desktop` on the return FIFO. `omarchy-session-start` stays in the same process, sets the selection to desktop, and `desktop()` runs `uwsm start` Hyprland. That path does not show the greeter.

The hole is `Relogin=true` in `/etc/sddm.conf.d/zz-omarchy-handheld.conf`. When `omarchy-session-start` exits, SDDM starts `omarchy-handheld.desktop` again. That runs `bin/omarchy-handheld-autologin`. If `/run/omarchy/handheld-autologin/stop` exists, the `session` verb exits 0 and does not start a session. Otherwise it execs `omarchy-session-start relogin`. `gaming_entry_selection` in `default/gaming/session.sh` prints `gaming` for `relogin` and does not read `next`. A process exit after Switch to Desktop therefore comes back as gaming.

Change, on the explicit return only: before the gamescope scope stops, write the existing one-shot `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/gaming-session/next` as `desktop`. `gaming_entry_selection relogin` consumes `next=desktop` once, returns `desktop`, and deletes the file. Any other relogin still returns `gaming`. Clear that same file once Hyprland is up in the in-process handoff, so a later logout is a normal relogin into gaming and does not pin the desktop. If the process dies before Hyprland is up, the file is still there and the one relogin lands in Hyprland, not the greeter and not gaming.

Do not write `next` on a crash, a timeout, a missing `gamescope` or `steam`, or a non-zero Steam exit. Those stay on today's failure path.

Crash-loop, unchanged: `omarchy-handheld-autologin fail` runs only when the process exits without the ready FIFO reading `started`. A switch after `started` has already called `reset`, so it adds no timestamp. Three failures inside 60 seconds still write `stop`, set `Relogin=false`, and show the greeter. The one-shot must not delete `stop` and must not set `Relogin` back to true. Do not set `Relogin=false` for a normal switch. That would be the greeter.

## 3. Desktop → gaming with no keyboard

No cheap path. The new row and `Super + Ctrl + G` need a keyboard, and the pad does not open the menu. Out of scope.

## Acceptance

1. On an RC71L with `omarchy-gaming-session` installed, System shows Switch to Gaming, and `Super + Ctrl + G` runs `omarchy-launch-gaming-session`.
2. On any other machine, and on an RC71L without that package, the row is absent and the binding is absent.
3. With Steam still running, the command exits and does not log out. With Steam exited, from the preference session, it reaches Gaming Mode. There is no new confirm dialog.
4. Steam Power → Switch to Desktop shows the Hyprland session. The greeter does not appear, and that return does not start gaming again.
5. If that process exits before Hyprland is up, the next autologin starts Hyprland once and then the one-shot is gone. A later logout with no one-shot returns to gaming.
6. A gaming start that never reads `started` does not write `next=desktop`. Three such starts in 60 seconds still write `/run/omarchy/handheld-autologin/stop`, set `Relogin=false`, and show the greeter.

## Out of scope

- Controller-only reachability, InputPlumber, the F17 escape, and the overlay watchdog.
- An unsaved-work or open-apps prompt.
- Dock switching, TDP, the suspend broker, and the greeter keyboard.
- Setting `Relogin=false` on a normal Switch to Desktop.
