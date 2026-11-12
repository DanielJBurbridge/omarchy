# ROG Ally RC71L TDP spike

What this spike checked, and what it did not. The prototype is a session-bus shim plus one root writer for the original Ally (board RC71L, Z1 and Z1 Extreme). It is gated on `omarchy-hw-rog-ally`. Laptops, desktops, the Ally X, and other ROG boards are unchanged.

This is not a merge of `feat/ally-power-20261111`. That branch's SteamOS Manager client (`default/handheld/power.py`, `omarchy-power-ally`, `omarchy-setup-rog-ally-power`) stays rejected. Stock `steamos-manager` and a fork of it stay rejected for the reasons in the 12 Nov red-team review (root daemon, private system-bus API, install-time activation, InputPlumber and SDDM side effects). Nothing here vendors Valve's daemon or its XML.

## Can Steam's slider drive this shim?

Realistically, yes. Demonstrated on this Ally, no.

Valve's own README for SteamOS Manager says the D-Bus API exists so that Steam's TDP controls can run on any distro that implements it, and that a missing property means the feature is unsupported. Steam probes interfaces when it starts, so the name has to be owned before `gamepadui` launches. The interface Steam still publishes on `main` (`2c51fc82`, 10 Nov 2026) is `com.steampowered.SteamOSManager1.TdpLimit1`. There is no `TdpLimit2` in that XML.

The slider lives in Steam's Quick Access Menu, which exists only in the `gamepadui` client (`-steamos3 -steampal -steamdeck -gamepadui`). `gamescope` and ChimeraOS `gamescope-session-plus` do not speak TDP. The session script starts Steam; Steam then talks to whoever owns the session-bus name.

How that call is known:

- README, lines 8–10 and 61–81: partial implementations are allowed; property absence means unsupported; method signatures stay binary compatible; the client may ignore an older interface version and follow the one in stable SteamOS. The system-bus API is private and is not used here.
- The interface file on that commit: name `com.steampowered.SteamOSManager1`, object `/com/steampowered/SteamOSManager1`, properties `TdpLimit`, `TdpLimitMin`, `TdpLimitMax`, all type `u` (uint32 watts). Steam writes with `org.freedesktop.DBus.Properties.Set`.
- ValveSoftware/SteamOS#1994: a `dbus-monitor` trace of Steam setting `TdpLimit` to a uint32, then `GpuPerformanceLevel` to `"auto"`, then `ManualGpuClock`, and reading `PerformanceProfile`. A per-game commit that cannot see those properties can stop after the TDP write.
- Bazzite ONEXPLAYER discussion: the slider is shown when `TdpLimit1` is published and hidden when it is not.
- Bazzite and CachyOS Handheld ship stock `steamos-manager`, which is the same public name with Valve's root daemon behind it. That shows the UX, and it is the design this spike does not copy.
- Io's `io-steamos-manager` is a from-scratch Python owner of the same name and claims the QAM slider. That claim is third-party. This spike did not repeat it on hardware.
- `hhd-steamos-bridge` is a remote behind Valve's daemon, not a foreign owner of the session name.
- SimpleDeckyTDP and PowerControl draw their own UI and talk to ryzenadj or WMI. They are not this API.

The fixture test proves our process can own the name, answer `Get`/`Set`/`Introspect`, write the derived PPT tuple, emit `PropertiesChanged` only after readback, reject an out-of-range set, refuse `ManualGpuClock`, and re-apply on `PrepareForSleep(false)`. It does not prove that Steam draws the slider. If the slider is missing on the device, the fallback is a Decky plugin or the Omarchy panel, not Manager.

## Shim

User command `omarchy-ally-tdp-shim` (hidden). On a non-Ally it prints a line and exits 0 without taking the name.

When the owner gate is open (RC71L, handheld variant marker present, and `omarchy-ally-tdp-apply` installed) it takes `com.steampowered.SteamOSManager1` on the session bus with `do_not_queue` and without replacement. A second owner exits 1. `dbus-python` releases a well-known name when the `BusName` object is collected, so the shim keeps that object for the life of the process. If the gate is closed it prints a line and exits 0 without taking the name, the same as on a laptop.

