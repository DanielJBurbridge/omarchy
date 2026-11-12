# Gamescope external overlay: does it draw above a fullscreen game without a focus change?

Researched 12 Nov 2026 (AWST). Primary source is Gamescope tag [`3.17.0`](https://github.com/ValveSoftware/gamescope/releases/tag/3.17.0) (`e6674a98118ca7b098b98a3874b8f195ae1bf750`, 23 Oct 2026). Line links below are that tag. **Unverified** means it was not confirmed from a primary source, or not exercised on the RC71L. No hardware session was run for this note.

Spec 04 (quick-access overlay) is still TODO in [`docs/handheld/README.md`](../README.md). Spec 01 already says the gaming overlay, when it exists, uses InputPlumber `intercept all` while open ([`01-controller-button-map.md`](../01-controller-button-map.md), rule C8).

## Answer

**Conditional yes for drawing. No for giving that window keyboard, pointer or touch.**

A client that sets the X11 atom `GAMESCOPE_EXTERNAL_OVERLAY` to a non-zero value is composited above the focused game and below the Steam overlay. Gamescope's focus picker skips that window, so it does not call `XSetInputFocus` on it and does not move the Wayland pointer or keyboard onto it. The game stays the focused app. That is a view-only overlay.

It does not, by itself, give the overlay a way to take controller, pointer or keyboard input without a focus change. An interactive quick-access panel has to take input on another path. The one that matches spec 01 is InputPlumber intercept, not a second Gamescope focus target.

Conditions, all from the 3.17.0 picker and paint path:

- The window is an X11 window on Gamescope's root Xwayland (the `DISPLAY` it exports, server 0). A window on a later Xwayland, the one a game uses when `--xwayland-count` is greater than 1, is not the window the compositor paints as the external overlay.
- `_NET_WM_WINDOW_OPACITY` is non-zero. Zero is not painted.
- Nothing else already holds the single external-overlay slot. A visible mangoapp does. Gamescope paints one external overlay, not a stack.
- The panel is drawn inside an output-sized transparent window. Gamescope maps that layer onto the whole output. A small X window is stretched to the output, and moving it does not move the layer. That is open issue [#2537](https://github.com/ValveSoftware/gamescope/issues/2537), reported on 3.17.0.
- `GAMESCOPE_NO_FOCUS` is not part of this. Mangoapp sets it. Gamescope 3.17.0 never reads it.

Setting `STEAM_OVERLAY` plus `STEAM_INPUT_FOCUS` is a different mechanism. That one does move focus. It is how Steam's own overlay, including the quick-access menu, takes the pointer and keyboard.

This was not tried on an RC71L gamescope session. The DRM-session behaviour, and whether a nested Wayland session delivers X events the picker did not ask for, is **unverified** on hardware. [#2537](https://github.com/ValveSoftware/gamescope/issues/2537) reports a nested 3.17.0 session where the overlay "doesn't let through user input". The sentence is ambiguous (blocked clicks versus a window that cannot be clicked). There is no maintainer reply. Treat the source as the contract and that report as an open contradiction to test.

## Compositing order

Planes, low to high ([`steamcompmgr.hpp`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.hpp)):

| zpos | Constant | What it is |
|---|---|---|
| 0 | `g_zposBase` | Focused window (Steam UI or the game) |
| 1 | `g_zposOverride` | Override-redirect window, painted relative to the focus window |
| 2 | `g_zposExternalOverlay` | External overlay |
| 3 | `g_zposOverlay` | Steam overlay, and the streaming client |
| 4 | `g_zposCursor` | Cursor |
| 5 | `g_zposMuraCorrection` | Mura correction |

`paint_window` assigns those z positions ([`steamcompmgr.cpp` `paint_window`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L2720)). `paint_all` draws the focused window first, then overrides and decorations, then the external overlay, then the Steam overlay, and reserves a layer for each so a pile of helper windows cannot push the overlay or the cursor out ([same file, `paint_all`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L3272)). The external overlay is painted only when `cv_paint_external_overlay_plane` is true (the default) and its opacity is non-zero ([`paint_all`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L3313)).

`NoScale` forces the layer's source size to the current output, so the buffer is placed on the full output rather than scaled like a game window ([`paint_window`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L2603)). Overlay opacity is the window's `_NET_WM_WINDOW_OPACITY` divided by fully opaque ([`paint_window`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L2707)). A screenshot requested as base-plane only drops every layer at `g_zposExternalOverlay` and above ([`steamcompmgr.cpp`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L3583)).

The extra layer means the frame is no longer a single scanout plane. The DRM backend composites, or uses another hardware plane, when more than one layer is present ([`DRMBackend.cpp`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/Backends/DRMBackend.cpp)). Whether the Ally's panel takes the composited path or a second plane was not measured. **Unverified** on device.

## How the window is found

The atom name is `GAMESCOPE_EXTERNAL_OVERLAY` ([`steamcompmgr.cpp`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L1543)). On map, and again on a property change, Gamescope reads it as a cardinal. A non-zero value sets `isExternalOverlay`. It then forces the window's app id to 0, so focus logic does not treat the overlay as a game ([`map_win`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L5855), [property handler](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L7074)). The comment on the app-id clear says this is what made mangoapp work when nested and not on SteamOS.

A related atom, `GAMESCOPE_MANGOAPP_MSG_TYPE`, tags a per-connector mangoapp. Untagged windows (type 0) compete in one slot: the highest `_NET_WM_WINDOW_OPACITY` wins. On a full focus pass the comparison is strict `>`, so the first window at that opacity stays selected ([`DetermineAndApplyFocus`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L4654)). On an opacity change the comparison is `>=`, so a later window at the same opacity can replace it ([property handler](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L6942)). A value of 0 is not greater than the starting maximum, so a fully transparent window is not chosen on the full pass. Setting the atom to 0 clears `isExternalOverlay` even if the property still exists (`bHasExternalOverlayProp` stays true). Mangoapp uses that to hide ([MangoHud `v0.8.4` `src/app/main.cpp`](https://github.com/flightlessmango/MangoHud/blob/v0.8.4/src/app/main.cpp#L426)).

The global paint focus does not search every Xwayland. It prefers a tagged mangoapp on the root server whose message type matches the virtual connector, otherwise the root server's untagged pick, otherwise a Wayland external overlay ([`determine_and_apply_focus`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L5222)). The root server is Xwayland 0, which is the `DISPLAY` Gamescope exports ([`main.cpp`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/main.cpp#L1069)).

`--xwayland-count N` creates N Xwaylands. When `N > 1` and Steam integration (`-e` / `--steam`) is on, Gamescope sets `STEAM_MULTIPLE_XWAYLANDS=1` and exports `STEAM_GAME_DISPLAY_*` for the extra servers ([`main.cpp`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/main.cpp#L614)). Games go there. The external overlay still has to be on server 0 to be the one `paint_all` draws. That is why mangoapp, started by Gamescope or by the session after `DISPLAY` is known, shows over a game that is on another X server: the compositor adds the layer after it has chosen the game as the base plane. It is not a child of the game's window.

Wayland is a second, narrower door. A `zwlr_layer_shell_v1` surface is marked `isExternalOverlay = true` with no atom ([`wlserver.cpp`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/wlserver.cpp#L2168)). A normal xdg-shell toplevel is not. It is an ordinary window and can become the focus window. `WAYLAND_DISPLAY` is exported only with `--expose-wayland`. `GAMESCOPE_WAYLAND_DISPLAY` is always set, and without `--expose-wayland` the session type is `x11` ([`main.cpp`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/main.cpp#L1072)). No handheld session below passes `--expose-wayland`. There is no shipped interactive layer-shell overlay to copy. Whether a layer-shell surface can still receive `wl_keyboard` through wlroots, despite the focus picker skipping it, is **unverified**. The X11 atom is the path mangoapp and the session scripts actually use.

## Focus and input

Focus candidates skip system-tray icons, `STEAM_OVERLAY` windows and external overlays, on both Xwayland and xdg ([`GetPossibleFocusWindows`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L4574), [xdg equivalent](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L5004)). The external overlay therefore cannot become `focusWindow`.

Input focus is chosen later, and only from the Steam overlay. On a single output, if the Steam overlay window has a non-zero `STEAM_INPUT_FOCUS` (`inputFocusMode`), that window becomes both the pointer target and the keyboard target. Otherwise both stay on the focused game, or on its override-redirect popup for the keyboard ([`determine_and_apply_focus`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L5259)). The same rule inside one Xwayland sets `XSetInputFocus` on that keyboard window ([`DetermineAndApplyFocus`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L4808)). Gamescope then calls `wlserver_keyboardfocus` and `wlserver_mousefocus` on those surfaces ([same function](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L5341)).

`inputFocusMode == 2` is the exception inside that Steam path: the pointer stays with the overlay and the keyboard is put back on the game ([`DetermineAndApplyFocus`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L4724), [global](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L5327)). Nothing in the external-overlay path sets `inputFocusMode`. The paint code updates touch scaling for the external overlay only when that window is already `inputFocusWindow` ([`paint_all`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L3320)). The picker never makes it so. Touch stays mapped to the game, or to the Steam overlay when that overlay has asked for focus.

`GAMESCOPE_FOCUSED_APP` is published from the input-focus window's app id, and `GAMESCOPE_FOCUSED_WINDOW` from the focus window ([`determine_and_apply_focus`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L5466)). An external overlay has app id 0 and is not the focus window, so those properties stay on the game. Showing it does not look like an alt-tab to Steam.

Gamescope itself sets `SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0` so an SDL game does not minimise when focus does move ([`main.cpp`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/main.cpp#L667)). That guard matters for the Steam overlay, which does move focus. It is not what keeps the external overlay from moving focus. The external overlay never asks for the move.

Gamepad buttons are not in this path. Gamescope does not route the Ally's gamepad. InputPlumber does. See below.

## Steam overlay and the QAM

`STEAM_OVERLAY` is a different atom ([`steamcompmgr.cpp`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L1542)). The window Gamescope treats as the interactive overlay is the one that is at least as wide as the root window, or that has `STEAM_INPUT_FOCUS` set, and that has the highest opacity. The comment names it "Steam/QAM". A `STEAM_OVERLAY` window that is narrower and does not request input is a notification instead ([`DetermineAndApplyFocus`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L4640)).

So the Steam client is the overlay window. The quick-access menu is that window made visible and given `STEAM_INPUT_FOCUS`, not a second process. It paints at zpos 3, above any external overlay. If both are visible, the QAM covers ours. Steam integration also drops the Steam overlay on a virtual connector that is not the Steam connector ([`determine_and_apply_focus`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L5251)). A normal handheld session is a single output, so the overlay is used.

Opening the QAM is a real focus change: pointer and keyboard move to Steam's window, and `GAMESCOPE_FOCUSED_APP` follows the overlay's app id. `inputFocusMode == 2` would leave the keyboard on the game. Steam's own value was not read out of the Steam binary. **Unverified** which mode the current Steam client writes. OpenGamepadUI writes `1`, which moves both ([below](#opengamepadui)).

## mangoapp

Mangoapp is MangoHud's standalone overlay. Gamescope's `--mangoapp` flag spawns it and tells Steam, via `STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND=1`, that Steam no longer has to set `GAMESCOPE_EXTERNAL_OVERLAY` for it ([`main.cpp`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/main.cpp#L222), [env](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/main.cpp#L626)). The spawn strips the Steam overlay preload so Steam does not hook mangoapp's swapchain as if it were the game ([`steamcompmgr.cpp`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L9652)).

MangoHud `v0.8.4` (`992103e4`) creates a transparent GLFW X11 window, sets `GAMESCOPE_EXTERNAL_OVERLAY` to 1, and sets `GAMESCOPE_NO_FOCUS` to 1 ([`src/app/main.cpp`](https://github.com/flightlessmango/MangoHud/blob/v0.8.4/src/app/main.cpp#L246)). When `no_display` is set it hides the window and writes the overlay atom as 0. When shown again it writes 1. It resizes itself to the output size Gamescope sends over the sysv message queue, and the comment says shrinking the height breaks direct scanout. It has keybinds, but those are mangoapp's own X key handling. Gamescope does not hand it the seat. A grep of Gamescope 3.17.0 finds no `GAMESCOPE_NO_FOCUS` string. The atom is a MangoHud write with no reader in this tag. Focus stays off mangoapp because of `isExternalOverlay` and the app-id clear, not because of that atom. MangoHud [#1283](https://github.com/flightlessmango/MangoHud/issues/1283) asked for Gamescope to implement `GAMESCOPE_NO_FOCUS` after a black screen with `no_display`. The issue was closed in March 2025. The 3.17.0 tree still does not read the atom.

While VRR is active, a new commit on the external overlay does not by itself schedule a non-base repaint. The comment says mangoapp's repaints were pulling the panel between the game's refresh and the maximum and flickering ([`steamcompmgr.cpp`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L8037)). An opacity change on an external overlay still sets `hasRepaint` with no VRR check ([property handler](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L6923)). Showing and hiding by opacity should still present. Animating the overlay while VRR is on can wait for the next game frame. The Ally panel can do VRR. Chimera's RC71L quirks set adaptive sync. What that looks like on this panel is **unverified**.

Per-connector mangoapp is on by default when Gamescope itself launched mangoapp and the backend uses virtual connectors ([`cv_mangoapp_per_connector`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/src/steamcompmgr.cpp#L8192)). That instance is tagged and is preferred over an untagged overlay for its connector. A visible one occupies the only slot. Hide it (atom 0) before showing ours, or do not run it at the same time.

## Decky Loader

Decky does not open an overlay window. `v3.3.1` (`backend/decky_loader/injector.py`) talks to Steam's CEF remote debugger at `http://localhost:8080` and runs JavaScript with `Runtime.evaluate` in the Steam Gamepad / SharedJSContext tab ([`injector.py`](https://github.com/SteamDeckHomebrew/decky-loader/blob/v3.3.1/backend/decky_loader/injector.py#L12)). The frontend then inserts a Quick Access tab, `QuickAccessTab.Decky` ([`plugin-loader.tsx`](https://github.com/SteamDeckHomebrew/decky-loader/blob/v3.3.1/frontend/src/plugin-loader.tsx#L115)). The drawing is inside the Steam client, which is already the `STEAM_OVERLAY` window. Decky is visible when that UI is visible. It does not composite a second surface over a game while the QAM is closed, and it does not avoid the focus change Steam makes when the QAM opens. The repository `LICENSE` is the GNU GPL version 2 text (June 1991). `injector.py` has no SPDX header. Do not copy it into this tree.

## OpenGamepadUI

OpenGamepadUI `v0.47.0` has an overlay mode (`opengamepadui --overlay-mode`) used by Chimera's `steam-plus` session and by Bazzite's OGUI session. It does not use `GAMESCOPE_EXTERNAL_OVERLAY` for that mode. `card_ui_overlay_mode.gd` writes `STEAM_OVERLAY` and `STEAM_INPUT_FOCUS` on its own window and on the underlay (Steam or the game). When the menu is open it sets its window's input focus to 1, the underlay's to 0, and its overlay atom to 1, and it sets InputPlumber intercept to ALL. When it returns to the base state it does the reverse and sets intercept to PASS ([`card_ui_overlay_mode.gd`](https://github.com/ShadowBlip/OpenGamepadUI/blob/v0.47.0/core/ui/card_ui_overlay_mode/card_ui_overlay_mode.gd#L292)). `STEAM_INPUT_FOCUS=1` is not mode 2, so Gamescope moves both pointer and keyboard. That is a focus change, which is the thing spec 04 wants to avoid.

The same tree can set `GAMESCOPE_EXTERNAL_OVERLAY` through `gamescope-x11-client`'s `ExternalOverlay` atom ([`atoms.rs`](https://github.com/ShadowBlip/gamescope-x11-client/blob/main/src/atoms.rs#L25)), and the Godot binding exposes `set_external_overlay` ([`x11_client.rs`](https://github.com/ShadowBlip/OpenGamepadUI/blob/v0.47.0/extensions/core/src/gamescope/x11_client.rs#L971)). Overlay mode's card UI does not call it. The README says "GNU GPLv3+". `gamescope-x11-client`'s `LICENSE` is the GPL-3.0 text. Whether that crate's grant is "or later" is **unverified** (no README licence line was found). Do not copy either.

## InputPlumber

InputPlumber does not draw. Intercept mode is the input side of an overlay. `v0.84.0` `docs/usage.md` defines `InterceptMode` 0 NONE, 1 PASS (Guide only, then it switches to ALL), and 2 ALL. ALL stops the event from reaching the target device and emits it on D-Bus instead, so the game does not see the buttons while the overlay is up ([usage](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/docs/usage.md)). The README says "GNU GPLv3+". Call the D-Bus property. Do not copy the daemon. Spec 01 C8 already requires `intercept all` while the Omarchy overlay is open and `none` on close, crash and session exit.

## What the handheld distros ship

None of them ship a third-party `GAMESCOPE_EXTERNAL_OVERLAY` client as their quick-access UI. The in-game panel is Steam's QAM. mangoapp, when started, is the performance HUD on the external-overlay slot.

| Distro | Gamescope launch | Overlay they actually use |
|---|---|---|
| CachyOS Handheld | `gamescope --xwayland-count ${XWAYLAND_COUNT:-2} ... -e` ([`gamescope-session`](https://github.com/CachyOS/gamescope-session/blob/cachyos/usr/lib/steamos/gamescope-session#L245)). Sets `STEAM_MULTIPLE_XWAYLANDS=1`, `STEAM_USE_MANGOAPP=1` and `STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND=1`. A user unit runs `/usr/bin/mangoapp` with the session environment ([`gamescope-mangoapp.service`](https://github.com/CachyOS/gamescope-session/blob/cachyos/usr/lib/systemd/user/gamescope-mangoapp.service)). The branch has no LICENSE file. | Steam QAM. Decky is manual ([`parity-matrix.md`](parity-matrix.md)). |
| ChimeraOS | `gamescope-session-plus` builds the command with `--xwayland-count` defaulting to 2 and `--steam`, then starts `mangoapp` in a loop if the binary exists ([script](https://github.com/ChimeraOS/gamescope-session/blob/main/usr/share/gamescope-session-plus/gamescope-session-plus#L168)). The steam session file sets the same mangoapp workaround env ([`sessions.d/steam`](https://github.com/ChimeraOS/gamescope-session-steam/blob/main/usr/share/gamescope-session-plus/sessions.d/steam#L76)). MIT, from the repository LICENSE. RC71L quirks set `ADAPTIVE_SYNC=1` ([`distros.md`](distros.md)). | Steam QAM. `steam-plus` adds OpenGamepadUI overlay mode (Guide+B), which uses `STEAM_OVERLAY`, not the external-overlay atom. |
| Bazzite deck | Built on `gamescope-session-plus` ([install script](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite-deck/04-install-gamescope-session.sh), [existing note](distros.md)). That install script downloads the Steam bootstrap. It does not show the gamescope argv. The exact flags in the image are **unverified** against Chimera's current script. | Steam QAM, plus OGUI on Armoury hold ([`parity-matrix.md`](parity-matrix.md)). |
| SteamOS | The session script on `gitlab.steamos.cloud` redirected to a sign-in page, so Valve's copy was not read. The CachyOS script still branches on Jupiter and Galileo and carries Valve's gamescope-session comments, which is the readable relative. SteamOS's argv is **unverified** beyond that family: `--xwayland-count` 2, `-e`, mangoapp integration. | Steam QAM. |

## Limits

- One external overlay is painted. [#527](https://github.com/ValveSoftware/gamescope/issues/527) (open since 2022) discusses rendering more than one. 3.17.0 still picks one.
- The layer covers the output. Position and size inside the X window do not become a corner overlay. Draw the panel in a full-size transparent buffer. [#2537](https://github.com/ValveSoftware/gamescope/issues/2537) (open, 5 Nov 2026, gamescope 3.17.0, nested Wayland, NVIDIA). The reporter did not tick the DRM backend.
- A visible mangoapp, or any other untagged window with equal or higher opacity, takes the slot. Order on a tie depends on which pass runs.
- The Steam overlay paints above it. The QAM covers this panel while both are open.
- The window does not receive keyboard, pointer or touch through Gamescope's focus. Controller input needs InputPlumber intercept, or some other channel that is not this window.
- VRR suppresses repaints that come only from the external overlay's commits. Opacity changes still request a repaint. Behaviour on the Ally panel is **unverified**.
- X11, on server 0. A Wayland xdg client is a normal window and can take focus. Layer shell is classified as an external overlay, but the session does not export `WAYLAND_DISPLAY` unless `--expose-wayland` is passed, and no distro above uses it for this.
- [#288](https://github.com/ValveSoftware/gamescope/issues/288) is closed. The 2023 maintainer reply is the X11 window plus `GAMESCOPE_EXTERNAL_OVERLAY`. A 2025 comment says that did not work in Steam Deck Big Picture mode, with no later reply. Whether that still happens on 3.17.0 in a Deck session is **unverified**.
- Games that pause, grab the pointer, or sample focus themselves were not tested. The source does not move X focus or the focused-app property. That is not a measurement of every game. **Unverified** on a real title.
- This branch's gaming-session note says the Ally display helper adds `--prefer-output` only ([`docs/rog-ally-gaming-session.md`](../../rog-ally-gaming-session.md)). The gamescope argv in the session scripts is not in this tree. Whether the session we ship passes `--xwayland-count` and `-e` is **unverified** from this checkout.

## Recommendation

Build a small X11 client on Gamescope's root `DISPLAY`. While the panel is open, set `GAMESCOPE_EXTERNAL_OVERLAY` to 1 and `_NET_WM_WINDOW_OPACITY` to non-zero. While it is closed, set the overlay atom to 0, as mangoapp does. Do not set `STEAM_OVERLAY` or `STEAM_INPUT_FOCUS`. Do not set `GAMESCOPE_NO_FOCUS` and expect Gamescope to honour it. Draw into an output-sized buffer with a transparent clear, and put the panel in a corner of that buffer.

Take the pad with InputPlumber `InterceptMode` ALL for the time the panel is open, and restore NONE on close, crash and session exit. That is spec 01 C8. The game does not see those buttons, and Gamescope does not retarget the game's X focus or the focused-app property. Pointer and touch stay with the game, so the panel is a controller UI, not a mouse UI, unless a later test shows we must add a pointer path. If we need the pointer, that is the Steam-overlay path and it is a focus change. Do not mix the two atoms on the same window.

Hide mangoapp, or accept that a visible one wins the only slot. If the QAM is open it paints over us. That is acceptable: the QAM is Steam's surface, and spec 01 already uses it as the fallback until spec 04 exists.

Test on the DRM session, with a fullscreen game, with `--xwayland-count 2`, with VRR on and off, and with mangoapp installed. The nested Wayland report in [#2537](https://github.com/ValveSoftware/gamescope/issues/2537) is not that test.

### Alternatives

1. **`STEAM_OVERLAY` plus `STEAM_INPUT_FOCUS`.** This is OpenGamepadUI's overlay mode and Steam's QAM. It draws above the game and it takes pointer and keyboard focus (value 1). Value 2 would keep the keyboard on the game and still move the pointer. Gamescope's SDL minimise guard reduces one symptom. It does not meet "without taking focus away". Do not copy OpenGamepadUI.
2. **Inject into Steam's CEF, as Decky does.** No second window. The UI lives in the QAM, so it is only there when Steam has already opened that overlay and taken focus. It does not give a hardware-button panel that stays out of Steam's menu. GPL-2.0. Do not copy it.
3. **A layer-shell Wayland client.** Gamescope would classify it as an external overlay, so the focus skip should apply. It needs a Wayland socket the session does not export today, and there is no working handheld example. **Unverified** as an interactive surface.
4. **Desktop-only UI.** Hyprland can show a panel. It does not draw over a game inside the gamescope session. That misses spec 04.

## Licences

Omarchy is MIT. Nothing from the GPL projects below should be copied into this tree. Reimplement the behaviour, or vendor the files in a separate path with their own `LICENSE` and SPDX headers.

| Piece | Licence | Reuse |
|---|---|---|
| Gamescope 3.17.0 | BSD-2-Clause. `LICENSE` at the tag: Copyright (c) 2013-2022 Valve, Copyright (c) 2022 NVIDIA. Two conditions, plus the disclaimer ([`LICENSE`](https://github.com/ValveSoftware/gamescope/blob/3.17.0/LICENSE)) | Use the Arch package. Do not vendor the compositor into the MIT tree. The atom protocol is a behaviour to reimplement, not a file to copy. |
| MangoHud / mangoapp `v0.8.4` | MIT. Copyright (c) 2020 flightlessmango ([`LICENSE`](https://github.com/flightlessmango/MangoHud/blob/v0.8.4/LICENSE)) | Do not copy `main.cpp`. A few `XChangeProperty` calls written here are enough. If any of that file is reused, keep the copyright and the permission notice. |
| Decky Loader `v3.3.1` | The repository `LICENSE` is the GNU GPL version 2 (June 1991). No SPDX header in `injector.py` ([`LICENSE`](https://github.com/SteamDeckHomebrew/decky-loader/blob/v3.3.1/LICENSE)) | Do not copy. |
| OpenGamepadUI `v0.47.0` | README: "GNU GPLv3+". SPDX id GPL-3.0-or-later ([`README`](https://github.com/ShadowBlip/OpenGamepadUI/blob/v0.47.0/README.md)) | Do not copy. |
| `gamescope-x11-client` | `LICENSE` is the GPL-3.0 text. "Or later" is **unverified** ([`LICENSE`](https://github.com/ShadowBlip/gamescope-x11-client/blob/main/LICENSE)) | Do not copy. Write the two atoms directly. |
| InputPlumber `v0.84.0` | README: "GNU GPLv3+". SPDX id GPL-3.0-or-later ([`README`](https://github.com/ShadowBlip/InputPlumber/blob/v0.84.0/README.md)) | Depend on the package and call D-Bus. Do not copy the daemon. |
| ChimeraOS `gamescope-session` | MIT, confirmed in [`distros.md`](distros.md) from the repository LICENSE | The launch line is a fact to cite. Do not copy the script for this overlay. |
| CachyOS `gamescope-session` branch `cachyos` | No LICENSE file in the branch. The PKGBUILD MIT claim is not a confirmed upstream licence ([`distros.md`](distros.md)) | Cite the launch line. Do not copy the script. |
