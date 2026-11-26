"""Exercise the real session supervisor with external process/seat boundaries faked.

These catch consumed-next regressions, accidental logout with absent dependencies,
early compositor exit, timeout, and return/cleanup failures. No compositor runs.
"""
import os
import pathlib
import runpy
import subprocess
import tempfile
import textwrap
from types import SimpleNamespace
from unittest.mock import Mock, patch

repo = pathlib.Path(os.environ['OMARCHY_TEST_ROOT'])


def check_removable_library(mount_path):
    watch = runpy.run_path(str(repo / 'default/gaming/removable-library.py'))['watch']
    from gi.repository import Gio, GLib, UDisks

    client = Mock()
    manager = client.get_object_manager.return_value
    manager.get_name_owner.return_value = ':1.1'
    obj = Mock()
    manager.get_objects.return_value = [obj]
    block = obj.get_block.return_value
    block.props = SimpleNamespace(id_uuid='AF04-DC18', id_usage='filesystem', hint_auto=True,
                                  hint_system=False, hint_ignore=False, configuration=GLib.Variant('as', []),
                                  symlinks=['/dev/disk/by-diskseq/1'])
    client.get_drive_for_block.return_value.props = SimpleNamespace(
        removable=True, seat=os.getenv('XDG_SEAT', 'seat0'))
    filesystem = obj.get_filesystem.return_value
    filesystem.props.mount_points = []
    mount = filesystem.call_mount_sync
    interrupted = GLib.Error.new_literal(Gio.dbus_error_quark(), 'udisksd disappeared', Gio.DBusError.NO_REPLY)
    denied = GLib.Error.new_literal(UDisks.error_quark(), 'access denied', UDisks.Error.NOT_AUTHORIZED)
    mount.side_effect = [interrupted, str(mount_path), denied, interrupted, interrupted]

    def events():
        signal, changed = client.connect.call_args.args
        assert signal == 'changed'
        changed(client)
        assert mount.call_count == 1, 'mount job changes must not retry the failed call'
        manager.get_name_owner.return_value = ':1.2'
        changed(client)
        assert mount.call_count == 2, 'a new UDisks owner must retry the interrupted mount'

        filesystem.props.mount_points = [str(mount_path)]
        changed(client)
        filesystem.props.mount_points = []
        manager.get_name_owner.return_value = ':1.3'
        changed(client)
        assert mount.call_count == 2, 'an intentional unmount must survive UDisks restarting'

        block.props.symlinks = ['/dev/disk/by-diskseq/2']
        changed(client)
        manager.get_name_owner.return_value = ':1.4'
        changed(client)
        assert mount.call_count == 3, 'a new insertion may mount, but access denials must not retry'

        block.props.symlinks = ['/dev/disk/by-diskseq/3']
        changed(client)
        manager.get_name_owner.return_value = ':1.5'
        changed(client)
        assert mount.call_count == 5, 'a second interrupted insertion gets one retry'
        manager.get_name_owner.return_value = ':1.6'
        changed(client)
        assert mount.call_count == 5, 'an interrupted retry must exhaust the retry budget'

    with patch.object(GLib, 'MainLoop', return_value=SimpleNamespace(run=events)), patch.object(os, 'write'):
        watch(client, block.props.id_uuid)
    print('PASS removable library retries interrupted mounts once after UDisks restarts')


