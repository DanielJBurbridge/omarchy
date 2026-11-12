# Ally authentication presentation — 12 November 2026

The executable/source cut is **`a05a96e4afb89cbab43fa6f7674b812dc26bcc0a`**: presentation commit `e4c89751aa64b17ef5730cc3c75c8f248c21715d` plus the physical navigation follow-up, after reviewed release `a3db80460a2b0f586ff19408ec31041e7cd65543` on `DanielJBurbridge/omarchy:feat/ally-parity-release-20261111`. Publication adds this receipt only. Build a distinct matching runtime/settings pair from the full publication SHA; do not reuse a moving branch pin or relabel the prior artifacts. This is a source-only change on Sigil. No Ally actions, package installs, real passwords, live owner changes, new checkouts, delegates or PRs were used.

## Presentation and boundary

- SDDM restores the original Omarchy logo, lock glyph and spare outlined, centred masked entry. User/session selection remains available in a compact row, with themed touch controls and visible Keyboard, Cancel and Sign in. It uses the existing `omarchy-plymouth-set` colour substitution and generated artwork; `omarchy-refresh-sddm` still calls its fixed-file publisher. No alternate palette source or publisher was added.
- The lockscreen retains its native wallpaper/poster, Commons palette, border, typography and `Ui.Button`. The password/actions are centred together above the keyboard, with larger action text and a visible keyboard-selected state. No clock, new branding, decorative panel or motion was added.
- Both processes use the same new fixed `KeyboardStyle`, outlined keys, native monospace typography, pressed/modifier states, readable alternatives and styled layout chooser. Keyboard height retains usable rows in portrait; the form/actions remain visible at 960×540 logical and 1920×1080 at scale 2. The chooser displays Qt's actual active input locale, including its default, rather than an empty settings preference. Qt still owns all layouts, modifiers, symbols and input behaviour.

The separate trusted host, owner selection, lease, PAM/fingerprint path, control protocol, compositor/context checks, unit supervision and sleep proof are unchanged. `default/lock-host/control.py`, the host unit and launchers are byte-identical to the baseline. No authentication object is exposed to the desktop shell. The new `Theme` singleton carries visual data only; it has no service, input object, loader or authentication method. Caller Qt/QML/style/environment sanitisation remains unchanged. Production receives no custom QML import path. No boot, encryption, autologin, PAM policy, INPUT, POWER or desktop keyboard source changed.

## Package closure

Continue using `omacom/omarchy-pkgs` pin `c271f571be7fa43fa97133da626379d048400d68`, now with this release's updated `packaging/rog-ally-release/omarchy-pkgs.patch`, applied with `--fuzz=0`. The original recipe hashes and wider package manifest remain in [the recovery handoff](rog-ally-source-handoff-20261112.md). The patched runtime recipe SHA256 stays `306f34368f7424745ab1bbaca2667dbdea4990e6711e21ea9ebc82ab9d21f20a`; the patched settings recipe is now **`9febf3b461bdce53b4f9a51ad58648bc0ffe5cc66b58cede1ae4f1c94bf3bd1b`**, before local version labelling.

| Changed payload | Package and destination |
| --- | --- |
| `shell/plugins/lock/LockView.qml`, `shell/lock-host/Keyboard.qml` | Runtime, corresponding files under `/usr/share/omarchy/shell/` |
| `default/sddm/omarchy/Main.qml` | Settings, `/usr/share/sddm/themes/omarchy/Main.qml` and its defaults-tree source |
| `default/virtual-keyboard/QtQuick/VirtualKeyboard/Styles/Omarchy/` | Settings, all seven fixed files under `/usr/lib/qt6/qml/QtQuick/VirtualKeyboard/Styles/Omarchy/`, also retained in the defaults tree |

