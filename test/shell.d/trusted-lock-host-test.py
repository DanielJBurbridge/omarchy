"""Focused ownership/control regressions; no system service or real password."""
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import socket
import shutil
import subprocess
import time
import tempfile
import threading
import unittest
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("lock_control", ROOT / "default/lock-host/control.py")
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)


class HostControlTests(unittest.TestCase):
  def setUp(self):
    self.temp = tempfile.TemporaryDirectory()
    self.runtime = Path(self.temp.name)
    self.home = self.runtime / "home"
    self.home.mkdir()
    self.env = patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(self.runtime), "HYPRLAND_INSTANCE_SIGNATURE": "fixture", "HOME": str(self.home), "OMARCHY_PATH": str(ROOT)})
    self.env.start()

  def tearDown(self):
    self.env.stop()
    self.temp.cleanup()

  def test_status_cannot_select_or_start_an_owner(self):
    with self.assertRaises(FileNotFoundError):
      control.mode()
    with patch.object(control.subprocess, "run") as process:
      with self.assertRaises(FileNotFoundError):
        control.request("status")
      process.assert_not_called()
    self.assertFalse(control.session_path("mode").exists())

  def test_future_preference_does_not_change_latched_owner_on_restart(self):
    self.assertEqual(control.mode(initialize=True), "shell")
    control.preference().parent.mkdir(parents=True)
    control.preference().touch()
    self.assertEqual(control.mode(initialize=True), "shell")
    with patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "next-session"}):
      self.assertEqual(control.mode(initialize=True), "host")
    control.preference().unlink()
    with patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "next-session"}):
      self.assertEqual(control.mode(initialize=True), "host")
      with patch.object(control.os, "execvpe") as execute:
        control.run("host", ["quickshell", "-p", str(ROOT / "shell/lock-host.qml")])
        execute.assert_called_once()  # Staged opt-out cannot defeat crash recovery.

  def test_host_never_runs_under_the_shell_owner(self):
    control.mode(initialize=True)
    with patch.object(control.os, "execvpe") as execute:
      self.assertEqual(control.run("host", ["unreachable"]), 0)
      execute.assert_not_called()

  def test_setup_stages_only_after_unlocked_ready_and_packaged_unit_checks(self):
    control.mode(initialize=True)
    state = dict(owner="trusted-host", ready=False, locked=False, requested=False, secure=False)
    fragment = "/usr/lib/systemd/user/omarchy-lock-host.service"
    overrides = ""
    def respond(args, **kwargs):
      value = ""
      code = 0
      if args[-2:] == ["lock", "status"]:
        value = json.dumps(state)
      elif args[0].endswith("omarchy-hyprland-session-locked"):
        code = 1
      elif "--property=FragmentPath" in args:
        value = fragment
      elif "--property=DropInPaths" in args:
        value = overrides
      return SimpleNamespace(returncode=code, stdout=value)
    with patch.object(control.subprocess, "run", side_effect=respond) as commands:
      with self.assertRaises(ValueError):
        control.setup("enable")
      state["ready"] = True
      fragment = str(self.home / "custom.service")
      with self.assertRaises(ValueError):
        control.setup("enable")
      fragment = "/usr/lib/systemd/user/omarchy-lock-host.service"
      overrides = str(self.home / "override.conf")
      with self.assertRaises(ValueError):
        control.setup("enable")
      overrides = ""
      control.setup("enable")
      self.assertTrue(control.preference().is_file())
      self.assertEqual(control.mode(), "shell")
      self.assertNotIn("--now", [arg for call in commands.call_args_list for arg in call.args[0]])

  def test_broker_preserves_exact_caller_ime(self):
    control.preference().parent.mkdir(parents=True)
    control.preference().touch()
    for values in ({}, {"QT_IM_MODULE": "", "QT_IM_MODULES": "", "QT_VIRTUALKEYBOARD_DESKTOP_DISABLE": ""},
                   {"QT_IM_MODULE": "fcitx", "QT_IM_MODULES": "qtvirtualkeyboard", "QT_VIRTUALKEYBOARD_DESKTOP_DISABLE": "0"}):
      env = {k: v for k, v in os.environ.items() if k not in ("QT_IM_MODULE", "QT_IM_MODULES", "QT_VIRTUALKEYBOARD_DESKTOP_DISABLE")}
      env.update(values)
      with patch.dict(os.environ, env, clear=True), patch.object(control.os, "execvpe") as execute:
        control.run("shell", ["quickshell", "-p", str(ROOT / "shell")])
        passed = execute.call_args.args[2]
        self.assertEqual({k: passed[k] for k in values}, values)
        for key in ("QT_IM_MODULE", "QT_IM_MODULES", "QT_VIRTUALKEYBOARD_DESKTOP_DISABLE"):
          self.assertEqual(key in passed, key in values)
        self.assertEqual(passed["OMARCHY_LOCK_HOST"], "1")

  def test_owner_lease_rejects_a_second_actual_owner(self):
    control.mode(initialize=True)
    with control.session_path("owner.lock").open("a+") as first:
      fcntl.flock(first, fcntl.LOCK_EX | fcntl.LOCK_NB)
      with patch.object(control.os, "execvpe") as execute:
        with self.assertRaises(BlockingIOError):
          control.run("shell", ["never-launched"])
        execute.assert_not_called()

  def test_host_rejects_user_keyboard_qml_and_interpreter_overrides(self):
    control.preference().parent.mkdir(parents=True)
    control.preference().touch()
    values = {"QT_IM_MODULES": "fcitx", "QML_IMPORT_PATH": "/untrusted/qml", "LD_PRELOAD": "/untrusted/native.so",
              "QT_VIRTUALKEYBOARD_STYLE": "/untrusted/style", "QT_VIRTUALKEYBOARD_LAYOUT_PATH": "/untrusted/layouts",
              "BASH_ENV": "/untrusted/startup", "BASH_FUNC_exec%%": "() { unsafe; }", "PYTHONPATH": "/untrusted/python",
              "QT_QPA_GENERIC_PLUGINS": "/untrusted/plugin", "LD_AUDIT": "/untrusted/audit.so"}
    with patch.dict(os.environ, values), patch.object(control.os, "execvpe") as execute:
      control.run("host", ["quickshell", "-p", str(ROOT / "shell/lock-host.qml")])
      passed = execute.call_args.args[2]
      self.assertEqual(passed["QT_IM_MODULES"], "qtvirtualkeyboard")
      self.assertEqual(passed["QT_VIRTUALKEYBOARD_DESKTOP_DISABLE"], "1")
      self.assertEqual(passed["QT_QPA_PLATFORM"], "wayland")
      for key in values:
        if key != "QT_IM_MODULES":
          self.assertNotIn(key, passed)

  def test_protected_entrypoints_reject_ordinary_bash_decoy_argument(self):
    for name in ("omarchy-lock-host", "omarchy-launch-lock-host"):
      result = subprocess.run(["/bin/bash", str(ROOT / "bin" / name), "--", "-p"], capture_output=True, text=True)
      self.assertNotEqual(result.returncode, 0)
      self.assertIn("requires privileged Bash startup", result.stderr)

  def test_strict_schema_and_no_password_unlock_or_eval(self):
    for key in ("ready", "locked", "requested", "secure"):
      state = dict(protocol=1, ready=True, locked=False, requested=False, secure=False, owner="trusted-host")
      state[key] = "false"
      with self.assertRaises(ValueError):
        control.validate_status(state)
    for method in ("password", "unlock", "eval", "submitPassword", "preview"):
      with self.assertRaises(ValueError):
        control.request(method)
    state = dict(protocol=1, ready=True, locked=False, requested=False, secure=False, owner="trusted-host", password="must-not-cross")
    self.assertNotIn("password", control.validate_status(state))

  def test_actual_unix_peer_uid_pid_and_unit_are_checked(self):
    with socket.socket(socket.AF_UNIX) as server:
      path = str(self.runtime / "peer.sock")
      try:
        server.bind(path)
      except PermissionError:
        self.skipTest("AF_UNIX unavailable in this sandbox")
      server.listen()
      with socket.socket(socket.AF_UNIX) as client:
        client.connect(path)
        connection, _ = server.accept()
        with connection, patch.object(control, "role_pid", return_value=os.getpid()), patch.object(control, "unit_pid", return_value=os.getpid()):
          control.checked_peer(client)
          with patch.object(control, "unit_pid", return_value=os.getpid() + 1):
            with self.assertRaises(ValueError):
              control.checked_peer(client)

  def test_orphan_recovery_exempts_only_validated_broker(self):
    def result(*args, **kwargs):
      class Result:
        returncode = 0
        stdout = self.lockers
      return Result()
    own, broker = 111, 222
    self.lockers = "111\n222\n"
    with patch.object(control.subprocess, "run", side_effect=result), patch.object(control, "mode", return_value="host"), \
         patch.object(control, "unit_pid", return_value=own), patch.object(control, "role_pid", side_effect=lambda role: own if role == "host" else broker):
      self.assertEqual(control.stranded(own), 0)  # normal broker + recovered host
      self.lockers += "333\n"
      self.assertEqual(control.stranded(own), 2)  # real/unknown competing locker
      self.lockers = "111\n222\n"
      with patch.object(control, "unit_pid", return_value=999):
        self.assertEqual(control.stranded(own), 2)
      with patch.object(control, "role_pid", side_effect=ValueError("stale PID start time")):
        self.assertEqual(control.stranded(own), 2)
    with patch.object(control.subprocess, "run", side_effect=OSError("probe failed")):
      self.assertEqual(control.stranded(own), 2)


