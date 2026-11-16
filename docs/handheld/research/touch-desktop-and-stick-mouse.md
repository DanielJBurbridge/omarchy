# Undocked touch desktop, and sticks as a mouse

Researched 16 Nov 2026. Read against [`feat/ally-parity-integration-20261111`](https://github.com/DanielJBurbridge/omarchy/tree/feat/ally-parity-integration-20261111). Research only. The status table that points here is [feature-parity-audit.md](feature-parity-audit.md). Login, the greeter grid, and controller-as-mouse before Steam is up are already in [touch-first-boot.md](touch-first-boot.md). Button codes are in [buttons-and-input.md](buttons-and-input.md).

The RC71L is landscape. This note is the Hyprland desktop you get when gaming is not running: Switch to Desktop, a failed gamescope start, or a dock that never grew a session switch. Bazzite, CachyOS Handheld and SteamOS leave that problem to KDE or GNOME. They do not ship a touch Hyprland.

**Unverified** means it was not read from a primary page, or not tried on this Ally. Nothing here was run on an RC71L.

Omarchy is MIT ([LICENSE](../../../LICENSE)). GPL code is a separate package. A repository with no licence is ideas only.

## (a) A touch desktop on the Ally alone

What a person needs, in order: see the controls, type, move windows, change workspace, and rotate only if the device is actually rotated. The panel stays landscape in the gaming session. Rotation is last.

### What this branch has

- Optional desktop keyboard. [`bin/omarchy-setup-rog-ally-keyboard`](../../../bin/omarchy-setup-rog-ally-keyboard) installs reviewed AUR `wvkbd` 0.21 and adds a bar button. [`bin/omarchy-toggle-desktop-keyboard`](../../../bin/omarchy-toggle-desktop-keyboard) shows it. The bind after setup is `Super+Ctrl+Y`.
- The menu is the shell. [`bin/omarchy-menu`](../../../bin/omarchy-menu) summons `omarchy.menu`. Walker and fuzzel are not in this tree. Spec 02 still says the picker uses "walker/shell styling". There is no handheld minimum size in `shell/plugins/menu/`.
- Scale is per monitor, `auto` until the display panel saves one ([`default/hypr/monitors.lua`](../../../default/hypr/monitors.lua), [`default/hypr/monitor-settings.lua`](../../../default/hypr/monitor-settings.lua)). No RC71L default of 1.5.
- `fcitx5` is a base package and holds Hyprland's one input-method slot. `wvkbd --auto` does not get that slot, and v0.21's fallback is empty. That is already written up in [touch-first-boot.md](touch-first-boot.md) and [07](../07-on-screen-keyboard.md).
- Brightness, audio, Bluetooth, network and battery are shell panels. They are usable with a finger if the rows are large enough to hit. They do not run in the gamescope session.

### Gestures

[hyprgrass](https://github.com/horriblename/hyprgrass) is the touch plugin people point at. GitHub's licence field is `BSD-3-Clause`. The LICENSE file is the BSD 3-Clause text, copyright Ching Pei Yang 2023, and the README says some parts follow AOSP (Apache-2.0) and the examples follow Waybar (MIT). That split is already in [touch-first-boot.md](touch-first-boot.md). AUR `hyprgrass-git` lists the licence as `BSD`, which is not an SPDX id.

Shipped gestures: workspace swipe, edge swipe, multi-finger swipe, and a custom command. The README still says a bad load can leave the touch device dead until the plugin is unloaded, and to keep a keyboard handy the first time. Last push seen on 16 Nov 2026 was 15 Nov 2026. There is no Arch extra package. Install is `hyprpm add` against the git URL, which means a Hyprland update needs a rebuild.

[omarchy-tablet](https://github.com/yeutterg/omarchy-tablet) is the closest "Omarchy as a tablet" repo found. There is no LICENSE file. GitHub reports no licence. Ideas only. Do not copy `install.sh` or the Lua. What it describes, as ideas:

- Long-press a border to resize. Two-finger long-press to move. It attributes that to hyprgrass.
- A bar that does not jump to another edge while detached.
- A tray that opens on tap without launching the app underneath.
- An on-screen keyboard that shows on text fields while detached.
- Rotation from a display plugin, with touch following the transform.
- A lock-screen PIN pad.

The sibling [omarchy-touchscreen](https://github.com/yeutterg/omarchy-touchscreen) does have a licence. GitHub reports `MIT`. It is the narrower base: map touch and pen to the internal panel, and give selected apps native touch. This note did not re-read its file list. Depending on it is a separate decision. The MIT grant can travel into this tree if the copyright and permission notice travel with the files. Read the files first. Do not vendor them on the strength of the GitHub badge alone.

[omarchy-osk](https://github.com/ekollof/omarchy-osk) is a Hyprland plugin plus a Quickshell keyboard. The LICENSE file fetched on 16 Nov 2026 is the MIT text, copyright (c) 2026 ekollof. GitHub's detected SPDX id is `NOASSERTION`. Trust the file. The README says it vendors hyprgrass for the edge swipe (`vendor/hyprgrass-0.57/`). That vendor is BSD-3-Clause and stays under its own notice. The plugin eats touch and re-emits a pointer: one finger moves, a tap clicks, a hold of about 450 ms is a right click, two fingers scroll with a fling, a pinch is zoom. Three fingers are left for hyprgrass. Summon is a bottom-edge swipe, `Super+Shift+K`, or a bar applet. It says Omarchy does not install `iio-sensor-proxy` by default, and that touch mapping goes wrong if the output rotates and the touch device does not.

A discussion on the upstream Omarchy repo says Walker's normal launcher accepts touch and the old dmenu mode does not ([discussion 1659](https://github.com/omacom/omarchy/discussions/1659)). The same thread says hyprgrass was incompatible with Hyprland 0.56 for that person. This branch's menu is the shell plugin, so the Walker sentence does not describe the launcher we ship. It is a warning that a dmenu-style picker fails on a finger.

`iio-hyprland` listens to `iio-sensor-proxy` and sets the output transform and the touch transform. Its LICENSE file is the GPL-3 text ([touch-first-boot.md](touch-first-boot.md)). Leave it out of this tree. The Ally is used landscape. Whether the accelerometer is worth a daemon is unverified.

### OSK, scale, rotation: what to do

1. Keep summon-by-button. `Super+Ctrl+Y` and the bar button already exist once `wvkbd` is installed. Auto-show waits on a design that does not need Hyprland's single IME slot. Do not drop fcitx5 to free the slot.
2. A bottom-edge swipe that runs `omarchy-toggle-desktop-keyboard` is the hyprgrass piece worth wiring first. One gesture, one command.
3. Default the internal panel to scale 1.5 on an RC71L, and leave other machines on `auto`. Spec 06 already asks for this. It is a one-line default, gated on `omarchy-hw-rog-ally`.
4. Grow the shell menu rows and the bar hit targets. That is core shell work and helps any touchscreen Omarchy machine. Walker font sizes are the wrong lever on this branch.
5. Leave rotation off until someone measures the sensor. A GPL rotator is a separate package if it is ever wanted.
6. Window move and resize by long-press is a hyprgrass bind. Ship it as an opt-in extra, with the keyboard warning from the hyprgrass README.

### Idea list

- Edge swipe up: desktop keyboard. Edge swipe down: the system menu.
- Three-finger horizontal swipe: next and previous workspace.
- Two-finger tap: right click, if we take the omarchy-osk idea and reimplement it. Their MIT code can be adapted if the notice travels. The vendored hyprgrass cannot be dropped into the MIT tree without the BSD notice and a decision to carry a plugin.
- A "touch targets" toggle that raises menu row height, bar height and cursor size together. One setting, RC71L default on, other machines default off.
- Text scale 1.5 as the Ally desktop default, overridable in the existing monitor panel.
- No autorotation in the first cut.
- The lock screen stays a keypad drawn by the lock (K07). wvkbd above the lock is the approach spec 07 already refuses.

## (b) Sticks as a mouse in desktop mode

Three mechanisms show up. They must not run together. InputPlumber and HHD grab the same evdev nodes ([buttons-and-input.md](buttons-and-input.md)). Steam's desktop layout only exists while Steam is running, and it fights a virtual pointer from InputPlumber if both translate the sticks ([parity-matrix.md](parity-matrix.md)).

### What Bazzite documents now

The handheld wiki, fetched 16 Nov 2026, says two things ([Handheld wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/)):

- A desktop controller layout may be missing if Steam did not set the handheld up. Fix it in Steam's controller settings.
- The virtual keyboard in desktop mode is Steam's on-screen keyboard. There is no default binding. The user adds one in that Desktop Layout.

Deck 44's input stack is InputPlumber, not HHD ([same wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/), and the January 2026 announcement cited in [buttons-and-input.md](buttons-and-input.md)). InputPlumber's Ally composite device lists target devices `xbox-elite`, `mouse` and `keyboard` ([50-rog_ally.yaml](https://github.com/ShadowBlip/InputPlumber/blob/main/rootfs/usr/share/inputplumber/devices/50-rog_ally.yaml)). A target named `mouse` does not move the cursor by itself. A profile has to map an axis to mouse motion. The docs say a profile translates one event into another, then the event is routed to a target that supports it ([InputPlumber site](https://shadowblip.github.io/InputPlumber/)).

The Ally page on the same wiki still says holding Armoury Crate switches to mouse mode, and the page says the wiki may be outdated ([ASUS page](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/ASUS_ROG_Ally/)). That sentence matches HHD, not the InputPlumber map. HHD's hold (0.4 s) sends the MCU a mouse-mode command ([buttons-and-input.md](buttons-and-input.md)). Treat it as legacy.

### InputPlumber profiles and target modes

Stock profiles in the package, listed 16 Nov 2026:

| File | What it does |
|---|---|
| [default.yaml](https://github.com/ShadowBlip/InputPlumber/blob/main/rootfs/usr/share/inputplumber/profiles/default.yaml) | Remaps a few extra buttons (paddles, keyboard chord, QuickAccess2 to Screenshot, dials to volume and brightness). No stick-to-mouse map |
| [mouse_keyboard_wasd.yaml](https://github.com/ShadowBlip/InputPlumber/blob/main/rootfs/usr/share/inputplumber/profiles/mouse_keyboard_wasd.yaml) | Right stick → mouse motion at `speed_pps: 800`. Right trigger → left click. Left trigger → right click. Bumpers → wheel. Left stick → WASD, deadzone 0.3. D-pad → arrow keys. Start → Esc. Select → Tab. Guide and QuickAccess go to D-Bus (`ui_guide`, `ui_quick`) |

So the shipped "mouse" profile is a hybrid desktop mode, not a pure pointer. Left stick types WASD. That is useful in a terminal and surprising in a file manager.

Profiles load at runtime with D-Bus `LoadProfilePath` ([buttons-and-input.md](buttons-and-input.md)). This branch already calls that method from [`bin/omarchy-gaming-input-profile`](../../../bin/omarchy-gaming-input-profile), pointed at a `gaming.yaml` that is not in the tree. The same call, with a different file, is the desktop switch. The bridge that would load it on Hyprland start is also not in the tree. The session calls `omarchy-hw-rog-ally-input gamepad` only when that package is installed ([`bin/omarchy-session-start`](../../../bin/omarchy-session-start)).

Target mode is the other half. `xbox-elite` gives Steam a pad with paddles and a Guide+South QAM chord. A DualSense Edge or `deck-uhid` target is what Bazzite recommends when gyro or a native QAM button matters ([wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/)). Desktop mode wants the `mouse` and `keyboard` targets and a profile that uses them. Leaving `xbox-elite` active at the same time means a stick can be a pointer and a gamepad axis together. Pick one mode per session. Gaming: gamepad target, no mouse profile. Desktop: mouse profile, and do not also run Steam's desktop layout on the same sticks.

Touchpad-to-mouse is a different translation. It was unimplemented in 0.78 and closed in 0.80.0 ([issue 692](https://github.com/ShadowBlip/InputPlumber/issues/692)). The Ally has no trackpad. Ignore that issue for RC71L. It matters the day a Steam Deck image is in scope. Arch `extra/inputplumber` was 0.84.0 when [buttons-and-input.md](buttons-and-input.md) was written, which is newer than 0.80.0. This note did not re-query the Arch page.

Licence: GitHub reports `GPL-3.0` for InputPlumber. The README says "GNU GPLv3+". Arch's package field has been recorded as `GPL-3.0-only` ([touch-first-boot.md](touch-first-boot.md)). Depend on the package. Do not copy `mouse_keyboard_wasd.yaml` into this MIT tree. A short profile we write against the published schema is our config. Keep it in the handheld package, next to a pointer at the upstream example, so a later edit does not become a silent paste.

### Steam Input's desktop config

Steam's Desktop Layout is a client feature. It applies while Steam is running. It does not exist at the greeter. A factory Deck config binds X alone to `SHOW_KEYBOARD` ([steam-for-linux #13794](https://github.com/ValveSoftware/steam-for-linux/issues/13794), cited in [touch-first-boot.md](touch-first-boot.md)). Bazzite's instruction is to open controller settings and add the OSK binding if the layout is empty.

On this branch, desktop mode should not depend on that layout. Steam may be closed. The Hyprland session is the one that has to move a pointer. Use InputPlumber's profile for that, and tell Steam not to load a desktop layout while the profile is active. The matrix already says the two fight.

HHD's firmware mouse mode is the third path. It does not need `hid-asus-ally`. It is LGPL-2.1. Upstream discourages the AUR build. Do not copy the MCU bytes. Do not run it beside InputPlumber.

### What we would reuse

1. Arch `extra/inputplumber`. One daemon. D-Bus `LoadProfilePath`, which this tree already speaks.
2. A new `desktop.yaml` we write: right stick pointer, right trigger click, left trigger right-click, bumpers scroll. Left stick as a slow pointer too, or as arrow keys, not as WASD, unless a terminal focus is detected. Detecting focus is extra and can wait.
3. Load that profile when Hyprland starts. Load the gaming profile when `omarchy-gaming-session.target` starts. The gaming unit is already `Wants=omarchy-gaming-input-profile.service`.
4. Leave Steam's Desktop Layout unset, and say so in the handheld manual, so the two do not both move the cursor.
5. Command Centre hold still summons `wvkbd` on the desktop. That chord is the `Keyboard` capability in InputPlumber's Ally map, delivered as a key the desktop bind already owns. The exact key this unit emits is still the press test.

## Port candidates

| Candidate | What we would take | Licence | Reuse |
|---|---|---|---|
| InputPlumber the package | The daemon, the Ally composite device, `LoadProfilePath` | `GPL-3.0` (GitHub). README says GPLv3+. Arch field recorded as `GPL-3.0-only` | Separate package we already can depend on. Do not copy sources or the stock YAML |
| Our own desktop profile | Stick → pointer, triggers → click, bumpers → scroll | MIT, written here | Opt-in handheld package. Describe the upstream example. Do not paste it |
| hyprgrass | Workspace swipe, edge swipe for the keyboard | `BSD-3-Clause`, plus AOSP Apache-2.0 in some parts and MIT examples ([README](https://github.com/horriblename/hyprgrass), [touch-first-boot.md](touch-first-boot.md)) | Opt-in plugin. BSD notice travels. Rebuild on Hyprland updates. First load with a keyboard nearby |
| omarchy-touchscreen | Touch mapped to the internal panel | GitHub `MIT`. Files not re-read | Read the LICENSE file before copying. Badge alone is not the grant |
| omarchy-osk | Pointer emulation and a shell keyboard that does not need the IME slot | LICENSE file is MIT, copyright 2026 ekollof. Vendored hyprgrass is BSD-3-Clause | MIT files can move if the notice travels. Keep the vendor under its own licence, or depend on hyprgrass instead of the vendor tree |
| wvkbd | The keyboard we already toggle | `GPL-3.0-only` as treated in [touch-first-boot.md](touch-first-boot.md) | Separate AUR package. Already the path in `omarchy-setup-rog-ally-keyboard` |
| squeekboard | Auto-show when a client asks for an input method | `GPL-3.0-or-later`, Arch extra ([touch-first-boot.md](touch-first-boot.md)) | Separate package. Same IME slot as fcitx5, so it is the wrong default here |
| iio-hyprland | Rotation | GPL-3 text in the repo ([touch-first-boot.md](touch-first-boot.md)) | Separate package only, and only after the sensor is worth it |
| HHD mouse mode and MCU bytes | Firmware mouse mode without `hid-asus-ally` | `LGPL-2.1` (GitHub) | Do not copy. Do not run beside InputPlumber |
| omarchy-tablet | Touch window move, PIN pad, tray behaviour | No licence file | Ideas only |
| Steam Desktop Layout | OSK binding while Steam is open | Proprietary client | Use only if the user turns it on. Default off while our profile is loaded |
| CachyOS session-select and autologin writer | Not a touch feature. Listed so it is not dragged in by accident | No LICENSE file on the branch | Do not copy. Already rejected in [distros.md](distros.md) |

## Suggested order

1. Fix autologin `User=` and the greeter submit. A touch desktop does not matter if the machine cannot get there. Those are gaps 1 and 2 in the audit.
2. Depend on InputPlumber. Write `desktop.yaml` and `gaming.yaml`. Load the desktop one from the Hyprland session and the gaming one from the target that already wants the profile unit.
3. Confirm `Super+Ctrl+Y` and Command Centre hold both show `wvkbd`, and that Steam's desktop layout is off.
4. Scale 1.5 on the internal panel, and taller menu rows.
5. hyprgrass as an opt-in extra: keyboard swipe, then workspace swipe. Window move after that.
6. Rotation and a lock PIN stay where they are: unverified sensor, and K07.