| Interface | What the shim does |
|---|---|
| `TdpLimit1` | `TdpLimit` / `Min` / `Max` as uint32 watts. `Set` of `TdpLimit` calls the writer. A non-integer is `InvalidArgs`. |
| `PerformanceProfile1` | Advertises only `performance`. Setting that value is a no-op. `platform_profile` is not written. |
| `GpuPerformanceLevel1` | Advertises only `auto`. `ManualGpuClock` returns `NotSupported`. GPU clocks are not written. |
| `Manager2` | `ReloadConfig` re-reads sysfs. `DeviceModel` is `("rog_ally", "RC71L")`. |

`PropertiesChanged` is emitted after the writer has read the three PPT values back. `BatteryChargeLimit1` is left out; charge limit is a later task.

The shim calls `/usr/bin/omarchy-ally-tdp-apply` through `pkexec` for `--set` and `--reassert`. `--show` is unprivileged. In the fixture it calls the checkout binary and skips `pkexec`. On startup, if no request is stored or the live SPL is outside the advertised range, it stores a clamped `--set` of the current value so resume has something to re-apply. If that first write is refused, the name still comes up and later sets fail until the writer works.

## Writer

`omarchy-ally-tdp-apply` is the only PPT writer. Verbs are `--show`, `--snapshot`, `--set WATTS`, and `--reassert`. Anything else, including a generic write, is rejected and writes nothing. Watts must be a canonical whole number (`15` is accepted; `15.5`, `1e1`, `+15`, and `015` are not).

Root derives SPPT and FPPT. It does not accept them from the caller.

- Ratio anchor for each limit is its boot-captured `default_value` when that is greater than zero, otherwise `max_value`. The RC71 AC table in `asus-armoury` has no `*_def`, so the driver exposes default equal to max: SPL 30, SPPT 43, FPPT 53. The DC table is min/def/max SPL 7/15/25, SPPT 15/20/30, FPPT 15/25/35.
- Integer half-up: `(requested * anchor + spl_anchor / 2) / spl_anchor`.
- On battery, SPL, SPPT and FPPT stay at or under the boot-captured defaults for that source. The SPL cap is the highest integer at or under the SPL default whose derived bursts still fit those defaults. It is computed from the frozen defaults, not stored as 15 or 25. With the stock DC defaults that integer is 15 W, and the tuple is 15/20/25. A derived burst above a default is a rejection, not a silent clamp.
- On AC the existing ceiling stays: SPL is `min(30, live max, boot-captured max)`, and each burst is `min(live max, boot-captured max)`, lifted to the live min when the ratio falls short of it.
- A result with SPPT below SPL, or FPPT below SPPT, is rejected.
- The advertised maximum is the highest integer in that range that still plans.

Stock tuples the fixture checks:

| Request | Source | SPL, SPPT, FPPT |
|---|---|---|
| 15 | AC | 15, 22, 27 |
| 10 | AC | 10, 15, 18 (bursts lifted to the firmware floor) |
| 30 | AC | 30, 43, 53 |
| 15 | battery | 15, 20, 25 |
| 14 | battery | 14, 19, 23 |
| 16 or 25 on battery, 31 on AC | either | rejected, no write |

Going above the DC defaults (toward the DC maximums of 25/30/35) needs reviewer sign-off and a `power*_input` measurement under load. This spike does not do that.

The first time a source is seen in a boot, min/max/default are stored under `/run/omarchy/ally-tdp/ceilings.json` keyed by `/proc/sys/kernel/random/boot_id`. A later rise in the live default or max does not raise that boot's ceiling. A new boot id reads the firmware again. `--show` does not persist the snapshot; `--set`, `--snapshot`, and `--reassert` do.

`--set` rejects out of range and does not clamp. It stores `requested_spl` as the number the user asked for. `--reassert` reads that request, clamps it into the current source, and does not change `requested_spl`. Unplugging after a 30 W AC set therefore applies 15/20/25 and still remembers 30, so plugging back in restores 30/43/53.

