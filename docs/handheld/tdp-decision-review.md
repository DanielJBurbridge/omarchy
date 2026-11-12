# Red team: TDP/power path decision review (ROG Ally RC71L)

## Rulings (12 Nov 2026)

These close the open items in the review below. The review text is kept as it was written.

- PPD is masked only when the handheld variant (`omarchy-hw-rog-ally` and `omarchy-gaming-session`) and backlog #10 (power writer) are both installed. Not on every RC71L, and not on the handheld pair alone. The setup records the mask and unmasks when either is removed or the device goes desktop-only. The same gate is PR #33.
- backlog #10 (power writer) owns power. Do not ship stock or patched `steamos-manager`.
- backlog #11 (Steam TDP shim) is the Steam session-bus shim, and it waits on the spike that shows Steam's QAM TDP slider with a non-Valve owner.
- TDP rows stay read-only until backlog #10 (power writer) lands.
- Where the capped-apply rules below differ from [PR #33](https://github.com/DanielJBurbridge/omarchy/pull/33) (`docs/handheld/tdp-spike-findings.md`), the spike is the rule. The single action is `org.omarchy.ally.set-tdp` on `/usr/bin/omarchy-ally-tdp-apply` (`allow_active=yes`, `allow_any=no`, `allow_inactive=no`). The caller passes watts. Root derives SPPT and FPPT.
- SPL ≤ SPPT ≤ FPPT on every write. Battery slider max is 20 W and the applied tuple is at most 20/20/25. AC slider max is 30 W. A request above the cap is clamped, not rejected: on battery `--set 25` applies 20/20/25. On battery, SPPT = clamp(derived, max(SPL, sppt_min), 20) and FPPT = clamp(derived, max(SPPT, fppt_min), 25). `--reassert` after an unplug clamps to 20/20/25 and keeps the stored AC request. Any battery tuple above 20/20/25, including the spike's 25/30/35, needs measured data and dev-red sign-off before it ships.

Reviewer: dev-red. Date: Thu 12 Nov 2026 (AWST). Written as a read-only review; this file is the copy in the repo.
Asked by dev-lead. Inputs: `feat/ally-power-20261111` (head of compare vs release, commits d3d00ea → 6e59faa), `feat/ally-parity-release-20261111`, `docs/handheld/research/parity-matrix.md`, backlog #10 (power writer) and backlog #11 (Steam TDP shim), upstream steamos-manager (gitlab.steamos.cloud/holo/steamos-manager) at tag `v26.4.1` (a0d399d) and branch `main` (2c51fc82, 10 Nov 2026), CachyOS PKGBUILD master (unchanged since ab15ca2, 18 Oct 2026).

Line refs: power-branch files read from the compare patch (whole-file adds = branch head). Release-branch `plans/rog-ally-parity.md` fetched live today. `docs/rog-ally-power.md` and the setup script have identical rejection lines on both branches.

## Verdict

**Don't ship stock steamos-manager, and don't start a patched Manager fork. Build #10 (small root writer) + #11 (session-bus shim on the public SteamOSManager1 API).** Every original rejection reason still holds on upstream `main` as of 10 Nov 2026. A gated or minimal Manager build can fix the packaging and activation reasons. It can't fix root authority without forking the root daemon. That root API is private, and upstream says it changes without warning. #10/#11 puts the root code on a small surface we own and the Steam integration on the API upstream keeps stable. Bazzite and CachyOS both ship stock Manager, so this matches their UX (QAM slider) without copying their implementation.

## 1. Original rejection reasons (quoted)

Source: independent read-only review of CachyOS recipe `ab15ca2` + upstream `a0d399d`. It's recorded in:

- `docs/rog-ally-power.md:7` (both branches; text from 0fbd941): "**Do not install unchanged `steamos-manager 26.4.1-3`, even as an inactive prerequisite.** … its install/upgrade scriptlet enables a root service for the next boot."
- `docs/rog-ally-power.md:11-15`:
  - R1 (L11) "Root daemon startup/hotplug manages InputPlumber targets and enables a PlayStation inhibitor by default, conflicting with INPUT ownership."
  - R2 (L12) "Broad RootManager system-bus access lacks caller/session/Polkit authorisation for privileged setters, including login policy. Restricting the Omarchy client cannot protect direct calls."
  - R3 (L13) "The mandatory networking helper is absent from the configured repositories and carries out-of-scope privileged Wi-Fi/NetworkManager behaviour…"
  - R4 (L14) "Activation scriptlets and login-manager payload prevent safe inactive installation and can contaminate a setup-time ownership receipt."
  - R5 (L15) "Public sustained-limit readback cannot prove restoration of the sequentially changed SPL/SPPT/FPPT limits…"
- `plans/rog-ally-parity.md:372` (release, live): the same list, plus "unconditional root input-target/PlayStation management, unauthorised privileged RootManager methods including login policy … The Omarchy client's public-session API, caps and opt-in do not protect direct backend callers."
- `docs/rog-ally-manager-remediation.md:3,21-27,29` (power branch, 0fbd941). R6: "Upstream currently exposes no existing power-only mode … root interface registration is monolithic, and removing platform configuration alone does not remove root methods." The table rows also cover sessions/login (L24) and other root duties: factory reset, storage format/trim, BIOS/dock update, CEC, tracing (L25).
- `docs/rog-ally-power-authority.md:3,62,82` (6e59faa). R7: "no production registrar or grant is authorised"; "retains **no Steam QAM legacy adapter** until its per-request origin/deputy boundary is reviewed: a user-wide session proxy can otherwise forward calls from unrelated sessions under its own grant"; "Recommendation: retain denial and generic PPD now."
- Enforcement: 313ca7a rewrote `bin/omarchy-setup-rog-ally-power:28-31` so `--configure-reviewed-package` always `exit 1`. It removed the old path, which did `sudo systemctl mask --now power-profiles-daemon`, `enable --now steamos-manager` (system + user) and only *then* captured `original.json` (old lines 50-56 in the 313ca7a diff). 313ca7a's test (`test/shell.d/power-test.sh` +22) asserts the refusal happens before any package query, service change or state write.

## 2. dev-research recommendation (parity-matrix.md)

L8: "Steam TDP slider: `steamos-manager` (MIT; CachyOS repo only, build from gitlab.steamos.cloud). It already knows RC71L and drives `asus-armoury` PPT + `platform_profile`." L52-53: ship it with InputPlumber as "gaming mode", stop or mask ppd/asusd, and package it from the CachyOS PKGBUILD, pinned. It doesn't engage with R1-R7. The matrix's own L29 also flags the ppd/asusd `platform_profile` conflict.

## 3. Do the reasons still hold against current upstream?

| # | Reason | Holds? | Evidence (upstream, checked today) |
|---|---|---|---|
| R1 | Root daemon takes InputPlumber targets | **Yes** | `main:src/daemon/root.rs` `start()` adds `DeckService::init()` unconditionally (around L128), then `reload_ds_inhibit`. `inputplumber.rs` `make_deck()` retargets *every* new CompositeDevice to the device-config target, defaulting to `deck-uhid`. `rog-ally-series.toml` has no `[inputplumber]` section, so RC71L gets `deck-uhid`. That fights Omarchy's IP desktop/mouse profile on every IP device re-add, including resume (**on-device effect unverified**). |
| R2 | No caller authorisation on root setters | **Yes** | `main:data/system/com.steampowered.SteamOSManager1.conf`: "Anyone can send messages to the service" (`policy context="default"` allow send). `manager/root.rs` setters (`set_tdp_limit` ~L584, `set_default_session` L793, `prepare_factory_reset` L156, `format_device` L393, `set_wifi_backend` L649) only check `SerialOrderValidator` (ordering, not identity). The one new check on `main` (fd665dae, Sep 2026) is in the *user* daemon. It rejects callers whose `/proc/<pid>/cgroup` contains `/app-steam-app`: a proc-derived denylist for games, not authorisation. Root is unchanged. `session.rs:408-418` writes `[Autologin] Session=…` to `/etc/sddm.conf.d`. Omarchy uses SDDM, and backlog #7 makes gaming autologin the default, so any local process could pick the autologin session. |
| R3 | Networking helper dependency / Wi-Fi paths | **Yes** | CachyOS PKGBUILD (master = ab15ca2) still `depends=(… 'steamos-networking-tools' … 'wireless_tools')`. `main` still has root `set_wifi_backend`, and `dfb4d435` (Sep 2026) only changed the default backend. Not in Arch `extra` (archlinux.org search: 0 results). AUR has only forks (`steamos-manager-hhd`, `-gpdwinmini-git`). |
| R4 | Activation on install / login payload | **Yes, and wider than recorded** | CachyOS `steamos-manager.install`: `post_install`/`post_upgrade` run `systemctl enable steamos-manager.service`. **New finding:** upstream `Makefile install` also ships `/usr/share/dbus-1/system-services/com.steampowered.SteamOSManager1.service` (`SystemdService=steamos-manager.service`) and a user-bus equivalent. Any system-bus message to the name can start the root daemon even when the unit is *disabled* (standard D-Bus/systemd activation; only `mask` stops it; **not tested on device**). It also installs `/usr/lib/systemd/system/sddm.service.d/reset-oneshot-boot.conf`, which deletes `/etc/sddm.conf.d/zzt-*-temp-login.conf` on every SDDM start, plus a user `steamos-manager-session-cleanup.service`. "Inactive install" isn't inactive. |
| R5 | SPL-only readback; 3 sequential writes | **Yes** | `main:src/power.rs:614-657` `FirmwareAttributeLimitManager::set_tdp_limit` writes SPL, then SPPT=max(limit, sppt_min), then FPPT=max(limit, fppt_min), with no rollback on partial failure. `get_tdp_limit` reads SPL only (L602-611). The bound is firmware `min_value..max_value` only (L615-618, 660-677). No Omarchy 25 W battery / 30 W AC cap is enforced at root. Extra risk (third-party, **RC73XA only, unverified on RC71L**): a `platform_profile` change silently drops armoury PPT enforcement while sysfs still reads the old values ([hpd report](https://github.com/CiroDev-Git/hpd-handheld-power-daemon/blob/main/docs/dev/UPSTREAM-ASUS-PPT-PROFILE-REPORT.md)), so readback alone can't prove enforcement. |
| R6 | No power-only mode upstream | **Yes** | No feature flag or entry point on `main`. 52 commits since v26.4.1 add GPU/devfreq, custom platform profiles and CPU EPP (branch `pastaq/epp_support`). The surface is growing. README L96-99: system-bus API "is considered a private implementation detail … may be changed at any moment and without warning." |
| R7 | Session delegation / QAM adapter deputy | **Yes** | User daemon is per-user on the session bus and forwards to root (README L91-94). No session binding upstream beyond the cgroup game check above. |

Upstream tag status: latest tag is still `v26.4.1` (22 Jul 2026, PDT). `main` has moved on (2c51fc82). The CachyOS package is still 26.4.1-3.

## 4. Would a patched or minimal Manager build, gated to the gaming session, fix it?

Proposed gating: RC71L-only install, user unit started only by the gamescope session, system unit masked otherwise, restricted D-Bus policy.

| Reason | Fixed by gating? | Residual |
|---|---|---|
| R4 activation | **Mostly.** Our own PKGBUILD with no `.install`, no D-Bus system-services activation file and no `sddm.service.d` drop-in. Mask the system unit outside gaming. | Gaming start has to unmask and start a root unit, which is a root transition per session. A mask/unmask race can leave it active after a crash. |
| R3 networking | **Only with code cuts.** Dropping the dep while `set_wifi_backend` remains reachable just breaks or exposes it (remediation doc L23). | Fork patch on root.rs/user.rs. |
| R1 input | **Partly.** The 0fbd941 `manage_input=false` patch is unbuilt and runtime-only (remediation L35-44). | Unbuilt and untested. Upstream default stays on, so every rebase has to re-check it. |
| R2 root authority | **No.** A D-Bus policy restricted to a user or group narrows transport, but every allowed caller still gets factory reset, format, SDDM session and Wi-Fi methods (remediation L58 says the same). Fixing it means deleting root methods, i.e. a hard fork of `manager/root.rs`. | Fork tracks a private API that changes without warning (R6). Root and user halves must match exactly. |
| R5 restore | **No.** Needs a new transactional 3-limit API in Rust (remediation L60-79). | Same fork cost. |
| R6/R7 | **No.** Gating changes *when* it runs, not *what* it exposes while running, which is exactly gaming mode, when Steam is up. | — |

Net: a "minimal Manager" is a Rust fork of a daemon that upstream reshapes monthly (52 commits in under 4 months). It costs more than #10/#11 and ends with a larger root surface.

## 5. #10/#11 vs patched Manager vs stock Manager

| | Stock Manager (dev-research) | Patched/minimal Manager | #10 writer + #11 shim (backlog L53-54) |
|---|---|---|---|
| Root surface | Whole RootManager (TDP, GPU, governor, sessions, factory reset, format, BIOS, Wi-Fi), any sender | Cut-down fork. Still a Rust daemon plus user half | One small helper: set profile + SPL/SPPT/FPPT from allow-listed values, no paths or args from the caller |
| Authorisation | None | Must be added in the fork | Polkit action on a fixed verb (see decision D1). Root enforces caps |
| Inactive footprint | Enable scriptlet, D-Bus activation, SDDM drop-in | Removable | Ours: no auto-enable, no SDDM payload |
| Input / network / login side effects | Yes (R1, R3, R2) | Patched out per release | None |
| Steam QAM slider | Yes (proven on Bazzite/CachyOS) | Yes | **Unverified.** Steam probes interfaces at start-up (README L8-10). Prior art for third-party owners of the name: Io's Python `io-steamos-manager` restricts the root half to root+`wheel` ([Io wiki](https://github-wiki-see.page/m/Lolzen/io-packages/wiki/Deviations)); `hhd-steamos-bridge`. Not tested by us |
| API drift | Valve's problem | Ours, on the *private* root API | Ours, on the *public* session API, which upstream must keep binary compatible (README L61-81). Caveat: "the client makes no guarantees that older versions of an interface will be used" (L77-81) |
| Upstream bug exposure | Remote registration deadlocks in 26.3.0 ([hhd-steamos-bridge](https://github.com/OuinOuin74/hhd-steamos-bridge)), RC71L resume TDP lock open on SteamOS 3.8 ([SteamOS #2790](https://github.com/ValveSoftware/SteamOS/issues/2790), open) | Same | Our own bugs, small code |
| Cost (estimate, unverified) | Low to package, high to make safe | High (Rust fork + rebases) | Medium: helper ~200-300 lines + Polkit + tests. Shim: TdpLimit1 + PerformanceProfile1 (+ BatteryChargeLimit1 later) |
| Parity with Bazzite/CachyOS | Same implementation | Same UX | Same UX (QAM slider). Different implementation |

What the others ship (verified today):
- Bazzite Deck 44: "SteamOS-Manager for handling everything from session switching to TDP control in steam. PowerStation for TDP/power control on devices SteamOS-Manager can't support today." HHD has been removed ([Universal Blue announcement](https://universal-blue.discourse.group/t/bazzites-biggest-update-deck-44-has-launched-happy-birthday-to-universal-blue/12373), [GamingOnLinux, 21 Aug 2026](https://www.gamingonlinux.com/2026/08/bazzite-linux-44-for-handhelds-finally-launches-with-some-massive-upgrades/)). Bazzite's own handheld wiki adds: "Make sure you only have one means of TDP Control … running!"
- CachyOS Handheld: `chwd` `[handheld]` profile installs `steamos-manager inputplumber steamos-powerbuttond` ([profiles.toml](https://github.com/CachyOS/chwd/blob/master/profiles/pci/handhelds/profiles.toml) L6). The `rog-ally` profile matches RC71L.
- Both are single-purpose gaming images that accept Manager's root model. Omarchy is a general desktop with SDDM autologin, so R2's SDDM write and R4's SDDM drop-in hit us harder than them.

## 6. Single power writer and conflicts with ppd/asusd

- Rule: `plans/rog-ally-parity.md:111` (release): "Use one active writer for each hardware power setting … Do not enable HHD/Adjustor, asusctl, PowerStation and custom sysfs writers together without explicit ownership boundaries." L230: POWER is to have "one power owner." `default/handheld/power.py:22` (power branch) lists the conflicting writers: ppd, powerstation, hhd*, adjustor, asusd, tlp, auto-cpufreq, tuned. It also checks GameMode at L81-89.
- ppd writes `platform_profile` and is D-Bus-activatable, so `disable` isn't enough and it must be **masked** ([asusctl #264](https://github.com/OpenGamingCollective/asusctl/issues/264)).
- asusd manages `platform_profile` + EPP and re-applies PPT on profile change ([asusctl docs](https://opengamingcollective.github.io/asusctl/distributions/ubuntu.html), [ArchWiki](https://wiki.archlinux.org/title/Asusctl)). It's a **static unit started by udev**, so either mask it or set `change_platform_profile_on_ac/battery: false` and `platform_profile_linked_epp: false` in `/etc/asusd/asusd.ron`. The device dump says asusd and ppd are both running now. Whether asusd re-applies PPT on RC71L specifically is **unverified**.
- Stock Manager adds a third `platform_profile` writer and a PPT writer, and its activation file means masking the *unit* is the only off switch.
- #10 must be the only PPT writer, and the only `platform_profile` writer while gaming. On desktop, either keep ppd (helper idle) or let the helper own both. Pick one per mode and test the hand-over.

## Recommendation

1. Keep the 313ca7a hold. Stock and patched Manager both stay NO-INSTALL. Close dev-research's recommendation 2 (package from the CachyOS PKGBUILD) as rejected, with this review linked.
2. Build #10: `omarchy-ally-power-helper` (root, system bus or a Polkit-run one-shot). Fixed verbs only: `apply(profile, spl)` and `restore(snapshot-id)`. Root derives SPPT/FPPT from reviewed policy, enforces RC71L DMI match, the firmware range and Omarchy caps (25 W battery / 30 W AC, `docs/rog-ally-power.md:40`), and the order profile → SPL/SPPT/FPPT → re-assert → read all three back. No paths or free-form args. Reuse Manager's MIT `FirmwareAttributeLimitManager` logic and `rog-ally-series.toml` as reference only.
3. Build #11 only after a **1-day spike** proves Steam's QAM shows a TDP slider with a non-Valve owner of `com.steampowered.SteamOSManager1` on the session bus inside our gamescope session. If the spike fails, fall back to the Decky route in backlog #11 or the Omarchy panel. Don't fall back to Manager.
4. Backlog #10 lists a 30 W preset. That's fine on AC only. Root must clamp to 25 W on battery.

### Decisions for Daniel / dev-lead
- **D1 Polkit model.** The authority doc (`rog-ally-power-authority.md:47`, `rog-ally-manager-remediation.md:54`) wants `auth_admin_keep` plus logind-bound grants. A password prompt can't appear inside gamescope from the QAM slider. Red team view: `allow_active=yes` for this one fixed, root-clamped verb is proportionate, with inactive/remote denied. The worst case for an active local user is "max reviewed TDP", which ppd already lets them do for profiles. This loosens the earlier design, so it needs an explicit sign-off.
- **D2 Burst caps.** SPPT/FPPT policy isn't reviewed. Live raw values were 30/43/53 with units unconfirmed (`plans/rog-ally-parity.md:403-407`, `docs/rog-ally-power-authority.md:78`).

## Top risks and mitigations

| Risk | Mitigation |
|---|---|
| Steam ignores the shim (no slider) | Spike first (rec. 3). Pin the interface XML from upstream `main`. Run a CI contract test that diffs our introspection against upstream XML |
| PPT silently unenforced after a profile change (RC73XA report) or after resume (SteamOS #2790) | Re-assert all three limits after every profile write and on `PrepareForSleep(false)`. Acceptance measures `power1_input` under load, not just sysfs readback |
| Two writers (ppd D-Bus activation, asusd via udev, GameMode, Decky TDP plugins) | Helper refuses to write if any CONFLICTS entry is active or the ppd/GameMode bus names have owners. Setup masks ppd and configures asusd.ron. Test both |
| Partial 3-limit write leaves odd state | Capture all three before writing, restore all three on any failure, return a transaction result. No success on queued ack (remediation L70-77 contract, scaled down) |
| Root helper bug = local privilege issue | Fixed verbs, integers only, no paths, no shell. Fuzz the argument parser. Run under systemd sandboxing (`ProtectSystem=strict`, `ReadWritePaths=/sys/class/firmware-attributes/asus-armoury /sys/firmware/acpi/platform_profile`) |
| Steam moves to a new interface version | Track SteamOS stable releases. Contract test. Shim exposes current and previous versions where cheap |
| Helper runs on a non-Ally machine | DMI RC71L gate in root (not just the installer). Exit if `asus-armoury` attributes are missing. Laptops keep ppd |

## Failing tests and acceptance checks to demand before merge

Fixture tests (CI, fake sysfs, private bus):
1. Root rejects SPL outside firmware min/max, above 25 W on battery, above 30 W on AC, non-integer, negative, or any extra argument, and nothing is written.
2. Rejects a non-RC71L DMI or missing armoury attributes, with no writes.
3. Order check: profile write happens first, then SPL/SPPT/FPPT, then all three are read back. An injected profile change afterwards triggers a re-assert.
4. Fault injection: each of the 3 writes fails in turn, and all three are restored to the captured originals (not values recomputed from SPL). Status is `rolled_back` or `partial`, never success.
5. Refuses to write while ppd, asusd (profile management on), powerstation, hhd, tuned or GameMode is active.
6. Inactive/remote caller is denied by Polkit (fake authority), and caller-supplied UID/PID is ignored.
7. Shim: introspection matches the pinned upstream XML for TdpLimit1/PerformanceProfile1. `TdpLimit` set → helper called → property-changed signal sent only after verified readback.
8. Resume: `PrepareForSleep(false)` re-applies the current source's preference through the same path.
9. No package scriptlet enables or starts anything. No files under `/etc/sddm.conf.d`, `sddm.service.d` or `dbus-1/system-services` except the ones we review.

On-device (sole rollout owner, per dev-lead's deploy rules):
10. Steam QAM slider visible in gamescope. Set 10 → 15 → 25 W and check `power1_input` settles near each value under load.
11. AC unplug at 30 W drops to ≤25 W. Suspend/resume keeps the limit enforced (measured, not read back).
12. Desktop: ppd behaviour restored, `powerprofilesctl` works, exactly one writer active (`busctl` + `systemctl` snapshot).
13. Rollback restores the original 3-limit tuple and service states recorded *before* install.

## Unverified items
- Steam QAM works with a non-Valve owner of the SteamOSManager1 name (only third-party claims).
- DeckService retargeting actually overrides Omarchy's IP profile on the Ally.
- D-Bus activation of a disabled root unit on this box (standard behaviour, not observed).
- asusd PPT re-apply and the profile-change PPT drop on RC71L.
- Raw 30/43/53 units; safe SPPT/FPPT burst caps.
- Cost estimates.