class HostProcessTests(unittest.TestCase):
  def test_owner_lease_survives_real_quickshell_exec(self):
    if not shutil.which("quickshell"):
      self.skipTest("Quickshell is unavailable")
    with tempfile.TemporaryDirectory(prefix="omarchy-lock-lease-test.") as work:
      base = Path(work)
      (base / "shell").mkdir()
      (base / "default/lock-host").mkdir(parents=True)
      shutil.copy(ROOT / "default/lock-host/control.py", base / "default/lock-host")
      (base / "runtime").mkdir(mode=0o700)
      (base / "shell/shell.qml").write_text('import QtQuick\nimport Quickshell\nShellRoot { Component.onCompleted: console.log("OWNER_EXEC_READY") }\n')
      env = dict(os.environ, OMARCHY_PATH=str(base), HOME=str(base), XDG_RUNTIME_DIR=str(base / "runtime"),
                 HYPRLAND_INSTANCE_SIGNATURE="lease", QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="")
      with (base / "owner.log").open("w") as output:
        owner = subprocess.Popen([str(ROOT / "bin/omarchy-lock-host"), "run-shell"], env=env, stdout=output, stderr=subprocess.STDOUT)
      try:
        for _ in range(50):
          if "OWNER_EXEC_READY" in (base / "owner.log").read_text():
            break
          if owner.poll() is not None:
            self.fail((base / "owner.log").read_text())
          time.sleep(0.1)
        else:
          self.fail((base / "owner.log").read_text())
        with (base / "runtime/omarchy-lock-owner.lock-lease").open("a+") as lease:
          with self.assertRaises(BlockingIOError):
            fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
          second = subprocess.run([str(ROOT / "bin/omarchy-lock-host"), "run-shell"], env=env, capture_output=True, timeout=3)
          self.assertNotEqual(second.returncode, 0)
          owner.terminate()  # This fixture has no lock service or compositor.
          owner.wait(timeout=5)
          fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
      finally:
        if owner.poll() is None:
          owner.terminate()
          owner.wait(timeout=5)

  def test_trusted_keyboard_pam_isolation_broker_restart_and_stream_death(self):
    if not shutil.which("quickshell"):
      self.skipTest("Quickshell is unavailable")
    with tempfile.TemporaryDirectory(prefix="omarchy-lock-host-test.") as work:
      base = Path(work)
      for folder in ("shell", "bin", "default/lock-host", "runtime", "home", "pam"):
        (base / folder).mkdir(parents=True)
      (base / "runtime").chmod(0o700)
      try:
        with socket.socket(socket.AF_UNIX) as probe:
          probe.bind(str(base / "runtime/probe"))
      except PermissionError:
        self.skipTest("AF_UNIX unavailable in this sandbox")
      fixtures = ROOT / "test/shell.d/fixtures/trusted-lock-host"
      shutil.copy(fixtures / "shell.qml", base / "shell/lock-host.qml")
      shutil.copy(fixtures / "main.qml", base / "shell/shell.qml")
      shutil.copy(fixtures / "Unrelated.qml", base / "shell/Unrelated.qml")
      for module in ("Commons", "Ui"):
        (base / "shell" / module).symlink_to(ROOT / "shell" / module)
      (base / "default/i18n").symlink_to(ROOT / "default/i18n")
      shutil.copy(ROOT / "bin/omarchy-lock-host", base / "bin")
      shutil.copy(ROOT / "default/lock-host/control.py", base / "default/lock-host")
      for name in ("omarchy-system-wake", "omarchy-brightness-display", "omarchy-brightness-keyboard"):
        target = base / "bin" / name
        target.write_text("#!/bin/bash\nexit 0\n")
        target.chmod(0o755)
      target = base / "bin/fprintd-list"
      target.write_text("#!/bin/bash\necho no\n")
      target.chmod(0o755)
      # Only systemd's MainPID lookup is mocked in the direct client calls;
      # native peer credentials, /proc identity, Qt sockets and PAM are real.
      # The separate main broker calls the real provider and stays failclosed
      # because this disposable host is not an installed systemd service.
      (base / "pam/deny").write_text("auth required pam_deny.so\naccount required pam_permit.so\n")
      (base / "pam/permit").write_text("auth required pam_permit.so\naccount required pam_permit.so\n")
      env = dict(os.environ, HOME=str(base / "home"), XDG_RUNTIME_DIR=str(base / "runtime"),
                 HYPRLAND_INSTANCE_SIGNATURE="pair-fixture", OMARCHY_PATH=str(base),
                 OMARCHY_AUTH_SOURCE_ROOT=str(ROOT), OMARCHY_AUTH_PAM_DIR=str(base / "pam"),
                 OMARCHY_AUTH_RELEASE_FILE=str(base / "release"), OMARCHY_AUTH_UNIT_PID_FILE=str(base / "unit-pid"),
                 OMARCHY_AUTH_START_FILE=str(base / "start"),
                 QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", QT_QUICK_BACKEND="software",
                 QT_IM_MODULE="qtvirtualkeyboard", QT_IM_MODULES="qtvirtualkeyboard", QT_VIRTUALKEYBOARD_DESKTOP_DISABLE="1",
                 PATH=str(base / "bin") + ":" + str(ROOT / "bin") + ":" + os.environ["PATH"])
      (base / "runtime/omarchy-lock-mode-pair-fixture").write_text("host\n")
      host_log = base / "host.log"
      def launch_host():
        stream = host_log.open("w")
        process = subprocess.Popen(["quickshell", "-n", "-p", str(base / "shell/lock-host.qml"), "--no-color"], env=env, stdout=stream, stderr=subprocess.STDOUT)
        stream.close()
        (base / "unit-pid").write_text(str(process.pid))
        role = dict(protocol=1, pid=process.pid, start=control.start_time(process.pid), role="host", instance="pair-fixture", root=str(base))
        (base / "runtime/omarchy-lock-host.json-pair-fixture").write_text(json.dumps(role))
        return process
      def await_log(marker):
        for _ in range(150):
          content = host_log.read_text()
          if "TRUSTED_LOCK_HOST_TEST_FAIL" in content or process.poll() is not None:
            self.fail(content)
          if marker in content:
            return
          time.sleep(0.1)
        self.fail(host_log.read_text())
      process = launch_host()
      reader = None
      try:
        await_log("TRUSTED_LOCK_HOST_UNREADY")
        reader = socket.socket(socket.AF_UNIX)
        reader.settimeout(2)
        reader.connect(str(base / "runtime/omarchy-lock-pair-fixture.sock"))
        feed = reader.makefile("rb")
        self.assertIs(json.loads(feed.readline())["locked"], True)
        with patch.dict(os.environ, env, clear=True), patch.object(control, "unit_pid", return_value=process.pid):
          self.assertFalse(control.request("status")["ready"])
        (base / "start").touch()
        await_log("TRUSTED_LOCK_HOST_DUMMY_READY")
        self.assertIs(json.loads(feed.readline())["locked"], False)  # Readiness is an observable edge.
        self.assertIs(json.loads(feed.readline())["locked"], True)   # Then private dummy lock request.
        # The canonical implementation remains available with no main shell.
        with patch.dict(os.environ, env, clear=True), patch.object(control, "unit_pid", return_value=process.pid):
          self.assertTrue(control.request("status")["ready"])
          self.assertFalse(control.request("status")["secure"])
          bad = json.loads((base / "runtime/omarchy-lock-host.json-pair-fixture").read_text())
          correct = dict(bad)
          bad["start"] = "not-the-running-process"
          (base / "runtime/omarchy-lock-host.json-pair-fixture").write_text(json.dumps(bad))
          with self.assertRaises(ValueError):
            control.request("status")
          (base / "runtime/omarchy-lock-host.json-pair-fixture").write_text(json.dumps(correct))
        for _ in range(2):
          main_env = dict(env, OMARCHY_LOCK_HOST="1")
          main = subprocess.run(["quickshell", "-n", "-p", str(base / "shell"), "--no-color"], env=main_env, capture_output=True, text=True, timeout=12)
          self.assertIn("MAIN_LOCK_ISOLATION_PASS", main.stdout + main.stderr)
          self.assertNotIn("MAIN_LOCK_ISOLATION_FAIL", main.stdout + main.stderr)
          self.assertIsNone(process.poll(), "broker restart must not stop host")
          with patch.dict(os.environ, env, clear=True), patch.object(control, "unit_pid", return_value=process.pid):
            self.assertTrue(control.request("status")["ready"])
          # The existing boolean connection stays usable without a forced
          # producer change when the broker disappears/returns.
          reader.settimeout(0.1)
          with self.assertRaises(socket.timeout):
            reader.recv(1, socket.MSG_PEEK)
          reader.settimeout(2)
        # Forbidden control methods cannot unlock or evaluate anything.
        for method in ("unlock", "password", "eval", "submitPassword"):
          with socket.socket(socket.AF_UNIX) as bad_client:
            bad_client.settimeout(2)
            bad_client.connect(str(base / "runtime/omarchy-lock-control-pair-fixture.sock"))
            bad_stream = bad_client.makefile("rb")
            self.assertTrue(json.loads(bad_stream.readline())["locked"])
            bad_client.sendall(json.dumps({"method": method}).encode() + b"\n")
            self.assertEqual(bad_stream.readline(), b"")
        with socket.socket(socket.AF_UNIX) as oversized:
          oversized.settimeout(2)
          oversized.connect(str(base / "runtime/omarchy-lock-control-pair-fixture.sock"))
          incomplete = oversized.makefile("rb")
          incomplete.readline()
          oversized.sendall(b"x" * 65)  # No newline: still bounded and rejected.
          self.assertEqual(incomplete.readline(), b"")
        (base / "release").touch()
        process.wait(timeout=12)
        self.assertIn("TRUSTED_LOCK_HOST_TEST_PASS", host_log.read_text())
        # Unlock is a real private permit result, then process death produces
        # EOF: consumers must discard their last false value on EOF.
        states = []
        while True:
          line = feed.readline()
          if not line:
            break
          states.append(json.loads(line)["locked"])
        self.assertIs(states[-1], False)
        feed.close()
        reader.close()
        reader = None
        (base / "release").unlink()
        process = launch_host()
        await_log("TRUSTED_LOCK_HOST_DUMMY_READY")
        with socket.socket(socket.AF_UNIX) as renewed:
          renewed.settimeout(2)
          renewed.connect(str(base / "runtime/omarchy-lock-pair-fixture.sock"))
          self.assertIs(json.loads(renewed.makefile("rb").readline())["locked"], True)
        # Crash only the disposable offscreen model (no compositor lock was
        # acquired), and verify EOF/failed fresh status rather than stale true.
        with socket.socket(socket.AF_UNIX) as crash_reader:
          crash_reader.settimeout(2)
          crash_reader.connect(str(base / "runtime/omarchy-lock-pair-fixture.sock"))
          crash_feed = crash_reader.makefile("rb")
          self.assertTrue(json.loads(crash_feed.readline())["locked"])
          process.kill()
          process.wait(timeout=5)
          self.assertEqual(crash_feed.readline(), b"")
          crash_feed.close()
        with patch.dict(os.environ, env, clear=True), patch.object(control, "unit_pid", return_value=process.pid):
          with self.assertRaises((OSError, ValueError)):
            control.request("status")
        process = launch_host()
        await_log("TRUSTED_LOCK_HOST_DUMMY_READY")
        with patch.dict(os.environ, env, clear=True), patch.object(control, "unit_pid", return_value=process.pid):
          self.assertTrue(control.request("status")["ready"])
        (base / "release").touch()
        process.wait(timeout=12)
        self.assertIn("TRUSTED_LOCK_HOST_TEST_PASS", host_log.read_text())
      finally:
        if reader is not None:
          reader.close()
        if process.poll() is None:
          # Only this disposable offscreen process; it never acquired a real
          # compositor lock or used a user's password/PAM configuration.
          process.terminate()
          process.wait(timeout=5)



if __name__ == "__main__":
  unittest.main()
