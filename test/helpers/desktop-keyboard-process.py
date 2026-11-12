#!/usr/bin/env python3
"""Exercise the real helper with a native signal sink, never wvkbd or Wayland.

Usage: python3 helper-process-test.py [path/to/omarchy-toggle-desktop-keyboard]
Requires Linux /proc, cc, Bash and flock. No packages, services or live session
are touched. This checks helper routing/identity/locking and the DMI gate
on keyboard setup. It does not check focus retention, held-key release or
overlay geometry.
"""
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
    else puts("--non-exclusive --wayland-layer");
    return 0;
  }
  if (getenv("FAIL_START")) return 42;
  fd = open(getenv("SIGNALS"), O_WRONLY|O_CREAT|O_APPEND, 0600);
  if (fd < 0) return 43;
  signal(SIGUSR1, handle); signal(SIGUSR2, handle);
  signal(SIGRTMIN, handle); signal(SIGTERM, handle);
  (void)write(fd, "B", 1);
  for (int i=1; i<argc; i++) { (void)write(fd, argv[i], strlen(argv[i])); (void)write(fd, "\n", 1); }
  (void)write(fd, "E", 1);
  for (;;) pause();
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
        print('[Haki] PASS DMI override: RC71L setup gate open; ROG laptop and generic laptop closed')


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
        for name in ('cat', 'readlink', 'mkdir', 'flock', 'nohup', 'sleep', 'rm'):
            tool = shutil.which(name)
            assert tool, f'Required system tool missing: {name}'
            (root / name).symlink_to(tool)
        present = Path(__file__).resolve().parents[2] / 'bin/omarchy-cmd-present'
        (root / 'omarchy-cmd-present').symlink_to(present)
        env = os.environ | {'PATH': str(root),
                            'XDG_RUNTIME_DIR': str(root), 'WAYLAND_DISPLAY': 'wayland-test',
                            'HYPRLAND_INSTANCE_SIGNATURE': 'hyprland-test',
                            'XDG_CURRENT_DESKTOP': 'Hyprland',
                            'SIGNALS': str(root / 'signals')}
        state = root / 'omarchy-desktop-keyboard-wayland-test'
        record = state / 'process'
        owned = set()

        def run(*args, ok=True, extra=None):
            result = subprocess.run(['/bin/bash', str(HELPER), *args], env=env | (extra or {}),
                                    capture_output=True, text=True, timeout=5)
            if record.exists():
                pid, stamp, executable = record.read_text().split()
                if executable == str(binary) and Path(f'/proc/{pid}').exists() and starttime(pid) == stamp:
                    owned.add(int(pid))
            assert (result.returncode == 0) == ok, (args, result.returncode, result.stderr)
            return result

        def events():
            return (root / 'signals').read_text()

        def wait_for(predicate):
            until = time.monotonic() + 2
            while time.monotonic() < until:
                if predicate():
                    return
                time.sleep(.01)
            raise AssertionError('Timed out waiting for fixture event')

        try:
            run('--help', extra={'WAYLAND_DISPLAY': '', 'XDG_RUNTIME_DIR': ''})
            run('invalid', ok=False)
            run('show', 'extra', ok=False)
            run('show', ok=False, extra={'WAYLAND_DISPLAY': ''})
            run('hide'); run('stop')
            assert not record.exists()
            print('[Haki] PASS help, invalid arguments, missing session, inactive hide/stop')

            # A dedicated Steam compositor must not acquire a desktop OSK.
            for action in ('show', 'toggle'):
                run(action, ok=False, extra={'HYPRLAND_INSTANCE_SIGNATURE': ''})
                run(action, ok=False, extra={'XDG_CURRENT_DESKTOP': 'Gamescope'})
                assert not record.exists() and not (root / 'signals').exists()
            print('[Haki] PASS non-Hyprland and Gamescope launches rejected before starting a process')

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
            run('show', ok=False, extra={'FAIL_START': '1'})
            assert not record.exists()
            binary.rename(root / 'disabled')
            result = run('show', ok=False)
            assert 'missing' in result.stderr
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
                time.sleep(.15)
                assert all(p.poll() is None for p in calls)
                assert events() == before and not record.exists()
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
