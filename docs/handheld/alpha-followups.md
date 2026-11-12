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
- L25. The greeter grid in `default/sddm/omarchy/Main.qml` has no backspace, shift, enter, or symbols, and it is shown on every machine's greeter. #39 / AUTH still own a complete VKB (AC 59). Source: PR #34, review 5870966296. Owner: AUTH.
- L26. After `stop` is written, choosing the handheld session entry exits 0 immediately. The regular desktop session is the way back in. Source: PR #34, review 5870966296.
- L27. There is no migration that enables `omarchy-handheld-autologin.service` and runs `apply` on an existing Ally install. A new install that runs the hardware leaf is fine. An Ally that is already installed has to do that apply step itself ([ALPHA.md](ALPHA.md)). Source: PR #34, review 5870966296. Owner: install.
- L28. `test/handheld/power-rollback-test.sh` still loads `bin/omarchy-setup-rog-ally-power` from `c88d5344` (`HANDHELD_RELEASE_SHA` in `test/handheld/gaming-fixture.sh`). The test stays skipped while power is on hold. Source: PR #34, review 5870592622. The PASS review did not close it.

From dev-red's low notes on #10 packaging in the [PR #33](https://github.com/DanielJBurbridge/omarchy/pull/33) PASS review, [review 5870574866](https://github.com/DanielJBurbridge/omarchy/pull/33#pullrequestreview-5870574866).

- L29. `21-omarchy-ally-tdp-variant.hook` enables a path unit from a package hook on Allys. That conflicts with the r1 "no scriptlet enables anything" test, so it needs an explicit sign-off. Source: PR #33, review 5870574866. Owner: #10 packaging.
- L30. If `write_recorded_spl` fails in the removal hook (for example armoury is missing), power-profiles-daemon stays masked after Omarchy is removed. Unmask anyway and log the tuple failure. Source: PR #33, review 5870574866. Owner: #10 packaging.

From the PASS review of [PR #42](https://github.com/DanielJBurbridge/omarchy/pull/42) at `1dc4aa63`, [review 5871600455](https://github.com/DanielJBurbridge/omarchy/pull/42#pullrequestreview-5871600455). These four were not in this file when #42 merged. Filed 12 Nov 2026.

- L31. `next` survives a reboot. It lives in the state home, not `/run`. A crash in the middle of the handoff, plus a reboot, lands the next boot on the desktop once, then gaming. That matches AC 5: one autologin, then the one-shot is gone. A boot-id or runtime-dir marker would make an unexpected mode after reboot impossible if that ever matters. Source: PR #42, review 5871600455.
- L32. The Hyprland-socket waiter gives up after 60 s. If the socket appears later than that, a later logout can consume a leftover `next` and open the desktop once. Source: PR #42, review 5871600455.
- L33. A relogin that consumes `next=desktop` never sets `gaming_autologin_ready`. Logging out of that recovery desktop, without a later successful gaming start in the same process, records one `fail`. One count, not three, and the following relogin is gaming. Source: PR #42, review 5871600455.
- L34. `[[ -f $gaming_state/next ]]` follows a same-user symlink for the read. The directory is mode 0700 and user-owned, so this is not a cross-user write. Refusing `-L` would be defence in depth. Source: PR #42, review 5871600455.
