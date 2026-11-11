"""Exercise bridge ownership and session transitions; no real input devices."""

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

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

    def active(self, session):
        return self.allowed

    def devices(self):
        return self.found

    def properties(self, path):
        return {"ProfileName": f"Omarchy Ally {self.mode}", "DbusDevices": ["/dbus7"],
                "InterceptMode": self.intercept_mode}

    def load(self, path, mode):
        self.loads.append((path, mode))
        self.mode = mode

    def intercept(self, path, mode):
        self.intercepts.append((path, mode))


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.transport = Transport()
        self.bridge = module.Bridge(self.transport, "/session")
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
        self.assertEqual(self.transport.intercepts[-1], ("/CompositeDevice9", 0))

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