The seven module files are `qmldir`, `Theme.qml`, `AuthButton.qml`, `AuthChoice.qml`, `AuthKey.qml`, `Keyboard.qml` and `style.qml`, all mode 0644. This is the documented Qt custom-style location, not a caller-selected path. The installed/extracted Qt 6.12.0 type definitions and [Qt's style documentation](https://doc.qt.io/qt-6/qtvirtualkeyboard-overview.html#keyboard-styles) were inspected. No new native module, Qt layout copy or third-party QML is added. Existing `qt6-virtualkeyboard` must match the Qt ABI; source fixtures used retained 6.12.0-1 extraction under `/tmp/ally-auth-qt`, with no Sigil installation.

Both real patched `package()` functions staged successfully into `/tmp/ally-auth-redesign/package-publication/`. The zero-fuzz application, Bash syntax, ten auth payload byte/mode comparisons and SHA256 manifest are in `/tmp/ally-auth-redesign/package-stage-publication.{log,exit}` (exit 0). This is package staging, not makepkg archives, dependencies, scriptlets or target installation. The source receipt adds no payload changes after staging.

## Focused evidence

| Check | Result and retained log |
| --- | --- |
| Native SDDM/lock UI | Pass: `/tmp/ally-auth-redesign/lock-autorepeat-physical-final.{log,exit}`. Existing fixture now exercises actual Qt pointer events on Sign in, layout chooser, Shift, character and symbol keys; masked non-US input, editing, physical Tab/Return, submit/cancel, duplicate guards, session retention, retry focus, landscape/portrait geometry and alternative-key targets. The compositor-dependent autorepeat portion explicitly skipped without Wayland. |
| Alternative popup regression | `/tmp/ally-auth-redesign/alternatives-geometry-red.{log,exit}` fails for separate readable character targets before the style identifier fix; the final UI check passes afterwards. An initial fixture attempt incorrectly assumed the German A key had alternatives; the retained earlier failure is superseded by the English-layout geometry case. |
| Trusted host boundary | `/tmp/ally-auth-redesign/lock-state.{log,exit}` passed all 18 cases, including private native sockets and dummy deny/permit PAM. After the final visual corrections, the affected native host/PAM/isolation/broker/stream case passed again in `/tmp/ally-auth-redesign/host-native-publication.{log,exit}`. No compositor lock or real user password was used. Unit/compositor/hardware identities remain substituted as described in the recovery handoff. |
| Existing theme/refresh pipeline | `/tmp/ally-auth-redesign/plymouth-set.{log,exit}` passed, including white/background/foreground substitution, fixed asset publication, refresh and unsafe-source rejection. All root/publisher operations are private fixtures. No installed boot or greeter files changed. |
| Native dummy renders | `/tmp/ally-auth-redesign/visual-final-complete.{log,exit}` and `/tmp/ally-auth-redesign/visual-scale2-staged.{log,exit}` passed. Final navigation-cut renders are `/tmp/ally-auth-redesign/visual-publication.{log,exit}`. Scale-2 renders load the staged system Qt module. Inspected logo/field/actions, masked input, default locale, retry, portrait, chooser popup, Shift, symbols, alternatives and a light palette change. Captures include window overlays, so popups are visible. |

`git diff --check` passed. No whole-suite run or compositor/live acceptance is claimed. The existing English lock catalogue is unchanged; the greeter's layout label uses its existing Qt translation mechanism. Dummy render logs contain expected missing-Hunspell/no-compositor notices; sandboxed render-only runs also lack a Quickshell IPC server. These are distinct from the native AF_UNIX/PAM case, which passed with narrow escalation.

Private evidence, outside Git:

- Before: `/tmp/ally-auth-redesign/before/sddm-landscape.png`, `/tmp/ally-auth-redesign/before/lock-landscape.png` from the clean baseline.
- After: `/tmp/ally-auth-redesign/after/sddm-landscape.png`, `/tmp/ally-auth-redesign/after/lock-landscape.png`; this directory also contains idle/retry/portrait/chooser/modifier/symbol/alternative/light-palette states.
- Staged module, final navigation cut at scale 2: `/tmp/ally-auth-redesign/publication-scale2/` (earlier presentation captures retained in `/tmp/ally-auth-redesign/scale2/`), including `sddm-landscape.png` at 1920×1080 and portrait captures at 1080×1920. The physical Tab focus, alternative-popup and light-palette images were inspected at this scale as well.
- Private visual harness: `/tmp/ally-auth-redesign/config/shell.qml`. All entry text is dummy-only. No screenshots are committed or published.

## Serial rollout and rollback

The parent coordinator owns source review, final matching archives and the sole live Ally rollout. Install the matching runtime/settings pair together, including the new system Qt module; a runtime-only update or dev link is insufficient. Preserve existing themed SDDM artwork/configuration and use the reviewed native theme refresh/reapply path if required. Review scriptlets and back up their touched paths as required by the recovery handoff; this UI change does not correct their existing configuration-overwrite behaviour.

Do not replace code beneath an active trusted owner or stop that owner to inspect the UI. Arrange the package/session boundary from a known unlocked session with physical keyboard/TTY recovery, retain the immutable current owner choice and follow the existing staged transition procedure. Roll back through a planned graphical-session boundary to the saved matching baseline pair and greeter/theme state. Do not remove only the module or one package side while either authentication surface still needs it. Retain the matching Qt keyboard dependency.

Next live visual gates: native Ally 960×540 logical at scale 2 and portrait/external outputs; actual touch on all keys, Shift/symbols/alternatives, chosen locale and Compose requirements; user/session chooser, physical input, Cancel, wrong-password retry and visible Sign in/Unlock/Return. Check the real selected wallpaper/theme, focus after suspend/VT changes, actual PAM/fingerprint success/failure and secure lock ownership across desktop restart/suspend. Offscreen source evidence proves neither physical appearance on Ally nor Wayland lock security. Keyboard-free coldboot remains the separate boot feasibility task; this source increment implements none of it.
