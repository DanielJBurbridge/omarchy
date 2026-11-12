# Preserved Ally cold-boot corrections

These are source handoff patches, not an installed package, active mkinitcpio hook or accepted boot image. See the [rollout handoff](../../docs/rog-ally-rollout-handoff-20261112.md) for completed authentication and remaining boot gates. No installation command reaches this directory.

## Exact inputs and scope

patch-inputs.json records before/after SHA256 values for every changed file. Apply only to matching source in a new private stage; preserve original stages and evidence.

| Patch | Base | Result |
| --- | --- | --- |
| pkgrel4-data-layout.patch | Ally /home/daniel/.local/state/fleet/ally-coldboot-maintained-corrected-20261112, with sources under package/ | Pkgrel4 recipe/SRCINFO, canonical-directory installer and an additional native-alias regression in the existing integration test |
| private-builder-data-layout.patch | Frozen builder manifest 907185f2e11517eaf1ee2e9395e215010859f924b6d8020f2741db7557ae70d4, used in /root/ally-coldboot-builder-menu-format-20261112T1520 | Private-root self bind, native error-log guard, corrected data hook, parent-alias-aware audit, firmware-notice audit requirements and native data regression |

The maintained patch preserves the pkgrel3 native die correction, exact runtime, guard, display/UI sources, activation template and licences. It updates the recipe's installer/test source checksums. The private builder's small data adapter is replaced with that same self-contained corrected installer; package executable/runtime hashes remain pinned to pkgrel2.

Both patches replay exactly against their recorded inputs. They omit source archives, binaries, real passwords, fingerprint templates, private images, root decisions and live configuration. Complete original sources and notices remain in the persistent private stages above.

## Checked and pending

Three focused maintained-installer checks passed using actual native mkinitcpio functions: mandatory/optional membership, missing-required-data fatal exit and canonical data/alias preservation. Restoring the old add_full_dir operation reproduces lost-link failure. The earlier Ally helper run passed native producer/auditor alias and generated-data checks. Python AST, Bash syntax, changed-shell ShellCheck and exact patch replay passed.

**The builder patch is not a complete runnable release.** runtime-data-manifest.json and its DATA_SHA must be refreshed from reviewed target public inputs, including both required firmware-notice directories, followed by a new complete BUNDLE.sha256. Do not reuse the stale preparation manifest. The maintained pkgrel4 patch still needs normal makepkg dependency checks, build/check, SRCINFO reconciliation, genuine allsource output and payload/closure inspection. No full corrected private image or hardware boot test was performed.

After source/build checks, a fresh owner must revalidate boot/configuration provenance and construct a new isolated private image. Actual image contents and clean native logs must pass before publication, followed by attended physical testing and maintained native rebuild/rollback verification. Existing package ALPM hooks can rebuild boot images even while the candidate activation template is disabled.

## Licences

New builder helpers/tests and integration changes retain the MIT notice in [NOTICE](NOTICE). The native encryption installer retains SPDX-License-Identifier: [GPL-2.0-only](GPL-2.0-only.txt); unl0kr is GPL-3.0-or-later. The patches do not relicense native sources, LVGL, fonts, firmware or other package content. Preserve all original notices when building or redistributing full sources.
