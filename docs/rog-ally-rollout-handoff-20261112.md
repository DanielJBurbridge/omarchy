# Ally authentication rollout handoff — 12 November 2026, 16:33 AWST

This is the last verified snapshot before ownership transferred, not a fresh host check after the other agent's work. The project PR carries source release **0fdba61bccdc3e1f31673d6992683fe1224de79a** and this handoff into **feat/ally-parity-integration-20261111**. That branch has parallel gaming/session changes to reconcile before merging. The PR does not merge or deploy itself.

Daniel requested that this owner finish up and relinquish the Ally to his grok-bot. Another agent is currently restarting it. Do not continue this owner's rollout automatically. No installation, image build, reboot, secret card or remote command from this owner is running. The latest SSH attempt was rejected by pam_nologin before its Python command ran. No credentials are retained.

## Installed and physically accepted

- Matching runtime/settings `dev.0fdba61b-1`, source `0fdba61bccdc3e1f31673d6992683fe1224de79a`, installed at 15:31 AWST through a full logout boundary. Package checks reported zero altered files; 273 protected paths checked, with only the approved Service.qml change. Trusted lock host was ready, unlocked and the compositor had no configuration errors after the new desktop started. Reboot makes those transient process observations historical.
- Daniel passed touch-password unlock and incorrect-password rejection; native appearance is "at least passable for now".
- Right-index fingerprint enrolled and successfully unlocked. A different finger stayed locked. The installed rejection wiggle and "Fingerprint not recognised" worked, followed by touch-password fallback.
- Latest physical acceptance: "About 30 seconds; wake and touch unlock worked." This closes the five-second lock-screen fade issue. The native lock idle and resume intervals are now 30 seconds.
- PAM passwords and existing enrolled print were preserved. No fingerprint re-enrolment is needed. Separate real SDDM sign-in, suspend/resume and special display/layout acceptance should not be inferred from lock-screen acceptance.

## Cold boot is unfinished and inactive

No touch-decryption package is installed, no candidate is published to the ESP or boot menu, no one-shot/default was armed, and no encryption/signing/enrolment configuration was changed. Known-good UKI/menu/loader hashes were unchanged at the last completed privileged check. Another agent's subsequent reboot/work must be reconciled before any further action.

First actual private build assembled raw images but was rejected. Retained root-only work is `/root/ally-coldboot-candidate-20261112T1520`; raw unaccepted outputs are under `target/work/output/`, with `build-private.log`. Do not boot those outputs. The source frozen for that attempt is `/root/ally-coldboot-builder-menu-format-20261112T1520`, manifest `907185f2e11517eaf1ee2e9395e215010859f924b6d8020f2741db7557ae70d4`.

The complete active-image provenance check accounted for all 1565 regular members, including exact reproduction of module indexes after supplying native modules.builtin, modules.builtin.modinfo and modules.order inputs. Root policy evidence and decision remain in that work directory. No unknown embedded key source, LUKS tokens or signing requirement was found. A future owner must revalidate this evidence against current state.

Two actual build faults were reproduced and corrected in a NEW, incomplete builder preparation:

1. Native `autodetect` could not detect the chroot's `/` filesystem. A disposable native namespace fixture proved that self-binding only the private target root makes `findmnt -uno fstype -T /` return btrfs. The new namespace adds this bind. The constructor also rejects native `==> ERROR:` log output even when mkinitcpio exits zero.
2. `/usr/share/X11/xkb` is an absolute directory symlink. Native `add_full_dir` alone changes the alias into a directory. The corrected installer copies the canonical directory and adds the original alias. The auditor resolves intermediate aliases while retaining final-link type/target and exact descendant-byte checks. Two targeted checks passed, including the actual native directory-alias fixture and data/cache-byte validation.

Ally's NEW preparation is `/home/daniel/.local/state/fleet/ally-coldboot-builder-data-layout-20261112`. **Its BUNDLE.sha256 is stale: do not execute it as root.** The last completed green log is `evidence/data-layout-green.log`. Root detection evidence is `/home/daniel/.local/state/fleet/ally-auth-acceptance-20261112/rootfs-namespace-probe.json`. The attempted later firmware-notice manifest update and counterfactual run did not execute because SSH was refused during shutdown.

Rune's newer local preparation is `/tmp/ally-image-builder-data-layout-20261112`. It includes `DATA-LAYOUT-CORRECTION.md` and explicit firmware-notice directory requirements/audits added after the last Ally upload. It still needs updated data metadata/pins, counterfactual/static checks, a final manifest and a fresh private construction. Preserve rejected work rather than overwriting its target or decision.

## Maintained package builds

The normal uninstalled pkgrel3 build completed with all 37 source checksums and 11 required integration tests. Both packaged ELFs match pkgrel2; 46-object static ELF closure has none missing. Disabled activation and 31 notices checked. This build includes the independently identified P1 fix: required-data failure must use native `die`, because `error; return 1` can be swallowed by native mkinitcpio and omit the decrypt runtime.

- Completed source/build: `/home/daniel/.local/state/fleet/ally-coldboot-maintained-corrected-20261112`.
- Main archive: `artifacts/unl0kr-ally-candidate-3.6.0-3-x86_64.pkg.tar.zst`, SHA256 `5edfb2827788c42d78b0c0b3e5f8dbf9d059d9c6e351f247a4cfedd0917388e3`.
- Build handoff: `release-build-20261112/RELEASE-HANDOFF.md`.
- **Do not install pkgrel3:** its XKB directory-copy bug remains. Its successfully checked binaries do not prove image correctness.
- Rune local `/tmp/ally-maintained-xkb-correction/package` has a prepared pkgrel4 recipe, installer and extended existing test source. This is not a built or validated release and has not been uploaded as a complete source stage. New hook SHA256 `569a56ce0172bcae85f9233138e07ecb54a4ffa0593bfe2064cc3f76d905e8dc`; test SHA256 `de2924f508e6df99ffc48e9f9e55e41f2af95f3eced7cf1d11ce12f25aaa7ac2`. Complete metadata/source checks and tests before building.

