# Trusted touch authentication

Source increment for inventory K06–K09/K12. Installed RC71L touch, controller and fingerprint acceptance remains the sole rollout owner's responsibility. K11 is investigated separately below.

## Boundaries and behaviour

The SDDM theme provides an editable user chooser, a visible session chooser, Password, Keyboard, Cancel and Sign in. It reads names and indices directly from SDDM's `userModel` and `sessionModel`. A valid remembered session wins; if no valid remembered session exists, the existing uwsm desktop is preferred. `omarchy.desktop`, `omarchy-gamescope.desktop` (Omarchy Gaming) and `omarchy-handheld.desktop` are discovered through SDDM, not launched by theme code. SESSION owns their installation and behaviour. No autologin or PAM policy is added.

The lock's Keyboard and Unlock controls live inside its existing `WlSessionLockSurface`. Qt Virtual Keyboard's application integration renders the keys as items in that surface. An external desktop wvkbd window cannot unlock it. The authentication service remains detached from the shell's host object tree and plugin facades; the keyboard introduces no authentication IPC and does not receive PAM authority.

Both fields mask immediately, mark input as sensitive, disable prediction and automatic capitalisation, and commit composed text before submission. Qt's packaged language key, Shift, symbols, long-press alternatives and Backspace provide layout/editing support. The language key selects a Qt keyboard layout; physical keyboards still use the compositor's XKB layout. The two layout choices are separate. Do not infer that all 50 Omarchy interface languages have a matching Qt password layout.

Cancel or Escape discards the entry and hides the keyboard. Cancel is disabled while authentication is in flight; it cannot unlock the session or cancel an SDDM PAM transaction. Return and the visible submit button use the same submission path. Duplicate submission is blocked during a password check; failure clears the field and restores focus for retry. The lock retains its existing empty-password guard. SDDM retains its existing PAM handling, including whether a user's account accepts an empty password.

The shell enables the trusted keyboard only when `omarchy-hw-rog-ally` recognises the RC71L, exporting `OMARCHY_TRUSTED_KEYBOARD=1` to its own process. Other hardware keeps its existing shell IME and has no lock Keyboard button. Qt input contexts are process-wide: on RC71L, text fields inside Quickshell use Qt Virtual Keyboard rather than Fcitx; other desktop applications keep their existing IME. This boundary avoids changing ordinary laptop/desktop composition.

The keyboard is created only on demand and only on the active monitor, since Qt supports one `InputPanel` per process. It is embedded, not a new window; opening and closing it does not animate. No process or polling timer is added for the keyboard. Desktop keyboard shortcuts remain TOUCH/INPUT's responsibility and are not authentication shortcuts.

The existing lock's separate password and fingerprint PAM contexts are unchanged. The enrolled-reader hint and unavailable-reader notice remain visible, and password entry remains available when a reader fails. This does not establish RC71L fingerprint support: the rollout owner must record driver, enrollment and actual PAM results. No fingerprint enrollment or PAM editing is performed by this increment.

## Dependencies and package manifest

Required package: `qt6-virtualkeyboard`. Arch Extra and the configured sync database supplied **6.12.0-1** when checked on 11 November 2026, matching local Qt 6.12.0. The package includes the platform input plugin, `QtQuick.VirtualKeyboard`, layouts, styles and their runtime dependencies. Reuse the installed package under its published licences; no upstream keyboard source is copied into Omarchy. The package metadata lists GPL-3.0-only, LGPL-3.0-only, LicenseRef-Qt-Commercial and Qt-GPL-exception-1.0; individual components retain their own notices.

Reviewed source-to-install mapping for the normal Omarchy package build:

| Source | Installed role/path |
| --- | --- |
| `install/omarchy-base.packages` | Required package set: add `qt6-virtualkeyboard` |
| `default/sddm/omarchy/Main.qml` | Settings package: `/usr/share/sddm/themes/omarchy/Main.qml` |
| `etc/sddm.conf.d/10-wayland.conf` | Settings package: `/etc/sddm.conf.d/10-wayland.conf` |
| `bin/omarchy-launch-shell` | Runtime package command, reached through the normal Omarchy installation |
| `shell/plugins/lock/Service.qml`, `LockView.qml` and `TrustedKeyboard.qml` | Runtime package shell sources |
| `default/i18n/en/shell.json` | Runtime package fallback strings |

The greeter and RC71L shell receive `QT_IM_MODULE=qtvirtualkeyboard`, `QT_IM_MODULES=qtvirtualkeyboard` and `QT_VIRTUALKEYBOARD_DESKTOP_DISABLE=1`. The last variable prevents an external keyboard window. The plural setting takes precedence in current Qt, so both IM settings must be local to these processes. Do not put them in the session environment: desktop application Fcitx and desktop wvkbd retain their own roles.

The source integrator must include the required keyboard package in the reviewed release dependency/install transaction; adding it to the source package list does not install it on an existing machine. Do not restart the shell against a release that lacks this dependency. Dev link alone does not publish the SDDM theme or fixed greeter configuration. Existing `omarchy-refresh-sddm` can publish the theme from a trusted installed/development tree, but it does not publish `/etc/sddm.conf.d/10-wayland.conf`.

## Serial deployment and rollback

Only the rollout owner executes this procedure. Before deploying, record existing runtime/settings package versions, save the matching package archives, back up the installed SDDM theme and configuration including any local overrides, and retain a working physical USB keyboard and TTY login. Save work before any planned logout. Do not modify disk encryption, autologin or PAM to make the test pass.

