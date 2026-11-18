#!/usr/bin/env python3
"""Exercise the real helper with a native signal sink, never wvkbd or Wayland.

Usage: python3 helper-process-test.py [path/to/omarchy-toggle-desktop-keyboard]
Requires Linux /proc, cc, Bash and flock. No packages, services or live session
are touched. This checks helper routing/identity/locking and the DMI gate
on keyboard setup. It does not check focus retention, held-key release or
overlay geometry.
"""
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys
import tempfile
import time

HELPER = (Path(sys.argv[1]) if len(sys.argv) > 1 else
          Path(__file__).resolve().parents[1] / 'source/bin/omarchy-toggle-desktop-keyboard')

# The sink records signal receipt; it intentionally implements no keyboard logic.
FIXTURE = r'''
#include <signal.h>
#include <sys/signalfd.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
static int fd;
static void handle(int sig) {
  char c = sig == SIGUSR1 ? 'H' : sig == SIGUSR2 ? 'S' : sig == SIGTERM ? 'X' : 'T';
  (void)write(fd, &c, 1);
  if (sig == SIGTERM) _exit(0);
}
int main(int argc, char **argv) {
  if (argc > 1 && !strcmp(argv[1], "--help")) {
    if (getenv("OLD_OPTIONS")) puts("old build");
    else puts("--non-exclusive --wayland-layer --text-press-sp");
    if (getenv("OUTPUT_OPTION")) puts("--output CONNECTOR");
    return 0;
  }
  fd = open(getenv("SIGNALS"), O_WRONLY|O_CREAT|O_APPEND, 0600);
  if (fd < 0) return 43;
  // wvkbd completes its Wayland handshake before it starts reading signals.
  const char *gate = getenv("START_GATE");
  if (gate) {
    (void)write(fd, "W", 1);
    while (access(gate, F_OK) != 0) usleep(5000);
  }
  if (getenv("FAIL_START")) return 42;
  sigset_t commands;
  sigemptyset(&commands);
  sigaddset(&commands, SIGUSR1); sigaddset(&commands, SIGUSR2);
  sigaddset(&commands, SIGRTMIN); sigaddset(&commands, SIGTERM);
  (void)write(fd, "B", 1);
  for (int i=1; i<argc; i++) { (void)write(fd, argv[i], strlen(argv[i])); (void)write(fd, "\n", 1); }
  (void)write(fd, "E", 1);
  if (sigprocmask(SIG_BLOCK, &commands, NULL) < 0) return 44;
  int controls = signalfd(-1, &commands, SFD_CLOEXEC);
  if (controls < 0) return 45;
  for (;;) {
    struct signalfd_siginfo info;
    if (read(controls, &info, sizeof(info)) == sizeof(info)) handle(info.ssi_signo);
  }
}
'''


def starttime(pid):
    return Path(f'/proc/{pid}/stat').read_text().rsplit(') ', 1)[1].split()[19]