Normal package installation can invoke native ALPM image rebuilding even with activation disabled; it is not a harmless preview. After private image proof, preserve independently selectable recovery, inspect actual native rebuild outputs and perform attended physical testing before declaring cold boot complete. A successful static candidate alone is insufficient for a maintained rollout.

## Recovery and coordination

At handoff Daniel had only a Bluetooth G915 keyboard available but can dock a USB keyboard. He explicitly accepted a trial with a USB keyboard/dock within reach: hot-plug should help at a functioning fallback prompt, while an earlier graphics/kernel hang may require a forced restart. Do not silently convert this into an absolute USB-connected prerequisite, and do not guarantee hot-plug recovery. AC had been connected; recheck fresh state before any disruptive testing. No cold-boot trial has been requested yet.

Native Limine research is in Rune `/tmp/ally-limine-research-20261112/receipt.json`. Actual loader was positively unenrolled (one checksum marker, 128 ASCII zeroes), SecureBoot off, no active signing requirement. This condition matters even with SecureBoot off: nonzero enrolled config hashes are enforced. Conditional publication through supported `limine-entry-tool --no-hooks --add-uki` avoids the existing reset/enrol/sign hooks only while those facts remain true. Explicit known-good default plus `remember_last_entry:no` and a uniquely resolved one-shot ID are needed for a trial. Do not publish or arm from this handoff without a fresh reviewed transaction.

## Other migration work held

Optional INPUT requires 1.0.3, matching dependencies/companions, temporary InputPlumber mask and verified lock-feed ownership before enablement. Do not enable frozen 1.0.2. POWER/Stock Manager remains under the no-install hold. Dedicated gaming session, real controller/gyro/rumble, suspend/resume, display/docking, game/save/storage/recovery and optional overlays/streaming still need their own installation/physical acceptance.

Status ledgers on the release branch are stale relative to today's live authentication: `plans/rog-ally-parity.md`, `plans/rog-ally-threads.md`, `docs/rog-ally-authentication.md`, `docs/trusted-lock-host.md`. Update only precise gates after reconciling the next owner's work. Preserve the existing uncommitted Fleet receipt `/home/daniel/Work/fleet/log/2026-11-12-ally-post-return-owner-check.md` (SHA256 `6eb08bf5be3be433f3ba666f42b1dc6b752472f63baeaf868e6e86f73e49d6a6`).

Logs and private acceptance receipts remain under `/home/daniel/.local/state/fleet/ally-auth-acceptance-20261112` on the Ally and `/tmp/ally-*20261112*` on Rune. The handoff and corrective source patches are now preserved by the project PR.

## Repository handoff and final local checks

The [preserved cold-boot corrections](../packaging/rog-ally-coldboot/README.md) include the maintained pkgrel4 recipe/installer/test patch, private-builder patch and exact before/after input hashes. They are source preparation, not an installable package or accepted image. They preserve the work beyond Rune temporary files. Existing private full source archives and notices remain in their persistent Ally stages.

After host access stopped, three focused maintained-installer checks passed on Rune: mandatory/optional membership, required-data fatal exit and canonical directory/alias preservation. Rune's native mkinitcpio/functions hashes exactly match the pinned Ally versions. A counterfactual restoring the old native copy operation fails because the alias becomes a directory. Both corrective patches replay exactly against their recorded inputs; Python AST, Bash syntax and changed-shell ShellCheck pass. No live host commands, full package build or image construction were performed during this final PR preparation.

The builder patch still needs refreshed runtime-data metadata and DATA_SHA, including both firmware-notice directories, and a final reviewed BUNDLE.sha256. Do not execute the stale uploaded preparation. Maintained pkgrel4 still needs a normal build/check, SRCINFO reconciliation, genuine allsource output and payload/closure checks. Then revalidate current boot/configuration provenance and construct a fresh private image; do not reuse the rejected target or old policy decision without review.

The installed UI stage is /home/daniel/.local/state/fleet/ally-ui-stage-0fdba61b-20261112. Archive SHA256 values are runtime **991251f831b4839df1832666da8bd00dc5ab35980e4253cdb649830b1ecace25** and settings **e04efbc0b1fb47ff7fb6812afc06aead8a2fde4ff2e2022aa8c313f6d9acbc84**. The reviewed 14-file bundle manifest is **8c0a8ae8465bd6b973813eba4fe1e030fb2cfbfe602da74ce411904069ca8f0e**. Preserve matching runtime/settings and their rollback stage /root/ally-ui-feedback-0fdba61b-20261112T1520.

Fingerprint support used libfprint-git 1:1.94.100.r10.g6f9479c-5, fprintd 1.94.5-2 and libgusb 0.4.9-2 for the 1c7a:0588 reader. No templates were exported. Fingerprint administration was configured but not separately physically accepted. Reader-unavailable behaviour, suspend/resume, lock survival across desktop restart, compositor/orphan recovery, competing-locker refusal, INPUT reconnect and native/scaled/external or special-layout checks remain distinct from today's successful lock unlocks.

The updated [feature ledger](../plans/rog-ally-parity.md), [thread index](../plans/rog-ally-threads.md), [authentication reference](rog-ally-authentication.md) and [trusted-host reference](trusted-lock-host.md) distinguish this snapshot from the retained source-only and prepared/uninstalled receipts.
