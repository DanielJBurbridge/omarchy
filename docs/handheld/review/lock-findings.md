# Lock findings

Reviewed against the lock and authentication work on `feat/ally-parity-release-20261111`, plus the handheld lock-screen keyboard (K07). The marker path is the one named in `docs/handheld/02-mode-switch-and-dock.md`: `/var/lib/omarchy/handheld/k07-landed`.

## Greeter import

`default/sddm/omarchy/Main.qml` used to import `QtQuick.VirtualKeyboard` unconditionally. The greeter then failed to load when `qt6-virtualkeyboard` or the Omarchy style module was not on the Qt import path. `Main.qml` no longer imports it. The styled form lives in `LoginForm.qml` and is loaded by a `Loader`; a load error falls back to a form with no virtual keyboard. Fresh installs already list `qt6-virtualkeyboard` in `install/omarchy-base.packages`. The style module still ships through the packaging patch. The greeter now survives both being absent.

Covered by `test/shell.d/sddm-keyboard-import-test.sh`. The quickshell half of that test skips where `quickshell` is not installed. `test/shell.d/plymouth-set-test.sh` still publishes `LoginForm.qml` with the theme.

## Lock under the old launcher

`omarchy-lock-host mode` created the per-session mode file only when the new launcher called it with `initialize`. A shell still started by the old launcher had no file, so `context()` raised `FileNotFoundError` and `omarchy-shell lock` refused the lock until a restart through `omarchy-lock-host run-shell`. A missing mode file now means the running shell still owns the generic lock. A status or lock read does not create the file and does not latch the trusted host.

Covered by `test_status_cannot_select_or_start_an_owner` and `test_missing_mode_file_keeps_shell_lock_for_the_old_launcher` in `test/shell.d/trusted-lock-host-test.py`, run from `test/shell.d/lock-state-test.sh`.

## TTY and SSH restart

`omarchy-restart-shell` recovers `HYPRLAND_INSTANCE_SIGNATURE` from the Hyprland runtime directory, then asks `context()` whether the lock is safe to replace. `context()` required `WAYLAND_DISPLAY` in the environment, so a TTY or SSH caller with a recovered signature exited before it could re-lock a dead lock client. The recovery is kept. When `WAYLAND_DISPLAY` is empty, both the restart command and `context()` take the newest real `wayland-[0-9]*` socket in the runtime directory. The existing peer check still requires that socket and the Hyprland socket to be the same live compositor.

`omarchy-shell lock` still requires both variables before it calls `context()`. A lock request from SSH does not guess a session from the newest socket.

Covered by `test/shell.d/restart-shell-test.sh` (recovered display, and refusal when no display socket exists) and `test_context_recovers_a_tty_display_from_the_session_socket`.

## Owner lease

`run()` opened the owner lease and closed it only on the `execvpe` failure path, so a failed role write left the descriptor open and the next launch could not take the lease. The descriptor is now held by a context manager. Every path except a successful `execvpe` closes it. The successful exec does not return, so the owner keeps the inheritable descriptor. That is required: the lease has to live in the quickshell process, and `role_pid()` checks that the owner's executable is quickshell.

Residual: quickshell's own children can still inherit the descriptor, because clearing close-on-exec would drop the lease at exec and the next `run-shell` could take it. `FD_CLOEXEC` is not set for that reason. A second owner still loses the non-blocking flock while the first quickshell is alive.

Covered by `test_failed_exec_closes_the_owner_lease`.

## K07 marker and desktop lock

`/var/lib/omarchy` and `/var/lib/omarchy/handheld` are root-owned mode `0755` and not writable by the desktop user. The marker file is root-owned mode `0644` and not user-writable. Readers treat ENOENT (missing file or missing directory) as absent. Any other stat error is present.

The desktop-lock value lives beside the marker at `/var/lib/omarchy/handheld/desktop-lock` and is read only from that path. A user-owned, group-writable, or world-writable file is not the setting. `on`, `default-off`, and `explicit-off` are distinct stored strings. Copies under `~/.local/state` are ignored.

Before the marker, the handheld variant (both `omarchy-hw-rog-ally` and the `omarchy-gaming-session` package) treats a missing, corrupt, or `default-off` value as off. Either condition alone stays on, so a laptop with the package stays on. After the marker, a missing, corrupt, or unreadable value fails closed to on. Only a root-owned `explicit-off` stays off. `omarchy-setup-handheld-k07` creates the marker and rewrites a stored `default-off` to `on`. It leaves `explicit-off` alone. Removing the marker is not part of a downgrade.