Power source follows the same idea as `omarchy-power-present`. A `Mains` or `USB` supply with `online` 1 is AC. Those types present but offline means battery. No mains-type supply is a refusal; the writer does not guess AC.

The write is one transaction. It reads all three currents, writes SPL, then SPPT, then FPPT, and reads them back. Any failure restores the captured currents. Status is `rolled_back` when the restore matches, and `partial` when a restore write does not stick. JSON status goes to stdout. Errors go to stderr.

While `power-profiles-daemon.service` is active, `--set` and `--reassert` are refused. The fixture defaults that check to inactive. If `systemctl` is missing outside the fixture, the writer refuses rather than guessing.

## polkit and units

One action, `org.omarchy.ally.set-tdp`, in `default/handheld/org.omarchy.ally.set-tdp.policy`.

- `allow_any=no`, `allow_inactive=no`, `allow_active=yes`. An active local seat is not prompted, because the Quick Access Menu has nowhere to show a prompt.
- `org.freedesktop.policykit.exec.path` is `/usr/bin/omarchy-ally-tdp-apply` and nothing else. The policy does not name a sysfs path.
- pkexec annotations cannot express "argv1 is one of these verbs", so the binary is the allowlist. Root still checks the DMI gate, the watt string, the caps, and the firmware ceiling.

pkexec clears the environment. The apply wrapper uses `$OMARCHY_PATH` when that tree contains the module, otherwise `/usr/share/omarchy/default/handheld/ally_tdp.py`. It does not invent `OMARCHY_PATH` from `$HOME`. When it is root and not in the fixture, `PATH` is pinned to the system directories. A dev tree that is not installed at `/usr/share/omarchy` has to be invoked with `sudo --preserve-env=OMARCHY_PATH`, because pkexec will not see the variable and will not find the module.

Three units live next to the policy. None of them is installed or enabled by this change. `default/handheld/` is not on the automatic unit install path (`default/systemd/` is). Copying them into the systemd directories is a manual step for the on-device run, and a later packaging change should not enable them from a package scriptlet.

- `omarchy-ally-tdp-shim.service` is a user unit, `ConditionEnvironment=OMARCHY_PATH`, `WantedBy=graphical-session.target`. A gamescope session that is not a systemd graphical session will not start it. Start the shim by hand before Steam until that wiring exists.
- `omarchy-ally-tdp-prepare.service` is a system oneshot that runs `omarchy-ally-tdp-prepare`.
- `omarchy-ally-tdp-resume.service` is a system oneshot, `ExecStart=/usr/bin/omarchy-ally-tdp-apply --reassert`, ordered after suspend, hibernate, hybrid-sleep, and suspend-then-hibernate.

The user shim also watches logind `PrepareForSleep(false)` and UPower `OnBattery`, and calls the same `--reassert`. The two resume paths are the same writer, so a double run is idempotent. Neither path changes `mcu_powersave`, restarts InputPlumber, or touches Wi-Fi. Those belong to backlog task 14. The probe only prints `mcu_powersave` when the attribute exists.

## power-profiles-daemon and asusd

`omarchy-ally-tdp-prepare` runs only as root (or in the fixture). It uses the same owner gate as the writer. The gate is open only when all three are true: `omarchy-hw-rog-ally` matches, the handheld variant marker `/var/lib/omarchy/variants/handheld` exists, and `omarchy-ally-tdp-apply` is executable (`$OMARCHY_PATH/bin` or `/usr/bin`). The marker is the handheld install's file. This spike does not create it. While the gate is open, prepare snapshots the current source's ceilings, warns if `asusd.service` is active, and runs `systemctl mask --now power-profiles-daemon.service`. It records the previous `is-enabled` state in `/var/lib/omarchy/ally-tdp/ppd-mask.json`.

An RC71L without that marker, or without the writer binary, does not call systemctl. PPD stays as it was. When the gate later stops applying and that record exists, prepare runs `systemctl unmask power-profiles-daemon.service` and, if PPD had been `enabled`, `systemctl enable --now`. A mask this command did not create is left alone. A laptop never matches the hardware half of the gate.

