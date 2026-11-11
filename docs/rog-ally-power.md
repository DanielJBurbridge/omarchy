# Original ROG Ally power integration

This is opt-in source support for ASUS RC71L only, behind `omarchy-hw-rog-ally`. It does not establish installed or physical acceptance. Ordinary laptops/desktops keep power-profiles-daemon (PPD). No feature worker installs, restarts or changes the live Ally: the integration/rollout owner performs the steps below serially.

## Backend and package boundary

Use **one SteamOS Manager**, not PowerStation, HHD/Adjustor, asusctl or custom sysfs writers alongside it. The checked [CachyOS standalone recipe](https://github.com/CachyOS/CachyOS-PKGBUILDS/blob/master/handheld/steamos-manager/PKGBUILD) packages `steamos-manager 26.4.1-3`, MIT, from upstream tag `v26.4.1`, commit `a0d399defebd60db30ba38325d9cf47dbda49bee`. Review the complete recipe, dependency closure and patches when building the standalone package for Omarchy. Do not add CachyOS repositories, install `cachyos-handheld` wholesale, install `jupiter-hw-support`, or copy their login/autologin policy.

The [RC71L device profile](https://github.com/evlaV/steamos-manager/blob/a0d399defebd60db30ba38325d9cf47dbda49bee/data/devices/rog-ally-series.toml) selects `asus-wmi` platform profiles and `asus-armoury` firmware attributes. The live audit's existing 30/43/53 W readings do **not** prove this newer firmware-attribute API exists. A missing interface is a concrete kernel/backend limit to report, not permission to fall back to another writer or replace the kernel.

Package-owned fixed-system files come from the reviewed standalone Manager package: `/usr/lib/steamos-manager`, its `steamosctl` client, device/platform data, system and user `steamos-manager.service`, and D-Bus activation/policy files. Review `pacman -Ql steamos-manager` before installation and preserve package ownership; `omarchy dev link` does not deploy them. The power client adds no system D-Bus or Polkit permissions. Upstream Manager's system policy is broad and must be included in the package review. Omarchy calls only its documented public **session** API, never the private RootManager API.

The existing Omarchy package must include `bin/omarchy-power-ally`, `bin/omarchy-setup-rog-ally-power`, `default/handheld/power.py`, `default/handheld/omarchy-ally-power.service`, the changed profile helpers and `shell/plugins/panels/power/`. Its existing recursive source packaging should cover these paths; verify the built package manifest before rollout. Python/PyGObject (`python-gobject`) is already in Omarchy's base package set. The user unit is copied from the packaged default during explicit setup, with no new fixed-system override.

## Public API and capability contract

Bus name `com.steampowered.SteamOSManager1`, object `/com/steampowered/SteamOSManager1`, session bus. [Pinned interface specification](https://github.com/evlaV/steamos-manager/blob/a0d399defebd60db30ba38325d9cf47dbda49bee/data/interfaces/com.steampowered.SteamOSManager1.xml).

| Control | Interface suffix and property | Behaviour |
| --- | --- | --- |
| Platform profile | `PerformanceProfile1.PerformanceProfile` (`s`) | Enumerate `AvailablePerformanceProfiles`; no invented quiet/balanced choices |
| Sustained APU limit | `TdpLimit1.TdpLimit` (`u`, watts) | Read `TdpLimitMin/Max`; intersect firmware range with conservative 25 W battery / 30 W AC ceilings |
| CPU boost | `CpuBoost1.CpuBoostState` (`u`) | 0 disabled, 1 enabled |
| CPU governor | `CpuScaling1.CpuScalingGovernor` (`s`) | Enumerate `AvailableCpuScalingGovernors` |
| GPU mode/clock | `GpuPerformanceLevel1.GpuPerformanceLevel` (`s`), `ManualGpuClock` (`u`, MHz) | Enumerate levels and min/max; explicit manual mode required before clock writes |
| Charge threshold | `BatteryChargeLimit1.MaxChargeLevel` (`i`, percent) | Honour `SuggestedMinimumLimit`; `default` maps to public sentinel -1; restore the recorded original percentage or default |

Probe each getter, not only interface presence. `TdpLimit1` is registered asynchronously only in the `performance` platform profile; it disappears in quiet/balanced. The panel explains that prerequisite. Select performance explicitly before custom watts. Selecting it does not guarantee the kernel exposes a usable TDP range.

Manager's [firmware-attribute implementation](https://github.com/evlaV/steamos-manager/blob/a0d399defebd60db30ba38325d9cf47dbda49bee/steamos-manager/src/power.rs) writes SPL and sets SPPT/FPPT to at least their firmware minimums. A 15 W sustained setting therefore does not promise a 15 W instantaneous package ceiling. There is no independent burst-watts control in this API. CPU frequency limits, SMT/core control, RC71L fan curves, thermal telemetry and battery bypass are unavailable; firmware keeps fan/thermal safety. Manager's generic BIOS/OS fan-service switch is not an Ally fan curve API. A charge threshold is not battery bypass.

`omarchy-power-ally status` returns JSON with `backend`, `configured`, `source` (`ac`/`battery`), `controls` keyed by `profile`, `tdp`, `boost`, `governor`, `gpu-level`, `gpu-clock`, `charge`, and `unavailable` reasons. Each control has `available`, then `value`, `choices` or `min`/`max`, or an explicit `reason`. `conflicts` lists active competing services. Top-level `error` marks unavailable state/failed policy restoration; consumers must not reuse stale values. Existing UPower battery watts in the panel remain battery flow, not APU telemetry.

## Installation and rollback (rollout owner only)

1. Record package versions, kernel/BIOS, `systemctl status power-profiles-daemon steamos-manager`, corresponding user-unit states, `omarchy-power-ally status`, and read-only `asus-armoury` capability evidence. Back up user configuration and preserve package rollback artifacts. Do not publish serials or personal information.
2. Build/review/install the standalone Manager package and updated Omarchy package through the integration owner's normal signed/package process. Check that neither brings a login policy, kernel change or extra power writer. A missing package artifact is a deployment blocker; this source does not fetch or execute an AUR recipe automatically.
3. From a visible terminal run `omarchy-setup-rog-ally-power --configure-reviewed-package`. This validates the exact reviewed package identity, refuses active competing writers, records service states, masks/stops PPD, enables system/user Manager, captures original readable settings and seeds separate AC/DC preferences. It then enables `omarchy-ally-power.service` for this user. No autologin, login-manager or power-button policy changes occur here. If setup partially fails, retain its receipt and run rollback rather than manually stacking writers.
4. Inspect `omarchy-power-ally status` and `journalctl --user -u omarchy-ally-power.service`. Open the existing desktop panel with `omarchy-shell shell toggle omarchy.power`. Capture and inspect the running UI for clipping, focus, correct readback and unavailable state.
5. Roll back with `omarchy-setup-rog-ally-power --rollback` from a terminal. It stops the policy listener, restores original readable settings through Manager and verifies readback before removing the opt-in marker, then restores the prior service/PPD states. If hardware restoration fails it stops with the receipt and marker retained; resolve that failure before restoring a different writer. Receipt/preferences remain under `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/ally-power/`. Restore the prior reviewed Omarchy package if source rollback is also needed. Do not remove Manager while other sessions depend on it.

Setup is repeatable without replacing the first rollback receipt or existing preferences. The unit uses the installed `/usr/bin/omarchy-power-ally`; a source link alone is insufficient. The original receipt is tied to the first takeover; archive it before deliberately taking a new baseline after a later rollback.

Takeover disables PPD globally on this RC71L; power preferences and the event listener belong to the configured user. Configure another user explicitly before expecting their desktop to restore power preferences. Rollback of an original AC limit above 25 W requires reconnecting AC; it fails safely on battery and retains the receipt/marker rather than bypassing the battery ceiling.

## Policy, controls and session contracts

`omarchy-power-ally set tdp 15` changes supported watts and saves only after actual backend readback matches. Invalid, nonfinite, fractional, out-of-range or unknown enum requests fail before the setter. A successful queued D-Bus setter alone is not success. All changes are serialised. CPU/GPU writes use the same backend and shared APU power budget; enabling boost/manual clocks does not increase the sustained-watts ceiling. Do not run GameMode CPU/governor adjustments alongside this owner.

`omarchy-ally-power.service` is a nonprivileged user event listener. It reacts to UPower `OnBattery`, logind `PrepareForSleep(false)` and Manager name-owner recovery. It applies the current source's saved profile first, then other controls, and reads back each change. Policy restoration clamps saved watts to the current capability/source ceiling. A missing power-source read is an error, never a guess that AC is connected. Manager property/interface signals update the panel's watched status file; there is no periodic or privileged polling. PPD helper writes are bypassed only for the explicit RC71L opt-in; the event listener is the sole AC/DC/resume policy owner. It does not initiate lock, suspend or shutdown; RELIABILITY owns those routes.

The panel offers 48-pixel touch targets, profile choices, 10/15/25 W presets within the reported range, ±1 W custom steps, and capability-aware CPU/GPU/charge choices. Up/down selects a control, left/right selects an action, Return/Space applies. Controller-to-key mappings must be exercised through INPUT; source key handlers do not prove physical controller acceptance.

`omarchy-power-ally run 15 -- GAME COMMAND` is an optional per-game wrapper. It snapshots readable settings, applies performance/15 W, retains a single locked override for source/resume events while the game runs, and restores the previous settings plus current AC/DC preferences after normal exit or handled termination. A second wrapper is rejected. SIGKILL cannot execute cleanup; its unlocked stale override is ignored and the next restore/login/resume reapplies source preferences. Use it as `omarchy-power-ally run 15 -- %command%` in Steam launch options. Avoid combining it with Steam's own per-game power policy; select one policy owner for a game.

Desktop route is `omarchy-shell shell toggle omarchy.power`. The Hyprland panel does not cross into Gamescope. Gaming uses Steam's QAM and the **same Manager session API**, with the input Guide/South proposal provisional until exercised. SESSION must start the user Manager and policy units inside its authenticated gaming session (it does not start `graphical-session.target`), and stop only the units it started when handing back; call the exact commands below once, not once per Steam child:

```bash
systemctl --user start steamos-manager.service omarchy-ally-power.service
# On session teardown, only if these were not active before entry:
systemctl --user stop omarchy-ally-power.service steamos-manager.service
```

The setup's opt-in marker must gate that power-policy unit. No shortcut, Steam QAM watt slider, gaming lifecycle or resume behaviour is physically accepted until rollout evidence establishes it. OGUI is not installed by this increment; if Steam QAM does not use Manager on this device, gaming overlay acceptance remains blocked and must be reported, not replaced with a desktop panel claim.

## Focused checks and physical acceptance

`bash test/shell.d/power-test.sh >/tmp/ally-power-test.log 2>&1` covers range validation, battery ceiling, missing capabilities, readback mismatch, no preference save on failure, distinct AC/DC state, resume policy application, stale TDP removal and writer conflicts. Run the existing `powerprofiles-set-test.sh`, `power-no-battery-test.sh` and CLI metadata suite for the changed integration paths. These software checks do not establish hardware support or visual/controller acceptance.

The rollout owner must record package versions and actual readback for performance → 15 W → another supported value → original, an out-of-range rejection, AC unplug/replug, boost/governor/manual-GPU/charge restore where exposed, game exit/failure restore, and lock/suspend/resume through RELIABILITY's route. Capture the desktop panel and actual gaming QAM with supported watts and honest unavailable states, then verify touch and controller navigation. Compare saved settings with actual Manager readback after resume. Check original fan behaviour, temperatures with an independently labelled read-only sensor tool, and battery flow under load; static D-Bus tests cannot prove thermal or battery outcomes. Finish by exercising rollback and verifying normal PPD behaviour returns without a second active writer.
