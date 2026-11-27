# Lock, SDDM and shell findings

Original review on `feat/ally-parity-release-20261111` at `c88d5344b2fdc64ba74e9221c52ccfca131b3ba2`. Status was rechecked against `105a9800`. The findings below retain their original reproduction details for the held lock-host work.

## Blocker: greeter imports a keyboard style the update does not install

**Resolved in the baseline.** `Main.qml` lazily loads `Keyboard.qml`, which imports Qt's standard Virtual Keyboard. If the module is unavailable, the loader disables the keyboard action and leaves keyboard sign-in available.

`default/sddm/omarchy/Main.qml:3` imports `QtQuick.VirtualKeyboard.Styles.Omarchy` unconditionally. `etc/sddm.conf.d/10-wayland.conf:4` sets `QT_IM_MODULE`, `QT_IM_MODULES` and `QT_VIRTUALKEYBOARD_DESKTOP_DISABLE` and does not set `QML_IMPORT_PATH`. The style sources live in `default/virtual-keyboard/QtQuick/VirtualKeyboard/Styles/Omarchy/`. The only install of those files onto the Qt import path is `packaging/rog-ally-release/omarchy-pkgs.patch:14-16`, which writes them to `/usr/lib/qt6/qml/QtQuick/VirtualKeyboard/Styles/Omarchy/`. `docs/file-layout.md` ships `default/sddm/omarchy/` to `/usr/share/sddm/themes/omarchy/` with the settings package. `install/omarchy-base.packages` adds `qt6-virtualkeyboard` for a fresh install. No migration installs that package or the style before the greeter changes.

What breaks: an existing install that receives the new greeter without that external package patch, or without `qt6-virtualkeyboard` and the style module on the default Qt import path, fails to load the sign-in screen.

Suggested fix: ship the style module in the same package that installs `Main.qml`, and install `qt6-virtualkeyboard` before the greeter is switched. If the import cannot be resolved, keep the previous theme.

Suggested test: load `Main.qml` with the system Qt import path and with `QML_IMPORT_PATH` unset. Expect the import to fail until the style is installed at the Qt module path the greeter actually searches.

## High: lock IPC fails closed until the new launcher has run

**Outside the baseline.** `omarchy-shell` uses the running Quickshell IPC and has no lock-host context dependency at `105a9800`. Recheck this if the trusted host is enabled.

`bin/omarchy-shell:45-49` sends every `omarchy-shell lock` through `omarchy-lock-host context` and refuses the lock when that command fails. `default/lock-host/control.py:42-63` opens `$XDG_RUNTIME_DIR/omarchy-lock-mode-$HYPRLAND_INSTANCE_SIGNATURE` without creating it. `mode(initialize=True)` inside `run()` (`control.py:211`) is what creates the file, and only the new `run-shell` launcher calls that. A shell still started as quickshell directly never creates it. `FileNotFoundError` is an `OSError`, and `control.py:338-343` turns that into exit 1. `setup("status")` treats a missing file as "no graphical owner"; `context()` does not.

What breaks: after the package update, lock IPC is refused until the shell is restarted through `omarchy-lock-host run-shell`. Suspend and explicit lock do nothing while the previous shell is still the one on screen.

Suggested fix: a missing mode file for `context()` means the running shell still owns the lock, and `omarchy-shell` should use its existing shell IPC in that case. Do not initialize a host as a side effect of a lock request.

Suggested test: call `context` with a mode `0700` runtime directory and `HYPRLAND_INSTANCE_SIGNATURE` set, and with no mode file. Expect lock IPC to still reach the shell owner.

## High: a locked restart from SSH dies on a missing Wayland display

**Outside the baseline.** The current restart path uses the shell's lock status and can derive the Hyprland signature. `omarchy-shell` discovers a Wayland socket when the display is unset. The held host's own context handling still needs its SSH recovery check.

`bin/omarchy-restart-shell:14-18` still says a caller outside the session, including SSH, can derive `HYPRLAND_INSTANCE_SIGNATURE` from the runtime directory. `bin/omarchy-restart-shell:53-58` then requires `omarchy-lock-host context` when the compositor is locked and the trusted host does not own it. `default/lock-host/control.py:137` reads `os.environ["WAYLAND_DISPLAY"]` and raises `KeyError` when it is unset. That exception exits 1 at `control.py:338-343`, and the restart script prints "Refusing locked desktop restart without a validated graphical session context." `test/shell.d/restart-shell-test.sh:258` asserts that refusal. The same test exports `WAYLAND_DISPLAY` at line 30, so it never covers a recovered signature with no display variable.

What breaks: the stranded-lock recovery described at `bin/omarchy-restart-shell:21-26` fails from SSH or a TTY. The signature can be derived, and the restart still stops because the display name was not in the environment.

Suggested fix: recover `WAYLAND_DISPLAY` from the live Hyprland socket the same way the signature is recovered, and pass that to `context()`. A missing display variable is not by itself an unsafe lock.

Suggested test: locked compositor, no `WAYLAND_DISPLAY`, signature taken from the runtime directory. Expect the restart to proceed and re-lock, rather than exit 1.

## Medium: the lock lease is inherited across exec

**Outside the baseline.** The lock-host lease code is absent at `105a9800`. Keep the inherited-lease regression with any future port.

`default/lock-host/control.py:218-226` opens `owner.lock` or `broker.lock`, takes `LOCK_EX|LOCK_NB`, then `os.set_inheritable(fd, True)` before `os.execvpe` of quickshell at line 244. The child keeps the flock. A surviving child holds the lease, so the next `run-shell` gets `BlockingIOError`. The broker role turns that into success; the shell role raises. `bin/omarchy-launch-shell:89-91` gives up after five relaunches in sixty seconds.

What breaks: a child that outlives the shell, and still holds the inherited lock, prevents the next shell from starting. The launcher then stops trying.

Suggested fix: keep the lease close-on-exec in the process that owns it. The quickshell child must not inherit the fd.

Suggested test: spawn a child that inherits the lock fd and stays alive, then run `run-shell` again. Today the second launch fails to take the lock. After the fix the child does not inherit the fd and the second launch takes it.

## SDDM rollback and system-service environment

**Resolved in the baseline.** The stock package guard and gaming companion removal both retire the generated handheld session drop-in. Recognised legacy owner entries are migrated to inactive `[OmarchyHandheld]` metadata. The installer’s `autologin.conf` and custom fragments are preserved. `105a9800` also allows the system-service callers to source `default/gaming/session.sh` with an empty environment and read the desktop lock policy.
