import os, pathlib, subprocess, tempfile
script = pathlib.Path(os.environ['OMARCHY_TEST_ROOT']) / 'bin/omarchy-setup-gaming'
with tempfile.TemporaryDirectory(prefix='haki-gaming-test-') as temp:
    root = pathlib.Path(temp)
    commands = {
        'omarchy-i18n': '#!/bin/bash\nvalue=$("$OMARCHY_TEST_ROOT/bin/omarchy-i18n" "$@") || exit $?\nif [[ ${TEST_TRANSLATED:-0} == 1 ]]; then printf "translated:%s\\n" "$value"; else printf "%s\\n" "$value"; fi\n',
        'omarchy-cmd-present': '#!/bin/bash\n[[ $1 == steam && $STEAM_PRESENT == 1 ]]\n',
        'omarchy-menu-select': '''#!/bin/bash
printf '%s\\n' "$*" >> "$TEST_ROOT/menus"
read -r count < "$TEST_ROOT/count"
printf '%s\\n' "$((count + 1))" > "$TEST_ROOT/count"
line=$(sed -n "$((count + 1))p" "$TEST_ROOT/choices")
case "$line" in CANCEL) exit 1;; ERROR) exit 2;; esac
valid=0
for option in "${@:2}"; do
  [[ $option == "--" ]] && break
  label=${option#*$'\t'}; label=${label%%$'\t'*}
  [[ $line == "$label" ]] && valid=1
done
[[ $valid == 1 ]] || { echo "Selection is not an offered row: $line" >&2; exit 93; }
printf '%s\\tfixture subtext\\n' "$line"
''',
        'omarchy-launch-steam-bigpicture': '#!/bin/bash\necho bigpicture >> "$TEST_ROOT/actions"\n',
        'omarchy-launch-steam-desktop': '#!/bin/bash\necho desktop >> "$TEST_ROOT/actions"\n',
        'omarchy-menu': '#!/bin/bash\necho "$*" >> "$TEST_ROOT/actions"\n',
        'omarchy-setup-ally-power': '#!/bin/bash\n[[ $* == gaming-status && -n ${POWER_STATUS:-} ]] || exit 1\nprintf "%s\\n" "$POWER_STATUS"\n',
        'pacman': '#!/bin/bash\n[[ $* == "-Q -- omarchy-gaming-session" && ${COMPANION_PRESENT:-0} == 1 ]]\n',
    }
    for name, source in commands.items():
        path = root / name
        path.write_text(source)
        path.chmod(0o755)
    cases = [
        ('installed-launch', 1, ['Open Big Picture'], 0, 'bigpicture\n'),
        ('translated-launch', 1, ['Open Big Picture'], 0, 'bigpicture\n'),
        ('missing-steam', 0, ['Install Steam…'], 0, 'summon install.gaming\n'),
        ('cancel', 1, ['CANCEL'], 0, ''),
        ('desktop-return', 1, ['Exit Steam Big Picture'], 0, 'desktop\n'),
        ('shell-failure', 1, ['ERROR'], 2, ''),
        ('guidance-return', 1, ['Help and first sign-in', 'First sign-in', 'Back', 'Help and first sign-in', 'Controller and typing', 'Back', 'Help and first sign-in', 'Return to desktop', 'Back', 'Close'], 0, ''),
        ('guidance-cancel', 1, ['Help and first sign-in', 'First sign-in', 'CANCEL'], 0, ''),
    ]
    for name, present, choices, status, actions in cases:
        translated = name.startswith('translated-')
        if translated:
            choices = ['translated:' + choice for choice in choices]
        (root / 'choices').write_text('\n'.join(choices) + '\n')
        (root / 'count').write_text('0\n')
        (root / 'actions').write_text('')
        (root / 'menus').write_text('')
        env = dict(os.environ, PATH=f'{root}:' + str(script.parent) + ':' + os.environ['PATH'], HOME=temp, OMARCHY_PATH=str(script.parent.parent), TEST_ROOT=temp, STEAM_PRESENT=str(present), TEST_TRANSLATED=str(int(translated)))
        result = subprocess.run([str(script)], env=env, capture_output=True, text=True, timeout=15)
        assert result.returncode == status, (name, result)
        assert (root / 'actions').read_text() == actions, name
        menus = (root / 'menus').read_text()
        assert ('Open Big Picture' in menus) == bool(present), name
        assert ('Exit Steam Big Picture' in menus) == bool(present), name
        assert ('Install Steam…' in menus) != bool(present), name
        print('PASS', name)
    result = subprocess.run([str(script), '--help'], env={'PATH': '/usr/bin:/bin'}, capture_output=True, text=True)
    assert result.returncode == 0 and 'first sign-in' in result.stdout
    print('PASS standalone-help')

    recovery = script.with_name('omarchy-menu-gaming-recovery')
    (root / 'vendor').write_text('ASUSTeK COMPUTER INC.\n')
    (root / 'board').write_text('unknown\n')
    (root / 'choices').write_text('CANCEL\n')
    state = root / 'state/omarchy/gaming-session'
    marker = state / 'recovery'
    cases = [
        ('ordinary-desktop', 'ROG Ally RC71L', 0, 0, None, 'not detected', 'No saved desktop fallback', 'Setup → Gaming'),
        ('fallback', 'ROG Ally RC71L_RC71L', 1, 1, 'local-only details\n', 'installed', 'Desktop fallback recorded', 'Steam from Apps'),
        ('partial', 'ROG Ally RC71L', 1, 0, '', 'installed', 'Saved fallback status unavailable', 'Setup → Gaming'),
        ('symlink', 'ROG Ally RC71L', 0, 1, 'symlink', 'not detected', 'Saved fallback status unavailable', 'Steam from Apps'),
        ('ally-x', 'ROG Ally X RC72LA', 1, 1, None, '', '', ''),
    ]
    env.pop('OMARCHY_HANDHELD_SESSION', None)
    env.update(TEST_TRANSLATED='0', XDG_STATE_HOME=str(root / 'state'), OMARCHY_LANGUAGE_FILE=str(root / 'language'),
               OMARCHY_DMI_SYS_VENDOR_PATH=str(root / 'vendor'), OMARCHY_DMI_BOARD_NAME_PATH=str(root / 'board'),
               OMARCHY_DMI_PRODUCT_NAME_PATH=str(root / 'product'))
    for name, model, companion, steam, saved, package_label, fallback_label, hint in cases:
        (root / 'product').write_text(model + '\n')
        (root / 'count').write_text('0\n')
        (root / 'menus').write_text('')
        if saved is not None:
            state.mkdir(parents=True, exist_ok=True)
            if saved == 'symlink':
                marker.symlink_to(root / 'nonexistent')
            else:
                marker.write_text(saved)
        result = subprocess.run([str(recovery)], env=dict(env, COMPANION_PRESENT=str(companion), STEAM_PRESENT=str(steam)),
                                capture_output=True, text=True, timeout=5)
        menus = (root / 'menus').read_text()
        if name == 'ally-x':
            assert result.returncode == 1 and not menus, (name, result, menus)
        else:
            assert result.returncode == 0 and not result.stdout and not result.stderr, (name, result)
            assert f'Gaming companion {package_label}\t{fallback_label}' in menus and hint in menus, (name, menus)
            assert ('Gaming power limits' in menus) == bool(companion), (name, menus)
            assert 'local-only details' not in menus, (name, menus)
        if saved is None:
            assert not marker.exists()
        elif saved == 'symlink':
            assert marker.is_symlink()
            marker.unlink()
        else:
            assert marker.read_text() == saved
            marker.unlink()
        print('PASS recovery-' + name)

    cases = [
        ('setup-asus', script, 'ROG Ally RC71L', 1, 'asus', ['Ally Power Controls'], 'ASUS owns power', True),
        ('setup-ready', script, 'ROG Ally RC71L', 1, 'ready', ['CANCEL'], 'Quick Access → Performance → Advanced', False),
        ('setup-conflict', script, 'ROG Ally RC71L', 1, 'conflict', ['CANCEL'], 'Another power service', False),
        ('setup-check-failed', script, 'ROG Ally RC71L', 1, '', ['CANCEL'], 'Could not check', False),
        ('setup-laptop', script, 'ROG Strix G16', 1, 'asus', ['CANCEL'], '', False),
        ('setup-no-companion', script, 'ROG Ally RC71L', 0, 'asus', ['CANCEL'], '', False),
        ('recovery-asus', recovery, 'ROG Ally RC71L', 1, 'asus', ['Gaming power limits', 'Ally Power Controls'], 'ASUS owns power', True),
    ]
    for name, command, model, companion, power_status, choices, power_hint, handoff in cases:
        (root / 'product').write_text(model + '\n')
        (root / 'choices').write_text('\n'.join(choices) + '\n')
        (root / 'count').write_text('0\n')
        (root / 'menus').write_text('')
        (root / 'actions').write_text('')
        result = subprocess.run([str(command)], env=dict(env, COMPANION_PRESENT=str(companion), POWER_STATUS=power_status),
                                capture_output=True, text=True, timeout=5)
        assert result.returncode == 0 and not result.stdout and not result.stderr, (name, result)
        menus = (root / 'menus').read_text()
        if power_hint:
            assert power_hint in menus, (name, menus)
        else:
            assert 'Gaming power limits' not in menus and 'Ally Power Controls' not in menus, (name, menus)
        assert (root / 'actions').read_text() == ('summon setup.ally-power\n' if handoff else ''), name
        print('PASS', name)
