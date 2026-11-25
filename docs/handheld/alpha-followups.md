# Alpha follow-ups

Not part of spec 02. These are the optional notes from [review 5870531064](https://github.com/DanielJBurbridge/omarchy/pull/36#pullrequestreview-5870531064) on PR #36.

- L14. Number the backstop rungs after a failed 5 s lock. That lock leaves 7 s before the 3 s margin: SIGTERM at 5 s, SIGKILL at 7 s, `terminate-session` at 9 s, decision by 12 s. Spec 02 still says only that the rungs are compressed into what remains.
- L15. The broker re-checks `EndDesktop` itself (handheld variant, `desktop-lock` `on`, no physical keyboard, a desktop session active, marker absent) and does nothing otherwise. The 30 s notice draws above the idle screensaver, which Quickshell starts at 150 s.

From the PASS re-review of [PR #36](https://github.com/DanielJBurbridge/omarchy/pull/36), [review 5870620048](https://github.com/DanielJBurbridge/omarchy/pull/36#pullrequestreview-5870620048). L14 and L15 above are the ones that review already counted as filed.

- L16. Relogin must force gaming and ignore the recovery latch and dock `auto`. Spec 02 still says the session applies `default`, which is gaming unless a latch says otherwise. That contradicts AC 57. `desktop()` still fail-closes if a latch sent the session to desktop with the lock on. Source: PR #36, review 5870620048. Owner: dev-ux.
- L17. Say that `/run/omarchy/handheld-autologin/{failures,stop}` are root-owned in `/run`. Source: PR #36, review 5870620048. Owner: dev-ux.
- L18. Align the stop trigger with AC 58: fire when the three timestamps span at most 60 s, not when the third timestamp is less than 60 s old. Source: PR #36, review 5870620048. Owner: dev-ux.
- L19. D10, F9 and AC 17 still say a spent D2 budget exits to SDDM and does not start another gaming attempt. Add the handheld Relogin / three-failure-stop exception already in §7.4. Source: PR #36, review 5870620048. Owner: dev-ux.
- L20. Tighten “a TDP writer may hold that lock for up to 5 s”. That 5 s is the acquire wait, and holds should stay well under the broker's 1 s so a timeout stays the exception. Source: PR #36, review 5870620048. Owner: dev-ux.

From [PR #34](https://github.com/DanielJBurbridge/omarchy/pull/34). The FAIL is [review 5870592622](https://github.com/DanielJBurbridge/omarchy/pull/34#pullrequestreview-5870592622). The PASS re-review is [review 5870966296](https://github.com/DanielJBurbridge/omarchy/pull/34#pullrequestreview-5870966296). The timeout hang from the FAIL is fixed on the PASS head and is not repeated here.

- L21. Spec 07 AC 17 wants `omarchy-rog-ally-input-gaming.service` `BindsTo=` and `After=` `omarchy-gaming-session.target`. What shipped is a drop-in on the desktop unit `omarchy-rog-ally-input.service`, with `PartOf=omarchy-gaming-session.target`. Deferred. Source: PR #34, reviews 5870592622 and 5870966296. Owner: input.
- L22. `omarchy-hw-physical-keyboard` still has no explicit `uhid` / `ID_BUS=uhid` case or test. Source: PR #34, reviews 5870592622 and 5870966296. Owner: input.
- L23. The 2 s uinput held-key fallback stays with the input PR. Source: PR #34, reviews 5870592622 and 5870966296. Owner: input.
- L24. A wheel user can call `reset` or `fail` through the NOPASSWD grant. `reset` clears the failure list and does not clear `stop`. `fail` can trip the guard and restart SDDM. The greeter stays available. Source: PR #34, review 5870966296.
- L25. **Open.** Shift and symbols are still absent from `default/sddm/omarchy/Main.qml`, and the row is on every machine's greeter. Backspace, space and enter are on that grid. Enter calls `sddm.login`. #39 / AUTH still own a complete VKB (AC 59). Source: PR #34, review 5870966296. Owner: AUTH.
- L26. After `stop` is written, choosing the handheld session entry exits 0 immediately. The regular desktop session is the way back in. Source: PR #34, review 5870966296. Fixed with L130: that entry now starts the Hyprland desktop once, with Relogin already false.
- L27. There is no migration that enables `omarchy-handheld-autologin.service` and runs `apply` on an existing Ally install. A new install that runs the hardware leaf is fine. An Ally that is already installed has to do that apply step itself ([ALPHA.md](ALPHA.md)). Source: PR #34, review 5870966296. Owner: install.
- L28. `test/handheld/power-rollback-test.sh` still loads `bin/omarchy-setup-rog-ally-power` from `c88d5344` (`HANDHELD_RELEASE_SHA` in `test/handheld/gaming-fixture.sh`). The test stays skipped while power is on hold. Source: PR #34, review 5870592622. The PASS review did not close it.

From dev-red's low notes on #10 packaging in the [PR #33](https://github.com/DanielJBurbridge/omarchy/pull/33) PASS review, [review 5870574866](https://github.com/DanielJBurbridge/omarchy/pull/33#pullrequestreview-5870574866).

- L29. **Superseded.** There is no `21-omarchy-ally-tdp-variant.hook` on this tip. Install is `bin/omarchy-ally-tdp-install`, run from `install/hardware/asus/ally-tdp.sh`. The session enable is `systemctl --global enable omarchy-ally-tdp-shim.service`, not a package-hook path unit. Source: PR #33, review 5870574866. Owner: #10 packaging.
- L30. **Superseded.** `write_recorded_spl` is not in the tree. `restore_ppd` in `bin/omarchy-ally-tdp-install` unmasks `power-profiles-daemon` from `/var/lib/omarchy/handheld/power-profiles-daemon.state` and does not read armoury. Source: PR #33, review 5870574866. Owner: #10 packaging.

From the PASS review of [PR #42](https://github.com/DanielJBurbridge/omarchy/pull/42) at `1dc4aa63`, [review 5871600455](https://github.com/DanielJBurbridge/omarchy/pull/42#pullrequestreview-5871600455). These four were not in this file when #42 merged. Filed 12 Nov 2026.

- L31. `next` survives a reboot. It lives in the state home, not `/run`. A crash in the middle of the handoff, plus a reboot, lands the next boot on the desktop once, then gaming. That matches AC 5: one autologin, then the one-shot is gone. A boot-id or runtime-dir marker would make an unexpected mode after reboot impossible if that ever matters. Source: PR #42, review 5871600455.
- L32. The Hyprland-socket waiter gives up after 60 s. If the socket appears later than that, a later logout can consume a leftover `next` and open the desktop once. Source: PR #42, review 5871600455.
- L33. A relogin that consumes `next=desktop` never sets `gaming_autologin_ready`. Logging out of that recovery desktop, without a later successful gaming start in the same process, records one `fail`. One count, not three, and the following relogin is gaming. Source: PR #42, review 5871600455.
- L34. `[[ -f $gaming_state/next ]]` follows a same-user symlink for the read. The directory is mode 0700 and user-owned, so this is not a cross-user write. Refusing `-L` would be defence in depth. Source: PR #42, review 5871600455.

From [spec 09](09-keyboard-free-boot.md), 16 Nov 2026. These are outside the alpha (the gaming session, autologin and the desktop power button). The research note is [research/touch-first-boot.md](research/touch-first-boot.md) via [PR #45](https://github.com/DanielJBurbridge/omarchy/pull/45).

- L35. The greeter needs `GreeterEnvironment` with `QT_IM_MODULE=qtvirtualkeyboard` so Qt Virtual Keyboard can submit by touch, and a touch or controller Back to Gaming that returns to the gaming session without the desktop password. The letter grid cannot do that. `[General] InputMethod=` stays unset. Same hole as L25, plus the return control. Source: spec 09 D3, research PR #47. Owner: AUTH.
- L36. K07 is a keypad drawn inside the lock: digits when the secret is a PIN, a full keypad when it is not. hyprlock 0.9.7 has no PIN pad, so this is not "turn hyprlock on". Before that keypad exists, no lock without a physical keyboard (spec 02 D11). Source: spec 09 D8, research PR #45 §4, §9, §10.5. Owner: AUTH. For that port: `omarchy-hw-physical-keyboard` sources `$OMARCHY_PATH/default/gaming/keyboard.sh`, which becomes `/default/gaming/keyboard.sh` when `OMARCHY_PATH` is unset, so the helper fails and the lock decision reads no keyboard. Source `/usr/share/omarchy/default/bash/env-bootstrap` when `OMARCHY_PATH` is unset, then the helper under that path. Do not invent a HOME fallback. That changes the K07 gate, so it stays with the lock port and out of the session PR.
- L37. `omarchy.polkit` takes exclusive keyboard focus and has no keyboard, so wvkbd cannot type into it. The dialog needs a keypad of its own, or polkit prompts stay off the handheld path (`allow_active` for the active local session where that is safe). A gap for wvkbd is not a fix. Turning `desktop-lock` off stays an interactive password, typed on that keypad. Source: spec 09 D7, research PR #47. Owner: AUTH.
- L38. **Fixed** in source. `install/hardware/asus/inputplumber.sh` installs inputplumber and the greeter pointer. `default/inputplumber/profiles/omarchy-ally-pointer.yaml` is the Omarchy map. `default/systemd/system/omarchy-ally-pointer.service` is `Before=display-manager.service`. The stock GPL composite is not copied. On-device stick motion stays L45. Source: spec 09, research PR #45 §6, §10.4, §11. Owner: input.
- L39. The first-boot wizard and buffyboard (spec 03) are not in the alpha. The gum form on tty1 still needs a keyboard. Source: spec 09 §1. Owner: INSTALL.
- L40. A Plymouth LUKS passphrase stays a USB or 2.4 GHz keyboard when the TPM does not unseal, or when the install chose a passphrase. The handheld default is TPM2 bound to PCR 7, with the recovery passphrase kept (spec 03 D9, spec 09 D9, revised 16 Nov 2026). unl0kr stays off the disk unlock until L68. Source: [tpm-unlock-installer-spec.md](tpm-unlock-installer-spec.md), [tpm-unlock.md](tpm-unlock.md). Owner: AUTH.
- L41. `omarchy-handheld-autologin apply` rewrites `zz-omarchy-handheld.conf` with `Session` and `Relogin` and no `User=`. Spec 02 §7.1 and research §11 want the installer-created user kept in that file. apply must not drop it and must not guess one. Source: spec 09 D4. Owner: session.

From the 16 Nov 2026 device findings and dev-red's review of the keyboard-free fallback, [review 5918323388](https://github.com/DanielJBurbridge/omarchy/pull/48#pullrequestreview-5918323388). L31–L41 stay as filed. The device notes are renumbered so they do not replace spec 09's entries.

- L42. mt7921e `Failed to start patch` / `hardware init failed` on `0000:06:00.0` happened on one boot and later boots associated. It is not rfkill. The hardware leaves run at install and first boot, so a per-boot PCI rebind does not fit that pattern and can drop a card that is already up. `omarchy-restart-wifi` does not reload firmware. Owner: hardware.
- L43. `omarchy-display-rog-ally` is on `feat/ally-parity-release-20261111` at `0fdba61` and is not on integ. Its verbs are status, native, touch, dock, handheld, vrr, hdr, gaming-output and gamescope-args. There is no `docked` verb, so `gaming_docked` stays undocked here. Relogin does not consult the helper. Porting the helper does not implement docked. Owner: display.
- L44. Lock-screen OSK stays out of scope until K07. Do not put wvkbd on the lock. Owner: AUTH.
- L45. InputPlumber's stock Ally composite creates a mouse target and does not map a stick to it. `default/inputplumber/profiles/omarchy-ally-pointer.yaml` is Omarchy's map, loaded by `omarchy-ally-pointer.service` before the greeter. Whether that stick moves the greeter pointer, and whether the profile stays loaded once Steam wants the gamepad, is unverified on device. The agent for password prompts is `omarchy.polkit`, not `hyprpolkitagent`. Whether that dialog accepts wvkbd while it is up is unverified. Owner: input.
- L46. apply rewrites `zz-omarchy-handheld.conf` and must not own `User=`. The installer file this branch writes is `/etc/sddm.conf.d/omarchy-handheld-user.conf`. Unencrypted installs delete `autologin.conf` after the first boot. L41 stays: spec 02 still wants the installer-created user kept where apply cannot drop it.
- L47. The Qt Virtual Keyboard style is back under `default/virtual-keyboard/`. `Main.qml` does not import it. An unresolved `QtQuick.VirtualKeyboard.Styles.Omarchy` import blanks the greeter, and `10-wayland.conf` does not set `QML_IMPORT_PATH` or `InputMethod`. The greeter uses Qt's own keyboard via `GreeterEnvironment`, plus backspace, space and enter on the grid. Wiring the Omarchy style needs the module on the Qt import path in the same package as `Main.qml`. Owner: AUTH.
- L48. The byte-identical bar-pin test exercises `BarModel.js`, which does not open the user's file. `shell.qml` (`storedShellConfig`, the early return, and the strip in `persistShellConfig`) has no test of its own. Reproduce that write decision in a node test, or move it into `BarModel.js`. Source: PR #48, review 5918323388.
- L49. A move, a removal, or a panel setting on a widget the handheld pin added is dropped, and the file is not written. `disabledPlugins` is the way to keep one of those widgets off, and the bar does not say so. Source: PR #48, review 5918323388.
- L50. `persistShellConfig` returns without writing when the config to save matches the stored one. That early return runs on every machine, not only an Ally. Source: PR #48, review 5918323388.
- L51. **Fixed** for the missing migration and the swallowed enable. `migrations/1794902400.sh` runs `install-greeter`. `migrations/1794988800.sh` runs `install-service` only when `omarchy-gaming-session` is present. `install/hardware/asus/inputplumber.sh` warns and names the command to re-run. It does not use `systemctl enable … || true`. Device motion stays L45. Source: PR #48, review 5918323388.
- L52. `migrations/1794830400.sh` does two jobs: the Ally `User=` write and `qt6-virtualkeyboard` for every machine. Upstream wants one problem per migration. The autologin half belongs with the gaming-session package. Source: PR #48, review 5918323388.
- L53. Gaming-session code sits in core rather than the opt-in `omarchy-gaming-session` package: `default/gaming/steam-ready.sh`, `bin/omarchy-session-start`, `bin/omarchy-gaming-steam`, `install-user`, and the `omarchy-provision-owner` hook. `packages/omarchy-gaming-session/PKGBUILD` ships the session and the desktop files. Source: PR #48, review 5918323388.
- L54. The bar pin matches the Ally with `isRogAllyDmi` and hard-coded DMI strings. A touch fix should be a touchscreen and no keyboard. `shellConfigForDisk` is an Ally branch on every machine's persist path. Source: PR #48, review 5918323388.
- L55. The greeter row for backspace, space and enter is on every machine's login screen. The labels are English and the colours are hard-coded. The plan shows that row only when there is a touchscreen and no keyboard. Source: PR #48, review 5918323388.
- L56. **Fixed.** The NOPASSWD grant for `fail`, `reset` and `apply` left the base `etc/sudoers.d/` tree. `packages/omarchy-gaming-session` installs it at `/etc/sudoers.d/omarchy-handheld-autologin`, mode 0440. `install-user` stays out of that file. Source: PR #48, review 5918323388.
- L57. The `Model:` trailer on commits is still an open question in the plan. Source: PR #48, review 5918323388.

From the PASS review of [PR #48](https://github.com/DanielJBurbridge/omarchy/pull/48) at `1b35fa47`, [review 5918767717](https://github.com/DanielJBurbridge/omarchy/pull/48#pullrequestreview-5918767717). L31, L33 and L34 already record the stale `next` marker across reboot, the fail count on recovery-desktop logout, and the symlink read. L42 and L43 already record the mt7921e `hardware init failed` retry and porting `omarchy-display-rog-ally` (there is still no `docked` verb). They are not repeated.

- L58. After the ready waiter times out, `omarchy-gaming-steam` keeps scanning `/proc` about every 1.2 s for the rest of the Steam session. Each `timeout 1s` write fails and the loop continues, because the reader is gone. Stop the scan after the timeout, or after one failed write. Medium. Source: PR #48, review 5918767717. Owner: session.
- L59. There is no way to clear `/run/omarchy/handheld-autologin/stop` except a reboot, which empties `/run`, or SSH. While `stop` exists, choosing the handheld session at the greeter exits 0 and SDDM returns to the greeter. Source: PR #48, review 5918767717. Owner: session.
- L60. The greeter has no Back to Gaming control. A touch or controller action should return to the gaming session without the desktop password. L35 names that control inside the greeter keyboard work. Low. Source: spec 09 D3, PR #48 review 5918767717. Owner: AUTH.
- L61. `wvkbd` is not in the pacman sync database. It is AUR. `omarchy-pkg-add wvkbd` and `pacman -S wvkbd` fail because the package is not in the sync db. The install path is `omarchy-setup-rog-ally-keyboard --install-reviewed-aur`, which calls `omarchy-pkg-aur-add`, after the PKGBUILD is reviewed. Do not add `wvkbd` to a repo package list. Owner: install.

From dev-red's FAIL review of the InputPlumber profiles, [PR #53](https://github.com/DanielJBurbridge/omarchy/pull/53), [review 5919651211](https://github.com/DanielJBurbridge/omarchy/pull/53#pullrequestreview-5919651211). Not fixed in that PR.

- L62. **Partial.** The gaming package now records an existing owner before installing the InputPlumber and TDP policies. If the owner is first provisioned after the package is installed, provisioning still needs to refresh those policies. Source: PR #53, review 5919651211.
- L63. `load pointer` does not set `InterceptMode` back to 0. The greeter oneshot and the crash-loop path leave a dead session's mode 2 in place, and the controller keeps feeding only the D-Bus target. Source: PR #53, review 5919651211.
- L64. **Partial.** The managed Desktop Mode requests `desktop` after Gaming stops and requests `pointer` again when Hyprland exits. Physical acceptance, direct exits from Gaming to SDDM and restoring the profile when the composite is recreated after suspend remain open. Source: PR #53, review 5919651211.
- L65. `gaming.yaml` targets `ds5-edge`. The Ally grips arrive as DualSense Edge Fn buttons, and Steam shows PlayStation glyphs, unless the glyph setting is changed. Whether Steam Input binds that pair is unverified on device. Source: PR #53, review 5919651211.
- L66. The package update removes `omarchy-ally-pointer-load` before migration `1794902400` rewrites `/etc/systemd/system/omarchy-ally-pointer.service`. A reboot in that window has touch at the greeter and no stick pointer. Source: PR #53, review 5919651211.
- L67. InputPlumber's own rules file grants YES to group `wheel` on every `org.shadowblip.Input*` action. The Omarchy user is normally in `wheel`, so the session can still call `LoadProfilePath` and the other InputPlumber methods. The allowlist holds for `sddm` and for users who are not in `wheel`. Source: PR #53, review 5919651211.

Rollback for the profile switch, when the gaming session package should stop owning InputPlumber profiles:

1. `sudo systemctl disable --now omarchy-inputplumber-profile.service`
2. Remove `/etc/systemd/system/omarchy-inputplumber-profile.service`, `/usr/share/dbus-1/system.d/org.omarchy.InputPlumberProfile.conf`, `/usr/share/polkit-1/actions/org.omarchy.inputplumber-profile.policy`, and `/etc/polkit-1/rules.d/50-omarchy-inputplumber-profile.rules`. Removing `omarchy-gaming-session` runs `post_remove`, which does those four removals and leaves `omarchy-ally-pointer.service`.
3. `sudo systemctl daemon-reload` and `sudo busctl call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig`.
4. The greeter unit stays, and its `ExecStart` is `omarchy-inputplumber-profile load pointer`. To drop the stick pointer as well, `sudo systemctl disable --now omarchy-ally-pointer.service`. The old `omarchy-ally-pointer-load` program is not in this tree, so there is no older loader to put back.

From the disk-unlock decision, 16 Nov 2026. The handheld default is TPM2 auto-unlock, PCR 7, recovery passphrase kept ([tpm-unlock-installer-spec.md](tpm-unlock-installer-spec.md)). This item is the other choice Daniel asked to have built.

- L68. **HIGH.** TPM2+PIN at the boot prompt. A numeric PIN, entered by touch or by the pad, when `systemd-cryptenroll --tpm2-with-pin=yes --tpm2-pcrs=7` enrolled the slot. The passphrase slot stays. The card on the install screen stays visible and unselectable until this exists. No-input TPM unlock plus SDDM autologin is [L129](alpha-followups.md). Daniel decides; no code change yet. Source: [tpm-unlock.md](tpm-unlock.md) §9, [tpm-unlock-installer-spec.md](tpm-unlock-installer-spec.md) D3. Owner: AUTH.

  What works today. systemd 262 on the checked RC71L accepts `--tpm2-with-pin=yes` and hardens the PIN with Argon2id. At boot, `systemd-cryptsetup` asks through `systemd-ask-password`. Plymouth (theme `omarchy`) draws bullets and has no keypad. The console agent needs a keyboard too. A USB or 2.4 GHz keyboard can type the PIN. Nothing else on this image can.

  Touch. The path is the `sd-unl0kr` hook from AUR `buffybox` (GPL-3.0-or-later; upstream buffybox, the old `unl0kr` split was removed in favour of that package). `sd-unl0kr` is a systemd password agent, so it can answer the TPM PIN, not only a LUKS passphrase. The UKI contains `hid-multitouch` and does not contain the I2C HID transport. The panel is `hid-multitouch` on `i2c_hid_acpi`. The modules that have to be added with the hook are `MODULES+=(i2c-hid i2c-hid-acpi hid-multitouch)`. Spec 03 has not accepted `buffybox` for disk unlock. `osk-sdl` is not a candidate: it was removed from the AUR in 2025, and postmarketOS replaced it with unl0kr.

  Pad. Not feasible without new work. The built-in pad is `xpad` (buttons `BTN_*`, d-pad `ABS_*`), and `xpad` is not in the UKI. unl0kr documents keyboards, mice, trackpads and touchscreens, not a gamepad. The N-KEY device (`hid-asus`) has function keys and chords, not digits. InputPlumber does not run in the initramfs.

  Proposed path. (1) dev-red reviews `buffybox` / `sd-unl0kr`, or an Omarchy agent that draws only digits, which is the target rather than unl0kr's full keyboard. (2) Add `i2c-hid`, `i2c-hid-acpi` and `hid-multitouch` to the UKI. (3) Run the agent on the `systemd-ask-password` socket in the initramfs, after `sd-encrypt`, without Plymouth taking the same request and leaving a bullet field with no keys. (4) Map the pad in that initramfs: d-pad and face buttons to digits. Do not start InputPlumber there. (5) Enrol with `--tpm2-with-pin=yes` and `--tpm2-pcrs=7`. Keep the passphrase slot. A wrong PIN counts toward the TPM dictionary-attack lockout; the passphrase slot still opens the disk. The fTPM lockout counter and recovery time are not measured on the RC71L yet (L76). (6) Acceptance on an RC71L with no USB keyboard: power on, enter the PIN by touch and by the pad, reach the gaming session. Plymouth's bullet field alone fails that check. The hook line is the core install, gated by `omarchy-hw-rog-ally` and the handheld variant, not `omarchy-gaming-session`.

From dev-red's FAIL on [PR #54](https://github.com/DanielJBurbridge/omarchy/pull/54), [review 5919985018](https://github.com/DanielJBurbridge/omarchy/pull/54#pullrequestreview-5919985018). The blockers in that review are answered in the docs. These are the items that review left open, plus the two HIGH items the blockers required.

- L69. **HIGH.** Secure Boot on the handheld path. With Secure Boot off, PCR 7 auto-unlock protects a drive removed from the handheld and does not protect the handheld at rest. The work is `sbctl` or Limine enrolment, signed Limine and UKI, `editor_enabled: no`, then re-enrol PCR 7. A one-shot `limine enroll-config` hash of `/boot/limine.conf` panics on the next `limine-update` or snapper rewrite once Secure Boot is on ([#15524](https://github.com/omacom/omarchy/issues/15524)). The enrol that survives that rewrite is limine-entry-tool: `limine-install --fallback` first, `ENABLE_ENROLL_LIMINE_CONFIG=yes`, and the `limine-reset-enroll` / `limine-enroll-config` hooks. PCR 15 (`tpm2-measure-pcr=yes`), `systemd-pcrlock`, or a signed PCR 11 policy (`ukify --pcr-private-key`) is the binding that also covers the volume-confusion attack. Not the no-input default. Source: PR #54, review 5919985018, B1. Owner: boot.
- L70. **HIGH. Blocking.** Do not ship an installer that enrols a TPM, or that switches the handheld to `sd-encrypt`, until `luks_dump_slots`, `luks_rekey_retire` and `luks_rekey_verify` in `install/provisioning/luks-rekey.sh` keep keyslots bound to a `systemd-tpm2` token and the recovery slot. Record that slot through `luks_record_slots recovery=`. Cover it with a `test/shell.d/` test. Today's retire kills every slot except the owner, and verify fails unless that is the only slot. The ISO must keep the busybox line and `cryptkey=` until rekey is `done`, because `sd-encrypt` does not read `cryptkey=`. This change does not patch the script. Source: PR #54, review 5919985018, B4. Owner: install.
- L129. **HIGH.** Daniel decides; no code change yet. With TPM no-input unlock, SDDM autologin gives anyone who powers on the device a passwordless session. It persists after `omarchy-gaming-session` is removed, because upstream's `autologin.conf` stays. Options: (1) TPM enrolment removes desktop autologin. (2) Autologin is allowed only with TPM+PIN (L68). (3) Switching from gaming to desktop requires the user's password. Source: dev-lead, and [PR #56](https://github.com/DanielJBurbridge/omarchy/pull/56) review [5920790949](https://github.com/DanielJBurbridge/omarchy/pull/56#pullrequestreview-5920790949) item 5. Sits with L68–L70. Owner: Daniel.
- L71. F1, lockout visibility. The install card body now says a failed automatic unlock needs a USB or 2.4 GHz keyboard, and the PCR 7 lists name fwupd/LVFS dbx updates, an AMD fTPM reset answered yes, a TPM clear, and that SSH cannot help at the initramfs prompt. Left here so the re-check can see the review item. Nothing further is open in the copy. Source: PR #54, review 5919985018, F1.
- L72. F2, the cmdline install check. The runbook no longer uses `exit 1`, and a failed `grep -q` for `tpm2-device=auto`, `root=` or `rd.luks.name=` prints `stop` and does not copy the file. Left here so the re-check can see the review item. Source: PR #54, review 5919985018, F2.
- L73. F3, UKI cmdline. Section 7 stops when the UKI cmdline has no `root=`, lacks `tpm2-device=auto`, or still has `cryptdevice=`. Left here so the re-check can see the review item. Source: PR #54, review 5919985018, F3.
- L74. F4, which package owns the hook line. The spec names the core install, gated by `omarchy-hw-rog-ally` and the handheld variant, writing `etc/mkinitcpio.conf.d/00-omarchy-hooks.conf` or a drop-in that package owns. It is not `omarchy-gaming-session`. Left here so the re-check can see the review item. Source: PR #54, review 5919985018, F4.
- L75. F5, the `--tpm2-pcrs=` default. The runbook cites systemd 258: the PCR mask defaults to empty, and earlier versions bound literal PCR 7 when the option was omitted. The Ally's systemd is 262. Left here so the re-check can see the review item. Source: PR #54, review 5919985018, F5. [systemd v258 NEWS](https://github.com/systemd/systemd/releases/tag/v258).
- L76. F6. **Open.** L68's dictionary-attack note is right. State the fTPM lockout counter and the recovery time once they are measured on the RC71L. Do not invent the numbers. Source: PR #54, review 5919985018, F6. Owner: hardware.

From the delta re-check of [PR #54](https://github.com/DanielJBurbridge/omarchy/pull/54), [review 5920097123](https://github.com/DanielJBurbridge/omarchy/pull/54#pullrequestreview-5920097123). The PASS review [5920160117](https://github.com/DanielJBurbridge/omarchy/pull/54#pullrequestreview-5920160117) left F-a to F-d open. They are answered in the docs.

- L77. F-a, the PIN enrolment gate. Section 9 of [tpm-unlock.md](tpm-unlock.md) now repeats section 8's gate: the header backup is still on the removable drive and non-empty, and `/var/lib/omarchy/provisioning/luks-rekey.state` is absent. The installer spec gives PIN enrolment that same gate. Left here so the re-check can see the review item. Nothing further is open in the copy. Source: PR #54, review 5920097123, F-a.
- L78. F-b, the header backup disk. The section 2 check compares `lsblk -no PKNAME` of the backup filesystem with the LUKS device and stops when they are the same disk, which includes the ESP and any other partition of it. The copy says the file has to leave the internal disk. Left here so the re-check can see the review item. Nothing further is open in the copy. Source: PR #54, review 5920097123, F-b.
- L79. F-c, unset `LUKS_DEV` and `backup`. Each section that expands them sets them at the top, including a fresh shell and the live ISO in section 13 and in [ALPHA.md](ALPHA.md). Left here so the re-check can see the review item. Nothing further is open in the copy. Source: PR #54, review 5920097123, F-c.
- L80. F-d, `limine enroll-config` arguments. The hardening section names the two arguments in prose: the Limine EFI executable, then the 128-character BLAKE2B-512 of the config (`b2sum -l 512`), and `--reset` as the clear. The one-shot runnable enrol is not the procedure. That panic, and the entry-tool re-enrol, are L69. Left here so the re-check can see the review item. Nothing further is open in the copy of the arguments. Source: PR #54, review 5920097123, F-d.

From dev-red's FAIL on [PR #55](https://github.com/DanielJBurbridge/omarchy/pull/55), [review 5920728504](https://github.com/DanielJBurbridge/omarchy/pull/55#pullrequestreview-5920728504). B1 is answered in the hardening section. The six follow-ups stay open. Integ's list ends at L76. L77–L80 are the resolved #54 notes and do not collide with it.

- L81. B1. The hardening section no longer runs `limine enroll-config`. A one-shot hash of `/boot/limine.conf` panics after `limine-update` or a snapper rewrite once Secure Boot is on ([#15524](https://github.com/omacom/omarchy/issues/15524)). The enrol is deferred to L69. The supported path is prose only: `ENABLE_ENROLL_LIMINE_CONFIG=yes`, `limine-enroll-config` with the snapshot hooks, and `limine-install --fallback` first. Recovery is Secure Boot off in firmware, or a live USB and `limine enroll-config --reset`. Left here so the re-check can see the review item. Nothing further is open in the copy. Source: PR #55, review 5920728504, B1.
- L82. F1. **Open.** Section 8 says to stop when the PCR 7 log has no `os-separator` line. The enrolment command is not inside `if sudo systemd-pcrlock log --pcr=7 | grep -q os-separator`. Source: PR #55, review 5920728504, F1.
- L83. F3. **Open.** The PCR pin block in section 8 enrols a second TPM slot and does not pass `--wipe-slot=tpm2`, so the slot from the plain enrolment stays. The pin has to be this Ally's sha256. Source: PR #55, review 5920728504, F3.
- L84. F4. **Open.** Before the unseal reboot, prove the token with `cryptsetup open --test-passphrase --token-only --token-type systemd-tpm2`, or `systemd-cryptsetup`. Section 8 compares `tpm2-policy-hash` with the PCR sha256 instead. Source: PR #55, review 5920728504, F4.
- L85. F5. **Open.** The path read on the RC71L is `/boot/EFI/limine/limine_x64.efi`. This tree does not name that file, and nothing checks `[[ -f ]]` before an enrol. Source: PR #55, review 5920728504, F5.
- L86. F2. **Open.** The runbook says os-separator extends PCR 7. `systemd-pcrosseparator.service` extends PCRs 0-7, 9 and 12-14. Name those registers. A later 7+14 or 0+7 binding has the same gap. Source: PR #55, review 5920728504, F2. [systemd-pcrosseparator.service(8)](https://man.archlinux.org/man/systemd-pcrosseparator.service.8.en).
- L87. F6. **Open.** "What other images bind" does not name the licences of the linked peers (ublue-os and Bazzite are Apache-2.0, Limine's docs are BSD-2-Clause) or say that only commands are cited and nothing is copied. Source: PR #55, review 5920728504, F6.

From [11](11-undocked-touch-desktop.md), 16 Nov 2026. The spec is the undocked Hyprland desktop. These are the build items it names. None of them block the spec. L64 already records that nothing loads `desktop` when a gaming session ends, and L43 already records that `omarchy-display-rog-ally` is not on this branch. They are not repeated. Open PR #55 already uses L77–L87, so these start at L88.

- L88. Trial a bottom-centre swipe handle to show the themed keyboard on the undocked desktop. Apps stays under Menu → Apps. Test typing into the focused app, scrolling beside the handle and reaching the keyboard’s bottom row. The handle must yield during lock, authentication and fullscreen. The remaining gesture proposals and their fallback controls are in [undocked touch desktop §4](11-undocked-touch-desktop.md#4-gestures). Owner: shell.
- L89. Auto-show wvkbd for clients that are not the shell, on text focus, and hide that auto-shown keyboard on blur. Unlocked session only. The lock, polkit and the greeter stay excluded. The keyboard helper gates itself and does not edit the lock. fcitx5 keeps Hyprland's input-method slot. `wvkbd --auto` and squeekboard are the wrong default while that slot is taken. A manual toggle already ships. Source: undocked touch desktop §3, OQ-5, spec 07 D2. Owner: TOUCH.
- L90. Touch scale and hit size, in core, off under the same gate as L88. Internal panel scale 1.5 unless the user chose Larger or Largest (spec 06). Menu rows, bar controls, and notification dismiss and actions are at least 44 logical px, in the current theme. A docked monitor keeps its saved scale. No theme fork. Source: undocked touch desktop §5, §11. Owner: shell.
- L91. While wvkbd is visible the session loads `osk` and restores the previous profile on hide, stop, or the process exiting. B returns to right click. Loading `desktop` on Switch to Desktop stays L64. Source: undocked touch desktop §3, §6. Owner: input.
- L92. Do not install AUR `hyprgrass-git` for L88. It depends on `hyprland-git`. Use `hyprpm` against a hyprgrass commit that builds on the extra `hyprland` this tree ships, and rebuild when Hyprland updates. The plugin is still alpha. Source: undocked touch desktop §4. Owner: shell.

From the ready-waiter fix, [PR #57](https://github.com/DanielJBurbridge/omarchy/pull/57), merged as `aa8c14fb`. These stay open.

- L120. **Open.** `test/shell.d/gaming-steam-ready-test.sh` covers an unreadable status (`chmod 000` on the middle `status`). Add an ENOENT case where that status vanishes between the glob and the read. Source: PR #57. Owner: session.
- L121. **Open.** `steam_tree_has_ui` in `default/gaming/steam-ready.sh` reads `key` and `value` in the status loop and does not declare them `local`. Source: PR #57. Owner: session.
- L122. **Open.** After a waiter timeout, the full `/proc` scan still polls. Check the battery cost. If it matters, use awk per file or a slower poll. L58 is the "stop the scan" item. This one is the cost of the scan that still runs. Source: PR #57. Owner: session.

From dev-red's PASS on [PR #56](https://github.com/DanielJBurbridge/omarchy/pull/56), [review 5920790949](https://github.com/DanielJBurbridge/omarchy/pull/56#pullrequestreview-5920790949), at `4cd0ddbe`. The passwordless desktop is L129, filed with L68–L70. These stay open.

- L123. **Open.** `post_remove` in `packages/omarchy-gaming-session/omarchy-gaming-session.install` deletes `omarchy-handheld-user.conf` and leaves `zz-omarchy-handheld.conf` (`Session=omarchy-handheld.desktop`) pointing at a removed session until the next boot's `apply`. Source: PR #56, review 5920790949. Owner: session.
- L124. **Open.** `warn_profile_step` prints `re-run: omarchy-inputplumber-profile …` and leaves out `sudo`. Source: PR #56, review 5920790949. Owner: session.
- L125. **Open.** An encrypted Ally keeps upstream `autologin.conf` and the handheld `User=` file, so two `User=` lines. They are the same name today. The handheld file wins on a mismatch. Source: PR #56, review 5920790949. Owner: session.
- L126. **Open.** The production scriptlet and `default/gaming/sddm-user.sh` honour `OMARCHY_SDDM_CONF_DIR` and `OMARCHY_SDDM_STATE`. Those overrides are for tests. A root shell with them set writes or deletes the wrong path. Ignore them unless a test flag is set. Source: PR #56, review 5920790949. Owner: session.
- L127. **Open.** #56's PR body says 1.0.0-2 had no `post_upgrade` and no `remove-service`. It had both. The pkgrel bump is still right because the scriptlet changed. Correct the body. Source: PR #56, review 5920790949.
- L128. **Open.** The attribution headers in `default/gaming/sddm-user.sh`, `steam-path.sh` and `steamos-update` say Pizzarchy and the commit `daa9376a`, and do not name the repo `https://github.com/villenull/Pizzarchy`. The MIT notice stays. Source: PR #56, review 5920790949.

From the re-check of [PR #61](https://github.com/DanielJBurbridge/omarchy/pull/61), [review 5920915276](https://github.com/DanielJBurbridge/omarchy/pull/61#pullrequestreview-5920915276), and the #60 notes folded into [brief-power-button.md](research/brief-power-button.md). L77–L103 are claimed by other open PRs. This range is L104–L111.

- L104. B1. The TDP brief now follows overlay §5.1. Battery `--set 25` applies 20/20/25, AC `--set 30` applies 30/43/53 on the stock tables, and replug restores 30/43/53. The writer reads live `min_value`, `max_value` and `default_value` and clamps to those. `bin/omarchy-ally-tdp-apply` and `test/shell.d/ally-tdp-test.sh` implement that. On-device stays L170 and L183. Left here so the re-check can see the review item. Source: PR #61, review 5920915276, B1.
- L105. F1. The writer gates on `omarchy-hw-rog-ally`. Recorded in the brief. Source: PR #61, review 5920915276, F1.
- L106. F2. The polkit rule denies `sddm` and adds no `wheel` grant. The shim only pkexecs `--set` and `--reassert`. D1's `allow_active=yes` sign-off is still outstanding. Source: PR #61, review 5920915276, F2. Owner: dev-red.
- L107. F3. AC sysfs `default_value` is 30/43/53, because the struct leaves `_def` unset and the driver reports the max. Recorded. Source: PR #61, review 5920915276, F3.
- L108. F4. `set_tdp_limit` checks `is_active`, then the live SPL range, then SPPT and FPPT `min_value`, then writes SPL, SPPT, FPPT. `current_value` is the getter. Recorded. Source: PR #61, review 5920915276, F4.
- L109. **Open.** No fallback is built if Steam ignores `steam://shortpowerpress` and `steam://longpowerpress`. The proposed wrapper fallback is in the power-button brief. Source: PR #60, review 5920908119. Owner: power.
- L110. **Open.** Measure the RC71L firmware long-hold force-off time. It is the only escape outside gamescope (spec 09 OQ-7). Do not invent the duration. Source: PR #60, review 5920908119. Owner: hardware.
- L111. AUR `steamos-powerbuttond` 4.2-3 `make install` paths are recorded. Do not take Bazzite's 4.2-2 debounce patch ([bazzite#6180](https://github.com/ublue-os/bazzite/issues/6180)). Source: PR #60, review 5920908119.

From dev-red's read-only review of the keyboard-free boot path on integ `a5593dac8532e9160abd937d5a4aab625c52e5ad`, 16 Nov 2026. It was read from the code and docs only. Nothing ran on the Ally. The path is power-on, Plymouth/LUKS, SDDM autologin, the gaming session, the Steam ready waiter, the switch to the desktop, and the crash-loop fallback.

Integ ships no TPM code. The hook line is still the busybox `encrypt` line in `etc/mkinitcpio.conf.d/00-omarchy-hooks.conf:34`. TPM unlock exists only as the manual runbook ([tpm-unlock.md](tpm-unlock.md)) and the draft installer spec. The TPM items below are about that runbook and spec.

These are already filed and are not repeated:

- Enrolling before the first `sd-encrypt` boot, and the gate not wrapping the enrol command: L82, L86.
- `limine enroll-config` with Secure Boot: L69, L80, L81.
- The passphrase fallback needs a USB or 2.4 GHz keyboard, and there is no keypad in the initramfs: L40, L68, L71.
- The rekey deletes TPM slots: L70.
- TPM no-input unlock plus autologin: L129.
- After package removal, `zz-omarchy-handheld.conf` still names the removed session: L123.
- `stop` is cleared only by a reboot: L59.
- The waiter keeps scanning after it times out: L58, L122.
- The stop-trigger wording: L18.
- Sudoers and polkit scope: L24, L56, L62, L67, L106.
- No enable migration on existing Allys: L27.

No new root-service, udev or polkit grant was found. Ranked by severity. Nothing here is a blocker on integ as it stands.

- L130. **Fixed.** The crash-loop stop does not see every failed start. If the supervisor exits before it arms the trap, is killed, or calls `fail` as a no-op, SDDM `Relogin=true` restarts the session with no limit, and the screen stays black or flickers. Source: dev-red boot-path review, `a5593dac`. Owner: session.

  Where. `bin/omarchy-session-start:164` sets `trap cleanup EXIT`, and `cleanup` is the only caller of `omarchy-handheld-autologin fail` (`:158-161`). Two earlier exits skip it: `:111` (`gaming_state_init && gaming_runtime_init || exit 1`) and `:114` (flock busy). SIGKILL of the supervisor skips it too. `bin/omarchy-handheld-autologin:24-29` turns `fail` into a silent `exit 0` when `sudo -n -l` refuses, for example when `/etc/sudoers.d/omarchy-handheld-autologin` is missing or a later sudoers rule overrides it.

  Scenario.
  1. Boot.
  2. `apply` writes `Relogin=true`.
  3. SDDM autologins `omarchy-handheld.desktop`, which runs `exec omarchy-session-start relogin` (`bin/omarchy-handheld-autologin:145`).
  4. The supervisor exits at `:111`. One way: `~/.local/state/omarchy/gaming-session` is not owned by the user after a root-run tool, so `-O` fails.
  5. No `fail` stamp is written, so `stop` never appears.
  6. SDDM relogs in at once, and the loop has no limit.
  7. The loop survives a reboot, because the cause is on disk.
  8. Nothing on screen takes input. Bazzite shows the same SDDM relogin black-screen loop when its session exits early ([bazzite#3282](https://github.com/ublue-os/bazzite/issues/3282), [bazzite#5125](https://github.com/ublue-os/bazzite/issues/5125)).

  Recovery.
  - Over SSH: `sudo install -D -m 0644 /dev/null /run/omarchy/handheld-autologin/stop && sudo omarchy-handheld-autologin apply && sudo systemctl restart sddm`.
  - With a USB keyboard: Ctrl+Alt+F3, or the Limine editor with `systemd.unit=multi-user.target`.
  - There is no route without a keyboard.

  Fix.
  - Record the attempt first and clear it on ready. Have the `session` action call `fail` before the `exec`, and keep `reset` on the ready read. Early exits and SIGKILL then count.
  - Make the non-root `fail` path log to the journal (`logger -t omarchy-handheld-autologin`) when the grant is missing, instead of exiting 0 silently.
  - Add a test that kills the supervisor before the trap and expects `stop` after three runs.

  Fixed. The attempt is recorded in the gaming state directory before Gamescope starts, so an early exit and a SIGKILL still count across relogin and reboot. Three failures start the Hyprland desktop with the on-screen keyboard and pin Relogin off. A `fail` that cannot become root is logged and returns non-zero. Ready and an explicit Switch to Desktop clear the count.

- L131. **HIGH.** Daniel decides; no code change yet. On an unencrypted handheld, the gaming package makes autologin permanent. Upstream removes `autologin.conf` after the first boot, so later boots ask for the SDDM password. Here, the `User=` file and `Relogin=true` keep the autologin, and with `desktop-lock` `default-off`, Switch to Desktop is an unlocked desktop on an unencrypted disk. L129 names only the TPM case. This is the same exposure with no disk encryption at all. Source: dev-red boot-path review, `a5593dac`. Sits with L129. Owner: Daniel.

  Where:
  - `bin/omarchy-provision-owner:782` writes `omarchy-handheld-user.conf`.
  - `:789` removes only `autologin.conf` on unencrypted installs.
  - `bin/omarchy-handheld-autologin:101-115` writes `Session=` and `Relogin=true` on every boot.
  - `default/gaming/session.sh:96-99` makes `default-off` effective.
  - Spec 09 says "An already-unencrypted disk still has no passphrase prompt" ([09-keyboard-free-boot.md](09-keyboard-free-boot.md) line 51). Nothing at install or package time tells the owner.

  Scenario.
  1. Unencrypted install on an Ally, with the gaming package.
  2. Anyone who powers the device on gets Steam, Switch to Desktop, the user's files, and sudo prompts.
  3. Pulling the drive also reads everything.

  Recovery. Remove the package, or run `omarchy-setup-gaming-session desktop-lock on`.

  Fix. Use L129's options, plus one of these:
  - `apply` writes the handheld autologin only when `/` is on dm-crypt.
  - The package or installer step states the trade-off and needs an explicit yes.

- L132. Medium. The crash-loop window is shorter than a slow failure. Three stamps within 60 s write `stop` (`bin/omarchy-handheld-autologin:167`, `:176`). A supervisor run where Gamescope comes up and Steam never becomes ready takes at least 123 s: two 60 s waits (`bin/omarchy-session-start:199-200`), plus the 3 s retry (`:325`, `:343-344`), before `desktop()`. If `desktop()` also fails fast (Hyprland crash after a Mesa or kernel update), each relogin adds one stamp about 2 minutes after the last. Three never fall inside 60 s, so `stop` never trips, and the device loops through 2-minute black Gamescope screens. L18 is only the spec wording. Source: dev-red boot-path review, `a5593dac`. Owner: session.

  Recovery. Same as L130.

  Fix.
  - Count consecutive starts since the last `reset`, not a 60 s window. Or size the window from the ready timeout: at least 2 × timeout + gap + margin.
  - Peer: `gamescope-session-plus`, which Bazzite runs, counts every session shorter than 60 s. It falls back to desktop at 5, however far apart they are, and only a session of 60 s or more rearms it ([gamescope-session-plus](https://github.com/ChimeraOS/gamescope-session/blob/main/usr/share/gamescope-session-plus/gamescope-session-plus)).

- L133. Medium. `omarchy-update-firmware` (Update › Firmware) runs `fwupdmgr update` with no TPM check (`bin/omarchy-update-firmware:17-18`). L71 puts fwupd/LVFS dbx updates in the install-card copy. The tool that applies them says nothing. Source: dev-red boot-path review, `a5593dac`. Owner: boot.

  Scenario.
  1. A TPM-enrolled Ally, with no keyboard.
  2. Update › Firmware applies a UEFI dbx or capsule update.
  3. PCR 7 changes.
  4. Next boot: Plymouth passphrase prompt, with no input that can type it. The token stays sealed until re-enrolled ([tpm-unlock.md](tpm-unlock.md) §14).

  Recovery. A USB or 2.4 GHz keyboard and the recovery passphrase, then §14's re-enrol. The Ally has one USB-C port, so that keyboard needs a USB-C cable or an adapter.

  Fix. On a disk with a `systemd-tpm2` token, `omarchy-update-firmware` should:
  - list the pending devices;
  - say that automatic unlock will stop;
  - refuse unless the user confirms and a physical keyboard is attached (`omarchy-hw-physical-keyboard`).

- L134. Medium. On the runbook machine, a kernel update can fail without any message. The `zz-tpm-sd-encrypt.conf` line freezes the whole hook array ([tpm-unlock.md](tpm-unlock.md) section 4, the `HOOKS=(…)` block). A later `00-omarchy-hooks.conf` baseline change is dropped without notice. If `limine-mkinitcpio-hook` renames or drops `sd-btrfs-overlayfs`, the rebuild fails. `limine-mkinitcpio` still exits 0 on a failed kernel (`bin/omarchy-hibernation-setup:125`), and on x86 `omarchy-update-boot` verifies nothing (`bin/omarchy-update-boot:7-11`). The update then reports success with a stale or missing UKI. Source: dev-red boot-path review, `a5593dac`. Owner: boot.

  Scenario.
  1. `omarchy update` brings a new kernel and a hook package that no longer has `sd-btrfs-overlayfs`.
  2. The UKI rebuild fails, and the update says done.
  3. On reboot, the old UKI loads a kernel whose modules are gone, or the entry is missing.
  4. The result is a black screen or the Limine menu.

  Recovery. A keyboard for a Limine snapshot entry, or the live-USB path in [tpm-unlock.md](tpm-unlock.md) §13.

  Fix.
  - Land spec D5: a package-owned, Ally-gated hook line, so no long-lived `zz-` file.
  - Until then, add a pacman hook after `linux*`, `mkinitcpio` and `limine*` upgrades that re-runs the runbook §7 UKI check: `systemd`, `sd-encrypt`, `sd-btrfs-overlayfs`, `libtss2`, `tpm2-device=auto`. It fails the update loudly.

- L135. Medium. A snapshot restore undoes the TPM boot config. `omarchy-snapshot restore` runs `limine-snapper-restore` (`bin/omarchy-snapshot:46-48`). Restoring a snapshot taken before the runbook reverts `/etc/mkinitcpio.conf.d/zz-tpm-sd-encrypt.conf` and `/etc/default/limine`. The next rebuild is the busybox `encrypt` image with `cryptdevice=`. The TPM slot stays in the header and is never used, so every boot asks for the passphrase. The runbook's section 2 snapshot is exactly such a snapshot. Source: dev-red boot-path review, `a5593dac`. Owner: boot.

  Recovery. A keyboard at every boot until runbook §4–§7 are re-run. The existing token unseals again once the `sd-encrypt` line is back and PCR 7 has not changed.

  Fix.
  - Spec D5: the hook line lives in a package file, not in `/etc`.
  - Until then, `omarchy-snapshot restore` warns when the header has a `systemd-tpm2` token and the target root lacks `tpm2-device=auto` in `/etc/default/limine`.

- L136. Medium. An offline first boot never reaches gaming, and the desktop it falls back to cannot join Wi-Fi without a keyboard. Expected from the code; unverified on the device. Source: dev-red boot-path review, `a5593dac`. Related: L39, L61. Owner: session.

  Scenario.
  1. Fresh install, no network.
  2. Steam's bootstrap needs to download its client.
  3. Its update or error window is an X client in the Steam tree. `steam_tree_has_ui` therefore writes `started` (`bin/omarchy-gaming-steam:35-39`), and `reset` clears the counter.
  4. Dismissing the dialog makes Steam exit non-zero within 120 s, which counts as a failure (`bin/omarchy-session-start:302-313`).
  5. One retry, then the recovery desktop (`:337-341`).
  6. wvkbd is AUR and not installed by default (L61), so the Wi-Fi passphrase cannot be typed.
  7. Every boot repeats this, because relogin forces gaming (L16).

  Recovery. A USB keyboard on the desktop, or a USB-C Ethernet adapter.

  Fix.
  - Check connectivity and Steam bootstrap state before starting Gamescope. When offline and the client is not yet bootstrapped, open a touch-usable network join instead of Steam.
  - Or bring the on-screen keyboard (L89) into the recovery desktop.

- L137. Medium. PCR 7 is not firmware-only on this path. Unverified. The `sd-encrypt` initrd extends PCR 7 with `os-separator` before cryptsetup ([tpm-unlock.md](tpm-unlock.md), section 8). So a systemd update that adds or changes a PCR 7 measurement in the initrd changes the sealed value. Booting an archived snapshot UKI built with another systemd can do the same. [tpm-unlock.md](tpm-unlock.md) "Security, in plain words" and [tpm-unlock-installer-spec.md](tpm-unlock-installer-spec.md) section 2 say a kernel or UKI rebuild never stops automatic unlock. That is true only while the initrd's PCR 7 events stay the same. Source: dev-red boot-path review, `a5593dac`. Related: L86. Owner: boot.

  Scenario. A routine `omarchy update` with a systemd that measures differently in the initrd. On the next boot the TPM does not unseal, and the device stops at the passphrase prompt with no keyboard.

  Recovery. A keyboard and the passphrase, then §14's re-enrol.

  Fix.
  - Qualify the "survives rebuilds" copy.
  - Ship spec section 7's "Automatic unlock stopped working" toast before any installer offers TPM.
  - Longer term, `systemd-pcrlock` or a signed policy (L69).

- L138. Low. The session sets no Steam reboot or shutdown sentinel. ChimeraOS's Steam session exports `STEAMOS_STEAM_REBOOT_SENTINEL` and `STEAMOS_STEAM_SHUTDOWN_SENTINEL` as a "workaround for steam getting killed immediately during reboot", and runs the reboot itself after Steam exits ([sessions.d/steam](https://github.com/ChimeraOS/gamescope-session-steam/blob/main/usr/share/gamescope-session-plus/sessions.d/steam)). `bin/omarchy-gaming-steam:9-11` sets neither. Restart or Shut down from Steam's power menu may kill Steam while it is writing config or cloud saves. The device effect is unverified. Source: dev-red boot-path review, `a5593dac`. Owner: session.

  Fix. Set both variables to paths under `$OMARCHY_GAMING_RUNTIME`, and act on them in `run_gaming` after the scope exits. The variable names are Steam's interface. Check the gamescope-session licence before copying any of its code.

- L139. Low. An Ally without the gaming package still locks with no keyboard. `gaming_lock_decision` returns `allow` when `gaming_handheld_variant` fails (`default/gaming/session.sh:178-181`). A desktop-only Ally, or one whose package was removed (L123), then locks on idle and before suspend. That lock has no on-screen keyboard (L44), so the device stays locked until a keyboard is attached. It is stock behaviour on any touch device, but the removal path in this tree leads straight to it. Source: dev-red boot-path review, `a5593dac`. Owner: AUTH.

  Recovery. Plug in a keyboard, or hold the power button to force it off (L110).

  Fix. Base the no-keyboard rule on `omarchy-hw-rog-ally` plus touch-and-no-keyboard, not on the package. Or remove the package with a notice that the lock will need a keyboard.

How peers compare. Bazzite binds PCR 7+14 with the passphrase kept, and Secure Boot is optional (already in [tpm-unlock.md](tpm-unlock.md)). CachyOS publishes no TPM default. For the session, Bazzite runs `gamescope-session-plus`:

- It counts short sessions in `/tmp` and falls back to the desktop after 5, which L130 and L132 would match in spirit.
- Its recovery re-extracts the Steam bootstrap, which can overwrite Steam settings ([bazzite#4045](https://github.com/ublue-os/bazzite/issues/4045)). Do not copy that part.
- Neither peer offers a keyboard-free disk-unlock fallback.

From the relogin fail-limit fallback. This range is L140–L149.

- L140. **Open.** `fail` as root reads `~/.local/state/omarchy/gaming-session/start-failures` through `SUDO_USER`, because sudo strips the environment. A relocated `XDG_STATE_HOME` still falls back to the desktop in the session, but this `fail` does not see that count, so it may leave Relogin on and a crashing desktop can start again. Owner: session.
- L141. **Open.** A second login that loses the session flock increments the same `start-failures` count. Three of those can latch the desktop while a healthy gaming session is still up. Owner: session.
- L142. **Open.** The in-process retry still uses the ordinary recovery latch and `desktop()`, with no on-screen keyboard. The keyboard starts only when the count reaches 3. An offline Steam dialog that returns before that still lands on the earlier desktop. Owner: session.
- L143. **Open.** The on-screen keyboard waiter gives up after 60 s if no Hyprland socket appears. A missing `wvkbd` (L61) is logged and the desktop still starts. Owner: session.
- L144. **Partial.** The managed fail-limit desktop now accepts one explicit Switch to Gaming through the regular logout worker. If that attempt fails, it returns to recovery. The root relogin stop remains pinned. Fixture checks pass. The device needs a fresh candidate with this change for physical verification. Source: PR #70, review 5922156206. Owner: session.
- L145. **Open.** Without the root grant, Relogin stays on. A crashing fallback Hyprland relogs with no limit, because the fallback does not count as another failure. This covers the locked path too: when desktop-lock is required and no physical keyboard is attached, the fallback exits 1 without pinning Relogin, so the greeter starts the session again and the device loops at a black screen. The passwordless grant is shipped today, so this does not block. Source: PR #70, review 5922156206, review 5922350588. Owner: session.
- L146. **Open.** `caller_failure_count` runs as root and then reads a user-owned path. A file swapped for a FIFO after the `-f` check blocks that read, and the parent directories are not symlink-checked. Only digits are used. Source: PR #70, review 5922156206. Owner: session.
- L147. **Open.** The fallback's own `fail` can be the third stamp inside 60 s. That restarts SDDM and leaves the greeter instead of the desktop. Source: PR #70, review 5922156206. Owner: session.

From the PASS review of [PR #65](https://github.com/DanielJBurbridge/omarchy/pull/65) at `00aecbec`, [review 5921631571](https://github.com/DanielJBurbridge/omarchy/pull/65#pullrequestreview-5921631571). This range is L150–L159. L150, L151 and L155 are fixed. L152–L154, L156 and L157 stay open. L158–L159 are held.

- L150. **Fixed.** Ready fired on any Steam X client, including the bootstrap, the updater, and the offline error dialog. A fast failure was counted as a healthy start and `reset` cleared the crash counter. Ready now requires `steamwebhelper` to hold the display socket.
- L151. **Fixed.** The ready scan was about 109 ms on a 167-process tree, against about 23 ms before the abstract-socket peer walk. `ss -p` walked every process fd, and the status read continued past `Uid`. The scan now uses `ss -Hxn`, stops the status read at `Uid`, and runs `ss` only when a `steamwebhelper` in the session holds an inode the unix table did not name.
- L152. **Open.** Without `unix_diag`, `ss` prints peer inode 0 and the abstract-socket check becomes a silent no-op. Log that. Owner: session.
- L153. **Open.** The cgroup match is exact, so a client in a sub-cgroup of the gamescope scope (`$scope` against `$scope/*`) is missed. Owner: session.
- L154. **Open.** A process that exits between the glob and the open writes "No such file" into `session.log`. The status and cgroup reads want `2>/dev/null`. Owner: session.
- L155. **Fixed.** `packages/omarchy-gaming-session` 1.0.0-6 depends on `iproute2`. `default/gaming/steam-ready.sh` calls `ss`. Arch base still ships it. Owner: packaging.
- L156. **Open.** The status read keeps only the first word of `Name:`, so a comm of `steam foo` matches `steam`. Owner: session.
- L157. **Open.** The 60 s ready-waiter timeout still marks ready when any `steam` process is alive, including an offline dialog, and that clears the failure count. The session stays up, so this is not another loop. Source: PR #70, review 5922156206. Owner: session.

From the RC71L gaming power-button package, 16 Nov 2026. The companion is Valve's unmodified powerbuttond v4.2 (`9392e688`, BSD-2-Clause), built by the in-tree recipe. This range is L160–L169.

- L160. **Open.** The brief's on-device power-button test was not run. No RC71L was available. Still to record: one short press suspends and resumes into the same game, a one-second hold opens Steam's power menu and the machine stays up, the desktop path is unchanged, and `HandlePowerKey` stays `ignore`. Source: power-button package, review 5921761248. Owner: hardware.
- L161. **Partial.** `omarchy-setup-gaming-session status` is read-only. The build and retry are explicit via `omarchy-setup-gaming-session install-power-button` when the session package is installed. The hardware leaf and migration also attempt that build when the session package is already present. Repository packaging and clean-install acceptance remain open. Source: power-button package, review 5921761248, review 5922010303. Owner: power.
- L162. **Open.** An Ally that already has `omarchy-rog-ally-powerbutton` installed is left on that package. A later recipe bump does not rebuild it. Source: power-button package. Owner: power.
- L163. **Fixed.** A conflicting handler or a failed build makes the migration warn and return 0. The script does not write a success marker, and later migrations still run. Source: review 5921761248. Owner: power.
- L164. **Fixed.** The build is under `timeout 90`, and git aborts when the transfer stays under 1000 bytes/s for 30 seconds, so a first-boot stall cannot hold the display manager. Source: review 5921761248. Owner: power.
- L165. **Fixed.** The udev rule grants `uaccess` only when one parent has both `name` `Power Button` and `phys` `PNP0C0C/button/input0` or `LNXPWRBN/button/input0`. Those two attributes are on the input device. The earlier rule also required the ACPI parent's modalias, and udev applies every `ATTRS` match to the same parent, so it never fired. A keyboard that merely advertises `KEY_POWER` is not tagged. Source: review 5921761248, review 5922010303. Owner: hardware.
- L166. **Open.** The recipe's git source uses `sha256sums=('SKIP')`. pacman 6.1 and later can checksum a git source. The pin `9392e688` is tag v4.2. A real `makepkg` on Arch was not run here. `libudev` comes from `systemd-libs`. `pkgconf`, `gcc` and `make` come from `base-devel`, which is already in `install/omarchy-base.packages`. The only network fetch is that source. `depends=('omarchy')` follows the gaming-session package. Source: review 5921761248. Owner: power.
- L167. **Open.** Migration stamp `1795075200` is about 65 hours ahead of its commit. `bin/omarchy-dev-add-migration` stamps from the last commit date. Markers are one file per migration, so a future stamp does not skip or reorder another migration. This fork already future-dates migrations. Prefer the tool's stamp for the next one. Do not rename this file once a machine has marked it. Source: review 5921761248. Owner: power.
- L168. **Open.** `steamos-powerbuttond` returns 0 and writes nothing when it can open no device. `posix_spawn` of `steam -ifrunning` inherits the launcher's flock fd 9 because it is not close-on-exec, so a lingering Steam child can hold the lock and the next session's `flock -n` exits 0 without starting the daemon. The launcher should log an immediate exit and hold the lock so Steam's children do not inherit it (the `flock` command form, after checking the fd is close-on-exec). Source: review 5921761248. Owner: power.
- L169. **Open.** `refresh_input_devices` runs `udevadm trigger --subsystem-match=input` on every hardware re-run even when the package did not change. The first version of this change was one commit. The empty `FAKE_CONFLICT=` assignment in the shell test (SC1007) is fixed here. Source: review 5921761248. Owner: power.

From the build brief [build-tdp-slider.md](research/build-tdp-slider.md), 16 Nov 2026. This range is L170–L179. Review [5921621153](https://github.com/DanielJBurbridge/omarchy/pull/66#pullrequestreview-5921621153) M1 is on L176, M2 is on L179, and M3 is on L182.

- L170. **Open.** Whether Steam draws the TDP slider on this RC71L with only `-steamos3 -steampal -steamdeck -gamepadui` is unverified. A further Deck-identity check was not found. Source: build-tdp-slider.md. Owner: hardware.
- L171. **Open.** GitLab `holo/steamos-manager` `power.rs` was not re-diffed against evlaV `85fbd8f`. The port uses the evlaV pin. Source: build-tdp-slider.md. Owner: power.
- L172. **Open.** Bazzite installs Terra rpm `steamos-manager-powerstation`. The spec was not opened, so what that rpm vendors is unverified. Source: build-tdp-slider.md. Owner: power.
- L173. **Open.** HHD's `hhd.steamos` docstring says steamos-manager forwards TDP through it. evlaV `85fbd8f` has no `hhd.steamos` string, and the HHD pin has no `remotes.d`. Whether a later manager execs the stub is unverified. Source: build-tdp-slider.md. Owner: power.
- L174. **Open.** asusd at `5346e184` saves and restores `asus-armoury` values. Whether that restore runs on this RC71L while the writer is installed is unverified. The writer refuses `--set` and `--reassert` while asusd is active. Source: build-tdp-slider.md, review 5921621153. Owner: hardware.
- L175. **Open.** The non-Extreme Z1, and whether `ppt_apu_sppt` and `ppt_platform_sppt` are absent, were not measured on this unit. Source: build-tdp-slider.md. Owner: hardware.
- L176. **Open.** The dumped unit's MCU is below 319. Update it before treating a resume that sticks near 4–7 W as a writer bug. M1: the resume oneshot stays active across sleep and runs `--reassert` from `ExecStop=`, after wake, as [systemd.special(7)](https://www.freedesktop.org/software/systemd/man/latest/systemd.special.html) describes for `sleep.target`. Source: build-tdp-slider.md, ally-hw-dump.md, review 5921621153. Owner: hardware.
- L177. **Open.** `BatteryChargeLimit1` stays out of the shim. Whether the QAM shows a charge limit on this RC71L is unverified. Source: build-tdp-slider.md. Owner: power.
- L178. D1's `allow_active=yes` on `org.omarchy.ally.set-tdp` is still outstanding. The build records the action and does not treat it as signed off. Already L106. Source: build-tdp-slider.md. Owner: dev-red.
- L179. **Open.** Whether the RC71L EC swaps the live PPT limit on plug without a userspace write is unverified. The source reapply path is L180. Source: build-tdp-slider.md, review 5921621153. Owner: hardware.

From the TDP slider build on 16 Nov 2026. L170–L179 stay as they are. This range is L180–L189.

- L180. **Partial.** Matching Mains and system USB power events now queue a reapply through a systemd path unit. A pending event during a write is handled when the service exits. USB peripheral power is ignored. Fixture checks pass. The Ally reports Mains today and still needs repeated physical AC and dock checks. Source: this build, review 5922419420. Owner: hardware.
- L181. **Open.** Upstream `set_tdp_limit` refuses the write unless the asus-wmi platform profile is `performance`. This writer does not. It must not write `platform_profile`, and the stock profile may not be `performance`. Source: evlaV `85fbd8f` `power.rs` `is_active`, this build. Owner: power.
- L182. **Open.** `--set` and `--reassert` take an exclusive `flock -w 5` on `/run/omarchy-ally-tdp.lock` across the three stores, so logind, the resume unit and udev cannot interleave a tuple. The 5 s is the acquire wait from L20. A timeout is logged and the command exits non-zero without writing. Whether 5 s is enough when resume, logind and udev coincide was not measured on the device. Source: this build, review 5921621153 M3. Owner: hardware.
- L183. **Open.** Nothing in this build was run on an RC71L. The acceptance tuples are fixture tests against the stock AC and DC tables. Source: this build. Owner: hardware.
- L184. **Open.** D1's `allow_active=yes` is still unsigned (L106, L178). The generated rule returns NO for every user except the recorded handheld user, so the policy default cannot authorize a different active session. `sddm` is NO and there is no `wheel` grant. Source: this build. Owner: dev-red.
- L185. **Open.** `ManualGpuClock` is rejected by the property setter. Whether Steam sees that failure as `NotSupported`, or only as a generic property error, was not checked against the client. Source: this build. Owner: power.
- L186. **Partial.** The writer now tries to restore the attempted fields when a store or readback fails on the same power source. Fixture coverage includes an SPPT refusal and a source change during failure. The saved request survives, and a remaining mismatch is logged. Physical verification is pending, and a power-source change requires a fresh reassert for the new source. Source: review 5922419420. Owner: hardware.

From the packaged install of the RC71L power-button recipe in merged #67, 16 Nov 2026. This range is L190–L199.

- L190. **Fixed.** The recipe is `default/rog-ally/powerbutton/` (`PKGBUILD`, `70-omarchy-rog-ally-power-button.hwdb`, `70-omarchy-rog-ally-power-button.rules`). `omarchy-settings` and `omarchy-settings-dev` `package()` copy that tree with `cp -a default/.` to `/usr/share/omarchy/default/` (omacom/omarchy-pkgs master, 16 Nov 2026; settings-dev `_commit` `7c8e05925391188d6e95e581dc51c12fb2facd48`, settings `_commit` `a948d8a6871f446b335258c827648ac5f4e9428b`). `omarchy-install-rog-ally-powerbutton` reads `$OMARCHY_PATH/default/rog-ally/powerbutton`. The BSD-2-Clause field and the Valve copyright credit stay on the recipe. Migration `1795075200` is a no-op. `1794843321` is the catch-up: it installs the companion when `omarchy-hw-rog-ally` and `omarchy-gaming-session` are both true and `omarchy-rog-ally-powerbutton` is not installed. A fresh user's skel marker skips that rerun. The hardware leaf and `omarchy-setup-gaming-session` still call the installer. L191 does not apply: the recipe is inside a tree `package()` already copies, so no new `cp` in omarchy-pkgs is required. Source: merged #67, this fix. Owner: power.

From the autologin grant moving into `omarchy-gaming-session` 1.0.0-5 or later, 17 Nov 2026. This range is L200–L209.

- L200. **Open.** Medium. `/etc/sudoers.d/omarchy-handheld-autologin` changes owner from `omarchy-settings` and `omarchy-settings-dev`, which install it with `cp -a etc/.`, to `omarchy-gaming-session` 1.0.0-5 or later. Installing the two separately either hits a pacman file conflict, when the new package arrives while the settings package still owns the file, or drops the grant, when settings is upgraded alone. A missing grant makes the relogin fallback's `sudo -n` refuse, which recreates the L145 black-screen relogin loop when desktop-lock is on. Install both packages in one `pacman -U`. Source: PR #79, review 5931524047. Owner: session.

From the 17 Nov 2026 cleanup. This range is L210–L219. It is claimed and empty. The cleanup items in that change were fixed there, and nothing was left open.

From the handheld pkgver sort, 17 Nov 2026. This range is L220–L229.

- L220. **Fixed.** `omarchy update` replaced handheld `omarchy-dev` and `omarchy-settings-dev` at `dev.<yyyymmddHHMM>.<sha8>` with upstream `4.0.0.r7967.g3b36b9e`. vercmp ranks a leading number above `dev.`, and sddm went into a relogin loop. pkgver is now `<base>.<yyyymmddHHMM>.r<count>.handheld.<sha8>`, with `.alpha` stripped from the `version` file. The stamp sorts above `4.0.0.r*` and above `dev.*`, and `4.0.1` or a later base sorts above it. Source: this fix. Owner: packaging.
- L221. **Fixed** by L250. Medium. The yield at the next upstream base version (4.0.1) silently brings back the sddm relogin loop when `omarchy update` replaces the `.handheld.` builds. The proposed gaming-session hook shipped as L250. It also keeps `dev.*` and `.allypreview.`. Source: PR #82, review 5932603045, L250. Owner: session.

From the RC71L button press test, 17 Nov 2026. This range is L230–L239.

- L230. **Open.** On Daniel's RC71L, with inputplumber stopped, M2 (the left back paddle) sent F15, M1 (the right back paddle) sent nothing, A was not reported while a paddle was held, and a 1 s hold of Command Centre sent nothing. The capture script had M1 and M2 swapped, did not put `inputplumber.service` back, and did not read the volume-button device (`AT Translated Set 2 keyboard`). The script now does those three. The readings stay pending a re-run with that script. Source: Daniel, 17 Nov 2026. Owner: hardware.

From the 17 Nov 2026 low fixes. This range is L240–L249.

- L240. **Fixed.** `keyboard_button_in_shell` in `bin/omarchy-setup-rog-ally-keyboard` read `$HOME/.config/omarchy/shell.json`. A custom `XDG_CONFIG_HOME` hid the Keyboard button, so a stopped shell stayed quiet instead of naming the later drop. The check now uses `${XDG_CONFIG_HOME:-$HOME/.config}`. Source: this fix. Owner: input.
- L241. **Fixed.** `packages/omarchy-gaming-session` created `/etc/sudoers.d` at 0755 because `install -D` makes parent directories that mode. pacman warns that the directory permissions differ (package 755, filesystem 750, the mode the `sudo` package ships). `package()` now runs `install -dm750` before the grant, and pkgrel is 8. `default/` does not contain `sudoers.d`. `etc/sudoers.d` is what `omarchy-settings` copies with `cp -a etc/.` from omarchy-pkgs, which is not in this tree, and git does not record the directory mode, so that package is unchanged here. Source: this fix. Owner: session.
- L242. **Fixed.** `omarchy update` over a non-login SSH session died with `OMARCHY_PATH: unbound variable` in `bin/omarchy-i18n` (`set -u`) where it reads the catalog directory. A non-login command does not source `default/bash/env-bootstrap`. `omarchy-i18n`, `omarchy-update-dev` and `omarchy-update-keyring` default `OMARCHY_PATH` to `/usr/share/omarchy`, the same fallback as `env-bootstrap` and `omarchy-migrate`. `omarchy-update` exports that default so `omarchy-update-stay-awake` and the reboot helper see it. The keyring script expands the path only on aarch64 when the Arch Linux ARM key is missing. Source: this fix. Owner: update.
- L243. **Fixed.** `docs/handheld/research/tools/ally-press-test.sh` restores `inputplumber.service` on EXIT, INT and TERM. An SSH drop sends HUP, which does not run EXIT, so the service stayed stopped until reboot. HUP now calls `restore_capture` and exits 129. `IP_RESTORED` still makes the following EXIT trap return without starting the service again. Source: this fix. Owner: hardware.
- L244. **Fixed** with L260. `apply_dropin` runs the guard `--status` and does not write `zz-omarchy-handheld.conf` when that status is `drop`. A missing version stays `unknown`, and apply still writes. Source: dev-red review of #84. Owner: session.
- L245. **Fixed** with L260. `local_version` globs `omarchy-dev-[0-9d]*` and keeps a directory only when the name parsed from `pkgname-pkgver-pkgrel` is `omarchy-dev`. Source: dev-red review of #84. Owner: session.
- L246. **Open.** Check once on the Ally for a leftover `User=` drop-in. The guard leaves `User=` in `omarchy-handheld-user.conf`. Whether this machine still has one after `zz-omarchy-handheld.conf` is removed is unverified. Source: dev-red review of #84. Owner: hardware.
- L247. **Fixed** with L302. The hook also runs for `omarchy-settings-dev`, but the guard only read the `omarchy-dev` version. Replacing `omarchy-settings-dev` alone with a build that is not `.handheld` and not `dev.*` left handheld autologin in place. The guard now classifies both packages, on `pacman -Q` and on the locked local database, and drops when either one is installed and is not a handheld build. Source: dev-red review of #84, L302. Owner: session.

From the handheld autologin guard, 17 Nov 2026. This range is L250–L259. #82 is not merged, so L220 is not in this file. L250 is that range's medium. L251–L259 are claimed and empty.

- L250. **Fixed.** Upstream `4.0.1` (and any later base) sorts above the handheld pkgver, so `omarchy update` replaces `omarchy-dev` and `omarchy-settings-dev` with builds that lack `.handheld` and lack the session pieces. sddm then relogins into the gaming session in a loop. The same loop already happened with `dev.*` builds (L220, [PR #82](https://github.com/DanielJBurbridge/omarchy/pull/82), review 5932603045). `omarchy-gaming-session` 1.0.0-7 ships `/usr/share/libalpm/hooks/omarchy-handheld-autologin-guard.hook`. After an install or upgrade of `omarchy-dev` or `omarchy-settings-dev`, the hook reads `pacman -Q omarchy-dev`, or the local database while that transaction holds `db.lck`. A version that is not `.handheld` and not `dev.*` removes `/etc/sddm.conf.d/zz-omarchy-handheld.conf`, which is the drop-in `omarchy-handheld-autologin apply` writes. `User=` in `omarchy-handheld-user.conf`, the sudoers drop-in and the TPM config stay. SDDM is not restarted. A `.handheld` or `dev.*` version leaves the drop-in. Re-enable is `sudo omarchy-handheld-autologin apply` after the `.handheld` builds are installed again. Source: this fix, L220. Owner: session.

From the allypreview autologin guard, 23 Nov 2026. This range is L260–L269. L260 is fixed here. L261–L269 are claimed and empty.

- L260. **Fixed.** Fleet's preview pair is `omarchy-dev` / `omarchy-settings-dev` `4.0.0.20261119224125.allypreview.g42fb2c857cb1.tf050deeb5a12-1`. That build has the session pieces. The 1.0.0-8 guard treated it as upstream, because the version is not `.handheld` and not `dev.*`, and removed `zz-omarchy-handheld.conf`. The keep list is one case: `dev.*`, `*.handheld.*`, `*.allypreview.*`. `.handheld.` and `.allypreview.` match anywhere in the version, including a trailing pkgrel. `apply_dropin` asks the guard `--status` and does not write the drop-in when the answer is `drop` (L244). The local-database read globs `omarchy-dev-[0-9d]*` and keeps a directory only when its package name is `omarchy-dev` (L245). `omarchy-gaming-session` pkgrel is 9. `User=`, the sudoers grant and the TPM config stay. SDDM is not restarted. Source: this fix, L244, L245. Owner: session.

From the gaming-session package sources, 23 Nov 2026. This range is L270–L279. L270 is that range's fix. L271–L279 are claimed and empty.

- L270. **Fixed.** `makepkg` looks a local source up by its basename in the PKGBUILD directory, so `packages/omarchy-gaming-session` could not build from a clean checkout. `source=()` listed `../../default/...` and `../../LICENSE`, and the box build only worked because a wrapper copied those files in beside the PKGBUILD first. `package()` now installs them from `_repo="$startdir/../.."`. `source=()` keeps the three files that sit next to the PKGBUILD, with their checksums. #86 took pkgrel 9 for the allypreview guard, so this source fix is pkgrel 10. The documented `makepkg` steps in `docs/rog-ally-gaming-session.md` work from a clean checkout. Source: this fix. Owner: packaging.

From the RC71L gaming profile, 23 Nov 2026. This range is L280–L289. L280 and L281 are that range's fixes. L282–L289 are claimed and empty.

- L280. **Fixed.** On a fresh RC71L install the gamescope session never loaded the InputPlumber gaming profile, so the DualSense Edge pad (`054c:0df2`) stayed absent until it was fixed by hand. `omarchy-session-start` copied the user units into `~/.config/systemd/user` and did not enable them. `omarchy-gaming-session` through 1.0.0-10 shipped no user units, and pacman warned that `omarchy-gaming-session.target` was missing. The package now installs the target, the profile oneshot and the gaming drop-ins under `/usr/lib/systemd/user`, with `omarchy-gaming-session.target.wants/omarchy-gaming-input-profile.service`. The four unit files are `file://` sources and `package()` installs them from `$srcdir`, the same way L290 packs the session files. That link is the gaming target only, so the Hyprland session keeps the desktop pointer profile. A checkout still copies the units and writes the same link. `post_install` and `post_upgrade` run `systemctl enable --now omarchy-inputplumber-profile.service` on an Ally, so the system service is running before the next boot. A disabled or masked unit stays that way. #87 took pkgrel 11, so this is pkgrel 12. Source: RC71L, 23 Nov 2026. Owner: session.
- L281. **Fixed.** `default/systemd/user/omarchy-ally-tdp-shim.service.d/10-gaming-session.conf` had `PartOf=omarchy-gaming-session.target`, and the shim unit had the same line. Stopping the gaming target on Switch to Desktop stopped the `--global` shim, so the desktop lost the Steam TDP slider. The drop-in keeps `After=` and `WantedBy=`. `PartOf=` is gone from the drop-in. The unit keeps `PartOf=graphical-session.target` and drops `PartOf=omarchy-gaming-session.target`. Source: PR #88, review 6022003419. Owner: session.

From the gaming-session clean-chroot sources, 23 Nov 2026. This range is L290–L299. L290 is that range's fix. L291–L299 are claimed and empty.

- L290. **Fixed.** `package()` installed the session files and the licence from `_repo="$startdir/../.."`. A clean chroot (`makechrootpkg` / `extra-x86_64-build`) bind-mounts only the PKGBUILD directory, and `makepkg --allsource` packs only `source=()`, so those files were missing and had no checksum. `source=()` now names them as `file://` URLs under `$startdir`, with sha256sums. `package()` installs from `$srcdir`. pkgrel is 11. Source: PR #85, review 6021180824. Owner: packaging.

From the open-low batch, 23 Nov 2026. This range is L300–L309. L300 is the batch. L301–L303 are the fixes. L304–L309 are the deferred or already-landed notes.

- L300. **Fixed.** One batch of the open lows that are small and in this repo. The pointer helper already defaults `OMARCHY_PATH`. The bash commands that still aborted under `set -u` are L301. A settings-dev-only swap is L302 (L247). The autologin guard's locked-database path already used the same keep list as `pacman -Q`; L303 asserts that for `dev.*` and `.allypreview.`. The session-start user-unit copy is L304. `gamescope-wl` is L305. The leftover `User=` file is L306. The root checkout-guard fallback is L307. L221's hook is already L250. The press-test HUP trap is already L243. L244 and L245 are already L260. `omarchy-gaming-session` pkgrel is 13. Source: this fix. Owner: session.
- L301. **Fixed.** `omarchy-session-start`, `omarchy-gaming-steam`, `omarchy-launch-gaming-session`, `omarchy-launch-gaming-desktop`, `omarchy-setup-gaming-session`, `omarchy-setup-handheld-dirs` and `omarchy-install-rog-ally-powerbutton` read `$OMARCHY_PATH` under `set -u`. A non-login ssh command does not source `env-bootstrap`, so the variable was unbound. They default it to `/usr/share/omarchy`, the same fallback as `omarchy-i18n` and `omarchy-migrate`. `omarchy-session-start` still sources the bootstrap when that file is installed, and the bootstrap still replaces the default. The handheld install leaves (`handheld-autologin.sh`, `inputplumber.sh`, `gaming-session.sh`, `ally-tdp.sh`) use the same default, because a `set -u` parent sources them. `omarchy-inputplumber-profile` already defaults the path in Python, which is what `omarchy-ally-pointer.service` runs. Source: this fix. Owner: session.
- L302. **Fixed.** L247. The hook runs for `omarchy-settings-dev`, and the guard only read `omarchy-dev`. An upstream `omarchy-settings-dev` with no `omarchy-dev`, or next to a handheld `omarchy-dev`, left `zz-omarchy-handheld.conf` in place. Both packages are classified with one keep list (`dev.*`, `*.handheld.*`, `*.allypreview.*`) on `pacman -Q` and on the locked local database. An explicit non-handheld version drops. A missing package is ignored. An unreadable or doubled database entry stays unknown and leaves the drop-in. `User=` stays (L306). SDDM is not restarted. pkgrel is 13. Source: this fix, L247. Owner: session.
- L303. **Fixed.** The #86 guard's `db.lck` fallback and the `pacman -Q` path already share `keeps_handheld_autologin`. A locked `dev.*` database and a locked `.allypreview.` database report `--status` `keep`, the same word the main path prints. The earlier lock tests only checked that the drop-in file was still there, which `unknown` also does. Source: this fix, L260. Owner: session.
- L304. **Documented.** `omarchy-session-start` still copies the four user units into `~/.config/systemd/user` and writes `omarchy-gaming-session.target.wants/omarchy-gaming-input-profile.service`. That link is the same enable the package ships under `/usr/lib/systemd/user`. Neither path `systemctl enable`s those user units into `default.target` or `graphical-session.target`, so the Hyprland session keeps the desktop pointer profile. The package's `enable --now` is `omarchy-inputplumber-profile.service`, the system profile service, and it stays in the scriptlet. The checkout copy remains because a checkout has no package yet. Source: L280, this note. Owner: session.
- L305. **Deferred.** No repo verify helper uses `pgrep gamescope`. Session liveness is the gamescope scope pid and `pgrep -u "$UID" -x steam`. This tree launches Gamescope with `--backend drm`, whose comm stays `gamescope`. Accepting `gamescope-wl` would be a guess about a wayland backend this session does not start. Source: this batch. Owner: session.
- L306. **Deferred.** L246. The guard still leaves `User=` in `omarchy-handheld-user.conf` when it removes `zz-omarchy-handheld.conf`. Deleting that file would drop the per-machine name L250 keeps so a later `apply` can turn autologin back on. Whether this Ally still has the file after the session drop-in is removed has to be checked on the device. Source: dev-red review of #84, L246. Owner: hardware.
- L307. **Deferred.** `handheld_dev_status` falls back to the checkout guard beside `bin/omarchy-handheld-autologin` when `/usr/lib/omarchy-gaming-session/omarchy-handheld-autologin-guard` is missing. Dropping that fallback for root would make `apply` ignore the version list on a dev checkout and in the tests, which is how preview and dev builds are accepted when the packaged guard is absent. A symlink from `/usr/bin` into a user-writable tree is a separate ownership problem. Source: PR #86 review. Owner: session.
- L308. **Deferred.** L230 stays a hardware re-run. L251–L259, L261–L269, L282–L289 and L291–L299 were claimed and are empty. L244 and L245 are already fixed with L260. The press-test HUP trap is already L243. Nothing in those ranges is a further repo change. Source: this batch. Owner: session.
- L309. **Deferred.** L221's hook is L250, recorded above. The HANDOFF no longer calls it open. Source: L250. Owner: session.

From the RC71L gaming glyphs, 23 Nov 2026. This range is L310–L319. L310 is the deck target. L311 is open until a press test. L312 is the `vhci_hcd` gate. L313–L319 are claimed and empty. #89 owns L300–L309 and pkgrel 13. This change does not touch `packages/omarchy-gaming-session`, so pkgrel stays 13.

- L310. **Fixed.** `default/inputplumber/profiles/gaming.yaml` targeted `ds5-edge` (Sony DualSense Edge, `054c:0df2`), so Steam drew PlayStation glyphs on an Ally whose face buttons are labelled ABXY. The gaming target is now InputPlumber's `deck` (Valve `28de:1205`). That target reports a gyroscope and accelerometer, maps `LeftPaddle1`/`RightPaddle1` to Deck L4/R4, and stores Quick Access as its own button. `xbox-elite` (`045e:0b00`) and `xbox-series` (`045e:0b12`) have no gyro capability, and `xbox-series` has no paddle capabilities; both turn Quick Access into Guide then South. `deck-uhid` on the Ally composite advertises `28de:12fd`, and InputPlumber only uses `28de:1205` on `deck`, because Steam checks the interface number. Bazzite's handheld note (paddles on a DualSense Edge or Steam Deck target; Xbox drops gyro; `deck-uhid` if gyro misbehaves) and HHD's Ally path (no `[inputplumber]` section, so `deck-uhid`) are the comparison. Those trees were compared and nothing was copied; the target name is the 0.84.0 schema enum, and the profile makes no licence claim. Guide, Quick Access, `omarchy_overlay` and Guide-then-West stay as they were. Desktop, greeter and osk stay on `xbox-elite`. Steam outside SteamOS treats `28de:1205` as a Steam Deck. The module gate is L312. The keyboard chord is L311. Rollback is `ds5-edge` plus `sudo omarchy-inputplumber-profile load gaming`. Source: this fix. Owner: input.
- L311. **Open.** Command Centre long stays Guide then West. InputPlumber sends West as Deck Y (`steam_deck.rs` 622–623), so the chord arrives as Steam+Y. Steam's keyboard chord is Steam+X, which is Guide then North. The mapping is unchanged until a press test on the RC71L. After that test, change the button to North and update the "gaming keeps Guide then West" check in `test/shell.d/inputplumber-profile-test.sh`. `docs/rog-ally-touch-keyboard.md` still calls that chord Guide+X (West). Source: dev-red review 6022864611. Owner: input.
- L312. **Fixed.** `vhci_hcd` is not loaded on the Ally, so after a kernel upgrade without a reboot the `deck` target has no pad. `install-vhci` writes `/etc/modules-load.d/omarchy-rog-ally-vhci.conf` (`vhci_hcd`) only when `omarchy-hw-rog-ally` succeeds, the same gate as `install/hardware/asus/inputplumber.sh`. That leaf calls it on a fresh install. `migrations/1795442196.sh` calls it for an existing install. A gaming load tries the module and then checks `/sys/module/vhci_hcd`. If the module cannot be loaded, or that directory is absent, the load sends `ds5-edge` for that load, logs it, and leaves `gaming.yaml` unchanged. A later load with the module present sends `deck` again. Desktop, greeter and osk do not load the module. Source: dev-red review 6022864611. Owner: input.

From the Ally Steam logon, 25 Nov 2026. L320 is that boot.

- L320. **Fixed.** Steam started about 2s after Wi-Fi activation (`steam -steamos3 -steampal -steamdeck -gamepadui`). The saved-token logon got Steam CM 'Service Unavailable' for about 25s, so gamepadui showed the sign-in screen. Closing it was handled as Switch to Desktop: `session.log` said 'Requested return to desktop.', `gaming-session/last` became `desktop`, and the next relogin started Hyprland. `RememberPassword=1` and `AutoLogin=1` were set. The keyring was not involved. `omarchy-gaming-steam` now waits for full connectivity before Steam, the same `nm-online -q -t 30` first-run uses, then `nmcli networking connectivity` until it prints `full`, within that 30s. `nm-online` also returns for a site-only link, which is this race. A timeout launches Steam and writes one line to `fallback.log`. A missing `nm-online` and `nmcli` skips the wait. A return-to-desktop before the ready marker relaunches the gaming session instead of writing `last=desktop`. Switch to Desktop after the marker is unchanged. `packages/omarchy-gaming-session` is untouched, so pkgrel stays 13. Source: RC71L boot, 25 Nov 2026. Owner: session.
- L321. **Fixed.** A pre-ready Switch to Desktop relaunched Gaming with no cap, so closing the sign-in screen again never opened the desktop. The count is `gaming-session/early-returns`, for this login. The second return writes `last=desktop`, logs and notifies that Steam was not ready, and uses the normal desktop path. Ready deletes the count. Source: PR #91, review 6051563503. Owner: session.
- L322. **Fixed.** `nmcli networking connectivity` printing `unknown` waited out the 30s budget. `unknown` is treated as online. The nmcli read is `timeout 2`, so a stuck client cannot hold Steam. `limited` and `portal` still wait. Source: PR #91, review 6051563503. Owner: session.