1. Install the required dependency through `omarchy-pkg-add qt6-virtualkeyboard`, then apply the integrator's reviewed runtime/settings package build through the established package release route. Record the exact installed versions and archive paths. Check package file ownership, fixed theme/config contents and `.pacnew` files before logout; a locally modified config may need an explicit reviewed merge.
2. From an unlocked desktop, the rollout owner can run `omarchy-restart-shell` once to load the runtime sources and process-local input settings. First exercise the preview for geometry; then test a real secure lock with a physical keyboard recovery path. A preview cannot prove secure-lock behaviour.
3. Exercise SDDM at the next deliberate logout/reboot. Do not restart the display manager under a live user session. Check that `QT_IM_MODULES`, `QT_IM_MODULE` and desktop-disable settings reached the greeter; never enable secret-bearing Qt/PAM debug logging during real password entry.
4. If the increment fails, return through the physical keyboard/TTY and reinstall the saved matching runtime/settings archives (`sudo pacman -U <previous-runtime-archive> <previous-settings-archive>`), restore the backed-up greeter config/theme where local files differed, and restart the shell from the unlocked desktop. Use the restored greeter on the next deliberate logout. Keep the keyboard dependency installed until no active or installed UI needs it. No LUKS rollback is needed because this increment changes no boot files.

Do not publish real passwords, keyboard traces, account names or personal screen contents. Screenshots and recordings use dummy input and stay outside Git.

## Focused checks and physical acceptance

`bash test/shell.d/lock-autorepeat-test.sh` now runs an offscreen fixture against the real Qt input plugin, lock view and greeter. It checks masked non-US input, layout selection, Backspace, virtual Return, visible submission, cancellation, failure/retry, duplicate submission guards and selected session forwarding. It would fail on the baseline (no trusted keyboard controls), and caught a zero-height keyboard layout loop during development. The existing live autorepeat check still requires a compositor. `launch-shell-test.sh` exercises the real supervisor with an inherited desktop IME and verifies process-local keyboard settings. Existing fingerprint, lock state and authentication-boundary checks remain relevant.

The fixture uses a dummy SDDM proxy only to capture calls and emit failure; it does not claim PAM, fingerprint or compositor security verification. It does not contact the actual device or take a session lock.

The rollout owner still needs to record:

- RC71L screen scale and keyboard geometry: password, session chooser, submit and Cancel remain visible with the keyboard shown; inspect at native resolution and configured scaling. Inspect the language popup and long-press symbol row for clipping. Repeat on an external monitor; at most one keyboard appears in the active surface.
- Actual touch keys: lowercase, Shift/capital, number, punctuation, non-US accented character, long-press alternative, layout switch and Backspace. Use a test account/password containing those characters. Verify the keyboard's key labels agree with the characters entered; never expose the actual password to demonstrate this.
- Real wrong-password PAM failure, retry, visible submit, Return and Cancel on SDDM and secure lock; physical keyboard entry with the OSK shown and hidden. Check focus after VT switch, suspend/resume and monitor changes.
- Real authenticated selection of desktop, gaming and managed-preference sessions when SESSION's package is installed; confirm failed login preserves the chosen session. No greeter shortcut may bypass authentication.
- Fingerprint success/failure/unavailable behaviour if this device has a working enrolled reader; password fallback remains usable. Distinguish absent driver support from UI regressions.
- Cold-boot LUKS result separately. A successful SDDM or lock keyboard says nothing about encrypted-disk input.

## K11: encrypted-disk input investigation

The current RC71L boot path uses the busybox mkinitcpio `udev`, `plymouth`, `keyboard` and `encrypt` hooks. `default/plymouth/omarchy.script` renders password bullets; it supplies no touch keyboard. Qt Virtual Keyboard is available only after the root filesystem and GUI have started.

Upstream [BuffyBox/unl0kr](https://gitlab.com/postmarketOS/mirror/buffybox/-/raw/master/unl0kr/README.md) provides fbdev/DRM touch password entry, hardware keyboard hotplug and runtime layouts. It is a candidate for a separate boot increment, not installed support here. Upstream's Arch package link points to AUR `buffybox`; no `buffybox` or `unl0kr` was available in the configured sync repositories. The current [AUR recipe](https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=buffybox) was retrieved and inspected: version 3.6.0-1 builds split packages `buffyboard` and `unl0kr`, with both busybox `unl0kr` and systemd `sd-unl0kr` mkinitcpio integration files. This establishes an available source recipe, not a reviewed boot release or RC71L support. The project is GPL-3.0-or-later. Its password goes to stdout and must be passed directly to the decrypt operation, never to logs or shell tracing.

A later boot increment needs a reviewed package/hook, actual RC71L touchscreen/display module discovery in the initramfs, a tested fallback boot entry and physical cold-boot verification. The [linux-surface integration reference](https://github.com/linux-surface/linux-surface/wiki/Disk-Encryption) distinguishes busybox `unl0kr` from systemd `sd-unl0kr`; its device module list is not evidence for the Ally. Bazzite's [early-boot OSK request](https://github.com/ublue-os/bazzite/issues/5842) was still open when checked. Keep the current encryption configuration and physical USB keyboard recovery intact.

## Primary references

- [Qt application integration and environment settings](https://doc.qt.io/qt-6/qtvirtualkeyboard-deployment-guide.html).
- [Qt InputPanel: one panel per application](https://doc.qt.io/qt-6/qml-qtquick-virtualkeyboard-inputpanel.html).
- [Arch package, dependencies and licences](https://archlinux.org/packages/extra/x86_64/qt6-virtualkeyboard/).
- [SDDM greeter model and login integration](https://github.com/sddm/sddm/blob/develop/src/greeter/GreeterApp.cpp). SDDM's normal `InputMethod` setting is deliberately skipped for a Wayland greeter; process-local `GreeterEnvironment` supplies the embedded application input plugin.
