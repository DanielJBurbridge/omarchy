"""Exercise bridge ownership and session transitions; no real input devices."""

import importlib.util
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("ally_input", sys.argv.pop(1))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Transport:
    def __init__(self):
        self.allowed = True
        self.found = ["/CompositeDevice7"]
        self.mode = "desktop"
        self.loads = []
        self.intercepts = []
        self.intercept_mode = 0
        self.real_locked = False
        self.profile_path = None

    def active(self, session):
        return self.allowed

    def devices(self):
        return self.found

    def desktop_unlocked(self):
        return not self.real_locked

    def properties(self, path):
        return {"ProfileName": f"Omarchy Ally {self.mode}", "DbusDevices": ["/dbus7"],
                "InterceptMode": self.intercept_mode,
                "ProfilePath": self.profile_path or str(module.PROFILE_DIR / f"{self.mode}.yaml")}

    def load(self, path, mode):
        self.loads.append((path, mode))
        self.mode = mode

    def intercept(self, path, mode):
        self.intercepts.append((path, mode))


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.transport = Transport()
        self.bridge = module.Bridge(self.transport, "/session")
        self.bridge.locked = False
        self.bridge.refresh_session()
        self.bridge.discover()
        self.launched = []
        module.launch = self.launched.append

    def test_ownership_and_release_edges(self):
        # Another controller must not trigger this session's menu or mode.
        self.bridge.event("/external", "omarchy_mode", 1)
        self.assertEqual(self.transport.mode, "desktop")
        self.bridge.event("/dbus7", "omarchy_menu", 0)
        self.assertEqual(self.launched, [])
        self.bridge.event("/dbus7", "omarchy_menu", 1)
        self.bridge.event("/dbus7", "omarchy_menu", 1)
        self.assertEqual(self.launched, [["omarchy-menu"]])
        self.bridge.event("/dbus7", "omarchy_menu", 0)
        self.bridge.event("/dbus7", "omarchy_menu", 1)
        self.assertEqual(len(self.launched), 2)

    def canonical_unavailable_snapshot(self):
        self.transport.real_locked = True
        monitor = module.LockMonitor.__new__(module.LockMonitor)
        monitor.bridge = self.bridge
        monitor.snapshot('{"locked": false}')
        self.assertIs(self.bridge.locked, False)
        self.assertFalse(self.bridge.allowed)
        self.transport.real_locked = False

    def test_owned_action_recovers_after_canonical_without_a_new_frame(self):
        self.canonical_unavailable_snapshot()
        self.assertEqual(self.transport.mode, "gamepad")
        self.bridge.event("/dbus7", "omarchy_power", 1)
        self.assertTrue(self.bridge.allowed)
        self.assertIs(self.bridge.locked, False)
        self.assertEqual(self.transport.mode, "desktop")
        self.assertEqual(self.launched, [["omarchy-shell", "shell", "toggle", "omarchy.power"]])
        original = list(self.transport.loads)
        self.bridge.event("/dbus7", "omarchy_power", 1)
        self.assertEqual(len(self.launched), 1, "duplicate press must stay suppressed after recovery")
        self.assertEqual(self.transport.loads, original)
        self.bridge.event("/dbus7", "omarchy_power", 0)
        self.assertEqual(len(self.launched), 1, "release never launches an action")
        self.bridge.event("/dbus7", "omarchy_power", 1)
        self.assertEqual(len(self.launched), 2)

    def test_recovery_boundary_cannot_take_another_input_owner(self):
        self.canonical_unavailable_snapshot()
        original = list(self.transport.loads)
        properties = self.transport.properties
        cases = [
            ("external target", "/external", {}),
            ("custom", "/dbus7", {"ProfileName": "Custom layout"}),
            ("forged name", "/dbus7", {"ProfileName": "Omarchy Ally gamepad", "ProfilePath": "/tmp/custom.yaml"}),
            ("unclaimed bootstrap", "/dbus7", {"ProfileName": "Default", "ProfilePath": module.DEFAULT_PROFILE}),
            ("unowned", "/dbus7", {"ProfileName": None, "ProfilePath": None}),
            *((f"intercept {mode}", "/dbus7", {"InterceptMode": mode}) for mode in (1, 2, 3)),
        ]
        for name, target, changed in cases:
            with self.subTest(name=name):
                self.transport.properties = lambda path: {**properties(path), **changed}
                self.bridge.event(target, "omarchy_mode", 1)
                self.bridge.event(target, "omarchy_power", 1)
                self.assertEqual(self.launched, [])
                self.assertEqual(self.transport.loads, original)
                self.assertEqual(self.transport.intercepts, [])
                self.assertFalse(self.bridge.allowed)

    def test_recovery_boundary_requires_real_unlock_and_active_session(self):
        self.canonical_unavailable_snapshot()
        original = list(self.transport.loads)
        for locked, active in ((True, True), (None, True), (False, False)):
            with self.subTest(locked=locked, active=active):
                self.bridge.locked = locked
                self.transport.allowed = active
                self.bridge.event("/dbus7", "omarchy_power", 1)
                self.assertEqual(self.launched, [])
                self.assertEqual(self.transport.loads, original)
                self.assertFalse(self.bridge.allowed)
        self.bridge.locked = False
        self.transport.allowed = True
        self.transport.desktop_unlocked = lambda: module.API.desktop_unlocked(self.transport)
        completed = subprocess.CompletedProcess
        for lock, compositor in (("true", 1), ("unknown", 1), ("false", 0), ("false", 2)):
            with self.subTest(lock=lock, compositor=compositor):
                with patch.object(module.subprocess, "run", side_effect=[
                    completed([], 0, lock), completed([], compositor)
                ]):
                    self.bridge.event("/dbus7", "omarchy_power", 1)
                self.assertEqual(self.launched, [])
                self.assertEqual(self.transport.loads, original)
                self.assertFalse(self.bridge.allowed)
        for error in (OSError("canonical unavailable"), subprocess.TimeoutExpired("lock query", 3)):
            with self.subTest(error=type(error).__name__):
                with patch.object(module.subprocess, "run", side_effect=error):
                    self.bridge.event("/dbus7", "omarchy_power", 1)
                self.assertEqual(self.launched, [])
                self.assertEqual(self.transport.loads, original)
                self.assertFalse(self.bridge.allowed)
        def failed_active(_session):
            raise module.GLib.Error("logind unavailable")
        self.transport.active = failed_active
        self.bridge.event("/dbus7", "omarchy_power", 1)
        self.assertFalse(self.bridge.allowed)
        self.assertIs(self.bridge.locked, False, "backend errors must not invalidate the healthy lock stream")
        self.assertEqual(self.launched, [])

    def test_mode_and_lock_transition(self):
        self.bridge.event("/dbus7", "omarchy_mode", 1)
        self.assertEqual(self.transport.mode, "gamepad")
        self.bridge.event("/dbus7", "omarchy_mode", 1)
        self.assertEqual(self.transport.mode, "gamepad", "duplicate press must not toggle back")
        self.bridge.event("/dbus7", "omarchy_mode", 0)
        self.bridge.event("/dbus7", "omarchy_mode", 1)
        self.assertEqual(self.transport.mode, "desktop")
        self.transport.allowed = False
        before = list(self.launched)
        self.bridge.event("/dbus7", "omarchy_power", 1)
        self.assertEqual(self.launched, before, "lock race must block an action")
        self.bridge.refresh_session()
        self.assertEqual(self.transport.mode, "gamepad")
        self.transport.allowed = True
        self.bridge.refresh_session()
        self.assertEqual(self.transport.mode, "desktop")

    def test_gamepad_and_custom_profiles_do_not_open_desktop_panels(self):
        for mode in ("gamepad", "dualsense", "custom"):
            self.transport.mode = mode
            self.bridge.event("/dbus7", "omarchy_power", 1)
            self.bridge.event("/dbus7", "omarchy_power", 0)
        self.assertEqual(self.launched, [])

    def test_custom_profile_owner_survives_lock_and_mode_action(self):
        self.transport.mode = "custom"
        original = list(self.transport.loads)
        self.bridge.event("/dbus7", "omarchy_mode", 1)
        self.transport.allowed = False
        self.bridge.refresh_session()
        self.transport.allowed = True
        self.bridge.refresh_session()
        self.assertEqual(self.transport.loads, original)

    def test_overlay_interception_blocks_desktop_actions(self):
        self.transport.intercept_mode = 2
        original = list(self.transport.loads)
        self.bridge.event("/dbus7", "omarchy_mode", 1)
        self.bridge.event("/dbus7", "omarchy_menu", 1)
        self.assertEqual(self.transport.loads, original)
        self.assertEqual(self.launched, [])

    def test_hotplug_does_not_reload_existing_controller(self):
        original = list(self.transport.loads)
        self.bridge.discover()
        self.assertEqual(self.transport.loads, original)
        self.transport.found = []
        self.bridge.discover()
        self.transport.found = ["/CompositeDevice9"]
        self.bridge.discover()
        self.assertEqual(self.transport.loads[-1], ("/CompositeDevice9", "desktop"))
        self.assertEqual(self.transport.intercepts, [], "discovery must never reset interception")

    def test_lifecycle_leaves_overlay_interception_and_profiles_untouched(self):
        for intercept_mode in (1, 2, 3):
            with self.subTest(intercept_mode=intercept_mode):
                self.transport.intercept_mode = intercept_mode
                original = list(self.transport.loads)
                # New bridge after restart and a reappearing composite.
                bridge = module.Bridge(self.transport, "/session")
                bridge.locked = False
                bridge.refresh_session()
                bridge.discover()
                bridge.locked = True
                bridge.refresh_session()
                bridge.locked = False
                bridge.refresh_session()
                bridge.cleanup()
                self.assertEqual(self.transport.loads, original)
                self.assertEqual(self.transport.intercepts, [])

    def test_vanished_composite_does_not_break_lock_or_rediscovery(self):
        properties = self.transport.properties
        def existing(path):
            if path not in self.transport.found:
                raise module.GLib.Error("UnknownObject")
            return properties(path)
        self.transport.properties = existing
        self.transport.found = []
        self.bridge.locked = True
        self.bridge.refresh_session()
        self.bridge.discover()
        self.assertEqual(self.bridge.devices, set())
        self.transport.found = ["/CompositeDevice9"]
        self.bridge.discover()
        self.bridge.locked = False
        self.bridge.refresh_session()
        self.assertTrue(self.bridge.allowed)
        self.assertEqual(self.transport.loads[-1], ("/CompositeDevice9", "desktop"))

    def test_backend_failure_does_not_invalidate_a_real_lock_snapshot(self):
        def failed_load(*_):
            raise module.GLib.Error("UnknownObject during profile change")
        self.transport.load = failed_load
        monitor = module.LockMonitor.__new__(module.LockMonitor)
        monitor.bridge = self.bridge
        monitor.snapshot('{"locked": true}')
        self.assertIs(self.bridge.locked, True)
        self.assertFalse(self.bridge.allowed)

    def test_discovery_claims_only_our_paths_or_upstream_bootstrap(self):
        for name, path in (("Custom layout", "/tmp/custom.yaml"),
                           ("Omarchy Ally desktop", "/tmp/imitation.yaml")):
            with self.subTest(name=name):
                props = {"ProfileName": name, "ProfilePath": path, "InterceptMode": 0}
                self.assertFalse(module.owns_profile(props, bootstrap=True))
                original = list(self.transport.loads)
                self.transport.properties = lambda _path: props
                bridge = module.Bridge(self.transport, "/session")
                bridge.discover()
                bridge.cleanup()
                self.assertEqual(self.transport.loads, original)
        self.assertTrue(module.owns_profile({"ProfileName": "Default", "ProfilePath": module.DEFAULT_PROFILE,
                                            "InterceptMode": 0}, bootstrap=True))

    def test_real_lock_without_logind_hint_blocks_and_releases_desktop(self):
        # Logind remains Active with LockedHint=false throughout this change.
        self.assertTrue(self.transport.allowed)
        self.transport.real_locked = True
        self.bridge.event("/dbus7", "omarchy_power", 1)
        self.assertEqual(self.launched, [], "query must catch a not-yet-delivered lock event")
        self.bridge.locked = True
        self.bridge.refresh_session()
        self.assertEqual(self.transport.mode, "gamepad")
        self.assertFalse(self.bridge.allowed)

    def test_overlay_release_while_locked_releases_only_our_desktop_inputs(self):
        self.transport.intercept_mode = 2
        original = list(self.transport.loads)
        self.bridge.locked = True
        self.bridge.refresh_session()
        self.assertEqual(self.transport.loads, original)
        self.transport.intercept_mode = 0
        self.bridge.refresh_session()  # Composite PropertiesChanged callback.
        self.assertEqual(self.transport.mode, "gamepad")
        self.assertEqual(self.transport.intercepts, [])

    def test_shutdown_preserves_a_later_game_profile(self):
        self.transport.mode = "dualsense"
        original = list(self.transport.loads)
        self.bridge.cleanup()
        self.assertEqual(self.transport.loads, original)
        self.transport.mode = "desktop"
        self.bridge.cleanup()
        self.assertEqual(self.transport.mode, "gamepad")

    def test_logind_failure_never_defaults_to_active(self):
        # Real GLib variant packing/unpacking and API method signatures, with
        # transport only replaced. No stub supplies the behaviour being tested.
        api = module.API.__new__(module.API)
        calls = []
        def call(*args):
            calls.append(args)
            return ({"Active": True},)
        api.call = call
        self.assertFalse(api.active("/session"), "missing LockedHint must fail closed")
        self.assertEqual(calls[0][-1], "org.freedesktop.login1")

    def test_backend_read_does_not_activate_missing_inputplumber(self):
        # An actually activatable private-bus service catches a backend-owner
        # disappearance race. No real InputPlumber/system bus is contacted.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            try:
                with socket.socket(socket.AF_UNIX) as probe:
                    probe.bind(str(root / "probe.sock"))
            except PermissionError:
                self.skipTest("AF_UNIX unavailable in this sandbox")
            marker = root / "activated"
            (root / f"{module.BUS}.service").write_text(
                f"[D-BUS Service]\nName={module.BUS}\nExec=/usr/bin/touch {marker}\n")
            bus = module.Gio.TestDBus.new(module.Gio.TestDBusFlags.NONE)
            bus.add_service_dir(directory)
            old_address = os.environ.get("DBUS_SESSION_BUS_ADDRESS")
            bus.up()
            connection = module.Gio.DBusConnection.new_for_address_sync(
                bus.get_bus_address(), module.Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
                | module.Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
            try:
                api = module.API.__new__(module.API)
                api.bus = connection
                available = api.call("/org/freedesktop/DBus", "org.freedesktop.DBus", "ListActivatableNames",
                                     destination="org.freedesktop.DBus")[0]
                self.assertIn(module.BUS, available)
                with self.assertRaises(module.GLib.Error):
                    api.devices()
                self.assertFalse(marker.exists(), "read must not activate a disappearing backend")
            finally:
                connection.close_sync(None)
                bus.down()
                if old_address is not None:
                    os.environ["DBUS_SESSION_BUS_ADDRESS"] = old_address

    def test_device_selection_uses_name_not_number(self):
        api = module.API.__new__(module.API)
        api.call = lambda *_: ({
            "/CompositeDevice0": {module.COMPOSITE: {"Name": "External pad"}},
            "/CompositeDevice4": {module.COMPOSITE: {"Name": module.NAME}},
        },)
        self.assertEqual(api.devices(), ["/CompositeDevice4"])

    def test_user_service_locates_graphical_session_without_its_pid(self):
        api = module.API.__new__(module.API)
        calls = []
        def call(*args):
            calls.append(args)
            if args[2] == "GetUser":
                return ("/user",)
            return ({"Display": ("c4", "/session4")},)
        api.call = call
        old = os.environ.pop("XDG_SESSION_ID", None)
        try:
            self.assertEqual(api.session(), "/session4")
        finally:
            if old is not None:
                os.environ["XDG_SESSION_ID"] = old
        self.assertEqual(calls[0][2], "GetUser")

    def test_logind_rejects_another_user_session(self):
        api = module.API.__new__(module.API)
        props = {"User": (os.getuid() + 1, "/user"), "Type": "wayland",
                 "Active": True, "LockedHint": False}
        api.call = lambda *_: (props,)
        self.assertFalse(api.active("/session"))
        props["User"] = (os.getuid(), "/user")
        self.assertTrue(api.active("/session"))

    def test_authoritative_lock_queries_reject_unknown_and_stranded_locks(self):
        api = module.API.__new__(module.API)
        completed = subprocess.CompletedProcess
        for lock_output, compositor in (("true\n", 1), ("false\n", 0), ("false\n", 2), ("garbage", 1)):
            with self.subTest(lock=lock_output, compositor=compositor):
                with patch.object(module.subprocess, "run", side_effect=[
                    completed([], 0, lock_output), completed([], compositor)
                ]) as run:
                    self.assertFalse(api.desktop_unlocked())
                    self.assertEqual(run.call_args_list[0].args[0], ["omarchy-shell", "lock", "isLocked"])
        with patch.object(module.subprocess, "run", side_effect=[
            completed([], 0, "false\n"), completed([], 1)
        ]):
            self.assertTrue(api.desktop_unlocked())

    def test_lock_stream_snapshot_transition_and_peer_death(self):
        with tempfile.TemporaryDirectory() as directory:
            env = {"XDG_RUNTIME_DIR": directory, "HYPRLAND_INSTANCE_SIGNATURE": "input-test"}
            with patch.dict(os.environ, env):
                service = module.Gio.SocketService.new()
                try:
                    service.add_address(module.Gio.UnixSocketAddress.new(str(Path(directory) / "omarchy-lock-input-test.sock")),
                                        module.Gio.SocketType.STREAM, module.Gio.SocketProtocol.DEFAULT, None)
                except module.GLib.Error as error:
                    if error.matches(module.Gio.io_error_quark(), module.Gio.IOErrorEnum.PERMISSION_DENIED):
                        self.skipTest("AF_UNIX unavailable in this sandbox")
                    raise
                peers = []
                def incoming(_service, connection, _source):
                    peers.append(connection)
                    connection.get_output_stream().write_all(b'{"locked":false}\n', None)
                    return True
                service.connect("incoming", incoming)
                service.start()
                self.bridge.locked = None
                self.bridge.refresh_session()
                monitor = module.LockMonitor(self.bridge)
                context = module.GLib.MainContext.default()
                def until(condition):
                    deadline = time.monotonic() + 3
                    while not condition() and time.monotonic() < deadline:
                        context.iteration(False)
                        time.sleep(0.001)
                    self.assertTrue(condition(), "lock stream callback arrived")
                try:
                    until(lambda: self.bridge.locked is False)
                    self.assertEqual(self.transport.mode, "desktop")
                    peers[0].get_output_stream().write_all(b'{"locked":true}\n', None)
                    until(lambda: self.bridge.locked is True)
                    self.assertFalse(self.bridge.allowed)
                    self.assertEqual(self.transport.mode, "gamepad")
                    peers[0].close(None)
                    until(lambda: monitor.connection is None)
                    self.assertIsNone(self.bridge.locked)
                    self.assertFalse(self.bridge.allowed)
                    service.stop()
                    service.close()
                    Path(monitor.path).unlink()
                    service = module.Gio.SocketService.new()
                    service.add_address(module.Gio.UnixSocketAddress.new(monitor.path),
                                        module.Gio.SocketType.STREAM, module.Gio.SocketProtocol.DEFAULT, None)
                    service.connect("incoming", incoming)
                    service.start()
                    until(lambda: self.bridge.locked is False)
                    self.assertTrue(self.bridge.allowed, "recreated producer supplies a fresh snapshot")
                    peers[-1].get_output_stream().write_all(b'{"locked":0}\n', None)
                    until(lambda: monitor.connection is None)
                    self.assertIsNone(self.bridge.locked, "a number is not a lock-state boolean")
                    self.assertFalse(self.bridge.allowed)
                finally:
                    monitor.stop()
                    service.stop()
                    service.close()


class SetupTests(unittest.TestCase):
    def test_unsupported_hardware_never_reaches_package_or_privileged_work(self):
        self.run_setup(False)

    @unittest.skipIf(os.getuid() == 0, "setup deliberately requires a desktop user")
    def test_active_hhd_instance_blocks_before_privileged_work(self):
        self.run_setup(True)

    def run_setup(self, ally):
        root = Path(module.__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as scratch:
            directory = Path(scratch)
            # These only supply external command output. The real setup parses
            # the running hhd@ instance and must prevent its own system writes.
            commands = {
                "omarchy-hw-rog-ally": f"exit {0 if ally else 1}",
                "pacman": "printf 'inputplumber 0.84.0-1\\n'",
                "vercmp": "echo 0",
                "systemctl": "printf 'hhd@player.service loaded active running Handheld Daemon\\n'",
                "sudo": "echo UNEXPECTED_PRIVILEGE; exit 90",
            }
            for name, body in commands.items():
                path = directory / name
                path.write_text("#!/bin/bash\n" + body + "\n")
                path.chmod(0o755)
            env = {**os.environ, "PATH": f"{directory}:{os.environ['PATH']}"}
            result = subprocess.run([str(root / "bin/omarchy-setup-rog-ally-input"), "--enable"],
                                    env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertNotIn("UNEXPECTED_PRIVILEGE", result.stdout + result.stderr)
            self.assertIn("competing input owners" if ally else "only for ASUS", result.stderr)


unittest.main()