def hardware_acceptance():
    """RC71L passes the setup gate. A ROG laptop and a generic laptop do not."""
    repo = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix='haki-keyboard-dmi-') as temp:
        root = Path(temp)
        stub = root / 'bin'
        stub.mkdir()
        pacman = stub / 'pacman'
        pacman.write_text('#!/bin/bash\nexit 1\n')
        pacman.chmod(0o700)
        home = root / 'home'
        home.mkdir()
        cases = (
            ('ally', 'ASUSTeK COMPUTER INC.', 'ROG Ally', 'RC71L', True),
            ('rog-laptop', 'ASUSTeK COMPUTER INC.', 'ROG Zephyrus', 'GU604', False),
            ('generic', 'Dell Inc.', 'XPS 13', '0A1B', False),
            ('ally-x', 'ASUSTeK COMPUTER INC.', 'ROG Ally X RC72LA_RC72LA', 'RC72LA', False),
            ('xbox', 'ASUSTeK COMPUTER INC.', 'ROG Xbox Ally RC73YA', 'RC73YA', False),
            ('xbox-x', 'ASUSTeK COMPUTER INC.', 'ROG Xbox Ally X RC73XA', 'RC73XA', False),
        )
        base = os.environ | {
            'PATH': f'{stub}:{repo / "bin"}:/usr/bin:/bin',
            'OMARCHY_PATH': str(repo),
            'HOME': str(home),
        }
        for name, vendor, product, board, enabled in cases:
            dmi = root / name
            dmi.mkdir()
            (dmi / 'sys_vendor').write_text(vendor + '\n')
            (dmi / 'product_name').write_text(product + '\n')
            (dmi / 'board_name').write_text(board + '\n')
            env = base | {
                'OMARCHY_DMI_SYS_VENDOR_PATH': str(dmi / 'sys_vendor'),
                'OMARCHY_DMI_PRODUCT_NAME_PATH': str(dmi / 'product_name'),
                'OMARCHY_DMI_BOARD_NAME_PATH': str(dmi / 'board_name'),
            }
            detector = subprocess.run([str(repo / 'bin/omarchy-hw-rog-ally')], env=env)
            setup = subprocess.run(
                [str(repo / 'bin/omarchy-setup-rog-ally-keyboard'), '--configure-reviewed-package'],
                env=env, capture_output=True, text=True)
            combined = setup.stdout + setup.stderr
            assert 'Keyboard button' not in combined, (name, combined)
            if enabled:
                assert detector.returncode == 0, name
                assert setup.returncode != 0, (name, combined)
                assert 'Install the reviewed wvkbd' in setup.stderr, (name, setup.stderr)
            else:
                assert detector.returncode != 0, name
                assert 'This optional setup is for ASUS ROG Ally RC71L.' in setup.stderr, (name, setup.stderr)
        missing = root / 'missing-dmi'
        env = base | {
            'OMARCHY_DMI_SYS_VENDOR_PATH': str(missing / 'sys_vendor'),
            'OMARCHY_DMI_PRODUCT_NAME_PATH': str(missing / 'product_name'),
            'OMARCHY_DMI_BOARD_NAME_PATH': str(missing / 'board_name'),
        }
        detector = subprocess.run([str(repo / 'bin/omarchy-hw-rog-ally')], env=env)
        setup = subprocess.run(
            [str(repo / 'bin/omarchy-setup-rog-ally-keyboard'), '--configure-reviewed-package'],
            env=env, capture_output=True, text=True)
        assert detector.returncode != 0
        assert 'This optional setup is for ASUS ROG Ally RC71L.' in setup.stderr
        assert 'Keyboard button' not in setup.stdout + setup.stderr
        print('[Haki] PASS DMI override: RC71L setup gate open; Ally X, Xbox Ally, laptops and missing DMI closed')

        pacman.write_text('#!/bin/bash\nprintf "wvkbd %s\\n" "$REVIEW_PACKAGE"\n')
        keyboard = stub / 'wvkbd-mobintl'
        keyboard.write_text('#!/bin/bash\necho "--non-exclusive --wayland-layer ${OUTPUT_OPTION:-}"\n')
        keyboard.chmod(0o700)
        ally = root / 'ally'
        env = base | {
            'OMARCHY_DMI_SYS_VENDOR_PATH': str(ally / 'sys_vendor'),
            'OMARCHY_DMI_PRODUCT_NAME_PATH': str(ally / 'product_name'),
            'OMARCHY_DMI_BOARD_NAME_PATH': str(ally / 'board_name'),
            'XDG_DATA_HOME': str(root / 'data'),
            'WAYLAND_DISPLAY': '',
        }
        for version, flags, accepted in (
            ('0.21-1', '', True),
            ('0.21-1.1', '--output CONNECTOR', True),
            ('0.21-1.1', '', False),
            ('0.21-2', '--output CONNECTOR', False),
        ):
            setup = subprocess.run(
                [str(repo / 'bin/omarchy-setup-rog-ally-keyboard'), '--configure-reviewed-package'],
                env=env | {'REVIEW_PACKAGE': version, 'OUTPUT_OPTION': flags},
                capture_output=True, text=True)
            assert (setup.returncode == 0) == accepted, (version, flags, setup.stderr)
        print('[Haki] PASS setup accepts only the reviewed stock and dock-capable builds')

