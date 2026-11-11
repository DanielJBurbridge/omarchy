"""Run real recovery commands with isolated package, service and picker boundaries."""
import os
import pathlib
import subprocess
import tempfile

repo = pathlib.Path(os.environ['OMARCHY_TEST_ROOT'])
with tempfile.TemporaryDirectory(prefix='ally-recovery-') as temp:
    root = pathlib.Path(temp)
    stubs = {
        'omarchy-hw-rog-ally': '[[ ${ALLY:-1} == 1 ]]',
        'pacman': '''if [[ $2 == steam ]]; then printf 'steam %s\\n' "${VERSION:-1.0-1}"; else exit 1; fi''',
        'systemctl': '''printf 'LoadState=%s\\nActiveState=%s\\n' "${LOAD:-loaded}" "${ACTIVE:-active}"''',
        'busctl': 'printf "%s\\n" "${BUS:-b false}"',
        'findmnt': 'echo btrfs',
        'omarchy-cmd-present': '[[ ${TOOLS:-0} == 1 && $1 == omarchy-install-gaming-tools || ${DISPLAY_TOOLS:-0} == 1 && $1 == omarchy-display-rog-ally || ${DECKY_TOOLS:-0} == 1 && $1 == omarchy-*-gaming-decky ]]',
        'checkupdates': '''printf '%s\\n' 'private-repo-package 1 -> 2'; exit "${UPDATE_STATUS:-0}"''',
        'omarchy-menu-select': '''printf '%s\\n' "$@" >> "$TEST_ROOT/menus"
read -r count < "$TEST_ROOT/count"
printf '%s\\n' "$((count+1))" > "$TEST_ROOT/count"
line=$(sed -n "$((count+1))p" "$TEST_ROOT/choices")
case "$line" in CANCEL) exit 1;; ERROR) exit 2;; esac
for option in "${@:2}"; do
  [[ $option == -- ]] && break
  label=${option#*$'\\t'}; label=${label%%$'\\t'*}
  if [[ $line == "$label" ]]; then printf '%s\\treturned subtext\\n' "$line"; exit 0; fi
done
exit 93''',
    }
    for command in ('omarchy-launch-floating-terminal-with-presentation', 'omarchy-menu', 'omarchy-drive-game-library'):
        stubs[command] = 'printf "%s\\n" "${0##*/} $*" >> "$TEST_ROOT/actions"'
    for name, body in stubs.items():
        path = root / name
        path.write_text('#!/bin/bash\n' + body + '\n')
        path.chmod(0o755)
    env = dict(os.environ, PATH=f'{root}:{repo}/bin:' + os.environ['PATH'], HOME=temp, OMARCHY_PATH=str(repo), TEST_ROOT=temp)

    # A hang guard, not a performance assertion: real probes have cumulative
    # timeouts, and the nine-stream build host can be heavily scheduled.
    def run(command, *args, choices=('CANCEL',), **overrides):
        (root / 'menus').write_text('')
        (root / 'actions').write_text('')
        (root / 'count').write_text('0\n')
        (root / 'choices').write_text('\n'.join(choices) + '\n')
        return subprocess.run([str(repo / 'bin' / command), *args], env=dict(env, **overrides), capture_output=True, text=True, timeout=60)

    for command in ('omarchy-hw-rog-ally-status', 'omarchy-setup-rog-ally'):
        result = run(command, ALLY='0')
        assert result.returncode == 1 and 'RC71L' in result.stderr, result
        assert not (root / 'menus').read_text() and not (root / 'actions').read_text()
    print('PASS unsupported hardware exits before querying or acting')

    result = run('omarchy-hw-rog-ally-status')
    assert result.returncode == 0, result
    assert 'Steam package\tinstalled 1.0-1' in result.stdout
    assert 'active; device function unverified' in result.stdout
    assert 'not established by this report' in result.stdout
    assert 'not checked offline' in result.stdout
    for overrides in ({'LOAD': 'not-found'}, {'ACTIVE': 'failed'}, {'ACTIVE': 'serial=SECRET\nuser@example.com'}, {'VERSION': '1.2\nSECRET'}):
        result = run('omarchy-hw-rog-ally-status', **overrides)
        assert result.returncode == 0 and 'SECRET' not in result.stdout and 'user@example.com' not in result.stdout, result
        if overrides.get('LOAD') == 'not-found':
            assert 'inputplumber service\tunavailable' in result.stdout
        if overrides.get('ACTIVE') == 'failed':
            assert 'inputplumber service\tfailed' in result.stdout
    for bus, expected in (('b true', 'API present'), ('b false', 'not ready (no bus owner)'), ('bad secret', 'unavailable or unreadable')):
        result = run('omarchy-hw-rog-ally-status', BUS=bus)
        assert expected in result.stdout and 'bad secret' not in result.stdout, result
    print('PASS packages, absent units, failed services and unsafe output remain distinct')

    for code, expected in (('0', '1 pending'), ('2', 'no repository package updates'), ('1', 'availability unknown')):
        result = run('omarchy-hw-rog-ally-status', '--updates', UPDATE_STATUS=code)
        assert result.returncode == 0 and expected in result.stdout, result
        assert 'private-repo-package' not in result.stdout
    print('PASS update failure does not masquerade as no updates')

    result = run('omarchy-hw-rog-ally-status', '--menu')
    assert result.returncode == 0 and 'Physical acceptance' in (root / 'menus').read_text()
    result = run('omarchy-hw-rog-ally-status', '--menu', choices=('ERROR',))
    assert result.returncode == 2, result
    print('PASS status picker cancellation and failure')

    for _ in range(2):
        result = run('omarchy-setup-rog-ally')
        assert result.returncode == 0 and not (root / 'actions').read_text(), result
    result = run('omarchy-setup-rog-ally', choices=('ERROR',))
    assert result.returncode == 2
    print('PASS repeated setup and cancellation make no changes; shell failures propagate')

    cases = [
        (('Game libraries',), 'omarchy-launch-floating-terminal-with-presentation omarchy-drive-game-library --menu\n'),
        (('Update and recovery', 'Omarchy updates'), 'omarchy-menu summon update\n'),
        (('Update and recovery', 'Create system snapshot'), 'omarchy-launch-floating-terminal-with-presentation omarchy-snapshot create\n'),
        (('Update and recovery', 'Restore system snapshot', 'Back', 'Close'), ''),
        (('Update and recovery', 'Restore system snapshot', 'Open snapshot restore'), 'omarchy-launch-floating-terminal-with-presentation omarchy-snapshot restore\n'),
        (('Desktop keyboard', 'Back', 'Close'), ''),
        (('Desktop keyboard', 'Configure reviewed keyboard'), 'omarchy-launch-floating-terminal-with-presentation omarchy-setup-rog-ally-keyboard --configure-reviewed-package\n'),
        (('Desktop keyboard', 'Install reviewed keyboard'), 'omarchy-launch-floating-terminal-with-presentation omarchy-setup-rog-ally-keyboard --install-reviewed-aur\n'),
    ]
    for choices, expected in cases:
        # Game libraries returns to setup; all other action cases exit.
        choices = (*choices, 'Close')
        result = run('omarchy-setup-rog-ally', choices=choices)
        assert result.returncode == 0, (choices, result)
        assert (root / 'actions').read_text() == expected, (choices, (root / 'actions').read_text())
    print('PASS storage, normal update and confirmed recovery route to real commands')
    result = run('omarchy-setup-rog-ally', choices=('Game software', 'Game installers'))
    assert result.returncode == 0 and 'summon install.gaming' in (root / 'actions').read_text(), result
    assert 'Compatibility tools' not in (root / 'menus').read_text()
    result = run('omarchy-setup-rog-ally', choices=('Game software', 'Compatibility tools'), TOOLS='1')
    assert result.returncode == 0 and (root / 'actions').read_text() == 'omarchy-launch-floating-terminal-with-presentation omarchy-install-gaming-tools compatibility\n', result
    print('PASS optional delivered tools are offered only when their command exists')
    for choice, args in (('Display status', 'status'), ('Apply touch preset', 'touch-preset'), ('Restore touch preset', 'touch-preset reset')):
        result = run('omarchy-setup-rog-ally', choices=('Display and touch layout', choice), DISPLAY_TOOLS='1')
        assert result.returncode == 0 and (root / 'actions').read_text() == f'omarchy-launch-floating-terminal-with-presentation omarchy-display-rog-ally {args}\n', result
    print('PASS delivered display actions use fixed arguments and explicit preset rollback')
    for steps, command in (
        (('Decky status',), 'omarchy-setup-gaming-decky status'),
        (('Install reviewed Decky',), 'omarchy-install-gaming-decky --install-reviewed-aur'),
        (('Enable root plugins', 'Allow root plugins'), 'omarchy-setup-gaming-decky enable --allow-root-plugins'),
        (('Disable Decky',), 'omarchy-setup-gaming-decky disable'),
    ):
        result = run('omarchy-setup-rog-ally', choices=('Game software', 'Decky', *steps), DECKY_TOOLS='1')
        assert result.returncode == 0 and (root / 'actions').read_text() == f'omarchy-launch-floating-terminal-with-presentation {command}\n', result
    result = run('omarchy-setup-rog-ally', choices=('Game software', 'Decky', 'Enable root plugins', 'Back', 'Close'), DECKY_TOOLS='1')
    assert result.returncode == 0 and not (root / 'actions').read_text(), result
    print('PASS optional Decky install, explicit activation and cancellation stay separate')
