# Gaming and Desktop on the original ROG Ally

The optional `omarchy-gaming-session` package provides a managed Steam and Hyprland login on the RC71L. Install and rollback instructions are in the [alpha runbook](ALPHA.md). The [feature-parity checklist](feature-parity.md) records the exact builds and physical results.

## Desktop to Gaming

Save desktop work and exit the desktop Steam client. Tap **Armoury Crate** to open the Omarchy menu, then use the right stick and RT to choose **System → Switch to Gaming**. With a keyboard, press **Super + Ctrl + G**.

The RC71L hardware check and gaming package gate both the menu row and the shortcut. The launcher checks for a managed Desktop session, Steam and Gamescope before submitting the switch. A running desktop Steam client leaves the desktop open. A transient user job records the requested mode and asks UWSM to log out. The supervisor starts Gaming after the desktop exits.

## Gaming to Desktop

Save and quit the game. Choose **Steam → Power → Switch to Desktop**. The Steam menu calls `steamos-session-select plasma` inside Gamescope. The supervisor asks Steam to exit on its own display, stops the Gamescope scope, then applies the desktop sign-in policy.

| Desktop sign-in policy | What happens on return |
|---|---|
| Passwordless | Hyprland starts in the managed login. The supervisor records a one-use Desktop choice before teardown. Once the new Hyprland socket appears it clears that choice. An interruption before the socket appears leaves one Desktop login available through SDDM relogin. |
| Sign-in required | The supervisor prepares SDDM with relogin disabled, requests the greeter pointer profile and ends the Gaming session. Signing in starts the managed desktop and its controller observer. The next return from Gaming requires a fresh sign-in. |

Steam can be usable even when its initial readiness probe times out. As long as Steam and Gamescope are still running, a later **Switch to Desktop** follows the same shutdown and sign-in path. A failed start has its own retry and recovery handling. Only an explicit passwordless return writes the one-use Desktop choice.

## Acceptance

1. On a managed RC71L with the companion installed, open Gaming from the desktop with the built-in controls. Confirm the right stick moves the pointer and RT selects the menu entry before the switch. On another model, or without the companion, the menu entry and shortcut should be absent.
2. Leave desktop Steam running and try the same action. The desktop should stay open. Exit Steam, repeat, and confirm the Steam library becomes interactive.
3. Exercise both return policies. For a passwordless return, use the pointer and RT on the desktop. For a required sign-in, enter the password at SDDM by touch, then try the pointer and RT. Confirm that an ordinary later login follows the configured policy.
4. For a post-game return, record the selection, Steam exit, Gamescope scope stop, first visible desktop or greeter, and first working input. Record the power source and whether the game had resumed from sleep.
5. In the supervisor fixtures, delay the explicit switch beyond the readiness window. Verify one graceful Steam exit, the intended destination and no retry or recovery latch. Exercise an interrupted passwordless handoff and a fast Hyprland start separately.

The [Steam readiness](../../test/shell.d/gaming-steam-ready-test.sh), [sign-in and recovery](../../test/shell.d/gaming-relogin-fallback-test.sh), [scope shutdown](../../test/shell.d/gaming-session-target-test.sh) and [session lifecycle](../../test/helpers/gaming-session.py) fixtures cover these branches.
