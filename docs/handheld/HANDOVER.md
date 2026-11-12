# Handheld handover (12 Nov 2026)

Standing brief for the next coding agent on the Omarchy handheld work. Written from integ `00daf17f`, the docs in this directory, and the device comment on PR #34. Anything not re-checked is marked unverified. The coordinator's running log is not in the repository.

## Goal

A gaming-first handheld mode for Omarchy on the original ROG Ally RC71L (Z1 Extreme). The bar is parity with Bazzite and CachyOS Handheld, and the result still has to feel Omarchy-native: existing Omarchy entry points, one input owner, no second launcher or theme system. Principles are in [README.md](README.md). The primary device is the RC71L. Ally X, Legion Go and Steam Deck are later models, not this alpha.

## Where we are

Coordinator's estimate, not a measured audit: a usable prototype is roughly 30-40% done, and parity is roughly 15%.

Integration branch: `feat/ally-parity-integration-20261111` at `00daf17f` (`Merge #42: handheld mode round trip (spec 08)`). Build on that tip. The Ally deploy commit `d3747faf` is an ancestor. After that deploy, this branch gained the alpha doc (#40) and the mode round trip (#42).

What this tip ships in source:

- Handheld gaming session (#34, merged at `d3747faf`). Gamescope plus Steam, and `omarchy-gaming-session.target`. Install and recovery: [ALPHA.md](ALPHA.md). Session behaviour: [../rog-ally-gaming-session.md](../rog-ally-gaming-session.md).
- SDDM autologin. `omarchy-handheld-autologin apply` writes `/etc/sddm.conf.d/zz-omarchy-handheld.conf` with `Session=omarchy-handheld.desktop` and `Relogin=true`, and no `User=`. The crash-loop guard: three gaming starts in 60 seconds that never read `started` write `/run/omarchy/handheld-autologin/stop` and set `Relogin=false`. A reboot clears `/run`, and the next boot writes `Relogin=true` again.
- The RC71L desktop power button. It runs `omarchy-system-sleep-lock`, then `systemctl suspend`. Until `/var/lib/omarchy/handheld/k07-landed` exists, `desktop-lock` is `default-off`. With no physical keyboard the lock is skipped and the button still suspends. The Ally N-KEY device does not count as a keyboard. Detail is in [ALPHA.md](ALPHA.md).
- Mode round trip, spec [08](08-mode-round-trip.md), #42, reviewed at `1dc4aa63` (review 5871600455) and merged as `00daf17f`. One-shot `next=desktop` marker, a System menu row **Switch to Gaming**, and `Super+Ctrl+G`. Both are in the tree (`default/omarchy/omarchy-menu.jsonc`, `default/hypr/bindings/utilities.lua`).
- [ALPHA.md](ALPHA.md) (#40). That page still names tip `d3747faf` and still lists the Switch to Gaming row as missing. The row is in this tree. Use ALPHA.md for install and recovery, and this page for status.

Not built:

- Controller map and InputPlumber (profiles, desktop bridge, gaming bridge). No `gaming.yaml` ships, so `omarchy-gaming-input-profile` does nothing.
- The F17 escape. No InputPlumber intercept ships, so there is nothing to escape. It becomes required when intercept lands.
- The quick-access overlay (spec 04).
- The TDP shim unit. `omarchy-ally-tdp-shim.service` is not in this tree. #33 is a draft spike, gated on battery tests at 15/20/25 W and a 30 W unplug test. See [Red-team open items](#red-team-open-items).
- Display and dock switching. `omarchy-display-rog-ally` is not in this tree.
- The suspend broker, the idle return to gaming, and the power-off backstop (spec 02 §7.7).
- The first-boot install wizard (spec 03).
- Accessibility (spec 06).
- A greeter on-screen keyboard that can backspace, shift, enter symbols, and submit (spec 02 AC 59). The greeter grid cannot submit by touch.

The shipped session has not been shown on the device. The only Ally boot of this line came up on the desktop. See below.

## Latest device result (12 Nov 2026)

Source, including deploy facts, symptoms, hypotheses, the read-only diagnostic list, and rollback: [Ally alpha deploy of integ d3747faf](https://github.com/DanielJBurbridge/omarchy/pull/34#issuecomment-6819644541). This agent did not SSH to the Ally. Live state after that comment is unverified. The comment's status: installed, not verified, no rollback. Root cause not found. Off-device analysis stopped before it produced findings.

Deployed integ `d3747faf`, which is behind current HEAD. One sudo chain at 16:29:46 AWST, logged in `~/omarchy-handheld-deploy.log` on the Ally. Reboot at 16:30:46 AWST.

Installed:

- `omarchy-dev` and `omarchy-settings-dev` at `dev.d3747faf-1`.
- `omarchy-gaming-session` `1.0.0-1`, built from `packages/omarchy-gaming-session/PKGBUILD` at `d3747faf`.
- pacman also pulled `gamescope` `3.17.0-1` and `libxres` `1.2.3-1`. The comment says that pull was unplanned. The session doc requires Gamescope ≥ 3.17.0, so the version matches the documented floor. Whether the session's Gamescope arguments match 3.17.0 is unverified.
- Autologin unit enabled. `apply` wrote `Session=omarchy-handheld.desktop` and `Relogin=true`.

Before the deploy: both dev packages were `dev.0fdba61b-1` (release tip `0fdba61`), gaming-session was absent, kernel `7.2.15-2-omarchy`. SDDM drop-ins included `autologin.conf` with `User=daniel` and `Session=omarchy.desktop`. Snapper snapshot 2 (`pre handheld alpha d3747faf`) is the pre-state. The `dev.0fdba61b-1` rollback packages are in `~/omarchy-handheld-pkgs`. The comment says those checksums were verified. This agent did not re-check them.

The upgrade removed the greeter virtual-keyboard styles under `/usr/lib/qt6/qml/QtQuick/VirtualKeyboard/Styles/Omarchy` and removed `omarchy-lock-host.service`. The comment's figure: integ is not a fast-forward of release (merge-base `f7194066d`, about 72 release commits differ).

After the reboot, reported by Daniel:

- The machine came up on the Omarchy desktop. The gaming session did not start.
- Wi-Fi was off, and the waybar network module was missing.
- The Ally was unreachable on LAN and on Tailscale. Touch only. No keyboard attached.

Root cause unknown. The comment's hypotheses are still unchecked:

1. Session fallback. Compare `Session=omarchy-handheld.desktop` with the `.desktop` installed under `/usr/share/wayland-sessions`. Check the crash-loop guard and the recovery latch (`/run/omarchy/handheld-autologin`, `~/.local/state/omarchy/gaming-session`). Compare Gamescope 3.17.0 with the arguments the scripts pass.
2. Wi-Fi and waybar. A release-only network or waybar change may have been lost in the package swap (diff `0fdba61..d3747faf` for iwd, NetworkManager, rfkill, waybar config, and Hyprland autostart). Also check the settings-dev `.INSTALL` scriptlet, and whether a handheld or power hook rfkill-blocks Wi-Fi.

First tasks, in this order:

1. Get the Ally online. That needs a keyboard. There is no touch-only path. This is a high-priority usability gap: the greeter grid cannot submit by touch ([ALPHA.md](ALPHA.md)), and on this boot the desktop has no network module to tap.
2. Read-only diagnostics once it is reachable. Leave the machine unchanged while reading.
   - `loginctl` for the session list. An active user session is also the abort rule under [Hard rules](#hard-rules).
   - Crash-loop state under `/run/omarchy/handheld-autologin` and `~/.local/state/omarchy/gaming-session`.
   - `journalctl -b` for sddm, gamescope, and the gaming session (`omarchy-gaming`, `omarchy-handheld`, `session-start`).
   - The session name in `zz-omarchy-handheld.conf` against the installed `.desktop` in `/usr/share/wayland-sessions`.
   - iwd and rfkill state, and a waybar config diff against the previous packages.
   Run the comment's command list. It is the full set.
3. Fix from those logs. Then redeploy current integ HEAD (`00daf17f` or later). Do not reinstall `d3747faf` and call it current. One deploy at a time, and write the log first.

## Open PRs and what happens next

Handheld PRs open on 12 Nov 2026. Other open PRs on the fork target `quattro` and are out of scope.

| PR | State checked 12 Nov 2026 | What to do |
|---|---|---|
| [#33](https://github.com/DanielJBurbridge/omarchy/pull/33) | Draft. Base integ. Head `b91c2943` on `cursor/ally-tdp-spike-1843`. Design PASS at `2722cfe74` (review 5870574866). The delta to `b91c2943` is i18n plus docs, and that PASS still stands (review 5870971429). `i18n-check` and `test` were green on that head. | Stays a draft until the device gates. |
| [#39](https://github.com/DanielJBurbridge/omarchy/pull/39) | Open. Base `feat/ally-parity-release-20261111`. Head `d1227ef6` on `cursor/ally-release-taskc-8006`. PASS at that sha against the release base (review 5871158684). The same review says this sha conflicts with integ. | Merging into the release branch is Daniel's call. This sha needs a resolution and a re-review before it can land on integ. |
| [#43](https://github.com/DanielJBurbridge/omarchy/pull/43) | Draft. Base integ. Head `f4de8d8f` on `handoff/ally-auth-rollout-20261112`. GitHub reports conflicts. Daniel's handoff of the accepted auth rollout and the unfinished cold boot. The coordinator identifies it as his own T3 Code work. | Leave it to him. |

`feat/ally-parity-release-20261111` is Daniel's lock branch. Additive PRs only. No force-push and no rebase.

A merge-tree of the #39 branch into integ `00daf17f`, run while writing this page, still conflicts in `default/sddm/omarchy/Main.qml`, `bin/omarchy-session-start`, `bin/omarchy-system-lock` and `bin/omarchy-system-sleep-lock`. That same tree merge conflicts in further files. It is a wholesale merge of the release line, which the plan forbids. The published conflict note (review 5871158684) was against integ `d3747faf` and already said "and others". The port below is a narrow copy, then a new Red review at the new sha.

Planned next, from the coordinator: one narrow additive PR that ports lock, auth, SDDM and the trusted lock-host from the release branch onto integ. In that PR, fix the two lock follow-ups. The lock gate's `|| true` swallows a launcher failure. Without the broker, logind can suspend an unlocked desktop after its 15 s delay. The broker is its own later PR. Both notes are in the #39 PASS review (5871158684). They are not yet copied into [alpha-followups.md](alpha-followups.md).

Feature order:

1. Device fix, then redeploy integ HEAD.
2. The lock port.
3. Controller map and InputPlumber, then the F17 escape.
4. The overlay, then TDP. #33 stays gated on the battery tests and the 30 W unplug test.

## Follow-ups

[alpha-followups.md](alpha-followups.md) is the list of mediums and lows. This change adds dev-red's four #42 items, which were missing after the merge: L31 (stale `next` across a reboot), L32 (the 60 s socket waiter), L33 (one fail count on a recovery-desktop logout), L34 (symlink read hardening). Source: review 5871600455 at `1dc4aa63`.

That same review names two further notes this change does not file. `Super+Ctrl+G` gates with absolute paths and then dispatches the bare command `omarchy-launch-gaming-session`. `desktop-entry-launch-test.sh` has a pre-existing EXIT-trap flake (`rm: Directory not empty`), unchanged from integ `3cadbb0c`. Read the review before treating L31–L34 as the whole list.

The #39 PASS review's follow-ups, including the lock-gate `|| true` and the 15 s logind window, are also still unfiled. Fix those two in the lock port. Filing them is not a substitute for the fix.

## Team method

Five roles. One feature at a time. A feature is specified before it is built, lands as one PR, and merges only after Red passes that exact sha.

| Role | Job |
|---|---|
| Research | Bazzite, CachyOS Handheld and SteamOS parity. Notes are in [research/](research/). Do not copy GPL or LGPL sources into this tree. The steamos-manager rejection is in that README. |
| UX | Specs and the button map before code. The specs are [01](01-controller-button-map.md) through [08](08-mode-round-trip.md) in this directory. There is no `docs/handheld/specs/` directory. |
| Blue | One feature per PR, on a feature branch off integ. A feature PR does not pick up lock-screen work on the side. |
| Red | Adversarial review of every PR at an exact head sha. Pass or fail, written as a GitHub review on that sha. Blockers are fixed before merge. Mediums and lows go to [alpha-followups.md](alpha-followups.md). A later commit needs a new review. A pass at an older sha does not cover it. |
| Lead | Owns the backlog, runs one feature at a time, and merges into integ only after a Red pass at the reviewed sha. Daniel's allow rule (12 Nov): dev-lead may merge into integ after a dev-red pass, at the reviewed sha. |

## Hard rules

- Pull requests go only into this fork's integ branch (`feat/ally-parity-integration-20261111`) or into feature branches based on it. The release branch takes additive PRs only, and merging there is Daniel's call.
- Never push, merge, rebase, or open a pull request into `quattro`, `dev`, or upstream `omacom/omarchy`.
- Every commit carries the trailer `Model: <model>`. The PR body names the model.
- Daniel's other machines are read-only: `x1carbon`, `legion`, `sigil`, `rune`. That includes writing no staging files on them. Coordinator rule. This agent did not inventory those hosts.
- The Ally (`ssh rog-ally`) may be changed. Before each deploy, append the package version, the commit, and the snapper snapshot to `~/omarchy-handheld-deploy.log` on the Ally. Deploy one change at a time. Run `loginctl` and confirm there is no active user session before the deploy and while it runs. Abort if a session is present.
- Daniel's Fleet repo and his dotfiles repo stay private. Never invent secrets, tokens, passwords, or sudoers contents. Do not copy them into the tree or into a PR.
- `/etc/sudoers.d/90-omarchy-handheld-deploy` is still on the Ally. The deploy comment left it for Daniel. He removes it himself. Leave that file alone.

## Deploy recipe

Pointer only. Install and recovery detail is [ALPHA.md](ALPHA.md). The session companion build is [../rog-ally-gaming-session.md](../rog-ally-gaming-session.md). The #34 comment says the long form of the 12 Nov rollback is in `DEPLOY.md`. That file is not in this repository. Where it lives is unverified.

Build the runtime packages from the `omacom/omarchy-pkgs` PKGBUILDs, versioned `dev.<sha>-1`, from the reviewed commit. Build `omarchy-gaming-session` from `packages/omarchy-gaming-session/PKGBUILD` at the same commit (`1.0.0-1` on the last deploy). Take a snapper snapshot. Install with `pacman -U`. Enable `omarchy-handheld-autologin.service`, run `omarchy-handheld-autologin apply`, append the log, then reboot.

An Ally that is already installed has no migration that enables the unit. Use the enable, daemon-reload, apply, and `systemctl restart sddm` steps in [ALPHA.md](ALPHA.md). Restarting SDDM ends the current graphical session.

Rollback of the 12 Nov deploy: pick snapshot 2 in Limine, then `sudo snapper -c root rollback 2`. Or reinstall the `dev.0fdba61b-1` pair from `~/omarchy-handheld-pkgs`, remove `omarchy-gaming-session`, disable the autologin unit, delete `zz-omarchy-handheld.conf`, and reboot.

## Red-team open items

1. #39 passed at `d1227ef6` against the release base, but it conflicts with integ in `Main.qml`, `session-start`, `system-lock` and `sleep-lock`, so it needs a resolution and a re-review.
2. #33 stays a draft until the device gates: battery at 15/20/25 W, with 25 expected to clamp to 20/20/25; an unplug test at 30 W with the shim stopped; and the #10 polkit matrix.
3. Fix before desktop-lock is ever enabled: the launcher `|| true` in the lock gate, and logind suspending an unlocked desktop after 15 s without the broker (needs the broker PR).
4. Existing Ally installs need the autologin enable, apply and restart steps from [ALPHA.md](ALPHA.md).

Review notes are on each PR.

The #33 design PASS also lists a third device gate: resume and poweroff through the #36 broker, and a QAM slider max of 20 on battery / 30 on AC after a desktop-to-gaming switch. Confirm it against review 5870574866 before calling the spike done. Whether that third gate is still the rule at head `b91c2943` was not re-litigated here. The delta review says the TDP logic was unchanged and the design PASS stands.

## Unverified

- The Ally after the #34 comment. No SSH from this agent.
- The root cause of the desktop boot, Wi-Fi off, and the missing waybar network module.
- The 30-40% and 15% figures. They are the coordinator's estimate.
- Checksums of the rollback packages. The comment says they were verified.
- Where `DEPLOY.md` is stored.
- The hosts `x1carbon`, `legion`, `sigil` and `rune`, beyond the coordinator's rule.
- Current CI on #39. At review time the `test` check had failed six files, described in that review as already failing on the previous commit of the same PR.
