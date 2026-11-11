# Original ROG Ally power integration

This is experimental source support for ASUS RC71L only, behind `omarchy-hw-rog-ally`. Activation is blocked by the package review below. It does not establish installed or physical acceptance. Ordinary laptops/desktops keep power-profiles-daemon (PPD). No feature worker installs, restarts or changes the live Ally.

## Package review hold

**Do not install unchanged `steamos-manager 26.4.1-3`, even as an inactive prerequisite.** The completed independent source/recipe review rejected it for this integration; its install/upgrade scriptlet enables a root service for the next boot. Client guards and a matching version string do not establish package approval. No remediated package, binary artifact, dependency closure or RC71L capability probe has been accepted.

The reviewed immutable CachyOS recipe is commit `ab15ca2048159897015eb0ac90eac8c756b86e7a`, PKGBUILD SHA256 `4cc9005e13cddf708f86bec2ad2dfb9effe1d249de65f5b95d4b6e85c999e403`, with upstream commit `a0d399defebd60db30ba38325d9cf47dbda49bee`. The review found these blockers:

- Root daemon startup/hotplug manages InputPlumber targets and enables a PlayStation inhibitor by default, conflicting with INPUT ownership.
- Broad RootManager system-bus access lacks caller/session/Polkit authorisation for privileged setters, including login policy. Restricting the Omarchy client cannot protect direct calls.
- The mandatory networking helper is absent from the configured repositories and carries out-of-scope privileged Wi-Fi/NetworkManager behaviour. Removing its dependency requires removing both root and user Wi-Fi paths first.
- Activation scriptlets and login-manager payload prevent safe inactive installation and can contaminate a setup-time ownership receipt.
- Public sustained-limit readback cannot prove restoration of the sequentially changed SPL/SPPT/FPPT limits. All three require typed capture, bounded application, verified readback and restoration before takeover can be accepted.

`omarchy-setup-rog-ally-power --configure-reviewed-package` now refuses before package queries, service changes or state writes. The existing `--rollback` action is retained for legacy receipts, but does not prove complete three-limit restoration or service ownership before package installation. Keep such a receipt and resolve its limitations through a reviewed recovery plan before changing owners.

POWER owns a bounded prerequisite input-management opt-out patch, immutable source/patch/Cargo.lock manifest and power-only interface/authorisation/transaction design. That opt-out alone is not a security or power-only fix. `omarchy-steamos-manager-power` is a reserved future identity only; no version or artifact is approved. Full builds and deployment wait for an agreed remediated design. The remaining sections document the experimental client and earlier proposed API, not an approved installation procedure.

## Backend and package boundary

