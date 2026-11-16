# TDP and AC/battery limits on the RC71L

16 Nov 2026. Brief for gap 4 in [feature-parity-audit.md](feature-parity-audit.md): AC and battery watts, a charge limit, and a reapply after resume, so Steam's Quick Access slider works under gamescope. Docs only. Nothing here was run on the device.

Standing decision, [tdp-decision-review.md](../tdp-decision-review.md): do not ship stock or forked steamos-manager. Build backlog #10 (root writer) and #11 (session-bus shim for the public SteamOSManager1 API). Reuse existing code, in the Omarchy shape: shell and units, `omarchy-*` names, opt-in on this hardware. Goal 1 is a working slider. Goal 2 is a later core fit. The spike ceiling in [PR #33](https://github.com/DanielJBurbridge/omarchy/pull/33) still bounds the write. Port the MIT write, then clamp it. Leave the spike's ratio in the spike.

[`bin/omarchy-session-start`](../../../bin/omarchy-session-start) already copies [`10-gaming-session.conf`](../../../default/systemd/user/omarchy-ally-tdp-shim.service.d/10-gaming-session.conf) and restarts `omarchy-ally-tdp-shim.service` only when that unit exists, before `gamescope`. The unit is not in the tree. [`bin/omarchy-gaming-steam`](../../../bin/omarchy-gaming-steam) runs `steam -steamos3 -steampal -steamdeck -gamepadui` and sets no fake Deck capability flags.

## (a) Kernel interfaces