The migration `migrations/1794466185.sh` runs that command and, on an Ally, stages `~/.local/state/omarchy/lock-host-enabled` for the next graphical session. The current session's mode file is already latched, so the shell keeps the lock until logout. While that session is up, with no physical keyboard and the trusted host not the owner, suspend and the lock hotkey do not lock. They return to gaming when desktop lock is on. That is the gap where a keyboard-less Ally would otherwise sit at a lock screen with no touch keyboard.

A physical keyboard is a udev keyboard that is not the Ally N-KEY interface (USB `0b05:1abe`), not under `/devices/virtual/`, and not uinput, inputplumber, ydotool, or py-evdev. `omarchy-hw-physical-keyboard` exits 0 when one is attached. With one attached, the ordinary lock stays available before and after K07.

Covered by `test/shell.d/desktop-lock-test.sh`.

## Sleep-lock exit codes

`omarchy-system-sleep-lock` exits 0 only after `lock status` confirms the lock surface is secure. The suspend broker runs that command as the desktop user and does not suspend on any other exit, or on a timeout. Exit 1 means a required lock was not confirmed. Exit 10 means the handheld skipped the lock because no physical keyboard is attached and desktop-lock is not on. Exit 11 means desktop-lock is on with no physical keyboard, so the desktop is sent back to gaming instead of locking. `test/shell.d/desktop-lock-test.sh` covers each code.

## Handheld idle lock

Quickshell's idle service (`shell/plugins/services/idle/Service.qml`, default 300 s) calls `omarchy-system-idle-lock`. On the handheld variant that locks only when a physical keyboard is attached. With none and desktop-lock on, it calls `org.omarchy.Handheld.Suspend1.Suspend` when that system bus name is present, and otherwise `omarchy-launch-gaming-session --confirm`. With `default-off` or `explicit-off` it blanks the outputs through `omarchy-brightness-display off` and does not lock or suspend. That is spec 02 revision 9 (acceptance 53). Open pull requests do not edit this idle file. `origin/t3-code` and `origin/t3-theme-support` still call `omarchy-system-lock` from an older copy of the service; neither has a commit past the release tip that changes it. Covered by `test/shell.d/desktop-lock-test.sh`.

## A1. wvkbd above the lock

On the Ally, wvkbd must not be shown above hyprlock and must not take touches over it. A Shift latched before the lock must not change the typed password. `omarchy-toggle-desktop-keyboard stop` sends USR1, which in wvkbd 0.21 releases held keys, then TERM. The hotkey lock, the suspend lock, and the lock plugin's `beginLock` all call it once a lock is actually taken. A skipped lock leaves the desktop keyboard alone. `stop` exits 0 when wvkbd is not running, and a missing command does not fail the lock.

Covered for the shell path by `test/shell.d/system-lock-test.sh`. A latched Shift on a real Ally, and whether wvkbd is above hyprlock, still needs a device with the compositor running. This environment has no compositor.

Follow-up, not done here: if wvkbd is killed with SIGKILL, `release_pressed_on_close` is what drops the latched modifier. `stop` does not use SIGKILL.

## A2. Wayland virtual keyboard

Any client of the same user can use Hyprland's `virtual-keyboard-v1`. That is a K07 threat. Qt Virtual Keyboard's input context also exposes the focused password object to any importer in the same process. Masking the password field is not an access-control boundary.

Mitigations in this tree:

- The touch keyboard loads only in the trusted lock host, a separate quickshell config. The plugin-bearing shell does not set `QT_IM_MODULE`.
- `keyboardAvailable` is true only when `trustedHost` is true, and the host sets `QT_VIRTUALKEYBOARD_DESKTOP_DISABLE=1` so the keyboard stays inside the lock surface.
- wvkbd is not an unlock path. It is hidden when a lock is taken.
- The host drops caller-controlled Qt, QML, and loader variables before exec.

A same-user client can still inject keys into the session through the compositor protocol. Isolating the password field from the desktop shell does not close that. Closing it would be a compositor policy change, not a shell change.

## A3. Lock-screen language

The lock surface reads `lock.enterPassword`, `lock.keyboard`, `lock.cancel`, `lock.unlock`, and `lock.keyboardLayout` through `shell/Commons/I18n.qml` and plugin catalogs through `Translations.qml`. The integ change finishes the FileView read already in flight, then reads the file again (`reloadWatched`). That is now what both files do on `onFileChanged`.

The English prompt is "Enter Password". The Danish prompt is "Indtast adgangskode". `test/shell.d/i18n-startup-test.sh` checks those catalog strings, and its quickshell fixture includes `lock.enterPassword` in the startup snapshot. The fixture half skips where `quickshell` is not installed.
