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

The optional game-tools picker is wired to the delivered `omarchy-install-gaming-tools` contract from GAMES/PERFORMANCE commit `a820984f5`. It is offered only when that command is installed; otherwise the existing game-installer menu remains usable. It passes only fixed component names and never runs GameMode on the Ally. The trusted keyboard package is listed as a package prerequisite, without claiming that fixed SDDM settings have been installed or password entry has passed.

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

For this stream's own increment, close any running picker, close games and unmount an external library with the same tool, then reinstall the preceding Omarchy package or revert its source commits in reverse order. There are no persistent mounts, services or boot settings to remove. Keep libraries, saves and backups. Backend setup changes, if separately chosen, require the respective owner's rollback command; package/source rollback alone does not undo them. User instructions live in [the recovery manual](../manual/rog-ally-recovery.md).
