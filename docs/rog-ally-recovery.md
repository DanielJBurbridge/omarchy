# Handheld setup and recovery integration

The recovery stream owns `bin/omarchy-setup-gaming`, `bin/omarchy-setup-rog-ally`, `bin/omarchy-hw-rog-ally-status`, `bin/omarchy-drive-game-library`, menu integration and user recovery instructions. It preserves the Steam/desktop setup from `f7194066d` and the integration correction to `omarchy-hw-rog-ally`. Non-RC71L machines keep the existing gaming flow; direct handheld commands fail before querying or changing their environment.

## Worker inventory and boundaries

These are the nine feature streams from [the parity plan](../plans/rog-ally-parity.md), not claims of installed functionality. Each stream's source-ready receipt and the integrator's release ledger determine whether its command can be exposed as an action. The shared setup must never guess an installer name or choose a substitute backend when a command is absent.

| Stream | Integration responsibility | Recovery acceptance |
| --- | --- | --- |
| INPUT | InputPlumber companion, controller profiles and event bridge | Report package, system-service and API readiness separately; actual pointer/controller tests remain physical |
| POWER | SteamOS Manager, power controls and one setting owner | Report supported controls and readback when its delivered JSON contract is integrated; never infer TDP from package presence |
| SESSION | Optional Gamescope and managed-preference login entries | Keep normal desktop login as recovery; expose delivered session setup only |
| AUTH | Trusted SDDM and lock input; encryption retained | Verify touch password entry and USB-keyboard fallback separately |
| TOUCH | Optional wvkbd desktop keyboard | Reuse the reviewed installer and existing toggle; no greeter/Gamescope substitution |
| DISPLAY | Modes, scaling, touch mapping and docking | Native panel stays SDR; actual dock/undock tests remain physical |
| RELIABILITY | Power button, lock-before-suspend, audio and reconnect | Do not enable another power-button or resume daemon from recovery |
| GAMES/PERFORMANCE | Steam/launchers, compatibility and performance tools | Preserve saves and prefixes; keep full-system update and normal package helpers |
| RECOVERY | Setup/status, updates, snapshots, libraries and backups | Idempotent/cancel-safe UI, unsupported-machine guards, explicit storage selection and restore guidance |

## Delivered command contract

- `omarchy-setup-rog-ally` opens native pickers. Opening/cancelling it writes nothing. Every install or recovery action is explicit; backend-specific setup owns its own changes and rollback.
- `omarchy-hw-rog-ally-status [--menu] [--updates]` reports allow-listed package versions, system-service states and non-activating bus-owner checks. Its default report performs no network check, sudo, firmware operation or log export. `--updates` calls `checkupdates --nocolor` with a timeout and distinguishes exit 2 (no updates) from sync failure. It shows a count, not private repository package names. Snapshot file presence is only a prerequisite, never proof of a bootable recovery point.
- `omarchy-drive-game-library` uses existing UDisks policy and removable data partitions; see [storage and save recovery](rog-ally-storage.md).

INPUT source review is cleared for canonical-readiness recovery correction `6350a539b`, integrated as `e1f6c712d88f388630ab7a3d6e29e1977630bd6e` with central `adbe8541b` preserved. Frozen release `47e0e976f47c86edf9962d0debde9b571fadc385` and its artifacts remain unchanged; its earlier `1.0.2-1` companion must not be newly enabled. The next frontend exposes `omarchy-setup-rog-ally-input --enable` only when both runtime helpers are present and `pacman -Q omarchy-rog-ally-input` reports exactly `1.0.3-1`. Earlier companions (including `1.0.2-1`), an unreviewed later version or a failed query do not qualify. The input owner's separately required exact-version guard at the actual `--enable` mutation boundary remains a source dependency; this frontend check does not replace it or make this commit independently deployable. An explicit confirmation explains terminal/recovery requirements; the helper/package checks run again before dispatch, so removal while the picker is open does not invoke setup. No packages are installed and nothing is enabled by opening setup or status. Readiness and disable remain available independently of that activation gate.

Status reports source review, installed-package eligibility, service/API readiness and physical acceptance separately. It first checks the system bus owner, then queries read-only composite/capability fields with bounded timeouts; the corrected client's `NO_AUTO_START` also prevents activation if the backend disappears between those calls. Only fixed profile/interception labels and array counts reach the shareable report; raw names, profile/source/target paths and backend errors are discarded. Missing or ambiguous composites remain unreadable, not physically verified.