The experimental client targets one SteamOS Manager power owner. PowerStation, HHD/Adjustor, asusctl or custom sysfs writers must not run alongside it. The rejected [CachyOS standalone recipe](https://github.com/CachyOS/CachyOS-PKGBUILDS/blob/ab15ca2048159897015eb0ac90eac8c756b86e7a/handheld/steamos-manager/PKGBUILD) packages `steamos-manager 26.4.1-3`, MIT, from upstream tag `v26.4.1`, commit `a0d399defebd60db30ba38325d9cf47dbda49bee`. Do not build/install it for this rollout. Do not add CachyOS repositories, install `cachyos-handheld` wholesale, install `jupiter-hw-support`, or copy their login/autologin policy.

The [RC71L device profile](https://github.com/evlaV/steamos-manager/blob/a0d399defebd60db30ba38325d9cf47dbda49bee/data/devices/rog-ally-series.toml) selects `asus-wmi` platform profiles and `asus-armoury` firmware attributes. The live audit's existing 30/43/53 W readings do **not** prove this newer firmware-attribute API exists. A missing interface is a concrete kernel/backend limit to report, not permission to fall back to another writer or replace the kernel.

The rejected package's predicted fixed-system payload includes `/usr/lib/steamos-manager`, its `steamosctl` client, device/platform data, system and user `steamos-manager.service`, and D-Bus activation/policy files. This is source-manifest evidence, not an inspected binary archive. A future remediated package needs its own reviewed manifest; `omarchy dev link` cannot deploy fixed-system files. The power client adds no system D-Bus or Polkit permissions and calls the documented public **session** API. That client choice does not remedy unauthorised direct RootManager access.

The experimental Omarchy runtime paths are `bin/omarchy-power-ally`, `bin/omarchy-setup-rog-ally-power`, `default/handheld/power.py`, `default/handheld/omarchy-ally-power.service`, the changed profile helpers and `shell/plugins/panels/power/`. Their presence is not activation clearance. Python/PyGObject (`python-gobject`) is already in Omarchy's base package set. The held setup does not copy or enable the policy unit.

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

## Installation blocked; legacy rollback

There is no approved installation or takeover procedure. Keep PPD and the current input/session owners unchanged. A future procedure must resolve the package blockers, inspect the actual remediated archive/dependencies, record service ownership before any install script can change it, capture every touched hardware limit, and obtain the sole rollout owner's RC71L capability evidence. Do not infer approval from the experimental API tests below.

For a previously recorded setup only, `omarchy-setup-rog-ally-power --rollback` stops the policy listener and attempts restoration of original publicly readable settings before returning recorded service/PPD states. Receipt/preferences remain under `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/ally-power/`. A failed restoration retains the receipt/marker; do not stack another writer. Reconnect AC for an original recorded limit above 25 W.

This legacy route does not capture SPPT/FPPT individually and may have recorded Manager's already-enabled state after its installation scriptlet. Successful public readback therefore does not prove full hardware or pre-install service restoration. Preserve the receipt/package backups and use a reviewed recovery plan for those gaps. Do not remove a Manager package while another session depends on it, or restore the rejected activation code as a rollback of this guard.

## Policy, controls and session contracts

`omarchy-power-ally set tdp 15` changes supported watts and saves only after actual backend readback matches. Invalid, nonfinite, fractional, out-of-range or unknown enum requests fail before the setter. A successful queued D-Bus setter alone is not success. All changes are serialised. CPU/GPU writes use the same backend and shared APU power budget; enabling boost/manual clocks does not increase the sustained-watts ceiling. Do not run GameMode CPU/governor adjustments alongside this owner.

`set --source ac|battery` applies the setting now and saves the explicitly requested source's preference, even when the other source is connected. The default `autodetect` samples the current source. `restore --source ac|battery` applies that source's saved settings, bounded for the actually connected source. The compatibility command `omarchy-powerprofiles-set` preserves these explicit-source semantics and validates its action before dispatching. Every performance-profile selection/restoration also probes and bounds actual sustained watts, including profile-only preferences and an already-active performance profile; unavailable TDP or failed safety readback is an explicit error, never a successful profile preference save. Repeated restores avoid setters when values already match.

`omarchy-ally-power.service` is a nonprivileged user event listener. It reacts to UPower `OnBattery`, logind `PrepareForSleep(false)` and Manager name-owner recovery. It applies the current source's saved profile first, then other controls, and reads back each change. Policy restoration clamps saved watts to the current capability/source ceiling. A missing power-source read is an error, never a guess that AC is connected. Manager property/interface signals update the panel's watched status file; there is no periodic or privileged polling. PPD helper writes are bypassed only for the explicit RC71L opt-in; the event listener is the sole AC/DC/resume policy owner. It does not initiate lock, suspend or shutdown; RELIABILITY owns those routes.

The panel offers 48-pixel touch targets, profile choices, 10/15/25 W presets within the reported range, ±1 W custom steps, and capability-aware CPU/GPU/charge choices. Up/down selects a control, left/right selects an action, Return/Space applies. Controller-to-key mappings must be exercised through INPUT; source key handlers do not prove physical controller acceptance.

`omarchy-power-ally run 15 -- GAME COMMAND` is an optional per-game wrapper. It snapshots readable settings, applies performance/15 W, retains a single locked override for source/resume events while the game runs, and restores the previous settings plus current AC/DC preferences after normal exit or handled termination. A second wrapper is rejected. SIGKILL cannot execute cleanup; its unlocked stale override is ignored and the next restore/login/resume reapplies source preferences. Use it as `omarchy-power-ally run 15 -- %command%` in Steam launch options. Avoid combining it with Steam's own per-game power policy; select one policy owner for a game.

TERM/INT/HUP handling is installed before the first startup power mutation. A signal during the initial setters or child launch enters the same restoration path; repeated handled signals during cleanup do not interrupt it. Original signal handlers are reinstated after cleanup, including failed launch and restoration failures.

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