asusd is not masked here. Another task owns that mask. The hardware dump shows asusd 6.5.0 and PPD both running, and asusd is a static unit started by udev, so skipping it in `install/hardware/asus/rog-ally.sh` does not stop it. asusd writes `platform_profile` and EPP and can re-apply PPT when the profile changes. A third-party report of PPT enforcement dropping after a profile change is about the RC73XA, and is unverified on the RC71L. This writer never writes `platform_profile`, which avoids being a second profile owner, and it cannot stop asusd from overwriting PPT until that mask lands. After the mask, confirm with a load measurement, not only by reading the sysfs integers back.

The writer and the PPD mask share that one gate, so an Ally that is not running the handheld variant keeps PPD as its platform-power owner. `power.py` is not revived, and no second power service is added beside the ones that already exist.

## Units of the PPT integers

`asus-armoury` stores the limits in a `u8` `struct power_limits`. The driver does not label the unit. The RC71 AC maximums are 30, 43, and 53, and the DC defaults are 15, 20, and 25 (DC maximums 25, 30, and 35). The live dump cited by the red team was 30/43/53 on AC, the same numbers as the AC maximums. That is consistent with watts and is not a measurement of package power.

`power*_input` under hwmon is microwatts. `amdgpu`'s `power1_input` is often the GPU rail alone, so it can sit under the package SPL and still not disprove the unit. An idle sample does not confirm it either.

What has to be measured, on the Ally, under a sustained CPU and GPU load (a few minutes, not a burst):

1. Read `ppt_pl1_spl`, `ppt_pl2_sppt`, and `ppt_pl3_fppt` `current_value`, `min_value`, `max_value`, and `default_value` for the current source.
2. Read every hwmon `power*_input`, with the hwmon `name` and any `power*_label`. Divide microwatts by 1e6.
3. On AC, at the stock SPL of 30, a package sensor (name like `amd_energy` or a RAPL package domain, not a GPU-only rail) should settle near 30 W if the integer is watts. Short spikes toward 43 W and 53 W support the SPPT and FPPT readings. A GPU-only sensor near 15–25 W does not.
4. Repeat at an applied 15 W. The package sensor should move to about 15 W. If it stays near 30 W, the sysfs write is not enforced.
5. If the integers were milliwatts, 30 would be 0.03 W and the package sensor would be about a thousand times higher than `30 * 1e6` µW. That mismatch is the failure signal. A match within a few watts, on a package sensor, under sustained load, is the confirmation.

`omarchy-ally-tdp-probe` is read-only. It prints the three PPT tuples, `mcu_powersave` if present, whether PPD and asusd are active, and every hwmon power sample. It writes nothing. `--json` prints one JSON object. It refuses to run when `omarchy-hw-rog-ally` is false.

## Risks and open questions

- The slider itself is unproven until Steam is started after the shim on this device. Steam can cache the probed range until it is restarted.
- Steam can add an interface version and stop calling `TdpLimit1`. The README says the client follows stable SteamOS, which is still `TdpLimit1` as of 10 Nov 2026. Re-check that XML before calling the shim done.
- The per-game path in issue 1994 also sets the GPU level and reads the performance profile. The stubs exist so that path does not abort. They do not change hardware. If Steam requires a profile other than `performance`, the stub will reject it and the commit may fail. That has to be watched in the QAM.
- asusd is still a second writer until its mask task lands. A sysfs readback can look right while the package power does not follow.
- Resume is re-applied in the fixture. On device it has to be checked with `power*_input` after wake, not only with `current_value`. SteamOS #2790 (TDP stuck after resume) is a different stack; it is a reason to measure, not evidence that this writer fails.
- polkit was checked as XML and as an exec-path allowlist. A live `pkexec` from the seat was not run.
- The units are not packaged. `graphical-session.target` may not be the gamescope session.
- The AC ratio uses max-as-default because the kernel table has no AC default. If a BIOS starts advertising a lower AC default, the ratio moves and the frozen boot snapshot keeps the first reading for that boot.
- Z1 and Z1 Extreme share the RC71 DMI match. The writer reads sysfs rather than hardcoding the Extreme table. A board the predicate accepts with a different table still gets that table's ceiling.