Write the firmware-attributes class. `asus-armoury` exposes `/sys/class/firmware-attributes/asus-armoury/attributes/<name>/` with `current_value`, `default_value`, `min_value`, `max_value` and `scalar_increment` of `1`. A store outside min/max returns `-EINVAL`. Names: `ppt_pl1_spl`, `ppt_pl2_sppt`, `ppt_pl3_fppt`, `ppt_apu_sppt`, `ppt_platform_sppt`. Max 0 is not a valid limit. Sources: [asus-armoury.c](https://github.com/torvalds/linux/blob/v7.2/drivers/platform/x86/asus-armoury.c) and [asus-armoury.h](https://github.com/torvalds/linux/blob/v7.2/drivers/platform/x86/asus-armoury.h) at tag `v7.2`. The RC71 block is unchanged on master `aebb72744764` (Linux 7.4-rc3, 15 Nov 2026).

`DMI_MATCH(DMI_BOARD_NAME, "RC71")` is a substring (`strstr` in [dmi_scan.c](https://github.com/torvalds/linux/blob/v7.2/drivers/firmware/dmi_scan.c)), so board `RC71L` matches.

| | SPL min/def/max | SPPT | FPPT |
|---|---|---|---|
| AC | 7 / none / 30 | 15 / none / 43 | 15 / none / 53 |
| DC | 7 / 15 / 25 | 15 / 20 / 30 | 15 / 25 / 35 |

`ppt_apu_sppt` and `ppt_platform_sppt` stay 0. The deprecated platform ABI is `ppt_pl1_spl`, `ppt_pl2_sppt`, `ppt_fppt` (not `ppt_pl3_fppt`), `ppt_apu_sppt`, `ppt_platform_sppt`, min 5 and max 250 or 130 ([sysfs-platform-asus-wmi](https://github.com/torvalds/linux/blob/v7.2/Documentation/ABI/testing/sysfs-platform-asus-wmi)). Do not write those files.

`get_current_tunables()` picks AC or DC with `power_supply_is_system_supplied()`. v7.2 has no power-supply notifier. Whether the EC swaps the live limit is **unverified**.

The dump's kernel is `7.2.15-2-omarchy` ([ally-hw-dump.md](ally-hw-dump.md)). There is no `v7.2.15` tag on torvalds/linux. The spike's AC run on that kernel read mins 7/15/15 and currents 30/43/53. `apu` and `platform` absence, and the non-Extreme Z1, are **unverified**.

`asusd` and `power-profiles-daemon` were both running and race on `platform_profile` and EPP ([Asusctl](https://wiki.archlinux.org/title/Asusctl)). That page does not say asusd writes PPT. An unfiled RC73XA draft says a profile change drops PPT enforcement while sysfs stays stale ([hpd report](https://github.com/CiroDev-Git/hpd-handheld-power-daemon/blob/main/docs/dev/UPSTREAM-ASUS-PPT-PROFILE-REPORT.md), `GPL-3.0-or-later`). **Unverified** on RC71L. Profile names are `quiet`, `balanced`, `performance` ([asus-wmi.c](https://github.com/torvalds/linux/blob/v7.2/drivers/platform/x86/asus-wmi.c)).

## (b) ryzenadj

[RyzenAdj](https://github.com/FlyGoat/RyzenAdj) is SPDX `LGPL-3.0` ([LICENSE](https://github.com/FlyGoat/RyzenAdj/blob/master/LICENSE)). It needs root, tries `ryzen_smu` then `/dev/mem`, and the README says device power management overwrites values. [#255](https://github.com/FlyGoat/RyzenAdj/issues/255): a Z1 Extreme Ally could set a limit on v0.13.0 while the PM table read failed. [#256](https://github.com/FlyGoat/RyzenAdj/pull/256) added Phoenix table reads (merged 15 Jul 2023). Prefer the kernel attributes. RyzenAdj has no RC71 AC/DC table.

## (c) What the slider expects

Session bus, `com.steampowered.SteamOSManager1`, object `/com/steampowered/SteamOSManager1`. The system bus is private. The client checks features at startup; a missing property means unsupported. Pin: [evlaV/steamos-manager](https://github.com/evlaV/steamos-manager) `85fbd8f97719277c4df326cf27e4803d4cb31ef9` (3 Mar 2026), [README](https://github.com/evlaV/steamos-manager/blob/85fbd8f97719277c4df326cf27e4803d4cb31ef9/README.md) and [XML](https://github.com/evlaV/steamos-manager/blob/85fbd8f97719277c4df326cf27e4803d4cb31ef9/data/interfaces/com.steampowered.SteamOSManager1.xml). SPDX `MIT` (Collabora, Valve, Igalia). GitLab's [Ally toml](https://gitlab.steamos.cloud/holo/steamos-manager/-/raw/master/data/devices/rog-ally-series.toml) matched that pin on 16 Nov 2026. [hhd-dev/steamos-manager-hhd](https://github.com/hhd-dev/steamos-manager-hhd) is an older MIT copy. GitLab `power.rs` was not re-diffed.

No step property. `TdpLimit1`: `TdpLimit` `u` rw, min and max `u` r. `PerformanceProfile1`: available profiles `as` r, profile `s` rw, suggested default `s` r. `GpuPerformanceLevel1`: levels `as` r, level `s` rw, `ManualGpuClock` `u` rw plus min and max. `Manager2.DeviceModel` is `(ss)` r. `BatteryChargeLimit1`: `MaxChargeLevel` `i` rw, `SuggestedMinimumLimit` `i` r.

The Ally toml matches `ASUSTeK COMPUTER INC.` and `RC71L`, method `firmware_attribute` on `asus-armoury`, active only when the `asus-wmi` profile is `performance`. `FirmwareAttributeLimitManager::set_tdp_limit` in [power.rs](https://github.com/evlaV/steamos-manager/blob/85fbd8f97719277c4df326cf27e4803d4cb31ef9/steamos-manager/src/power.rs) reads SPL `current_value`, then writes SPL, SPPT `max(limit, sppt_min)`, FPPT `max(limit, fppt_min)`. That is the write to port.

Steam is proprietary. A Deck-identity check beyond the four flags is **unverified**. CachyOS execs the same four ([steam-launcher](https://github.com/CachyOS/gamescope-session/blob/f151b891b3936f1a90ae3c7a659adf2298f484ea/usr/lib/steamos/steam-launcher)). Own the bus name before Steam starts.

## (d) Bazzite and CachyOS

Bazzite (`Apache-2.0`, `e13f4fdade42f9de66567b3b60f589860feb9781`) sends `ROG Ally*` to steamos-manager, not PowerStation ([steamos-manager-hardware](https://github.com/ublue-os/bazzite/blob/e13f4fdade42f9de66567b3b60f589860feb9781/system_files/desktop/shared/usr/libexec/hwsupport/steamos-manager-hardware), [powerstation-hardware](https://github.com/ublue-os/bazzite/blob/e13f4fdade42f9de66567b3b60f589860feb9781/system_files/desktop/shared/usr/libexec/hwsupport/powerstation-hardware)). One TDP controller ([wiki](https://docs.bazzite.gg/Handheld_and_HTPC_edition/Handheld_Wiki/)). HHD was removed in Deck 44 ([announcement](https://universal-blue.discourse.group/t/bazzites-biggest-update-deck-44-has-launched-happy-birthday-to-universal-blue/12373)).

CachyOS `[handheld]` installs `steamos-manager inputplumber steamos-powerbuttond`. `[handheld.rog-ally]` matches `RC71L` and links audio only ([profiles.toml](https://github.com/CachyOS/chwd/blob/b5278a3aa999c5ea243a67e4416257406a5fe57c/profiles/pci/handhelds/profiles.toml), GPL-3.0-only). They ship stock Manager. We do not.

## (e) Resume, AC, charge limit

[SteamOS #2790](https://github.com/ValveSoftware/SteamOS/issues/2790) (open): an RC71L on 3.8.x wakes near 4–7 W, and the slider does not recover it. [Bazzite #5904](https://github.com/ublue-os/bazzite/pull/5904) was closed unmerged. Do not copy it.

evlaV writes `charge_control_end_threshold` for `acpi_sb`, suggested minimum 10. The kernel attribute is 0–100 percent ([sysfs-class-power](https://github.com/torvalds/linux/blob/v7.2/Documentation/ABI/testing/sysfs-class-power)). The dump does not mention the file. QAM visibility here is **unverified**. Leave `BatteryChargeLimit1` out of #11. The unit is s2idle only, MCU below 319 ([ally-hw-dump.md](ally-hw-dump.md)). Update the MCU before blaming the writer.

## #10 and #11

Opt-in package. The writer checks board `RC71L` itself and exits if the three attributes are missing. Laptops keep ppd. Mask ppd only when the Ally gate, the gaming session and this writer are all installed.

**#10.** `/usr/bin/omarchy-ally-tdp-apply`. Polkit `org.omarchy.ally.set-tdp` (`allow_active=yes`, `allow_inactive=no`, `allow_any=no`) via `pkexec`. No sudoers `NOPASSWD`. Verbs `--show`, `--snapshot`, `--set WATTS`, `--reassert`, canonical whole watts. Port the MIT three-write, then clamp: SPL floor 7, battery tuple at most 20/20/25, AC at most 30. `--set 5` stores 5 and writes SPL 7. `--reassert` keeps the stored request. Unplug after 30 W AC stays inside 20/20/25 and still remembers 30. Stock mins make that write 20/20/20 on battery and 30/30/30 on AC. Keep SPL ≤ SPPT ≤ FPPT after every store and read them back. Refuse while ppd, asusd, hhd, tuned, gamemoded or powerstation is active. AC is `Mains` or `USB` with `online` 1. Do not write `platform_profile` or the deprecated files.

**#11.** User unit `omarchy-ally-tdp-shim.service`, `PartOf=` and `WantedBy=` `graphical-session.target` and `omarchy-gaming-session.target`. Claim the name before Steam. Speak `TdpLimit1` from the vendored XML. `PerformanceProfile1` advertises only `performance` and does not write the profile. `GpuPerformanceLevel1` advertises only `auto`; `ManualGpuClock` returns `NotSupported`. `DeviceModel` is `("rog_ally", "RC71L")`. No factory-reset, storage, Wi-Fi, session or BIOS methods. `PropertiesChanged` only after readback. Do not install evlaV's user service file: it sets `SystemdService=steamos-manager.service`.

**Resume and AC.** `omarchy-ally-tdp-resume.service` on the sleep targets, and udev `99-omarchy-ally-tdp.rules` (`power_supply` change, `PROGRAM` `omarchy-hw-rog-ally`, `SYSTEMD_WANTS` `omarchy-ally-tdp-source.service`). Both `--reassert`.

## Code to reuse

| Piece | Pin | SPDX | What to do |
|---|---|---|---|
| Interface XML | evlaV `85fbd8f`, `data/interfaces/com.steampowered.SteamOSManager1.xml` | MIT | Vendor with the copyright and permission notice, in the handheld package. #11 introspects against this file. |
| TDP write | same pin, `steamos-manager/src/power.rs`, `FirmwareAttributeLimitManager` | MIT | Port the three `current_value` writes into `omarchy-ally-tdp-apply`. Keep the notice beside the port. Do not depend on the package. |
| Ally device toml | same pin, `data/devices/rog-ally-series.toml` | MIT | Read it. The shell hard-codes RC71L and `asus-armoury`. Do not load upstream toml. |
| User D-Bus service | same pin, `data/user/com.steampowered.SteamOSManager1.service` | MIT | Do not vendor. `Exec=/bin/false` and it activates `steamos-manager.service`. |
| PowerStation Asus path | `9799ca99cc2bc87aaeb66f63f326eae8c2eb1aa5`, `src/performance/gpu/asus/asus_wmi.rs` | `GPL-3.0` | Do not vendor or depend. `set_boost` uses `ppt_platform_sppt`, max 0 on this board. |
| HHD Asus TDP | `180f0cd8515787789ce82a8d8a116076c36c98a6`, `src/adjustor/drivers/asus/__init__.py` `set_tdp` | `LGPL-2.1` | Do not vendor. Writes deprecated `asus-nb-wmi` `ppt_*`. |
| RyzenAdj | `5775fc3e6dbb25c7030ee2d100a1bdd6e8bf2d0a` | `LGPL-3.0` | Do not vendor and do not depend. |
| Bazzite hardware scripts | `e13f4fda`, the two `hwsupport` scripts above | `Apache-2.0` | Idea only. `omarchy-hw-rog-ally` already matches the board. |
| CachyOS launcher | `f151b891`, `usr/lib/steamos/steam-launcher` | No licence file in that tree | The four flags are already in `omarchy-gaming-steam`. Do not copy the script. |
| chwd profile | `b5278a3a`, `profiles/pci/handhelds/profiles.toml` | GPL-3.0-only | Do not copy. It is how CachyOS installs stock Manager. |

## Omarchy core fit

Goal 1 is the slider moving the three attributes on an RC71L, using the restart the session already performs. Goal 2 is the same commands in core later: a shell binary, two units, one polkit file, one udev rule, names `omarchy-ally-tdp-*`, installed only with the Ally package. No new language runtime, no daemon on laptops, no GPL or LGPL source in the MIT tree.

## On-device test

Read package power under load. Battery, unplug, resume and the slider are still open.

1. QAM slider once the shim owns the name. Max 20 on battery and 30 on AC, including after desktop-to-gaming.
2. Battery 15 writes 15/15/15. A request of 25 stays inside 20/20/25. AC 30 writes 30/30/30, inside 30/43/53.
3. Unplug at 30 W with the shim stopped: inside 20/20/25, stored request still 30. Plug in restores the AC write.
4. Suspend and resume: the limit holds under load. If it sticks near 4–7 W, record the MCU first.
5. Afterwards `powerprofilesctl` works, and gaming had one PPT writer.
6. A non-RC71L, a missing armoury class, and an inactive or remote caller write nothing.

## Licences

Vendor only the MIT XML and the ported write, with the copyright and permission notice. steamos-manager `MIT`. RyzenAdj `LGPL-3.0`. PowerStation `GPL-3.0`. HHD `LGPL-2.1`. Bazzite `Apache-2.0`. chwd `GPL-3.0-only`. The hpd note `GPL-3.0-or-later`. The kernel is GPL-2.0. Omarchy is MIT.
