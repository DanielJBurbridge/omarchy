# Touch-first boot on the ROG Ally RC71L

Researched 16 Nov 2026 (AWST). The goal is a power-on, login and network join on the original Ally with the touchscreen and the built-in controller only. This is a research note for the UX spec. It does not change code.

Omarchy is MIT ([LICENSE](https://github.com/DanielJBurbridge/omarchy/blob/feat/ally-parity-integration-20261111/LICENSE)). GPL and LGPL projects below are installed as their own packages. Their source stays out of this tree. SPDX ids are the ones printed by Arch or by the upstream licence file fetched for this note. A GitHub licence badge that is not an SPDX id is marked as such.

**Unverified** means no primary source was fetched for that claim, or the fetched page did not say it. Device behaviour on this Ally is unverified until the open-question list is tried on the hardware.

## 1. Hyprland on touch-only devices

Hyprland is in Arch extra (`hyprland` 0.57.2-1, SPDX `BSD-3-Clause`) ([package](https://archlinux.org/packages/extra/x86_64/hyprland/)). Its protocol directory ships `input-method-unstable-v2.xml` and `virtual-keyboard-unstable-v1.xml` ([protocols](https://github.com/hyprwm/Hyprland/tree/main/protocols)). `CInputMethodRelay::onNewIME` refuses a second input method: it logs `Cannot register 2 IMEs at once!` and calls `unavailable()` ([InputMethodRelay.cpp](https://github.com/hyprwm/Hyprland/blob/5e441cae/src/managers/input/InputMethodRelay.cpp)). Virtual keyboards are a separate path: `InputManager` listens for `newVirtualKeyboard` ([InputManager.cpp](https://github.com/hyprwm/Hyprland/blob/0b0d7ede/src/managers/input/InputManager.cpp)).

Touch gestures are the plugin [hyprgrass](https://github.com/horriblename/hyprgrass) (workspace swipe, edge swipe, multi-finger swipe, custom commands). Its LICENSE file is the BSD 3-Clause text, copyright Ching Pei Yang 2023 ([LICENSE](https://raw.githubusercontent.com/horriblename/hyprgrass/main/LICENSE)). The README also says some parts are based on AOSP (Apache-2.0) and the examples on Waybar (MIT). AUR `hyprgrass-git` lists the licence as `BSD`, which is not an SPDX id ([AUR](https://aur.archlinux.org/packages/hyprgrass-git)). The README warns that a bad load can leave the touch device unusable until the plugin is unloaded, and tells you to keep a keyboard handy the first time. There is no extra package; install is `hyprpm add` against the git URL. No report of Omarchy on an iPad was found. A 2-in-1 request on end-4/dots-hyprland points at hyprgrass for gestures and at `iio-hyprland` for rotation ([issue 1339](https://github.com/end-4/dots-hyprland/issues/1339)).

`iio-hyprland` listens to `iio-sensor-proxy` and sets the Hyprland output and touch transform ([README](https://github.com/JeanSchoeller/iio-hyprland/)). Its LICENSE file is the GPL-3 text ([LICENSE](https://raw.githubusercontent.com/JeanSchoeller/iio-hyprland/master/LICENSE)). No SPDX header was read, and no Arch extra package was confirmed, so this note does not name an SPDX id beyond "the shipped file is GPL-3". Leave it out of the MIT tree. Whether the RC71L accelerometer is worth rotating for is unverified; the panel is used landscape in the gaming session.

Hyprgrass's own list of keyboards is squeekboard (auto show/hide, poor with fcitx/ibus), wvkbd, and `fcitx-virtual-keyboard-adapter` as an addon that shows some other keyboard ([hyprgrass README](https://github.com/horriblename/hyprgrass)). A layer rule can put wvkbd above the lock: Hyprland issue 6195 records `layerrule = abovelock true, wvkbd`, and a later comment that the new syntax still left the keyboard under the lock for that user ([issue 6195](https://github.com/hyprwm/Hyprland/issues/6195)). That is not a tested Ally result.

## 2. How handheld distros avoid a keyboard at boot

They autologin into a gamescope session and let Steam draw the UI. The greeter is not the daily path.

| Distro | What boots | Source |
|---|---|---|
| Bazzite Deck | SDDM Wayland autologin, `Session=gamescope-session-ogui-steam.desktop`, `Relogin=true` | [holo.conf](https://github.com/ublue-os/bazzite/blob/main/system_files/deck/shared/usr/lib/sddm/sddm.conf.d/holo.conf) |
| Bazzite user | `bazzite-autologin` writes `/etc/sddm.conf.d/zz-holo-autologin.conf` for uid 1000 | [script](https://github.com/ublue-os/bazzite/blob/main/system_files/deck/shared/usr/libexec/bazzite-autologin) |
| CachyOS Handheld | Plasma Login autologin `User=deck`, `Session=gamescope-session.desktop`, `Relogin=true`, first boot only; a later file overrides it | [steam-deckify.conf](https://raw.githubusercontent.com/CachyOS/CachyOS-Handheld/main/etc/plasmalogin.conf.d/steam-deckify.conf) |
| CachyOS switch | `steamos-session-select oneshot` boots Gamescope every fresh boot; `plasma` is Steam's Switch to Desktop and uses `pkexec` | [script](https://raw.githubusercontent.com/CachyOS/gamescope-session/cachyos/usr/bin/steamos-session-select) |
| ChimeraOS | First boot shows setup screens, then a Steam login. Repeated gamescope or Steam init failure drops to the Gnome desktop | [Getting Started](https://github.com/ChimeraOS/chimeraos/wiki/Getting-Started) |
| SteamOS | Gaming Mode is the default. Desktop is a switch, and since 3.8 Steam asks steamos-manager which desktop sessions exist | [VideoCardz on 3.8](https://videocardz.com/newz/valve-releases-steamos-3-8-stable-with-steam-machine-support) |

Bazzite's repository licence is Apache-2.0 ([ublue-os/bazzite](https://github.com/ublue-os/bazzite)). ChimeraOS `gamescope-session` is MIT ([LICENSE](https://github.com/ChimeraOS/gamescope-session/blob/main/LICENSE)). The CachyOS `gamescope-session` branch `cachyos` still has no LICENSE file in the repository root; do not copy that script. Its `pkexec` rewrite of the autologin user conflicts with spec 02 §7.1, which writes the installer-created user once ([02](../02-mode-switch-and-dock.md)).

Gamescope's embedded touch flag is `--default-touch-mode 0: hover, 1: left, 2: right, 3: middle, 4: passthrough` ([main.cpp help](https://github.com/ValveSoftware/gamescope/blob/master/src/main.cpp)). ChimeraOS defaults `TOUCH_MODE` to 4 ([gamescope-session-plus](https://github.com/ChimeraOS/gamescope-session/blob/main/usr/share/gamescope-session-plus/gamescope-session-plus)). Arch `gamescope` 3.17.0-1 is `BSD-2-Clause`, `BSD-3-Clause`, `LicenseRef-Reshade` ([package](https://archlinux.org/packages/extra/x86_64/gamescope/)). Omarchy's Ally session already launches `gamescope --backend drm -e --xwayland-count 2 --default-touch-mode 4` ([bin/omarchy-session-start](https://github.com/DanielJBurbridge/omarchy/blob/feat/ally-parity-integration-20261111/bin/omarchy-session-start)). Mode 4 leaves touch to the client. Steam's own UI is that client in gaming mode.

A Bazzite discussion says the deck image autologins because typing a password with no keyboard is the hard case, and points at Steam's PIN for game mode rather than a boot password ([thread](https://www.answeroverflow.com/m/1334405906246537236)). That is a forum thread, not a Bazzite spec.

## 3. On-screen keyboards

### Greeter

Arch's SDDM page: install `qt6-virtualkeyboard` and set `[General] InputMethod=qtvirtualkeyboard`. SDDM then shows a button at the lower left. On a `kwin_wayland` greeter the same page says to pass `--inputmethod` on `CompositorCommand` and to leave `InputMethod` empty, or the keyboard disappears ([SDDM wiki](https://wiki.archlinux.org/title/SDDM), [sddm.conf(5)](https://man.archlinux.org/man/sddm.conf.5)). `sddm` 0.21.0-7 is `GPL-2.0-or-later` ([package](https://archlinux.org/packages/extra/x86_64/sddm/)). `qt6-virtualkeyboard` 6.12.0-1 is `GPL-3.0-only`, `LGPL-3.0-only`, `LicenseRef-Qt-Commercial`, `Qt-GPL-exception-1.0` ([package](https://archlinux.org/packages/extra/x86_64/qt6-virtualkeyboard/)). `plasma-keyboard` 6.8.3-1 is `GPL-2.0-or-later` and depends on `qt6-virtualkeyboard` ([package](https://archlinux.org/packages/extra/x86_64/plasma-keyboard/)). Both stay separate packages.

This branch's greeter is Hyprland, `CompositorCommand=start-hyprland -- --config /usr/share/sddm/hyprland.lua` ([10-wayland.conf](https://github.com/DanielJBurbridge/omarchy/blob/feat/ally-parity-integration-20261111/etc/sddm.conf.d/10-wayland.conf)). `Main.qml` does not import Qt Virtual Keyboard. A grid inserts `q`–`p`, `a`–`l`, `z`–`m` and `0`–`9` into the password field. The comment says the Qt style is not in this tree. Physical Return/Enter calls `sddm.login`. The grid has no Shift, Backspace, symbol or submit key ([Main.qml](https://github.com/DanielJBurbridge/omarchy/blob/feat/ally-parity-integration-20261111/default/sddm/omarchy/Main.qml)). [ALPHA.md](../ALPHA.md) says the greeter grid cannot submit by touch. Spec 07 already assigns the greeter keyboard to Qt Virtual Keyboard on the auth branches, and records that this integration tip does not have it ([07](../07-on-screen-keyboard.md)).

greetd 0.10.3-2 is `GPL-3.0-only` ([package](https://archlinux.org/packages/extra/x86_64/greetd/)). `greetd-regreet` is `GPL-3.0-or-later` ([package](https://archlinux.org/packages/extra/x86_64/greetd-regreet/)). Its feature list has no on-screen keyboard ([README](https://github.com/rharish101/ReGreet)). An AUR comment shows one person starting squeekboard under a Sway greeter and calling `sm.puri.OSK0.SetVisible` ([squeekboard-git comment](https://aur.archlinux.org/packages/squeekboard-git)). That is a user comment, not upstream regreet. `greetd-tuigreet` is `GPL-3.0-only` and is a console UI ([package](https://archlinux.org/packages/extra/x86_64/greetd-tuigreet/), [README](https://github.com/tuigreet/tuigreet)). No OSK is documented. Replacing SDDM is not the recommendation.

`maliit-keyboard` is AUR only, licence field `LGPL` (not an SPDX id), Qt5, and a comment says 2.3.1-3 is older than the build that used to be in the repos ([AUR](https://aur.archlinux.org/packages/maliit-keyboard)). No Hyprland test was found. Leave it.

### Hyprland desktop

`wvkbd` 0.21-1 is AUR. The licence field is `GPL3`, which is not SPDX. The v0.21 LICENSE file is the GPL-3 text, and the opening of `main.c` has no SPDX line ([AUR](https://aur.archlinux.org/packages/wvkbd), [LICENSE](https://raw.githubusercontent.com/jjsullivan5196/wvkbd/v0.21/LICENSE)). Treat it as `GPL-3.0-only` and do not copy it. Signals: `SIGUSR1` hide, `SIGUSR2` show, `SIGRTMIN` toggle. `--auto` needs `zwp_input_method_v2` ([README](https://github.com/jjsullivan5196/wvkbd/)). `im_unavailable` in v0.21 is an empty function ([main.c](https://github.com/jjsullivan5196/wvkbd/blob/v0.21/main.c)). With Fcitx5 already holding Hyprland's single input-method slot, `--auto` does not get the slot, and the empty handler does not fall back to a visible keyboard. Omarchy's base package list includes `fcitx5` ([omarchy-base.packages](https://github.com/DanielJBurbridge/omarchy/blob/feat/ally-parity-integration-20261111/install/omarchy-base.packages)). Spec 07 already chooses manual summon for that reason ([07](../07-on-screen-keyboard.md), [touch-keyboard note](../../rog-ally-touch-keyboard.md)).

`squeekboard` 1.43.1-6 is extra, `GPL-3.0-or-later` ([package](https://archlinux.org/packages/extra/x86_64/squeekboard/)). It wants `layer-shell` and `virtual-keyboard-v1`, recommends `input-method-v2`, and can be shown over D-Bus `sm.puri.OSK0.SetVisible` ([README](https://github.com/droidian/squeekboard)). It appears when a client asks for an input method. That is the same single slot Fcitx5 holds, so auto-show has the same conflict. It is the wrong default next to Fcitx5.

Steam's keyboard inside gamescope is drawn by Steam, not by gamescope. The gamescope maintainer: "Gamescope has nothing to do with the Steam keyboard -- that's provided entirely by Steam." ([gamescope #668](https://github.com/ValveSoftware/gamescope/issues/668)).

## 4. Login, autologin and the lock

Spec 02 §7.1: the handheld installer writes SDDM `[Autologin] User=<installer-created user> Session=omarchy-handheld.desktop Relogin=false` once. The handheld drop-in then sets `Relogin=true` so a finished session returns to gaming. Three failed gaming starts inside 60 seconds set `Relogin=false` and the greeter shows. Getty is not autologin. OQ-4 is resolved there: a desktop reached from that autologin goes through `desktop()` in `bin/omarchy-session-start`, and the lock runs only when `desktop-lock` is effectively `on` ([02 §7.1–§7.4](../02-mode-switch-and-dock.md)).

Until auth item K07 (a keyboard inside the trusted lock surface), the handheld variant ships `desktop-lock` `default-off`. With that value, Switch to Desktop, Exit Steam, the dock prompt and the gaming-failure fallback all show the Hyprland desktop with no lock. Spec 02 §7.5 states the trade-off in plain terms: anyone holding the Ally then has the desktop UI, autostart and the user's files. The gaming session is already the desktop user's UID, with Steam, games and anything that session starts. The lock, once on, protects the desktop UI only. It does not protect user files, Steam data or a shell started inside gamescope. A TTY still asks for a password. This gap is accepted because there is no lock-screen touch keyboard yet. It is not a user opt-out. After `/var/lib/omarchy/handheld/k07-landed` exists, a missing value fails closed to `on`.

`hyprlock` 0.9.7-2 is extra, `BSD-3-Clause` ([package](https://archlinux.org/packages/extra/x86_64/hyprlock/)). There is no PIN pad in the release. Issue 120 asks for a PIN widget so a tablet can unlock, and the replies point at PAM rather than a widget ([#120](https://github.com/hyprwm/hyprlock/issues/120)). Issue 1012 asks for auto-submit after N digits and is still an open enhancement ([#1012](https://github.com/hyprwm/hyprlock/issues/1012)). Putting wvkbd above the lock is the unfinished idea in Hyprland #6195, and spec 07 forbids wvkbd as the unlock path (K-R2). K07 is a keypad drawn by the lock itself. That matches §9.

## 5. Getting online when the bar has no network control

Omarchy enables `NetworkManager.service` and disables `iwd.service` ([enable-services.sh](https://github.com/DanielJBurbridge/omarchy/blob/feat/ally-parity-integration-20261111/install/config/enable-services.sh), [network.sh](https://github.com/DanielJBurbridge/omarchy/blob/feat/ally-parity-integration-20261111/install/hardware/network.sh)). `networkmanager` is a base package. Arch `networkmanager` 1.58.1-3 is `GPL-2.0-or-later` and `LGPL-2.1-or-later`, depends on `wpa_supplicant`, and lists `iwd` as an optional alternative ([package](https://archlinux.org/packages/extra/x86_64/networkmanager/)). The Arch wiki's iwd backend is opt-in: write `wifi.backend=iwd` and do not enable `iwd.service` yourself ([wiki](https://wiki.archlinux.org/title/NetworkManager#Using_iwd_as_the_Wi-Fi_backend)). This tree has no `wifi.backend=iwd` file. NetworkManager's own default backend is `wpa_supplicant`; `iwd` is the experimental alternative ([Igalia note](https://mafm.pages.igalia.com/blog/wifi-back-ends-in-steamos-36.html)). A machine-local `wifi_backend.conf` on the Ally was not read, so a box that someone has already switched is unverified.

SteamOS does the other thing. NetworkManager's iwd backend is what SteamOS uses by default, for a faster wake; `steamos-wifi-set-backend wpa_supplicant` switches it, and NetworkManager keeps the saved secrets ([Igalia note](https://mafm.pages.igalia.com/blog/wifi-back-ends-in-steamos-36.html), [SteamOS #2122](https://github.com/ValveSoftware/SteamOS/issues/2122)). Copying that backend onto Omarchy would fight `network.sh`. Do not do it for the Ally.

Steam's gaming-mode Wi-Fi page is Steam → Settings → Internet, then the network, then Connect. A passphrase uses Steam's on-screen keyboard. That description is a third-party walkthrough of Gaming Mode, not a Valve manual ([Foxy Tech, 10 Nov 2026](https://foxytechtips.com/connect-to-a-wifi-network-on-steam-deck/)). Whether that page writes NetworkManager connections on Omarchy, with no `steamos-manager` and with the `wpa_supplicant` backend, is spec 03 OQ-10 and is still unverified ([03](../03-first-boot-and-install.md)). Do not ship stock steamos-manager. The research README already records why.

The default shell bar includes `omarchy.network` ([shell.json](https://github.com/DanielJBurbridge/omarchy/blob/feat/ally-parity-integration-20261111/config/omarchy/shell.json)). The widget is a Wi-Fi list with connect ([bar README](https://github.com/DanielJBurbridge/omarchy/blob/feat/ally-parity-integration-20261111/shell/plugins/bar/README.md)). The panel keeps a passphrase field ([Panel.qml](https://github.com/DanielJBurbridge/omarchy/blob/feat/ally-parity-integration-20261111/shell/plugins/panels/network/Panel.qml)). This tree has no waybar config. The 12 Nov handover records Daniel's report that, after a deploy, Wi-Fi was off and the waybar network module was missing, and that the cause is unverified ([HANDOVER](../HANDOVER.md)). If the Quickshell widget is also absent, the menu has no `omarchy.network` summon. `setup.network.qr` only runs when Wi-Fi is already connected ([omarchy-menu.jsonc](https://github.com/DanielJBurbridge/omarchy/blob/feat/ally-parity-integration-20261111/default/omarchy/omarchy-menu.jsonc)).

Fallbacks that match NetworkManager:

| UI | Repo | Touch | Licence |
|---|---|---|---|
| `nm-connection-editor` (split of `network-manager-applet`) | extra 1.36.0-2 | GTK window. Touch can drive it if a pointer exists. Unverified on the Ally | `GPL-2.0-or-later` ([package](https://archlinux.org/packages/extra/x86_64/network-manager-applet/)) |
| `nmtui` | shipped with `networkmanager` (the package depends on `libnewt`) | Terminal UI. Needs a keyboard or a controller that sends keys. Unverified by touch | same package as NetworkManager |
| Shell `omarchy.network` | this tree | Touch list plus a passphrase field, once something summons it | MIT, part of Omarchy |

`impala` 0.9.0-1 is extra, `GPL-3.0-only`, and depends on `iwd`. Its README says to disable NetworkManager ([package](https://archlinux.org/packages/extra/x86_64/impala/), [README](https://github.com/pythops/impala/)). `iwgtk` is AUR, last updated 2023-01-03, a GTK front-end for iwd. The AUR licence field is `GPL3`. The upstream COPYING file is the GPL-3 text ([AUR](https://aur.archlinux.org/packages/iwgtk), [COPYING](https://raw.githubusercontent.com/J-Lentz/iwgtk/master/COPYING)). Both target the backend Omarchy turns off. They are the wrong tools here. A passphrase in any of the useful UIs still needs an OSK: Steam's in gaming mode, wvkbd on the Hyprland desktop.

## 6. Controller as a mouse, including before login

InputPlumber 0.84.0-1 is extra. Arch lists `GPL-3.0-only` ([package](https://archlinux.org/packages/extra/x86_64/inputplumber/)). The upstream LICENSE file is the GPL-3 text ([LICENSE](https://raw.githubusercontent.com/ShadowBlip/InputPlumber/main/LICENSE)). Depend on the package. Do not copy the Ally YAML into this tree. The RC71L composite config `50-rog_ally.yaml` matches board `RC71L` and sets `target_devices` to `xbox-elite`, `mouse` and `keyboard` ([yaml](https://raw.githubusercontent.com/ShadowBlip/InputPlumber/main/rootfs/usr/share/inputplumber/devices/50-rog_ally.yaml)). Those targets are virtual devices. A stick becomes a cursor only when a profile maps it. The schema accepts a gamepad axis mapped to mouse motion; a requested trackpad-to-mouse translation was still unimplemented in the report that became 0.80.0 ([issue 692](https://github.com/ShadowBlip/InputPlumber/issues/692)). Which stock profile, if any, maps the Ally's sticks to the mouse target was not re-read for this note. [buttons-and-input.md](buttons-and-input.md) already recommends InputPlumber and says not to run HHD beside it, because both grab the same evdev nodes.

The unit is `WantedBy=multi-user.target` ([inputplumber.service](https://raw.githubusercontent.com/ShadowBlip/InputPlumber/main/rootfs/usr/lib/systemd/system/inputplumber.service)). `multi-user.target` is up before the display manager, so the virtual mouse can exist before SDDM. Whether SDDM and this greeter actually move a pointer from that device is unverified. Install docs are `systemctl enable --now inputplumber` ([install](https://shadowblip.github.io/InputPlumber/install/)).

HHD's Ally mouse mode is a firmware command, `MODE_MOUSE` / `xpad_mode_mouse`, in `const.py` ([const.py](https://github.com/hhd-dev/hhd/blob/d3bbd7fa25fe9a4838896a2c5cfda460abe48dc6/src/hhd/device/rog_ally/const.py)). [buttons-and-input.md](buttons-and-input.md) records the project as `LGPL-2.1-or-later` from the upstream readme. That readme was not re-fetched on 16 Nov. Upstream tells people not to use the AUR. Do not copy the MCU bytes. Do not run it next to InputPlumber.

Steam's desktop layout is a Steam client feature. It applies while Steam is running. A factory Deck config binds X alone to `SHOW_KEYBOARD` ([steam-for-linux #13794](https://github.com/ValveSoftware/steam-for-linux/issues/13794)). It does not exist before login, because Steam is not running. Bazzite's handheld wiki is cited by the parity matrix for a desktop-layout binding ([matrix](parity-matrix.md)).

makima remaps evdev devices, including controller sticks to cursor motion, and can be installed as a system `makima.service` ([README](https://github.com/cyber-sushi/makima)). The GitHub metadata says GPL-3.0. The LICENSE file was not opened, so `-only` versus `-or-later` is unverified. This tree does not reference it. A second grabber next to InputPlumber is the conflict already recorded for HHD. Leave makima out.

## 7. Password prompts without a keyboard, and a gaming crash loop

### Prompts

SteamOS desktop is KDE Plasma, Wayland by default as of the 3.8 notes (Plasma 6.4.3) ([Steam news feed excerpt](https://store.steampowered.com/news/posts/?enddate=1781051413&feed=steam_community_announcements)). The password is set in System Settings → Personalization → Users. That is the path in a confirmed Plasma bug, not a guess ([KDE 457772](https://bugs.kde.org/show_bug.cgi?id=457772)). Plasma's lock and login UI has its own virtual keyboard. `VirtualKeyboardLoader.qml` calls `Qt.inputMethod.show()` and `passwordField.forceActiveFocus()` so keystrokes are not eaten ([loader](https://lxr.kde.org/source/plasma/plasma-workspace/lookandfeel/components/VirtualKeyboardLoader.qml), `LGPL-2.0-or-later` in that file's SPDX header). Nate Graham, on the same bug: the lock screen normally has its own virtual keyboard. On the Deck it was not showing, and Steam+X still injected keys while the Steam keyboard stayed under the lock, invisible and not touchable.

KDE's polkit agent handbook describes a password dialog. It does not mention an on-screen keyboard ([handbook](https://docs.kde.org/stable_kf6/en/plasma-workspace/PolicyKit-kde/authorizationagent-dialog.html)). A separate polkit dialog that covers another keyboard is a known failure: Debian's Cinnamon pkexec window is modal and blocks Onboard, so a touch-only machine cannot authenticate ([debian-cinnamon, Oct 2025](https://lists.debian.org/debian-cinnamon/2025/10/msg00006.html)). KDE's own polkit issue asks for a system-modal dialog ([invent.kde.org work item 2](https://invent.kde.org/plasma/polkit-kde-agent-1/-/work_items/2)). A modal dialog is safe only when the keyboard is inside it.

CachyOS Handheld's desktop is that same Plasma session (`plasma.desktop` in `steamos-session-select`). No CachyOS page was found that says the sudo prompt is usable by touch. Treat that as unverified, with Plasma's lock-screen keyboard as the nearest sourced behaviour.

Bazzite's deck image avoids a boot password by autologin. The same thread says a LUKS passphrase still needs a physical keyboard ([thread](https://www.answeroverflow.com/m/1334405906246537236)). A third-party layer, `bazzite-touch-unlock`, puts unl0kr on the Plymouth passphrase screen. It is not Bazzite upstream, it needs a USB keyboard for the first install, and touch is the supported input ([repo](https://github.com/jg00dman/bazzite-touch-unlock)). unl0kr comes from BuffyBox. AUR `buffybox` is `GPL-3.0-or-later` ([AUR](https://aur.archlinux.org/packages/buffybox)). Spec 03 already refuses unl0kr as the lock keyboard and the disk-unlock keyboard.

On Omarchy, turning `desktop-lock` off needs an interactive password, and a passwordless polkit rule must not be able to do it ([02 §7.4](../02-mode-switch-and-dock.md)). `install/omarchy-base.packages` does not name a polkit agent. Whether `hyprpolkitagent` (listed in extra beside the other hypr* packages) can take wvkbd input is unverified, and its SPDX id was not fetched, so it is not a reuse candidate in the table below. Until K07, the handheld does not put that prompt on the boot path: `default-off` skips the lock.

### Crash loop

| System | After gamescope or Steam dies | Source |
|---|---|---|
| Bazzite | `Relogin=true` sends the autologin session back to `gamescope-session-ogui-steam.desktop`. A counted "give up and show the greeter" path was not found | [holo.conf](https://github.com/ublue-os/bazzite/blob/main/system_files/deck/shared/usr/lib/sddm/sddm.conf.d/holo.conf) |
| CachyOS | `Relogin=true` on first boot. `oneshot` makes every fresh boot Gamescope. `plasma` logs the desktop in. No crash counter in `steamos-session-select` | [conf](https://raw.githubusercontent.com/CachyOS/CachyOS-Handheld/main/etc/plasmalogin.conf.d/steam-deckify.conf), [script](https://raw.githubusercontent.com/CachyOS/gamescope-session/cachyos/usr/bin/steamos-session-select) |
| ChimeraOS | Repeated init failure drops to the Gnome desktop | [Getting Started](https://github.com/ChimeraOS/chimeraos/wiki/Getting-Started) |
| Omarchy | One retry, then the desktop through `desktop()`. Three starts in 60 seconds that never read `started` write `/run/omarchy/handheld-autologin/stop`, set `Relogin=false`, and show the greeter. A reboot clears `/run` and the next boot writes `Relogin=true` again | [ALPHA.md](../ALPHA.md), [02 §7.2](../02-mode-switch-and-dock.md) |

The greeter is the recovery screen, and on this branch it cannot submit the password by touch. SSH works only when sshd was already enabled ([ALPHA.md](../ALPHA.md)). That is the hole this note is trying to close.

## 8. Steam's on-screen keyboard outside a game

Steam draws it. Gamescope does not ([gamescope #668](https://github.com/ValveSoftware/gamescope/issues/668)).

Summon paths with a source:

| Path | What the source says | Limit |
|---|---|---|
| Steam+X | Valve's chord layout binds `button_x` to `controller_action SHOW_KEYBOARD`. Sam Lantinga: all-zero `steam://open/keyboard` parameters match that chord | The Oct 2026 client logs `Guide button skipped due to chording` and does nothing for Steam+X in Desktop Mode. X alone still opens it when the stock desktop config is loaded ([#13794](https://github.com/ValveSoftware/steam-for-linux/issues/13794), [SDL PR 6515](https://github.com/libsdl-org/SDL/pull/6515)) |
| X alone | `desktop_neptune.vdf` binds `button_x` to `SHOW_KEYBOARD` | Needs Steam running and that desktop config applied. A blank desktop config is a different case; #13794 says a blank config was not the cause of the chord bug |
| `steam://open/keyboard` | SDL opens `steam://open/keyboard?XPosition=%d&YPosition=%d&Width=%d&Height=%d&Mode=0`. Close is `steam://close/keyboard`. `xdg-open steam://open/keyboard` showed the keyboard on a Deck while a game was running | The URL is handled by Steam. slouken: Wayland reporting three keyboards made SDL skip the OSK, because it thought a hardware keyboard was present ([SDL #12595](https://github.com/libsdl-org/SDL/issues/12595)) |
| `ISteamUtils::ShowFloatingGamepadTextInput` | Opens a floating keyboard and sends OS key events to the game. Mode 0 dismisses on Enter | Partner API, in-game ([docs](https://partner.steamgames.com/doc/api/ISteamUtils#ShowGamepadTextInput)) |
| Text field in Game Mode | A third-party guide says holding Steam and pressing X, or focusing a text box, opens it. It also says the chord does not work on the home screen or inside Settings | [How-To Geek](https://www.howtogeek.com/898672/how-to-use-and-customize-the-virtual-keyboard-on-your-steam-deck/). Not a Valve page. The Valve FAQ URLs fetched for this note returned no article body |

Hyprland: no source says the Steam keyboard window maps, accepts touch, or sits above Hyprland surfaces. #13794 and KDE 457772 are Desktop Mode on Plasma. Spec 07 already says Big Picture inside Hyprland uses wvkbd, and Steam's desktop layout stays off while the InputPlumber `desktop` profile is active. Whether `xdg-open steam://open/keyboard` from a Hyprland terminal does anything on the Ally is an open question. Steam must be running or the URL has nobody to handle it ([SDL PR 6515](https://github.com/libsdl-org/SDL/pull/6515)).

## 9. iPadOS patterns worth copying

Two patterns, from Apple's own pages. Apple's software is not reusable. Copy the behaviour.

**Lock screen keypad.** If the passcode is only digits, the Lock Screen shows a numeric keypad. If it is alphanumeric, the Lock Screen shows a full keypad. The passcode is what unlocks the device, and a numeric code can be stronger in practice because people will actually use a longer one ([Apple Platform Security](https://support.apple.com/guide/security/passcodes-and-passwords-sec20230a10d/web)). That is K07: the keypad is part of the lock surface. Plasma does the same thing with `VirtualKeyboardLoader` inside the lock, rather than a keyboard from another process (see §7). hyprlock does not have this widget (§4).

**Keyboard follows the field.** Apple's Human Interface Guidelines for text fields tell the app to show the keyboard type that matches the content (email, number, URL) on iOS and iPadOS ([text fields](https://appstoreguidelines.com/human-interface-guidelines/version/23/text-fields/)). That page is a republication of the HIG, not developer.apple.com. Apple's own keyboards guideline URL was fetched and returned no article body, so this note does not quote it ([keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards)). The pattern to lift is: the focused field chooses the keyboard, and a secure field uses a secure entry. Hyprland cannot do the automatic half today while Fcitx5 holds the only input-method slot (§1, §3). Spec 07 already records manual summon, with auto-show only for Omarchy's own search fields. A PIN field should be a keypad of its own, as on the iPad lock screen, and should not wait for that protocol.

## 10. Ranked options

Best first. Each line is something Omarchy can ship without copying copyleft source.

1. **Autologin into the gamescope session that already exists.** Touch is passthrough (`--default-touch-mode 4`). Steam's UI, Steam's Internet page and Steam's keyboard are the keyboardless path. Spec 02 already chose this. The security cost is §4.
2. **Stay on NetworkManager with `wpa_supplicant`.** Join Wi-Fi in Steam if OQ-10 passes, otherwise in `omarchy.network` with wvkbd for the passphrase. Do not switch the backend to iwd.
3. **Make the greeter able to submit.** Qt Virtual Keyboard (`extra/qt6-virtualkeyboard`) inside the existing SDDM theme, with Backspace, Shift, symbols and a submit control. The current grid cannot finish a login. Do not swap SDDM for greetd.
4. **InputPlumber as a system service before the greeter**, with an explicit stick-to-mouse profile for the greeter and the desktop. The package is already the plan in [buttons-and-input.md](buttons-and-input.md). Confirm on device that the pointer moves in SDDM.
5. **K07 as a numeric keypad inside the lock**, on the iPad and Plasma pattern. `desktop-lock` stays `default-off` until that exists. hyprlock's missing PIN widget is why this is not "turn hyprlock on".
6. **wvkbd, manual, on the Hyprland desktop only.** Already spec 07. `--auto` stays off while Fcitx5 is the input method.
7. **hyprgrass, later, for workspace swipes.** BSD-3-Clause plugin, loaded by hyprpm, not copied. Not required to get online. First load can kill touch; try it with a USB keyboard attached.
8. **Do not use** greetd, tuigreet, regreet, maliit, impala, iwgtk, HHD, makima, or stock steamos-manager for this goal. Reasons are in the sections above.

## 11. Recommended setup for the RC71L

Packages to add, when the matching piece is built. Versions are the Arch pages fetched on 16 Nov 2026.

| Package | Where | SPDX | Role |
|---|---|---|---|
| `gamescope` 3.17.0-1 | extra | `BSD-2-Clause`, `BSD-3-Clause`, `LicenseRef-Reshade` | Already pulled by the session. Keep `--default-touch-mode 4` |
| `inputplumber` 0.84.0-1 | extra | `GPL-3.0-only` | System service. Mouse and keyboard targets. Do not vendor the YAML |
| `qt6-virtualkeyboard` 6.12.0-1 | extra | `GPL-3.0-only`, `LGPL-3.0-only`, `LicenseRef-Qt-Commercial`, `Qt-GPL-exception-1.0` | Greeter keyboard. Not copied into the theme |
| `wvkbd` 0.21-1 | AUR | treat as `GPL-3.0-only` (see §3) | Desktop OSK, manual. Already the spec |
| `network-manager-applet` | extra | `GPL-2.0-or-later` | `nm-connection-editor` if the shell panel cannot be opened |
| `hyprgrass` | AUR git, or hyprpm | `BSD-3-Clause` upstream | Optional gestures. Not on the boot path |

Leave installed and unchanged: `networkmanager`, `sddm`, `fcitx5`, `hyprland`. Do not add `iwd`, `impala` or `iwgtk`.

Autologin, written once by the installer, as spec 02 §7.1 and spec 03 W9 already say:

```
# /etc/sddm.conf.d/zz-omarchy-handheld.conf
[Autologin]
User=<installer-created user>
Session=omarchy-handheld.desktop
Relogin=true
```

`Relogin=false` is the installer's first write. The handheld unit sets `true`. Three failures set it back to `false` ([ALPHA.md](../ALPHA.md)). Do not guess the user at runtime. Do not copy CachyOS `steam-set-session`.

Session command, already in `bin/omarchy-session-start`:

```
gamescope --backend drm -e --xwayland-count 2 --default-touch-mode 4 -- …/omarchy-gaming-steam
```

InputPlumber, system-wide, so it exists at the greeter:

```
systemctl enable --now inputplumber.service
```

The mouse profile is a new file under `/etc/inputplumber/profiles/`, loaded with `LoadProfilePath` on the composite device. The stock `50-rog_ally.yaml` creates the mouse target and does not, by itself, document a stick-to-cursor map. Write that map in Omarchy's own words, or vendor InputPlumber's file beside its LICENSE. Do not paste the GPL YAML into an MIT file.

Greeter: extend `default/sddm/omarchy/Main.qml` with Backspace and a submit button that calls the same `sddm.login` the Return key calls, or switch that grid for Qt Virtual Keyboard. The auth branches already point at `GreeterEnvironment` in `etc/sddm.conf.d/10-wayland.conf` ([07](../07-on-screen-keyboard.md)). This integration file has no `InputMethod=` line. The kwin-specific `--inputmethod` advice does not apply to `start-hyprland` until someone tests it.

Desktop passphrase: summon wvkbd with the existing helper, then type into `omarchy.network`. If the bar widget is missing, a menu row that summons `omarchy.network` is the small product change. `nm-connection-editor` is the fallback window. Both need the pointer from InputPlumber or a finger.

Pieces already on this branch that the setup touches:

- `bin/omarchy-session-start` runs gamescope with touch mode 4, then falls back to the desktop.
- `bin/omarchy-handheld-autologin` writes the SDDM drop-in and the three-failure stop.
- `default/gaming/wayland-sessions/omarchy-handheld.desktop` is the autologin session. Spec 02 names it. Confirm the installed file matches `Session=`.
- `default/sddm/omarchy/Main.qml` is the greeter that cannot submit.
- `config/omarchy/shell.json` already lists `omarchy.network`. The handover's missing waybar module is a different bar.
- `install/hardware/network.sh` and `install/config/enable-services.sh` keep NetworkManager and retire iwd.
- Spec 07's wvkbd helper and spec 01's InputPlumber profiles are on other Ally branches. This note does not move them.

## 12. Open questions / needs an on-device test

1. Steam → Settings → Internet on this Ally: does it list SSIDs and save a connection while NetworkManager's backend is `wpa_supplicant` and steamos-manager is not installed? Spec 03 OQ-10.
2. With the shell network widget removed, can a finger still open `omarchy.network`? If not, the menu row in §11 is required.
3. `xdg-open steam://open/keyboard` from Hyprland, Steam running, no physical keyboard. Does a window appear, and does touch type into a GTK passphrase dialog?
4. Steam+X and X-alone against the stock Steam desktop config, in gamescope and in Hyprland. #13794 says the chord is broken in Plasma Desktop Mode as of the Oct 2026 client.
5. `inputplumber.service` active before SDDM: does the stick move the greeter pointer, and can A click a key on the grid?
6. wvkbd typed into a real polkit or sudo prompt on this desktop. If the dialog is modal and covers the keyboard, the prompt is not usable. Record which agent is installed. The base package list does not name one.
7. The greeter grid: confirm there is no submit control on the device, matching `Main.qml`.
8. hyprgrass on the Ally touchscreen, with a USB keyboard plugged in for the first load.
9. Whether the RC71L accelerometer should drive `iio-hyprland`. Not required for boot.

## Licences for anything this note might reuse

| Project | SPDX | Reuse |
|---|---|---|
| Omarchy | MIT | This tree |
| Hyprland, hyprlock | `BSD-3-Clause` | Already packaged. hyprlock has no PIN pad |
| hyprgrass | `BSD-3-Clause` (AUR says `BSD`) | Plugin via hyprpm. Keep the BSD notice if any file is copied. AOSP pieces stay Apache-2.0 |
| gamescope | `BSD-2-Clause`, `BSD-3-Clause`, `LicenseRef-Reshade` | Package. Do not copy source |
| gamescope-session (ChimeraOS) | MIT | Package or rewrite. Keep the MIT notice if copied |
| SDDM | `GPL-2.0-or-later` | Package. Theme QML in this tree is Omarchy's |
| qt6-virtualkeyboard | `GPL-3.0-only`, `LGPL-3.0-only`, `LicenseRef-Qt-Commercial`, `Qt-GPL-exception-1.0` | Package only |
| plasma-keyboard | `GPL-2.0-or-later` | Package only. Not recommended; it pulls Plasma |
| squeekboard | `GPL-3.0-or-later` | Package only. Not recommended next to Fcitx5 |
| wvkbd | GPL-3 text; AUR `GPL3`; treat as `GPL-3.0-only` | Package only |
| greetd | `GPL-3.0-only` | Not recommended |
| greetd-regreet | `GPL-3.0-or-later` | Not recommended |
| greetd-tuigreet | `GPL-3.0-only` | Not recommended |
| InputPlumber | Arch: `GPL-3.0-only` | Package. Do not vendor the Ally YAML into MIT files |
| HHD | `LGPL-2.1-or-later` as recorded in buttons-and-input.md | Do not use beside InputPlumber. Do not copy MCU bytes |
| makima | GitHub metadata: GPL-3.0; `-only` vs `-or-later` unverified | Do not use |
| NetworkManager | `GPL-2.0-or-later`, `LGPL-2.1-or-later` | Already installed |
| iwd | `LGPL-2.1-or-later` | Do not switch the backend |
| network-manager-applet | `GPL-2.0-or-later` | Package, if the shell panel is not enough |
| impala | `GPL-3.0-only` | Do not use. Requires iwd |
| iwgtk | GPL-3 text; AUR `GPL3` | Do not use. Requires iwd |
| buffybox / unl0kr | AUR `GPL-3.0-or-later` | Spec 03 already keeps it off the lock and the disk unlock |
| iio-hyprland | GPL-3 text, no SPDX header read | Do not copy. Not on the boot path |
| maliit-keyboard | AUR `LGPL` (not SPDX) | Do not use |
| Bazzite tree | Apache-2.0 | Patterns only |
| CachyOS session scripts | no LICENSE file in the `cachyos` branch root | Do not copy |
| Steam client | proprietary | Use the installed client. Do not copy |
| steamos-manager | MIT | Do not ship. See the research README |
| Apple HIG and Platform Security | Apple's docs | Behaviour only. No code |
