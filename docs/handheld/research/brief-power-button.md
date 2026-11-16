# Gaming power button on the RC71L

16 Nov 2026. Gap 6 in [feature-parity-audit.md](feature-parity-audit.md). Nothing in this note was run on a device.

Short press in the gamescope session suspends. A one-second hold opens Steam's power menu. The desktop button stays lock-then-suspend, with the K07 exception below.

## Recommendation

Build `omarchy-rog-ally-powerbutton` 4.2-1 from [`packaging/rog-ally-powerbutton/PKGBUILD`](../../../packaging/rog-ally-powerbutton/PKGBUILD). It compiles unmodified [powerbuttond v4.2](https://gitlab.steamos.cloud/holo/powerbuttond/-/tags/v4.2) (commit [`9392e688`](https://gitlab.steamos.cloud/holo/powerbuttond/-/commit/9392e68883fdb0c40bc01ab39ae75c83a541e413), which was also `main` on 16 Nov 2026) and installs only:

| Path | Role |
|---|---|
| `/usr/bin/steamos-powerbuttond` | Upstream daemon |
| `/usr/share/licenses/omarchy-rog-ally-powerbutton/LICENSE` | BSD-2-Clause notice |
| `/usr/lib/udev/hwdb.d/70-omarchy-rog-ally-power-button.hwdb` | `OMARCHY_POWER_BUTTON=1` on KEY_POWER (`k74`) modaliases |
| `/usr/lib/udev/rules.d/70-omarchy-rog-ally-power-button.rules` | `STEAMOS_POWER_BUTTON=1` and `TAG+=uaccess`, and only when `/usr/bin/omarchy-hw-rog-ally` succeeds |

Leave the [v4.2 Makefile](https://gitlab.steamos.cloud/holo/powerbuttond/-/blob/v4.2/Makefile) paths uninstalled: `/usr/lib/hwsupport/steamos-powerbuttond`, `/usr/lib/systemd/user/steamos-powerbuttond.service`, `gamescope-session.service.wants/`, `/usr/lib/udev/hwdb.d/70-steamos-power-button.hwdb` and `/usr/lib/udev/rules.d/70-steamos-power-button.rules`. The unit is `Requisite=gamescope-session.service` ([unit](https://gitlab.steamos.cloud/holo/powerbuttond/-/blob/v4.2/steamos-powerbuttond.service)). This session has no such unit.

No new unit. [`bin/omarchy-session-start`](../../../bin/omarchy-session-start) runs Gamescope with [`bin/omarchy-gaming-steam`](../../../bin/omarchy-gaming-steam) inside `omarchy-gamescope-$XDG_SESSION_ID.scope`. The wrapper starts [`bin/omarchy-launch-gaming-powerbutton`](../../../bin/omarchy-launch-gaming-powerbutton) when `omarchy-pkg-present omarchy-rog-ally-powerbutton` and `/usr/bin/steamos-powerbuttond` are both true, and kills that pid with Steam. A missing package or binary skips it. The helper exits unless this is an RC71L, `XDG_CURRENT_DESKTOP` is `gamescope`, `DISPLAY` is set, and `HYPRLAND_INSTANCE_SIGNATURE` is unset. It and [`bin/omarchy-system-power-button`](../../../bin/omarchy-system-power-button) share `$XDG_RUNTIME_DIR/omarchy-power-button.lock` (`flock -n`; the loser exits 0).

Keep [`etc/systemd/logind.conf.d/10-ignore-power-button.conf`](../../../etc/systemd/logind.conf.d/10-ignore-power-button.conf) (`HandlePowerKey=ignore`; leave `HandlePowerKeyLongPress` unset) and the bind in [`default/hypr/bindings/utilities.lua`](../../../default/hypr/bindings/utilities.lua) (`XF86PowerOff` → `omarchy-system-power-button`, `locked`). `omarchy-sleep-lock.service` stays for suspend that is not this button.

The daemon, hwdb and rule stay in the Ally package. The ignore drop-in and the desktop command stay in core. logind's default for `HandlePowerKey` is `poweroff`, and `HandlePowerKeyLongPress` defaults to `ignore` ([logind.conf, systemd 256+](https://www.freedesktop.org/software/systemd/man/latest/logind.conf.html)). The recipe `conflicts` with `steamos-powerbuttond`, `steam-powerbuttond` and `steam-powerbuttond-git`.

## What v4.2 sends

[`powerbuttond.c` at v4.2](https://gitlab.steamos.cloud/holo/powerbuttond/-/blob/v4.2/powerbuttond.c), read 16 Nov 2026. SPDX header `BSD-2-Clause` (C file copyright 2023–2025; the [LICENSE](https://gitlab.steamos.cloud/holo/powerbuttond/-/blob/v4.2/LICENSE) notice is copyright 2023, two conditions).

It lists `input`/`event*` nodes with `STEAMOS_POWER_BUTTON=1`, skips `STEAMOS_POWER_BUTTON_IGNORE`, and opens a node that has `KEY_POWER`, or both `KEY_LEFTMETA` and `KEY_F16`, or `SW_LID`. It does not grab the device. No match returns 0.

`KEY_POWER` value 1 sets `alarm(1)` (one second) and the alarm sends `steam://longpowerpress`. A release while that press is still active sends `steam://shortpowerpress`. Meta held alone plus `KEY_F16` also sends `steam://longpowerpress`. Lid close sends `steam://lidswitch`. The spawn is `$HOME/.steam/root/ubuntu12_32/steam -ifrunning <url>`. The process never calls `systemctl`.

The client is proprietary. [Bazzite PR 5306](https://github.com/ublue-os/bazzite/pull/5306) says a long press shows Steam's power menu while the daemon runs, and that `HandlePowerKey=ignore` with the daemon down makes gamescope ignore the key. SteamOS 3.8 says short and long presses work on a wide set of devices ([news](https://www.steamdeck.com/en/news/?p=18)) and does not name the two actions. What this Ally's client does with each URL is **unverified**.

## Device match

The v4.2 [hwdb](https://gitlab.steamos.cloud/holo/powerbuttond/-/blob/v4.2/steamos-power-button.hwdb) tags every modalias with KEY_POWER (`k*74*`), KEY_F16 (`k*BA*`) or a lid switch, then ignores the Deck "Power Button" (Jupiter, Galileo). It has no `RC71L` line. The older [evlaV mirror](https://gitlab.com/evlaV/powerbuttond/-/blob/main/steamos-power-button.hwdb) (v3.3, July 2025) and [matte-schwartz/steamos-powerbuttond](https://github.com/matte-schwartz/steamos-powerbuttond/blob/5a971c50893dd1706d69f3dd61f4bb6001acabf1/steamos-power-button.hwdb) match `evdev:name:Power Button` plus board `RC71L`. [SteamOS #1832](https://github.com/ValveSoftware/SteamOS/issues/1832) records a Z1 Ally working with a local copy of that older file.

The 12 Nov dump lists ACPI `event0/1` as "Power / Sleep Button" and says Omarchy tags the power key ([ally-hw-dump.md](ally-hw-dump.md)). Names, modaliases and which node has `KEY_POWER` were not captured (no evtest). Those three are **unverified**. A `KEY_POWER` node matches v4.2's glob and this package's comma-bounded `k74` lines. N-KEY exposes F16. Whether one node also has `KEY_LEFTMETA` is **unverified**. The companion hwdb tags neither F16 nor the lid, and the rule still runs `omarchy-hw-rog-ally`.

## Packages and the other handlers

CachyOS `steamos-powerbuttond` 4.2-1 ([PKGBUILD](https://github.com/CachyOS/CachyOS-PKGBUILDS/blob/master/handheld/steamos-powerbuttond/PKGBUILD), 16 Nov 2026) `make install`s tag `v4.2`: binary `/usr/lib/hwsupport/steamos-powerbuttond`, plus the broad hwdb and the user unit. `license` is `BSD-2-Clause`. `url` says `jupiter/powerbuttond`; `source` is `holo/powerbuttond`. The wrapper requires `/usr/bin/steamos-powerbuttond`.

AUR `steamos-powerbuttond` 4.2-3 ([RPC](https://aur.archlinux.org/rpc/v5/info?arg[]=steamos-powerbuttond)): `BSD-2-Clause`, depends `libevdev` `udev` `gamescope`, provides/conflicts/replaces `powerbuttond`. Absent from Arch extra ([search](https://archlinux.org/packages/search/json/?q=steamos-powerbuttond)). PKGBUILD body **unverified** (Anubis). Our recipe already conflicts with that name. An in-tree script would resend the same URLs. Ship the BSD binary and its notice.

HHD ([`base.py` at `180f0cd`](https://github.com/hhd-dev/hhd/blob/180f0cd8515787789ce82a8d8a116076c36c98a6/src/hhd/plugins/powerbutton/base.py)) uses 2.0 s, the same URLs, a `handle-power-key:handle-lid-switch` inhibitor, a name or `KEY_POWER` match, and `systemctl suspend` if Steam fails. [LICENSE](https://github.com/hhd-dev/hhd/blob/180f0cd8515787789ce82a8d8a116076c36c98a6/LICENSE) is LGPL-2.1 text (`LGPL-2.1-only`). Leave it off.

InputPlumber [`50-rog_ally.yaml`](https://github.com/ShadowBlip/InputPlumber/blob/main/rootfs/usr/share/inputplumber/devices/50-rog_ally.yaml) on `main` (16 Nov 2026) has no ACPI power source and no `KeyPower` (`GPL-3.0-or-later`, [profiles brief](inputplumber-profiles-brief.md)). Keep `KEY_POWER` out of the profiles. [ShadowBlip/steam-powerbuttond](https://github.com/ShadowBlip/steam-powerbuttond) is archived; GitHub records GPL-3.0 and the README points at holo.

`HandlePowerKey=suspend` suspends at the greeter and on the desktop. Steam's menu is the daemon's URL. CachyOS also sets `KillUserProcesses=True` ([steam-deckify.conf](https://github.com/CachyOS/CachyOS-Handheld/blob/main/etc/systemd/logind.conf.d/steam-deckify.conf)); that repo has no LICENSE file ([distros.md](distros.md)). Our drop-in is the ignore line only. The desktop bind has no hold timer: RC71L runs sleep-lock then `systemctl suspend` (the system menu when suspend is disabled); every other machine opens the system menu. Gaming clears the Hyprland signature first, so that bind is absent there.

## Lock and K07

The gaming helper does not call sleep-lock ([spec 02](../02-mode-switch-and-dock.md)). Suspend there is Steam's. Whether resume shows Steam's lock is **unverified**.

The desktop button calls [`omarchy-system-sleep-lock`](../../../bin/omarchy-system-sleep-lock), which uses `gaming_apply_lock_gate` in [`default/gaming/session.sh`](../../../default/gaming/session.sh). Marker: `/var/lib/omarchy/handheld/k07-landed`. A physical keyboard excludes USB `0b05:1abe` and any N-KEY name ([`keyboard.sh`](../../../default/gaming/keyboard.sh)).

| Marker | Effective lock | Physical keyboard | This button |
|---|---|---|---|
| Present, or a physical keyboard is attached | any | — | Lock, then suspend |
| Absent | `default-off` or `explicit-off` | Absent | Suspend, lock skipped ([ALPHA.md](../ALPHA.md)) |
| Absent | `on` | Absent | Gate starts a return to gaming (`--confirm` is accepted by [`omarchy-launch-gaming-session`](../../../bin/omarchy-launch-gaming-session)) and sleep-lock exits 1, so the button cancels suspend |

Spec 02 D11's broker (end the desktop, then suspend from gaming) is absent ([spec 09](../09-keyboard-free-boot.md)). Spec 01's note that `omarchy-system-power-button` is missing is stale. Spec 09 OQ-7, the greeter short press, stays open: ignore is set and Hyprland is down, so the expected result is no action. **Unverified** on the device.

## On-device test

Install this package alone. `steamos-powerbuttond.service` is absent, and so are the five upstream paths above. `sudo systemd-hwdb update`, `sudo udevadm control --reload`, `sudo udevadm trigger --subsystem-match=input`. The ACPI power node has `STEAMOS_POWER_BUTTON=1` and a seat ACL. N-KEY nodes do not. Record the evdev name and the KEY bit.

In gaming the process sits in `omarchy-gamescope-$XDG_SESSION_ID.scope` and logs `Found power button device`. One short press: one `steam -ifrunning steam://shortpowerpress`, one suspend, resume into the same game. One hold of about one second: `steam://longpowerpress` and Steam's power menu, and the machine stays up. A much longer hold is the firmware power-off already separated in [rog-ally-reliability.md](../../rog-ally-reliability.md). Its duration is **unverified**. `busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandlePowerKey` stays `ignore`. The journal shows one action per press.

Leave gaming and the process is gone. Desktop, marker absent, no USB keyboard: one suspend and no lock screen. `omarchy-setup-gaming-session desktop-lock on`, still no USB keyboard: the press does not suspend. With a USB keyboard, or once the marker exists: lock, then one suspend. Enter and leave gaming twice. One daemon each time.

## Licences

| Piece | SPDX |
|---|---|
| This note, and Omarchy | `MIT` |
| powerbuttond v4.2 | `BSD-2-Clause` |
| HHD power plugin | `LGPL-2.1-only` |
| InputPlumber | `GPL-3.0-or-later` |
| ShadowBlip/steam-powerbuttond | GitHub field `GPL-3.0`. LICENSE file not opened |
| CachyOS Handheld logind snippet | No licence file. Left uncopied |
| Steam client | Proprietary |