with tempfile.TemporaryDirectory(prefix='omarchy-gaming-session-') as temporary:
    root = pathlib.Path(temporary)
    check_removable_library(root)
    bindir = root / 'bin'
    bindir.mkdir()

    def command(name, content):
        path = bindir / name
        first, _, rest = content.partition('\n')
        path.write_text(first + '\n' + textwrap.dedent(rest))
        path.chmod(0o755)
        return path

    # Fixed login bootstrap and timeout are the only rewritten boundaries.
    selector = command('selector', (repo / 'bin/omarchy-session-start').read_text()
                       .replace('source /usr/share/omarchy/default/bash/env-bootstrap', ':'))
    command('omarchy-hw-rog-ally', '#!/bin/bash\n[[ ${HARDWARE:-ally} == ally ]]\n')
    command('omarchy-pkg-present', '''#!/bin/bash
        case $1 in
          omarchy-gaming-session) exit 0 ;;
          omarchy-rog-ally-input) [[ ${INPUT:-absent} != absent ]] ;;
          *) exit 1 ;;
        esac
    ''')
    command('omarchy-handheld-autologin', '#!/bin/bash\nexit 0\n')
    command('omarchy-hw-rog-ally-input', '#!/bin/bash\necho "input:$*" >> "$TEST_ROOT/actions"\n[[ $INPUT == good ]]\n')
    command('omarchy-cmd-present', '''#!/bin/bash
        if [[ $1 == wvkbd-mobintl && ${WVKBD:-present} == missing ]]; then exit 1; fi
        [[ ${MISSING:-} != "$1" ]] && command -v "$1" >/dev/null
    ''')
    command('pgrep', '#!/bin/bash\n[[ ${BUSY:-0} == 1 ]]\n')
    command('omarchy-notification-send', '#!/bin/bash\nexit 0\n')
    command('omarchy-system-lock', '#!/bin/bash\necho "lock" >> "$TEST_ROOT/actions"\nexit 0\n')
    command('omarchy-system', '#!/bin/bash\necho "system:$*" >> "$TEST_ROOT/actions"\nif [[ $MODE == logout-fail && ${2:-} == --execute ]]; then sleep 0.05; exit 42; fi\n')
    command('wvkbd-mobintl', '#!/bin/bash\nexit 0\n')
    command('omarchy-toggle-desktop-keyboard', '''#!/bin/bash
        echo "keyboard:$*:$WAYLAND_DISPLAY" >> "$TEST_ROOT/actions"
        [[ ${KEYBOARD_STOP:-ok} == ok ]]
    ''')
    command('uwsm', '''#!/bin/bash
        echo "desktop:$*" >> "$TEST_ROOT/actions"
        if [[ $MODE == return-up ]]; then
          sig=$XDG_RUNTIME_DIR/hypr/handoff
          mkdir -p "$sig"
          (cd "$sig" && python3 -c 'import socket; s=socket.socket(socket.AF_UNIX); s.bind(".socket.sock")')
          next=$XDG_STATE_HOME/omarchy/gaming-session/next
          for _ in $(seq 1 40); do
            [[ -f $next ]] || exit 0
            sleep 0.05
          done
          echo 'next-stuck' >> "$TEST_ROOT/actions"
          exit 1
        fi
        if [[ $MODE == switch && ! -f $TEST_ROOT/switched ]]; then
          touch "$TEST_ROOT/switched"
          # UWSM excludes XDG_SESSION_ID from the desktop user manager.
          env -u XDG_SESSION_ID HYPRLAND_INSTANCE_SIGNATURE=fixture WAYLAND_DISPLAY=wayland-test omarchy-launch-gaming-session
        fi
    ''')
    command('systemd-run', '''#!/usr/bin/python3
        import os, pathlib, subprocess, sys
        args = sys.argv[1:]
        while args and args[0].startswith('--'): args.pop(0)
        child = subprocess.Popen(args, start_new_session=True)
        if os.environ['MODE'] == 'logout-fail': sys.exit(0)
        if '--scope' in sys.argv:
            pid_path = pathlib.Path(os.environ['TEST_ROOT'], 'scope-pid')
            pending = pid_path.with_suffix('.new')
            pending.write_text(str(child.pid))
            pending.replace(pid_path)
        sys.exit(child.wait())
    ''')
    command('systemctl', '''#!/usr/bin/python3
        import os, pathlib, signal, sys
        with open(os.environ['TEST_ROOT'] + '/actions', 'a') as out:
            out.write('scope-stop:' + ' '.join(sys.argv[1:]) + '\\n')
            if 'stop' in sys.argv and sys.argv[-1].endswith('.scope'):
                next_path = pathlib.Path(os.environ['XDG_STATE_HOME'], 'omarchy', 'gaming-session', 'next')
                if next_path.is_file():
                    out.write('next-at-scope-stop:' + next_path.read_text())
                else:
                    out.write('next-at-scope-stop:absent\\n')
        if 'is-active' in sys.argv:
            sys.exit(0 if sys.argv[-1] in os.environ.get('ACTIVE_UNITS', '').split(',') else 3)
        if 'start' in sys.argv:
            if sys.argv[-1] == 'omarchy-gaming-session.target' and 'TARGET_DELAY' in os.environ:
                import time
                time.sleep(float(os.environ['TARGET_DELAY']))
            sys.exit(1 if sys.argv[-1] == os.environ.get('POWER_FAIL') else 0)
        if not sys.argv[-1].endswith('.scope'): sys.exit(0)
        import time
        pid_path = pathlib.Path(os.environ['TEST_ROOT'], 'scope-pid')
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            try:
                pid = int(pid_path.read_text())
            except FileNotFoundError:
                time.sleep(0.05)
                continue
            # Consume this attempt's PID so the next stop waits for its own scope.
            pid_path.unlink()
            try:
                os.killpg(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            else:
                with open(os.environ['TEST_ROOT'] + '/actions', 'a') as out:
                    out.write('scope-terminated:' + sys.argv[-1] + '\\n')
            sys.exit(0)
        sys.exit('Fixture Gamescope scope did not register within 2s')
    ''')
    command('gamescope', '''#!/bin/bash
        printf 'gamescope:%s\\n' "$*" >> "$TEST_ROOT/actions"
        case $MODE in crash) exit 23;; early) exit 0;; timeout) exec sleep 10;; esac
        while [[ $1 != -- ]]; do shift; done
        shift
        DISPLAY=:77 "$@"
        # Real Gamescope may mask the primary child's exit status.
        exit 0
    ''')
    command('steam', '''#!/bin/bash
        echo "steam:$*:DISPLAY=$DISPLAY" >> "$TEST_ROOT/actions"
        if [[ $MODE == return || $MODE == return-up ]]; then
          timeout 2 bash -c 'printf "started\\n" > "$1"' _ "$OMARCHY_GAMING_RUNTIME/ready" || true
          last=$XDG_STATE_HOME/omarchy/gaming-session/last
          for _ in $(seq 1 80); do
            [[ -f $last ]] && break
            sleep 0.05
          done
          steamos-session-select plasma
          exec sleep 10
        fi
        # There is no display in this fixture. Signal the ready FIFO when the simulated client starts.
        if [[ $MODE == normal || $MODE == switch ]]; then
          printf 'started\\n' > "$OMARCHY_GAMING_RUNTIME/ready"
        fi
        # Let the supervisor consume startup before the client exits normally.
        sleep 0.05
        if [[ $MODE == steam-fail ]]; then exit 42; fi
    ''')

    def case(name, **updates):
        directory = root / name
        directory.mkdir()
        (directory / 'runtime').mkdir()
        (directory / 'actions').touch()
        # Start from a fresh login, even when the suite runs inside a managed desktop.
        # The real profile observer may only reach the fixture's private D-Bus.
        bus = os.environ['DBUS_SESSION_BUS_ADDRESS']
        env = dict(HOME=str(directory), XDG_STATE_HOME=str(directory / 'state'),
                   XDG_RUNTIME_DIR=str(directory / 'runtime'), XDG_SESSION_ID='c71',
                   DBUS_SESSION_BUS_ADDRESS=bus, DBUS_SYSTEM_BUS_ADDRESS=bus,
                   OMARCHY_PATH=str(repo), TEST_ROOT=str(directory), MODE='normal',
                   OMARCHY_GAMING_READY_TIMEOUT='3', OMARCHY_GAMING_RETRY_GAP='0',
                   OMARCHY_GAMING_NETWORK_TIMEOUT='0', OMARCHY_STEAM_PROC_ROOT=str(directory / 'proc'),
                   PATH=f'{bindir}:{repo / "bin"}:/usr/bin:/bin')
        env.update(updates)
        return directory, env

    def run(env, executable, *args, status=0, timeout=6):
        result = subprocess.run([str(executable), *args], env=env, capture_output=True, text=True, timeout=timeout)
        assert result.returncode == status, (args, result)
        return result

    def relogin(env):
        script = 'source "$OMARCHY_PATH/default/gaming/session.sh"\ngaming_entry_selection relogin\n'
        result = subprocess.run(['bash', '-c', script], env=env, capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, (result.returncode, result.stderr)
        return result.stdout.strip()

    def state(directory):
        return directory / 'state/omarchy/gaming-session'

    setup = repo / 'bin/omarchy-setup-gaming-session'
    directory, env = case('preference')
    run(env, setup, 'default', 'gaming')
    run(env, setup, 'next', 'desktop')
    run(env, selector, 'preferred')
    assert not (state(directory) / 'next').exists()
    assert 'gamescope:' not in (directory / 'actions').read_text()
    # 0.2s runs out on a loaded runner while the units are copied, before
    # Steam logs. The return cases keep the same longer waiter.
    env['OMARCHY_GAMING_READY_TIMEOUT'] = '8'
    run(env, selector, 'preferred', timeout=25)
    actions = (directory / 'actions').read_text()
    assert 'steam:-steamos3 -steampal -steamdeck -gamepadui:DISPLAY=:77' in actions, (actions, (state(directory) / 'session.log').read_text())
    assert '--xwayland-count 2' in actions, actions
    run(env, setup, 'display', '720p', '40', 'fsr')
    # A remembered card and an unavailable UDisks on the private bus must still allow play.
    library = state(directory) / 'library'
    library.write_text('AF04-DC18\n')
    (directory / 'actions').write_text('')
    run(env, selector, 'gaming', timeout=25)
    actions = (directory / 'actions').read_text()
    assert 'omarchy-gaming-steam AF04-DC18' in actions and 'steam:-steamos3' in actions
    assert '-w 1280 -h 720 --framerate-limit 40 -F fsr' in actions
    run(env, setup, 'display', 'bad', status=2)
    assert (state(directory) / 'display').read_text() == '720p 40 fsr\n'
    run(env, setup, 'reset')
    assert not library.exists(), 'reset must also revoke the removable-library opt-in'
    print('PASS persistent, consumed one-shot, display parser and reset')

    for mode in ('crash', 'early', 'timeout', 'steam-fail', 'return', 'return-up', 'switch'):
        directory, env = case(mode, MODE=mode)
        if mode == 'timeout':
            env['OMARCHY_GAMING_READY_TIMEOUT'] = '0.2'
        run(env, setup, 'default', 'gaming')
        if mode == 'switch':
            run(env, setup, 'default', 'desktop')
        elif mode in ('return', 'return-up'):
            # Switch to Desktop after the ready marker. A request before that
            # marker relaunches Gaming and does not write next=desktop. The
            # longer waiter keeps the marker from losing the race on a loaded runner.
            env['OMARCHY_GAMING_READY_TIMEOUT'] = '8'
        # A retry and the Desktop fallback can start three real profile
        # observers, each with a four-second startup wait of its own.
        run(env, selector, 'preferred', timeout=25)
        actions = (directory / 'actions').read_text()
        assert 'desktop:' in actions, (mode, actions)
        assert 'scope-stop:' in actions, (mode, actions)
        assert not list((directory / 'runtime').rglob('active')), mode
        assert not list((directory / 'runtime').rglob('return')), mode
        if mode == 'timeout':
            fallback = (state(directory) / 'fallback.log').read_text()
            assert fallback.count("Gamescope exited before Steam's UI was ready.") == 2, fallback
            assert actions.count('scope-terminated:omarchy-gamescope-c71.scope\n') == 2, actions
        if mode in ('crash', 'early', 'timeout', 'steam-fail'):
            assert 'next-at-scope-stop:desktop' not in actions, (mode, actions)
            assert not (state(directory) / 'next').exists(), mode
            assert (state(directory) / 'recovery').exists(), mode
            before = actions.count('gamescope:')
            run(env, selector, 'preferred')
            assert (directory / 'actions').read_text().count('gamescope:') == before
        if mode in ('return', 'return-up'):
            # Steam's steamos-session-select plasma is the explicit return.
            assert 'next-at-scope-stop:desktop\n' in actions, (mode, actions)
            assert not (state(directory) / 'recovery').exists(), mode
        if mode == 'return':
            next_file = state(directory) / 'next'
            assert next_file.read_text() == 'desktop\n', next_file.read_text() if next_file.exists() else 'missing'
            assert next_file.stat().st_mode & 0o777 == 0o600, oct(next_file.stat().st_mode)
            assert next_file.stat().st_uid == os.getuid()
            state_dir = state(directory)
            assert state_dir.stat().st_mode & 0o777 == 0o700, oct(state_dir.stat().st_mode)
            assert state_dir.stat().st_uid == os.getuid()
            (state_dir / 'recovery').write_text('failed\n')
            assert relogin(env) == 'desktop', 'one relogin lands in the desktop'
            assert not next_file.exists()
            assert (state_dir / 'recovery').is_file()
            assert relogin(env) == 'gaming', 'the following relogin returns to gaming'
        if mode == 'return-up':
            assert not (state(directory) / 'next').exists(), actions
            (state(directory) / 'recovery').write_text('failed\n')
            assert relogin(env) == 'gaming', 'Hyprland coming up clears the one-shot'
        if mode == 'switch':
            stop_at = actions.index('keyboard:stop:')
            assert stop_at < actions.index('system:logout')
            assert stop_at < actions.index('gamescope:')
        print('PASS lifecycle', mode)

    for name, updates in [('hardware', {'HARDWARE': 'laptop'}), ('busy', {'BUSY': '1'}),
                          ('missing', {'MISSING': 'gamescope'}), ('input-failure', {'INPUT': 'bad'})]:
        directory, env = case(name, **updates)
        run(env, selector, 'gaming')
        actions = (directory / 'actions').read_text()
        assert 'gamescope:' not in actions, actions
        assert 'desktop:' in actions, actions
        assert not (state(directory) / 'next').exists(), (name, actions)
        print('PASS entry guard', name)

    directory, env = case('ordinary-desktop', WAYLAND_DISPLAY='fixture', HYPRLAND_INSTANCE_SIGNATURE='fixture')
    active = directory / 'runtime/omarchy-gaming-c71'
    active.mkdir()
    (active / 'active').write_text('desktop\n')
    run(env, repo / 'bin/omarchy-launch-gaming-session', status=1)
    assert not (directory / 'actions').read_text()
    assert not (active / 'switch').exists()
    print('PASS ordinary Hyprland login never stops its keyboard or logs out for Gaming')

    directory, env = case('missing-before-logout', MISSING='gamescope', WAYLAND_DISPLAY='fixture',
                          HYPRLAND_INSTANCE_SIGNATURE='fixture', OMARCHY_HANDHELD_SESSION='c71')
    active = directory / 'runtime/omarchy-gaming-c71'
    active.mkdir()
    (active / 'active').write_text('desktop\n')
    run(env, repo / 'bin/omarchy-launch-gaming-session', status=1)
    assert not (directory / 'actions').read_text()
    assert not (active / 'switch').exists()
    print('PASS absent Gamescope never stops keyboard or logs out')

    def launch_from_desktop(name, **updates):
        directory, env = case(name, WAYLAND_DISPLAY='fixture', HYPRLAND_INSTANCE_SIGNATURE='fixture',
                              OMARCHY_HANDHELD_SESSION='c71', **updates)
        active = directory / 'runtime/omarchy-gaming-c71'
        active.mkdir()
        (active / 'active').write_text('desktop\n')
        run(env, repo / 'bin/omarchy-launch-gaming-session')
        return (directory / 'actions').read_text()

    missing_keyboard = launch_from_desktop('keyboard-missing', WVKBD='missing')
    assert 'keyboard:' not in missing_keyboard and 'system:logout' in missing_keyboard, missing_keyboard
    print('PASS a missing wvkbd does not block the Gamescope switch')

    stuck_keyboard = launch_from_desktop('keyboard-stuck', KEYBOARD_STOP='fail')
    assert stuck_keyboard.index('keyboard:stop:') < stuck_keyboard.index('system:logout'), stuck_keyboard
    print('PASS a failing keyboard stop still requests the switch')

    directory, env = case('failed-logout-job', MODE='logout-fail', WAYLAND_DISPLAY='fixture',
                          HYPRLAND_INSTANCE_SIGNATURE='fixture', OMARCHY_HANDHELD_SESSION='c71')
    active = directory / 'runtime/omarchy-gaming-c71'
    active.mkdir()
    (active / 'active').write_text('desktop\n')
    run(env, repo / 'bin/omarchy-launch-gaming-session')
    assert not (active / 'switch').exists(), 'failed asynchronous logout must not change a later ordinary logout'
    print('PASS a submitted logout job clears its gaming request on actual failure')

    # The upstream desktop bridge is private and rejects policy mutations.
    run(env, repo / 'default/gaming/bin/steamos-session-select', 'persistent', status=2)
    print('PASS private Steam bridge rejects login policy changes')

    command('mangoapp', '#!/bin/bash\nexit 0\n')
    directory, env = case('optional-integrations', INPUT='good', ACTIVE_UNITS='steamos-manager.service')
    run(env, setup, 'overlay', 'on')
    drm = directory / 'drm'
    env['OMARCHY_DRM_PATH'] = str(drm)
    for connector in ('card0-eDP-1', 'card0-DP-2'):
        (drm / connector).mkdir(parents=True)
        (drm / connector / 'status').write_text('connected\n')
    (drm / 'card0-DP-2' / 'edid').write_bytes(b'\0' * 128)
    run(env, repo / 'bin/omarchy-gaming-output', 'DP-2')
    marker = directory / 'state/omarchy/ally-power/enabled'
    marker.parent.mkdir(parents=True)
    marker.touch()
    run(env, selector, 'gaming')
    actions = (directory / 'actions').read_text()
    assert 'input:gamepad' in actions and '--prefer-output DP-2,eDP-1' in actions and '--mangoapp' in actions, actions
    assert 'ally-power' not in actions and 'steamos-manager' not in actions, actions
    assert 'gamescope:' in actions, actions
    print('PASS optional input, display and overlay, with no ally-power units')

    directory, env = case('missing-overlay', MISSING='mangoapp')
    run(env, setup, 'overlay', 'on')
    result = run(env, selector, 'gaming')
    actions = (directory / 'actions').read_text()
    assert actions.count('gamescope:') == 1 and 'steam:-steamos3' in actions, (actions, result.stderr)
    assert '--mangoapp' not in actions, actions
    assert not (state(directory) / 'recovery').exists(), actions
    assert (state(directory) / 'overlay').read_text() == 'on\n'
    assert 'mangoapp is missing' in result.stderr, result.stderr
    print('PASS an unavailable overlay preserves the preference and lets Gaming start')

    # The historical companion contains its profiles and service, but the
    # matching gamepad helper used to come from the runtime package.
    (bindir / 'omarchy-hw-rog-ally-input').unlink()
    directory, env = case('legacy-companion-without-helper', INPUT='installed',
                          TARGET_DELAY='1.1', OMARCHY_GAMING_READY_TIMEOUT='1')
    run(env, selector, 'gaming')
    actions = (directory / 'actions').read_text()
    assert '--user start omarchy-gaming-session.target' in actions and 'steam:-steamos3' in actions, actions
    assert actions.count('gamescope:') == 1 and not (state(directory) / 'recovery').exists(), actions
    print('PASS Gaming starts once after the older input target prepares the controller')

    for name in ('omarchy-launch-gaming-session', 'omarchy-launch-gaming-desktop'):
        run({'PATH': '/usr/bin:/bin'}, repo / 'bin' / name, '--help')
        run({'PATH': '/usr/bin:/bin'}, repo / 'bin' / name, 'unknown', status=2)
    print('PASS help and invalid arguments cannot trigger session actions')