## On-device test

Nothing below was run here. The machine that runs it must be the RC71L, with the tree installed so `/usr/bin/omarchy-ally-tdp-apply` and `/usr/share/omarchy/default/handheld/ally_tdp.py` exist, or with `OMARCHY_PATH` pointing at a checkout and the apply command invoked by `sudo --preserve-env=OMARCHY_PATH` rather than pkexec. Copy the policy before expecting an unprompted `pkexec`.

Confirm the gate and record the units before changing anything:

```bash
omarchy-hw-rog-ally && echo ally
OMARCHY_PATH=/usr/share/omarchy omarchy-ally-tdp-probe | tee /tmp/ally-tdp-idle.txt
```

Then start a sustained CPU and GPU load and run the probe again into `/tmp/ally-tdp-load-stock.txt`. Compare the package `power*_input` with `ppt_pl1_spl` using the rules above. Stop if they disagree by an order of magnitude.

Install the policy. Prepare does nothing to PPD until the handheld variant marker exists. For this on-device run, create that marker only for the test and remove it afterwards; the handheld install is what will own the file.

```bash
sudo install -m 0644 /usr/share/omarchy/default/handheld/org.omarchy.ally.set-tdp.policy /usr/share/polkit-1/actions/org.omarchy.ally.set-tdp.policy
sudo /usr/bin/omarchy-ally-tdp-prepare
systemctl is-enabled power-profiles-daemon.service
```

That first prepare must leave PPD enabled. Then:

```bash
sudo install -d /var/lib/omarchy/variants
sudo touch /var/lib/omarchy/variants/handheld
sudo /usr/bin/omarchy-ally-tdp-prepare
systemctl is-enabled power-profiles-daemon.service
systemctl is-active asusd.service
```

`power-profiles-daemon.service` should now be masked. asusd should be unchanged, and the prepare command should have said so if it was active. Removing the marker and running prepare again must unmask PPD and start it if it was enabled before the mask.

Start the shim in the same user session that will run Steam, before Steam:

```bash
OMARCHY_PATH=/usr/share/omarchy omarchy-ally-tdp-shim
```

From another terminal in that session:

```bash
busctl --user introspect com.steampowered.SteamOSManager1 /com/steampowered/SteamOSManager1
busctl --user get-property com.steampowered.SteamOSManager1 /com/steampowered/SteamOSManager1 com.steampowered.SteamOSManager1.TdpLimit1 TdpLimit
busctl --user get-property com.steampowered.SteamOSManager1 /com/steampowered/SteamOSManager1 com.steampowered.SteamOSManager1.TdpLimit1 TdpLimitMax
```

Expect `TdpLimitMax` 30 on AC and 15 on battery with the stock DC defaults. Launch Steam's gamepadui through the gamescope session only after the name is owned. Open the Quick Access Menu performance page and move the slider through 10 and 15 on battery, and through 10, 15, and 30 on AC. After each stop, under load:

```bash
OMARCHY_PATH=/usr/share/omarchy omarchy-ally-tdp-probe --json
```

The SPL integer should match the slider, SPPT and FPPT should match the table above, and the package sensor should move with the SPL. Set 99 from `busctl` and confirm the integers do not change.

On AC, set 30, then unplug. SPL must fall to the stock DC default tuple 15/20/25 while the stored request stays 30. Plug back in and confirm 30/43/53 returns. Then suspend and resume, and repeat the load probe. Readback alone is not the resume check. A battery limit above those defaults is out of scope until a reviewer signs off with probe data.

On a laptop, or any machine where `omarchy-hw-rog-ally` is false, `omarchy-ally-tdp-prepare` must leave PPD enabled, and `omarchy-ally-tdp-apply --set 15` must refuse without writing `platform_profile` or the armoury attributes.

After the run, remove `/var/lib/omarchy/variants/handheld` unless the handheld variant is actually installed, and run prepare once more so PPD comes back. asusd stays as the other task left it. Do not start `steamos-manager`.