Installation order and the temporary pre-dependency runtime mask are owned by [INPUT's installation manifest](rog-ally-input.md). Disable before companion removal; newly installed InputPlumber must be removed before restoring an earlier owner because the companion guard no longer exists after uninstall. Recovery does not perform dependency installation or ownership transfer on startup.

POWER client corrections (`1256ff0609744151b9e8581052e2aa745a0e9648` plus integration `67e882`) passed focused review, but the independent package review rejected unchanged `steamos-manager 26.4.1-3`, including installation as an inactive prerequisite. Its scriptlet enables the root service for the next boot. No remediated power-only package is approved. Central guard `180aa53b2c061c6687776b6d204a911416fe8e41` refuses setup before package queries, service changes or state writes; legacy rollback remains available without claiming complete three-limit restoration or pre-install ownership. The picker keeps readiness/rollback only; the writable desktop power-panel action stays absent. The adapter checks the session bus owner before invoking read-only status, suppresses values on conflicts/top-level errors, and renders only fixed control keys, known enums and bounded numeric readback/ranges. A charge value of -1 means firmware default. Raw backend reasons/errors are omitted from the public report. Unavailable TDP is never inferred from package presence or historical sysfs readings. See [power package blockers](rog-ally-power.md#package-review-hold).

SESSION wiring targets delivered `c52affb7bd94aca48f4a1a218596d15716012a0f`: actual `status`, `default`, `next`, `display`, `overlay` and confirmed `reset` verbs, plus explicitly confirmed gaming launch. The same-release runtime and registration companion are required. Source delivery does not bypass integration review. Local session status remains a separate explicit terminal action; the shareable read-only report does not invoke it because the delivered implementation creates its private state directory. The original desktop session remains the independent escape. No backend setup is implicitly run on login or from status.

The display picker is wired to delivered DISPLAY commit `4357ecd01c4a39b28c162943158d784af42e9841`: local status, explicit touch-preset apply and guarded reset. It never guesses a touch device identity, enables HDR or copies raw display status into the shared diagnostic report.

The keyboard picker supports the delivered TOUCH contract (`c2ce33d5d`, `bdb732d94`): configure an already reviewed package, explicitly install reviewed AUR source, or toggle the installed desktop keyboard. No automatic IME activation or gaming-session keyboard is introduced.

The optional game-tools picker is wired to the delivered `omarchy-install-gaming-tools` contract from GAMES/PERFORMANCE commit `a820984f5`. It is offered only when that command is installed; otherwise the existing game-installer menu remains usable. It passes only fixed component names and never runs GameMode on the Ally. The trusted keyboard package is listed as a package prerequisite, without claiming that fixed SDDM settings have been installed or password entry has passed.

Delivered GAMES Decky commit `c178cbec9` adds an optional picker only when both its install and setup commands exist. Status remains local because the upstream systemctl output includes a user instance/logs. Installation stays disabled; activation requires a separate explicit root-plugin confirmation and the owner's reviewed companion. No automatic plugin installation or in-app updating is exposed.

No new repositories, firmware writes, kernel changes, bootloader entries, login policy, system services or `/etc` files are introduced by these commands. Fixed backend files belong in the relevant reviewed companion package, outside this stream.

Primary interfaces checked 11 November 2026: [checkupdates](https://man.archlinux.org/man/checkupdates.8.en) uses a separate temporary package database and distinct exit status for no updates; [InputPlumber usage](https://github.com/ShadowBlip/InputPlumber/blob/main/docs/usage.md) documents the system bus name; [fwupdmgr](https://fwupd.github.io/libfwupdplugin/fwupdmgr.html) distinguishes inspection from installation, which may reboot. The normal firmware installer remains separate from this read-only report. SteamOS Manager's user bus name follows the POWER owner's pinned 26.4.1 package contract. Only names/readiness are queried here; no third-party source is copied.

## Tests and rollout

Run the focused gaming/setup tests and storage tests, redirecting whole output to logs:

```bash
bash test/shell.d/gaming-setup-test.sh >/tmp/ally-recovery-gaming.log 2>&1
bash test/shell.d/drive-game-library-test.sh >/tmp/ally-storage-test.log 2>&1
```

The recovery tests run real commands with isolated package, bus, service, update and picker boundaries. They catch false update success, absent/failed units, personal output leaking into diagnostics, unsupported hardware, cancel/error confusion and unintended snapshot/backend dispatch. Storage tests exercise the actual block-tree filter and readiness logic. No test touches a real block device or restarts the desktop.

The source integrator merges the atomic commits, resolves the shared top-level gaming/menu changes, packages the release and routes it to the sole Ally rollout owner. Install through the normal Omarchy package route; this increment needs no separate fixed-path installation or post-install configuration. Feature workers do not mutate the live Ally.

The rollout owner must record installed package versions, open **Setup > Gaming > ROG Ally handheld** using touch/controller input, inspect picker layout at the Ally scale, cancel and repeat setup, compare status with actual package/service/API state, run an online update check, create a snapshot and inspect its Limine entry, and perform the external-library/save-backup checks. Confirm the unsupported-machine flow in a safe fixture or other machine. Record whether firmware menus, direct-boot fallback, disk unlock and a snapshot boot/restore can actually be operated. These are pending until device evidence is supplied; do not infer them from source tests or from an API owner.

## Rollback

Reverting the reviewed-input frontend option only hides activation; it does not disable an integration already enabled by the user. Use INPUT's disable/rollback before companion removal.

For this stream's own increment, close any running picker, close games and unmount an external library with the same tool, then reinstall the preceding Omarchy package or revert its source commits in reverse order. There are no persistent mounts, services or boot settings to remove. Keep libraries, saves and backups. Backend setup changes, if separately chosen, require the respective owner's rollback command; package/source rollback alone does not undo them. User instructions live in [the recovery manual](../manual/rog-ally-recovery.md).
