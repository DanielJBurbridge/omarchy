"""Exercise the real session supervisor with external process/seat boundaries faked.

These catch consumed-next regressions, accidental logout with absent dependencies,
early compositor exit, timeout, and return/cleanup failures. No compositor runs.
"""
import os
import pathlib
import subprocess
import tempfile
import textwrap

repo = pathlib.Path(os.environ['OMARCHY_TEST_ROOT'])

with tempfile.TemporaryDirectory(prefix='omarchy-gaming-session-') as temporary:
    root = pathlib.Path(temporary)
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
    command('omarchy-pkg-present', '#!/bin/bash\n[[ ${INPUT:-absent} != absent ]]\n')
    command('omarchy-hw-rog-ally-input', '#!/bin/bash\necho "input:$*" >> "$TEST_ROOT/actions"\n[[ $INPUT == good ]]\n')
    command('omarchy-cmd-present', '#!/bin/bash\n[[ ${MISSING:-} != "$1" ]] && command -v "$1" >/dev/null\n')
    command('pgrep', '#!/bin/bash\n[[ ${BUSY:-0} == 1 ]]\n')
    command('omarchy-notification-send', '#!/bin/bash\nexit 0\n')
    command('omarchy-system-lock', '#!/bin/bash\necho "lock" >> "$TEST_ROOT/actions"\nexit 0\n')
    command('omarchy-system', '#!/bin/bash\necho "system:$*" >> "$TEST_ROOT/actions"\nif [[ $MODE == logout-fail && ${2:-} == --execute ]]; then sleep 0.05; exit 42; fi\n')
    command('omarchy-toggle-desktop-keyboard', '#!/bin/bash\necho "keyboard:$*:$WAYLAND_DISPLAY" >> "$TEST_ROOT/actions"\n')
    command('uwsm', '''#!/bin/bash
        echo "desktop:$*" >> "$TEST_ROOT/actions"
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
        pathlib.Path(os.environ['TEST_ROOT'], 'scope-pid').write_text(str(child.pid))
        sys.exit(child.wait())
    ''')
    command('systemctl', '''#!/usr/bin/python3
        import os, pathlib, signal, sys
        with open(os.environ['TEST_ROOT'] + '/actions', 'a') as out:
            out.write('scope-stop:' + ' '.join(sys.argv[1:]) + '\\n')
        if 'is-active' in sys.argv:
            sys.exit(0 if sys.argv[-1] in os.environ.get('ACTIVE_UNITS', '').split(',') else 3)
        if 'start' in sys.argv:
            sys.exit(1 if sys.argv[-1] == os.environ.get('POWER_FAIL') else 0)
        if not sys.argv[-1].endswith('.scope'): sys.exit(0)
        try: os.killpg(int(pathlib.Path(os.environ['TEST_ROOT'], 'scope-pid').read_text()), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError): pass
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
        if [[ $MODE == return ]]; then
          steamos-session-select plasma
          exec sleep 10
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
        env = dict(os.environ, HOME=str(directory), XDG_STATE_HOME=str(directory / 'state'),
                   XDG_RUNTIME_DIR=str(directory / 'runtime'), XDG_SESSION_ID='c71',
                   OMARCHY_PATH=str(repo), TEST_ROOT=str(directory), MODE='normal',
                   OMARCHY_GAMING_READY_TIMEOUT='0.2', OMARCHY_GAMING_RETRY_GAP='0',
                   PATH=f'{bindir}:{repo / "bin"}:/usr/bin:/bin')
        for key in ('WAYLAND_DISPLAY', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
            env.pop(key, None)
        env.update(updates)
        return directory, env

    def run(env, executable, *args, status=0):
        result = subprocess.run([str(executable), *args], env=env, capture_output=True, text=True, timeout=6)
        assert result.returncode == status, (args, result)
        return result

    def state(directory):
        return directory / 'state/omarchy/gaming-session'

    setup = repo / 'bin/omarchy-setup-gaming-session'
    directory, env = case('preference')
    run(env, setup, 'default', 'gaming')
    run(env, setup, 'next', 'desktop')
    run(env, selector, 'preferred')
    assert not (state(directory) / 'next').exists()
    assert 'gamescope:' not in (directory / 'actions').read_text()
    run(env, selector, 'preferred')
    assert 'steam:-steamos3 -steampal -steamdeck -gamepadui:DISPLAY=:77' in (directory / 'actions').read_text(), ((directory / 'actions').read_text(), (state(directory) / 'session.log').read_text())
    run(env, setup, 'display', '720p', '40', 'fsr')
    run(env, selector, 'gaming')
    assert '-w 1280 -h 720 --framerate-limit 40 -F fsr' in (directory / 'actions').read_text()
    run(env, setup, 'display', 'bad', status=2)
    assert (state(directory) / 'display').read_text() == '720p 40 fsr\n'
    run(env, setup, 'reset')
    print('PASS persistent, consumed one-shot, display parser and reset')

    for mode in ('crash', 'early', 'timeout', 'steam-fail', 'return', 'switch'):
        directory, env = case(mode, MODE=mode)
        run(env, setup, 'default', 'gaming')
        if mode != 'switch':
            run(env, selector, 'preferred')
        else:
            run(env, setup, 'default', 'desktop')
            run(env, selector, 'preferred')
        actions = (directory / 'actions').read_text()
        assert 'desktop:' in actions, (mode, actions)
        assert 'scope-stop:' in actions, (mode, actions)
        assert not list((directory / 'runtime').rglob('active')), mode
        assert not list((directory / 'runtime').rglob('return')), mode
        if mode in ('crash', 'early', 'timeout', 'steam-fail'):
            assert (state(directory) / 'recovery').exists(), mode
            before = actions.count('gamescope:')
            run(env, selector, 'preferred')
            assert (directory / 'actions').read_text().count('gamescope:') == before
        if mode == 'switch':
            assert 'keyboard:stop:wayland-test' in actions and 'system:logout' in actions
        print('PASS lifecycle', mode)

    for name, updates in [('hardware', {'HARDWARE': 'laptop'}), ('busy', {'BUSY': '1'}),
                          ('missing', {'MISSING': 'gamescope'}), ('input-failure', {'INPUT': 'bad'})]:
        directory, env = case(name, **updates)
        run(env, selector, 'gaming')
        actions = (directory / 'actions').read_text()
        assert 'gamescope:' not in actions, actions
        assert 'desktop:' in actions, actions
        print('PASS entry guard', name)

    directory, env = case('missing-before-logout', MISSING='gamescope', WAYLAND_DISPLAY='fixture', HYPRLAND_INSTANCE_SIGNATURE='fixture')
    active = directory / 'runtime/omarchy-gaming-c71'
    active.mkdir()
    (active / 'active').write_text('desktop\n')
    run(env, repo / 'bin/omarchy-launch-gaming-session', status=1)
    assert not (directory / 'actions').read_text()
    assert not (active / 'switch').exists()
    print('PASS absent Gamescope never stops keyboard or logs out')

    directory, env = case('failed-logout-job', MODE='logout-fail', WAYLAND_DISPLAY='fixture', HYPRLAND_INSTANCE_SIGNATURE='fixture')
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
    command('omarchy-display-rog-ally', '#!/bin/bash\nprintf "%s\\n" --prefer-output DP-2\n')
    directory, env = case('optional-integrations', INPUT='good', ACTIVE_UNITS='steamos-manager.service')
    run(env, setup, 'overlay', 'on')
    marker = directory / 'state/omarchy/ally-power/enabled'
    marker.parent.mkdir(parents=True)
    marker.touch()
    run(env, selector, 'gaming')
    actions = (directory / 'actions').read_text()
    assert 'input:gamepad' in actions and '--prefer-output DP-2' in actions and '--mangoapp' in actions, actions
    assert 'start omarchy-ally-power.service' in actions, actions
    assert 'stop omarchy-ally-power.service' in actions, actions
    assert 'stop steamos-manager.service' not in actions and 'start steamos-manager.service' not in actions, actions
    print('PASS optional input, display, overlay and acquired power service ownership')

    directory, env = case('partial-power-failure', POWER_FAIL='omarchy-ally-power.service')
    marker = directory / 'state/omarchy/ally-power/enabled'
    marker.parent.mkdir(parents=True)
    marker.touch()
    run(env, selector, 'gaming')
    actions = (directory / 'actions').read_text()
    assert 'start steamos-manager.service' in actions and 'stop steamos-manager.service' in actions, actions
    assert 'gamescope:' not in actions and 'desktop:' in actions, actions
    print('PASS partial power setup failure releases acquired manager and returns desktop')

    for name in ('omarchy-launch-gaming-session', 'omarchy-launch-gaming-desktop'):
        run({'PATH': '/usr/bin:/bin'}, repo / 'bin' / name, '--help')
        run({'PATH': '/usr/bin:/bin'}, repo / 'bin' / name, 'unknown', status=2)
    print('PASS help and invalid arguments cannot trigger session actions')
