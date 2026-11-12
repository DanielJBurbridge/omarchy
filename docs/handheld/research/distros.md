# Handheld distros: how gaming mode is built (Bazzite, CachyOS Handheld, SteamOS, ChimeraOS, Nobara)

Researched 12 Nov 2026 (AWST). Focus: what Omarchy (Arch + Hyprland) can reuse directly. **Unverified** = no primary source found.

## Bazzite (Deck images, v44+)
- **Selection/install:** you choose a `-deck` image at download. Device fixes apply only to supported handhelds ([Handheld wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/)). Repo licence: Apache-2.0 ([ublue-os/bazzite](https://github.com/ublue-os/bazzite)).
- **Boot to gaming mode:** SDDM (Wayland) autologin `Session=gamescope-session-ogui-steam.desktop`, `Relogin=true` ([holo.conf](https://github.com/ublue-os/bazzite/blob/main/system_files/deck/shared/usr/lib/sddm/sddm.conf.d/holo.conf)). `bazzite-autologin` writes `/etc/sddm.conf.d/zz-holo-autologin.conf` for uid 1000 ([script](https://github.com/ublue-os/bazzite/blob/main/system_files/deck/shared/usr/libexec/bazzite-autologin)). Built on `gamescope-session-plus` ([build script](https://github.com/ublue-os/bazzite/blob/main/build_files/bazzite-deck/04-install-gamescope-session.sh)).
- **Desktop ↔ gaming:** `/usr/libexec/os-session-select` is *"deprecated, please use steamosctl"*. It calls `steamosctl set-default-login-mode desktop|game`, `set-default-desktop-session`, `switch-to-desktop-mode` and `switch-to-game-mode` ([script](https://github.com/ublue-os/bazzite/blob/main/system_files/deck/shared/usr/libexec/os-session-select)). In other words, **steamos-manager does the switching**.
- **Input:** InputPlumber, with HHD dropped ([announcement](https://universal-blue.discourse.group/t/a-brighter-future-for-bazzite/11575)). Ships extra IP configs under `/etc/inputplumber/devices.d` and `capability_maps.d`.
- **TDP/power:** steamos-manager in the Steam QAM for devices listed in [`steamos-manager-hardware`](https://github.com/ublue-os/bazzite/blob/main/system_files/desktop/shared/usr/libexec/hwsupport/steamos-manager-hardware) (**ROG Ally included**, matched on `product_name == "ROG Ally"*`). PowerStation (in OGUI) for the rest ([GamingOnLinux](https://www.gamingonlinux.com/2026/08/bazzite-linux-44-for-handhelds-finally-launches-with-some-massive-upgrades/)). Warning: run only one TDP controller ([wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/)).
- **Fan:** some devices lost manual fan control in 44 ([GoL](https://www.gamingonlinux.com/2026/08/bazzite-linux-44-for-handhelds-finally-launches-with-some-massive-upgrades/)).
- **Decky:** `ujust setup-decky` ([wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/)).
- **Kernel:** OGC kernel ([announcement](https://universal-blue.discourse.group/t/a-brighter-future-for-bazzite/11575)).
- **Docking:** no automatic switch documented.

## CachyOS Handheld (Arch, most reusable)
- **Install:** dedicated Handheld ISO with Calamares, online install and systemd-boot ([README](https://github.com/CachyOS/CachyOS-Handheld)). `chwd` detects the device by DMI: the generic handheld profile installs `steamos-manager inputplumber steamos-powerbuttond`, and the `rog-ally` profile (board `RC71L|RC72LA|RC73XA|RC73YA`) links RC71L audio configs ([profiles.toml](https://github.com/CachyOS/chwd/blob/master/profiles/pci/handhelds/profiles.toml), GPL-3.0).
- **Meta package `cachyos-handheld`** 1.4.2 (GPL-3.0-or-later). Depends on `gamescope-session-cachyos jupiter-hw-support lib32-gamescope mangohud plasma-login-manager scx-scheds steam-jupiter-stable cachyos-vapor` ([PKGBUILD](https://github.com/CachyOS/CachyOS-PKGBUILDS/blob/master/handheld/cachyos-handheld/PKGBUILD)). Other packages in [`handheld/`](https://github.com/CachyOS/CachyOS-PKGBUILDS/tree/master/handheld): `steamos-manager` 26.4.1 (MIT, from gitlab.steamos.cloud), `steamos-powerbuttond` 4.2 (BSD-2-Clause), `jupiter-fan-control`, `jupiter-hw-support` (MIT), `gamescope` and `linux-cachyos-deckify` (kernel with handheld patch).
- **Boot to gaming mode:** Plasma Login autologin `Session=gamescope-session.desktop User=deck` for first boot ([plasmalogin.conf.d/steam-deckify.conf](https://github.com/CachyOS/CachyOS-Handheld/tree/main/etc/plasmalogin.conf.d)). `gamescope-session.desktop` → `start-gamescope-session` → user unit `gamescope-session.service` (`Type=notify`, `XDG_SESSION_TYPE=x11`) ([CachyOS/gamescope-session, branch `cachyos`](https://github.com/CachyOS/gamescope-session/tree/cachyos), MIT per PKGBUILD).
- **Switching:** `steamos-session-select {plasma|gamescope|persistent|oneshot}`. pkexec `steam-set-session` writes `zz-steamos-autologin.conf` for plasmalogin or sddm. `oneshot` (default) means every boot goes to gamescope; `persistent` means the last session is remembered (masks `cachyos-gamescope-autologin.service`) ([script](https://github.com/CachyOS/gamescope-session/blob/cachyos/usr/bin/steamos-session-select), [README](https://github.com/CachyOS/CachyOS-Handheld)). The desktop entry "Return to Gaming Mode" runs `steamosctl switch-to-game-mode` ([desktop file](https://github.com/CachyOS/CachyOS-Handheld/blob/main/usr/share/applications/steamos-gamemode.desktop)).
- **Power button:** logind `HandlePowerKey=ignore`, `KillUserProcesses=True`, with powerbuttond handling the key ([logind.conf.d](https://github.com/CachyOS/CachyOS-Handheld/tree/main/etc/systemd/logind.conf.d)).
- **Other reusable bits:** `modules-load.d/hid-preload.conf` (preload `hid_nintendo`, `hid_playstation` so Steam gets hidraw), `70-led-control.rules`, RC71L `pipewire/filter-chain.conf` + `wireplumber/alsa-card0.conf`, `environment.d/handheld.conf` (Decky user vars), `sysctl.d/20-steamos-customizations.conf`.
- **Scheduler:** `scx_lavd` by default ([README](https://github.com/CachyOS/CachyOS-Handheld)).

## SteamOS 3.7/3.8 (Valve)
- **Install:** recovery image. Secure Boot off. AMD + NVMe. The original Ally has "improved support" plus config instructions ([Ars Technica](https://arstechnica.com/gadgets/2025/05/steamos-3-7-brings-valves-gaming-os-to-other-handhelds-and-generic-amd-pcs/)).
- **Session/switching:** 3.8: *"Steam now uses steamos-manager to query available desktop sessions and trigger desktop session switching"*. Desktop is Wayland by default. Kernel 6.16. LAVD via `steamosctl set-cpu-scheduler lavd` ([VideoCardz](https://videocardz.com/newz/valve-releases-steamos-3-8-stable-with-steam-machine-support)).
- **Power:** steamos-manager device TOML for RC71L: `tdp_limit.method="firmware_attribute"` (asus-armoury), `platform_profile_name="asus-wmi"`, `battery_charge_limit acpi_sb` ([rog-ally-series.toml](https://gitlab.steamos.cloud/holo/steamos-manager/-/blob/master/data/devices/rog-ally-series.toml), MIT). Fan control is only `jupiter-fan-control.service` ([platform.toml](https://gitlab.steamos.cloud/holo/steamos-manager/-/blob/master/data/platform.toml)). Steam probes SOM interfaces at start-up and hides unsupported settings ([README mirror](https://github.com/hhd-dev/steamos-manager-hhd/blob/master/README.md)). `remotes.d` lets an external daemon provide missing interfaces ([example](https://github.com/OuinOuin74/hhd-steamos-bridge)).
- **Open bug:** RC71L TDP stuck at minimum after resume on 3.8.x ([#2790](https://github.com/ValveSoftware/SteamOS/issues/2790)).

## ChimeraOS
- **Sessions:** `steam`, `steam-plus` (Steam + OGUI overlay, Guide+B), `opengamepadui`, `desktop`, chosen with `chimera-session <name>` ([General Configuration](https://github.com/ChimeraOS/chimeraos/wiki/General-Configuration)). Session framework is `gamescope-session-plus` (MIT, [repo](https://github.com/ChimeraOS/gamescope-session)): `gamescope-session-plus@.service`, per-device `device-quirks` (RC71L: `ADAPTIVE_SYNC=1`, `PANEL_TYPE=external`, refresh limits 40–120) and env from `/etc/environment.d` + `~/.config/environment.d`. Plus `gamescope-session-steam` (MIT): `steamos-session-select` delegates to `/usr/lib/os-session-select` ([repo](https://github.com/ChimeraOS/gamescope-session-steam)).
- **TDP:** OGUI/PowerStation, or Decky plugins. Steam's own slider is not used on ChimeraOS ([wiki](https://github.com/ChimeraOS/chimeraos/wiki/General-Configuration)).
- **Image-based updates:** `frzr-deploy`.

## Nobara (Steam-Handheld edition)
- Fedora-based image with a gamescope Steam session ([downloads](https://www.nobaraproject.org/download.html)). Packages: `gamescope-session-plus`, `gamescope-session-steam` (with its own `os-session-select`, `steamos-desktop-return`, `Return.desktop`) and `jupiter-hw-support` ([Nobara-Project/steamdeck-edition-packages](https://github.com/Nobara-Project/steamdeck-edition-packages)). Uses InputPlumber per Bazzite's list ([announcement](https://universal-blue.discourse.group/t/a-brighter-future-for-bazzite/11575)). TDP and docking details are **unverified**.

## Comparison

| | Bazzite 44 | CachyOS Handheld | SteamOS 3.8 | ChimeraOS | Nobara |
|---|---|---|---|---|---|
| Base | Fedora Atomic | Arch | Arch (immutable) | Arch (frzr) | Fedora |
| Session pkg | gamescope-session-plus (`-ogui-steam`) | gamescope-session-cachyos | Valve | gamescope-session-plus/-steam | gamescope-session-plus/-steam |
| Autologin | SDDM `zz-holo-autologin.conf` | plasmalogin `zz-steamos-autologin.conf` | SDDM | (**unverified**) | (**unverified**) |
| Switch | `steamosctl` (SOM) | `steamos-session-select` / `steamosctl` | SOM | `chimera-session` / `os-session-select` | `os-session-select` |
| Input | InputPlumber | InputPlumber | InputPlumber | InputPlumber | InputPlumber |
| TDP | SOM (Ally) / PowerStation | SOM | SOM | PowerStation / Decky | **unverified** |
| Fan | partial | Deck only | Deck only | none | **unverified** |
| Decky | `ujust setup-decky` | manual | manual | manual installer | **unverified** |
| Overlay | Steam QAM + OGUI | Steam QAM | Steam QAM | Steam QAM + OGUI | Steam QAM |
| Dock auto-switch | no | no | no | no | not found |

## Directly reusable for Omarchy (with licence)
| Item | Source | Licence | Use |
|---|---|---|---|
| `steamos-manager` PKGBUILD | [CachyOS-PKGBUILDS/handheld/steamos-manager](https://github.com/CachyOS/CachyOS-PKGBUILDS/tree/master/handheld/steamos-manager) / [upstream](https://gitlab.steamos.cloud/holo/steamos-manager) | MIT | TDP slider, session switching, screen-reader plumbing |
| `steamos-session-select`, `steam-set-session`, autologin unit, polkit policy | [CachyOS/gamescope-session@cachyos](https://github.com/CachyOS/gamescope-session/tree/cachyos) | MIT (per PKGBUILD) | Conflicts with spec 02. That design chose user-state switching and does not edit SDDM configuration (`docs/rog-ally-gaming-session.md` on `feat/ally-session-20261111`). pkexec `steam-set-session` writes autologin config under `/etc`. A polkit rule that lets the session user rewrite display-manager autologin without authentication is a privilege surface. Do not ship this path without review |
| `gamescope-session-plus` + `device-quirks` | [ChimeraOS/gamescope-session](https://github.com/ChimeraOS/gamescope-session) | MIT | Alternative session runner with RC71L quirks |
| `os-session-select` via `steamosctl` | [Bazzite](https://github.com/ublue-os/bazzite/blob/main/system_files/deck/shared/usr/libexec/os-session-select) | Apache-2.0 | Thin wrapper pattern |
| RC71L audio, logind, hid preload, LED udev | [CachyOS-Handheld](https://github.com/CachyOS/CachyOS-Handheld) | GPL-3.0-or-later | Reimplement from behaviour, or vendor as separately-licensed files with LICENSE and SPDX headers. Decision for Daniel. Omarchy is MIT. These files stay GPL-3.0-or-later; attribution alone does not cover copying them in |
| `steamos-powerbuttond` | [CachyOS PKGBUILD](https://github.com/CachyOS/CachyOS-PKGBUILDS/tree/master/handheld/steamos-powerbuttond), AUR | BSD-2-Clause | Short/long power press in gaming mode |

## Prioritised recommendations
1. **Adopt the steamos-manager-centred design** (Bazzite 44 / SteamOS 3.8): SOM owns TDP, the performance profile and session switching, and Omarchy provides a `steamos-session-select`/`os-session-select` shim plus a desktop-session config pointing at Hyprland. The shim follows spec 02 (user-state switching, no SDDM edits). Do not ship CachyOS `steam-set-session` or its polkit autologin rule without review.
2. **Base the session runner on `gamescope-session-cachyos`** (Arch-native, simplest). CachyOS oneshot/persistent semantics that rewrite display-manager autologin via pkexec conflict with spec 02 (user-state switching, no SDDM edits) and must not ship without review. See the reuse table.
3. **Package `steamos-manager` and `steamos-powerbuttond`** in Omarchy's repo (neither is in Arch extra; powerbuttond is in AUR).
4. **CachyOS RC71L audio and logind configs** (GPL-3.0-or-later): reimplement from behaviour, or vendor as separately-licensed files with LICENSE and SPDX headers. Decision for Daniel.
5. **Keep Decky and OGUI out of the default.** Bazzite and ChimeraOS both note breakage and conflicts.