def main():
    assert HELPER.is_file(), f'Helper missing: {HELPER}'
    hardware_acceptance()
    with tempfile.TemporaryDirectory(prefix='haki-keyboard-test-') as temp:
        root = Path(temp)
        source = root / 'sink.c'
        source.write_text(FIXTURE)
        binary = root / 'wvkbd-mobintl'
        subprocess.run(['cc', '-Wall', '-Wextra', str(source), '-o', str(binary)], check=True)
        # Only the fixture keyboard and the helper's real system dependencies
        # are visible. Appending the host PATH lets a genuinely installed
        # wvkbd escape the missing-dependency case when ours is renamed.
        for name in ('awk', 'cat', 'dirname', 'env', 'readlink', 'mkdir', 'flock', 'nohup', 'sleep', 'rm', 'jq', 'sort'):
            tool = shutil.which(name)
            assert tool, f'Required system tool missing: {name}'
            (root / name).symlink_to(tool)
        repo = Path(__file__).resolve().parents[2]
        (root / 'omarchy-cmd-present').symlink_to(repo / 'bin/omarchy-cmd-present')
        (root / 'omarchy-i18n').symlink_to(repo / 'bin/omarchy-i18n')
        (root / 'omarchy-theme-color').symlink_to(repo / 'bin/omarchy-theme-color')
        notify = root / 'notify'
        notifier = root / 'omarchy-notification-send'
        notifier.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >"$NOTIFY_LOG"\n')
        notifier.chmod(0o755)
        locked = root / 'omarchy-hyprland-session-locked'
        locked.symlink_to(repo / 'bin/omarchy-hyprland-session-locked')
        shell = root / 'omarchy-shell'
        shell.write_text('#!/bin/bash\nprintf "%s\\n" "${SHELL_LOCK:-false}"\n')
        shell.chmod(0o700)
        hyprctl = root / 'hyprctl'
        hyprctl.write_text("""#!/bin/bash
if [[ -n $EDGE_IPC && $1 == "--batch" ]]; then
  IFS=';' read -ra requests <<<"$2"
  for request in "${requests[@]}"; do
    cat "$EDGE_IPC/${request#j/}" || exit 1
    echo
  done
  exit 0
fi
if [[ -n $EDGE_IPC && -f $EDGE_IPC/$2 ]]; then
  exec cat "$EDGE_IPC/$2"
fi
case $2 in
  monitors) printf '[{"solitaryBlockedBy":["%s"]}]\\n' "${MONITOR_BLOCKER:-CANDIDATE}" ;;
  layers) printf '{"eDP-1":{"levels":{"3":[{"namespace":"omarchy-menu"},{"namespace":"%s"}]}}}\\n' "${LAYER:-omarchy-notifications}" ;;
esac
""")
        hyprctl.chmod(0o700)
        env = os.environ | {'PATH': str(root), 'NOTIFY_LOG': str(notify),
                            'HOME': str(root / 'home'),
                            'OMARCHY_PATH': str(repo),
                            'XDG_RUNTIME_DIR': str(root), 'WAYLAND_DISPLAY': 'wayland-test',
                            'HYPRLAND_INSTANCE_SIGNATURE': 'hyprland-test',
                            'XDG_CURRENT_DESKTOP': 'Hyprland',
                            'SIGNALS': str(root / 'signals')}
        state = root / 'omarchy-desktop-keyboard-wayland-test'
        record = state / 'process'
        owned = set()

        def track_keyboard():
            if record.exists():
                pid, stamp, executable = record.read_text().split()
                try:
                    if executable == str(binary) and starttime(pid) == stamp:
                        owned.add(int(pid))
                except FileNotFoundError:
                    pass

        def run(*args, ok=True, extra=None, timeout=5):
            result = subprocess.run(['/bin/bash', str(HELPER), *args], env=env | (extra or {}),
                                    capture_output=True, text=True, timeout=timeout)
            track_keyboard()
            assert (result.returncode == 0) == ok, (args, result.returncode, result.stderr)
            return result

        def events():
            return (root / 'signals').read_text()

        def wait_for(predicate, seconds=5):
            until = time.monotonic() + seconds
            while time.monotonic() < until:
                if predicate():
                    return
                time.sleep(.01)
            raise AssertionError('Timed out waiting for fixture event')

        def assert_pending(call):
            try:
                call.wait(timeout=.25)
            except subprocess.TimeoutExpired:
                return
            raise AssertionError(f'Command returned early with status {call.returncode}')

        def finish(call, ok=True):
            out, err = call.communicate(timeout=5)
            assert (call.returncode == 0) == ok, (call.args, call.returncode, out, err)

        def start_with_gate(tag, fail=False):
            gate = root / f'{tag}-release'
            receipt = root / f'{tag}-signals'
            receipt.touch()
            options = {'START_GATE': str(gate), 'SIGNALS': str(receipt)}
            if fail:
                options['FAIL_START'] = '1'
            # A pre-blocked caller must not fulfil the keyboard's readiness check.
            call = subprocess.Popen(['/usr/bin/env', '--block-signal=USR1,USR2,RTMIN',
                                     '/bin/bash', str(HELPER), 'show'], env=env | options,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                wait_for(lambda: receipt.read_text() == 'W')
                assert_pending(call)
                assert not record.exists()
            finally:
                gate.touch()
                track_keyboard()
            finish(call, ok=not fail)
            track_keyboard()
            return receipt

        try:
            run('--help', extra={'WAYLAND_DISPLAY': '', 'XDG_RUNTIME_DIR': ''})
            run('invalid', ok=False)
            run('show', 'extra', ok=False)
            run('show', ok=False, extra={'WAYLAND_DISPLAY': ''})
            run('hide'); run('stop')
            assert not record.exists()
            print('[Haki] PASS help, invalid arguments, missing session, inactive hide/stop')

            # A dedicated Steam compositor must not acquire a desktop OSK.
            for action in ('show', 'toggle', 'show-for-menu', 'show-for-edge'):
                run(action, ok=False, extra={'HYPRLAND_INSTANCE_SIGNATURE': ''})
                run(action, ok=False, extra={'XDG_CURRENT_DESKTOP': 'Gamescope'})
                assert not record.exists() and not (root / 'signals').exists()
            print('[Haki] PASS non-Hyprland and Gamescope launches rejected before starting a process')

            for guard in ({'SHELL_LOCK': 'true'}, {'SHELL_LOCK': 'unknown'},
                          {'MONITOR_BLOCKER': 'LOCK'}, {'MONITOR_BLOCKER': 'WORKSPACE'},
                          {'LAYER': 'omarchy-polkit'}, {'LAYER': 'wvkbd'}):
                run('show-for-menu', extra=guard)
                assert not record.exists(), guard

            run('show-for-menu')
            wait_for(lambda: events().endswith('E'))
            run('hide-for-menu')
            wait_for(lambda: events().endswith('EH'))
            run('show-for-menu')
            wait_for(lambda: events().endswith('EHS'))
            run('show')
            wait_for(lambda: events().endswith('EHSS'))
            before = events()
            run('hide-for-menu')
            run('show-for-menu')
            assert events() == before
            run('stop')
            wait_for(lambda: events().endswith('EHSSHX'))
            print('[Haki] PASS menu cleanup hides its own keyboard, preserves manual show and skips lock and polkit')

            # Only the compositor can distinguish a sole internal touch device
            # from two devices routed to the same Wayland seat.
            (root / 'omarchy-hw-rog-ally').symlink_to(repo / 'bin/omarchy-hw-rog-ally')
            (root / 'vendor').write_text('ASUSTeK COMPUTER INC.')
            (root / 'board').write_text('RC71L')
            monitor = dict(name='eDP-1', transform=0, focused=True, dpmsStatus=True, solitaryBlockedBy=['WINDOWED'])
            device = dict(name='nvtk0603:00-0603:f200')
            levels = {'1': [{'namespace': 'omarchy-keyboard-edge'}], '2': [], '3': []}
            ipc = dict(monitors=[monitor], devices={'touch': [device]}, layers={'eDP-1': {'levels': levels}},
                       activewindow={'mapped': True, 'class': 'foot', 'initialClass': 'foot'})
            edge = {'EDGE_IPC': str(root), 'OMARCHY_DMI_SYS_VENDOR_PATH': str(root / 'vendor'),
                    'OMARCHY_DMI_BOARD_NAME_PATH': str(root / 'board'),
                    'OMARCHY_DMI_PRODUCT_NAME_PATH': str(root / 'missing-product')}
            for query, response in ipc.items():
                (root / query).write_text(json.dumps(response))
            for query, response in (
                ('devices', {'touch': [device, dict(name='usb-touchscreen')]}),
                ('devices', {'touch': [dict(name='usb-touchscreen')]}),
                ('monitors', [monitor, monitor | {'name': 'HDMI-A-1'}]),
                ('monitors', [monitor | {'solitaryBlockedBy': ['WINDOWED', 'LOCK']}]),
                ('monitors', [monitor | {'solitaryBlockedBy': None}]),
                ('activewindow', {}),
                ('activewindow', ipc['activewindow'] | {'initialClass': 'gamescope'}),
                ('layers', {'eDP-1': {'levels': levels | {'3': [{'namespace': 'omarchy-polkit'}]}}}),
            ):
                (root / query).write_text(json.dumps(response))
                run('show-for-edge', extra=edge)
                assert not record.exists(), (query, response)
                (root / query).write_text(json.dumps(ipc[query]))
            run('show-for-edge', extra=edge | {'SHELL_LOCK': 'unknown'})
            assert not record.exists()
            run('show-for-edge', '2', extra=edge)
            assert not record.exists(), 'A half-turn since the stroke started must cancel it'
            run('show-for-edge', '0', extra=edge)
            assert record.exists() and (state / 'visibility').read_text().strip() == 'manual'
            run('hide-for-menu')
            assert (state / 'visibility').read_text().strip() == 'manual'
            run('stop')
            print('PASS edge summon requires a known desktop and one internal panel and touch device')

            external = monitor | {'name': 'DP-1'}
            docked = [monitor | {'focused': False}, external]
            pinned = edge | {'OUTPUT_OPTION': '1'}
            run('show', extra=edge)
            pid = int(record.read_text().split()[0])
            assert b'--output' not in Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
            (root / 'monitors').write_text(json.dumps(docked))
            run('check-output', extra=edge)
            assert not record.exists()
            run('show', ok=False, extra=edge)
            run('toggle', ok=False, extra=edge)
            assert not record.exists()
            run('show', extra=pinned)
            panel_record = record.read_text()
            pid = int(panel_record.split()[0])
            argv = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
            assert argv[argv.index(b'--output') + 1] == b'eDP-1', argv
            run('check-output', extra=pinned)
            assert record.read_text() == panel_record
            (root / 'monitors').write_text(json.dumps([external]))
            run('check-output', extra=pinned)
            run('show', ok=False, extra=pinned)
            assert not record.exists()
            (root / 'monitors').write_text(json.dumps(docked))
            menu = levels | {'3': [{'namespace': 'omarchy-menu'}]}
            (root / 'layers').write_text(json.dumps({'DP-1': {'levels': menu}}))
            run('show-for-menu', extra=pinned)
            assert not record.exists()
            (root / 'layers').write_text(json.dumps({'eDP-1': {'levels': menu}}))
            run('show-for-menu', extra=pinned)
            assert (state / 'visibility').read_text().strip() == 'menu'
            run('stop')
            print('PASS stock and pinned display selection, dock teardown and menu ownership')

            failed = start_with_gate('failed', fail=True)
            assert not record.exists() and failed.read_text() == 'W'
            receipt = start_with_gate('ready')
            saved = record.read_text()
            ready_pid = int(saved.split()[0])
            wait_for(lambda: receipt.read_text().endswith('E'))
            print('PASS an incomplete handshake cannot publish startup success, and a delayed one can finish')

            # Linux can deliver USR1 (hide) before an older, pending USR2
            # (show). Pause this ready receiver across both requests.
            os.kill(ready_pid, signal.SIGSTOP)
            try:
                run('show')
                hide = subprocess.Popen(['/bin/bash', str(HELPER), 'hide'], env=env,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                assert_pending(hide)
            finally:
                os.kill(ready_pid, signal.SIGCONT)
            finish(hide)
            assert record.read_text() == saved
            wait_for(lambda: receipt.read_text().endswith('ESH'))
            run('stop')
            wait_for(lambda: receipt.read_text().endswith('ESHHX'))
            print('PASS show then hide while a ready keyboard stalls reach it in order')

            for _ in range(3):
                run('show')
                saved = record.read_text()
                assert events().endswith('E')
                pid = int(saved.split()[0])
                # Real argv observed by the native child, not source-text assertions.
                argv = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')[1:-1]
                assert argv == [b'-H', b'264', b'-L', b'264', b'--non-exclusive',
                                b'--wayland-layer', b'overlay', b'-l', b'full,special',
                                b'--landscape-layers', b'full,special', b'--no-popup'], argv
                suffix = ''
                for action, expected in [('show', 'S'), ('show', 'S'), ('toggle', 'T'),
                                         ('hide', 'H'), ('hide', 'H'), ('show', 'S')]:
                    run(action)
                    suffix += expected
                    wait_for(lambda: events().endswith('E' + suffix))
                    assert record.read_text() == saved
                run('stop')
                wait_for(lambda: events().endswith('E' + suffix + 'HX'))
                assert not record.exists()
            print('[Haki] PASS three cycles: real argv, repeated show/hide, toggle signals, hide-before-TERM stop')

            theme = root / 'home/.local/state/omarchy/current/theme'
            theme.mkdir(parents=True)
            colors = theme / 'colors.toml'
            colors.write_text('background = "#05182e"\nforeground = "#f6dcac"\naccent = "#faa968"\n')
            run('show')
            pid = int(record.read_text().split()[0])
            argv = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')[1:-1]
            assert argv[argv.index(b'--bg') + 1] == b'05182e', argv
            assert argv[argv.index(b'--fg') + 1] != argv[argv.index(b'--fg-sp') + 1], argv
            assert argv[argv.index(b'--text') + 1] == b'f6dcac', argv
            assert argv[argv.index(b'--press') + 1] == b'faa968', argv
            assert argv[argv.index(b'--text-press') + 1] == b'05182e', argv
            run('stop')
            run('show-for-menu')
            pid = int(record.read_text().split()[0])
            menu_argv = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')[1:-1]
            assert menu_argv == argv, (argv, menu_argv)
            run('stop')
            # This palette has a legible foreground, but blending it into
            # the modifier key at full strength makes its label less legible.
            colors.write_text('background = "#2d353b"\nforeground = "#d3c6aa"\naccent = "#7fbbb3"\n')
            run('show')
            pid = int(record.read_text().split()[0])
            flags = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
            def luminance(flag):
                colour = bytes.fromhex(flags[flags.index(flag) + 1].decode())
                values = [v / 255 for v in colour]
                linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in values]
                return sum(x * y for x, y in zip(linear, (0.2126, 0.7152, 0.0722)))
            dark, light = sorted((luminance(b'--fg-sp'), luminance(b'--text-sp')))
            assert (light + 0.05) / (dark + 0.05) >= 4.5, flags
            run('stop')
            colors.write_text('background = "05182e"\nforeground = "#f6dcac"\n')
            run('show')
            pid = int(record.read_text().split()[0])
            assert b'--bg' not in Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0'), argv
            run('stop')
            colors.unlink()
            print('[Haki] PASS active theme styles the keyboard and an invalid palette keeps stock defaults')

            # A package upgrade unlinks the running executable inode. Keep ownership.
            run('show')
            saved = record.read_text()
            replacement = root / 'new-keyboard'
            shutil.copy2(binary, replacement)
            os.replace(replacement, binary)
            assert os.readlink(f'/proc/{saved.split()[0]}/exe').endswith(' (deleted)')
            before = events()
            run('hide'); run('show')
            assert record.read_text() == saved
            wait_for(lambda: events().endswith('HS'))
            assert events()[len(before):].count('B') == 0
            run('stop')
            wait_for(lambda: events().endswith('HX'))
            assert not record.exists()
            print('[Haki] PASS executable replacement preserves hide/show/stop ownership')

            # The real executable with a wrong birth time must not be signalled.
            run('show')
            saved = record.read_text()
            pid, stamp, executable = saved.split()
            before = events()
            record.write_text(f'{pid} {int(stamp)+1} {executable}\n')
            run('stop')
            assert events() == before and Path(f'/proc/{pid}').exists()
            record.write_text(saved)
            run('stop')
            # A live unrelated executable must survive even with a matching birth time.
            other = subprocess.Popen(['/bin/sleep', '20'])
            try:
                record.write_text(f'{other.pid} {starttime(other.pid)} {binary}\n')
                run('stop')
                assert other.poll() is None and not record.exists()
            finally:
                other.terminate(); other.wait(timeout=2)
            record.write_text('not-a-pid 0 missing\n'); run('hide')
            assert not record.exists()
            print('[Haki] PASS stale birth time, unrelated executable and malformed PID isolation')

            run('show', ok=False, extra={'OLD_OPTIONS': '1'})
            assert not record.exists()
            # A keyboard which has already exited must release the command lock
            # before the two-second startup budget for a living child elapses.
            run('show', ok=False, extra={'FAIL_START': '1'}, timeout=1.8)
            assert not record.exists()
            binary.rename(root / 'disabled')
            result = run('show', ok=False)
            assert 'missing' in result.stderr
            assert 'wvkbd-mobintl is missing' in notify.read_text()
            (root / 'disabled').rename(binary)
            print('[Haki] PASS obsolete options, failed startup and missing dependency')

            # Hold the actual flock: no helper may start or signal through it.
            lock = subprocess.Popen(['/usr/bin/flock', '-x', str(state / 'lock'),
                                     '/bin/sh', '-c', 'echo ready; read line'],
                                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
            assert lock.stdout.readline().strip() == 'ready'
            before = events()
            calls = [subprocess.Popen(['/bin/bash', str(HELPER), 'show'], env=env,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(6)]
            try:
                until = time.monotonic() + 0.5
                while time.monotonic() < until:
                    assert all(p.poll() is None for p in calls)
                    assert events() == before and not record.exists()
                    time.sleep(0.01)
                lock.communicate('release\n', timeout=2)
                for call in calls:
                    out, err = call.communicate(timeout=5)
                    assert call.returncode == 0, (out, err)
                owned.add(int(record.read_text().split()[0]))
                assert events()[len(before):].count('B') == 1
                # Standard signals may coalesce: process identity/count is the invariant.
                run('stop')
            finally:
                for call in calls:
                    if call.poll() is None:
                        call.kill(); call.wait()
                if lock.poll() is None:
                    lock.kill(); lock.wait()
            print('[Haki] PASS lock blocks work; six simultaneous shows create one process')
        finally:
            # Only terminate fixture PIDs recorded by this private test runtime.
            for pid in owned:
                try:
                    if os.readlink(f'/proc/{pid}/exe') == str(binary):
                        os.kill(pid, signal.SIGTERM)
                except (FileNotFoundError, ProcessLookupError):
                    pass
    print('[Haki] LIMIT: fixture tests helper process safety and the DMI setup gate; focus retention and overlay geometry UNTESTED')


if __name__ == '__main__':
    main()
