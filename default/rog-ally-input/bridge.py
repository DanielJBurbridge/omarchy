#!/usr/bin/python
"""RC71L session actions using InputPlumber's public system D-Bus API.

Input translation stays in InputPlumber. This process only reacts to device,
session and button signals; it never reads evdev or runs a refresh timer.
"""

import json
import os
from pathlib import Path
import signal
import sys

from gi.repository import Gio, GLib

BUS = "org.shadowblip.InputPlumber"
ROOT = "/org/shadowblip/InputPlumber"
COMPOSITE = "org.shadowblip.Input.CompositeDevice"
PROPERTIES = "org.freedesktop.DBus.Properties"
OBJECTS = "org.freedesktop.DBus.ObjectManager"
PROFILE_DIR = Path("/usr/share/omarchy-rog-ally-input/profiles")
NAME = "ASUS ROG Ally"
MODES = ("desktop", "gamepad", "dualsense")


class API:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

    def call(self, path, interface, method, signature=None, args=(), destination=BUS):
        parameters = GLib.Variant(signature, args) if signature else None
        return self.bus.call_sync(destination, path, interface, method, parameters,
                                  None, Gio.DBusCallFlags.NONE, 5000, None).unpack()

    def properties(self, path, interface=COMPOSITE):
        return self.call(path, PROPERTIES, "GetAll", "(s)", (interface,))[0]

    def devices(self):
        objects = self.call(ROOT, OBJECTS, "GetManagedObjects")[0]
        # Never assume CompositeDevice0: docks/external controllers can come first.
        return [path for path, interfaces in objects.items()
                if interfaces.get(COMPOSITE, {}).get("Name") == NAME]

    def load(self, path, mode):
        self.call(path, COMPOSITE, "LoadProfilePath", "(s)",
                  (str(PROFILE_DIR / f"{mode}.yaml"),))

    def intercept(self, path, mode):
        self.call(path, PROPERTIES, "Set", "(ssv)",
                  (COMPOSITE, "InterceptMode", GLib.Variant("u", mode)))

    def session(self):
        # A systemd user service belongs to user@.service, outside the login
        # session's cgroup. GetSessionByPID therefore cannot locate its session.
        session_id = os.environ.get("XDG_SESSION_ID")
        if session_id:
            return self.call("/org/freedesktop/login1", "org.freedesktop.login1.Manager",
                             "GetSession", "(s)", (session_id,),
                             "org.freedesktop.login1")[0]
        user = self.call("/org/freedesktop/login1", "org.freedesktop.login1.Manager",
                         "GetUser", "(u)", (os.getuid(),), "org.freedesktop.login1")[0]
        props = self.call(user, PROPERTIES, "GetAll", "(s)",
                          ("org.freedesktop.login1.User",), "org.freedesktop.login1")[0]
        _identifier, path = props.get("Display", ("", "/"))
        if path == "/":
            raise ValueError("logind has no graphical display session for this user")
        return path

    def active(self, session):
        props = self.call(session, PROPERTIES, "GetAll", "(s)",
                          ("org.freedesktop.login1.Session",),
                          "org.freedesktop.login1")[0]
        return (props.get("User", (-1, "/"))[0] == os.getuid()
                and props.get("Type") == "wayland"
                and props.get("Active", False) and not props.get("LockedHint", True))


def current_mode(properties):
    name = properties.get("ProfileName", "")
    for mode in MODES:
        if name == f"Omarchy Ally {mode}":
            return mode
    return "custom"


def desktop_session():
    desktops = os.environ.get("XDG_CURRENT_DESKTOP", "").lower().split(":")
    return "hyprland" in desktops and bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"))


def launch(argv):
    process = Gio.Subprocess.new(argv, Gio.SubprocessFlags.NONE)
    process.wait_check_async(None, process_done, None)


def process_done(process, result, _data):
    try:
        process.wait_check_finish(result)
    except GLib.Error as error:
        print(f"Ally action failed: {error}", file=sys.stderr, flush=True)


class Bridge:
    def __init__(self, api, session):
        self.api = api
        self.session = session
        self.devices = set()
        self.preferred = "desktop"
        self.allowed = False
        self.pressed = set()

    def refresh_session(self):
        allowed = self.api.active(self.session)
        if allowed != self.allowed:
            owned = {path for path in self.devices
                     if current_mode(self.api.properties(path)) in MODES}
            if self.allowed:
                for path in owned:
                    mode = current_mode(self.api.properties(path))
                    if mode in MODES:
                        self.preferred = mode
            self.allowed = allowed
            self.pressed.clear()
            for path in owned:
                self.api.load(path, self.preferred if allowed else "gamepad")

    def discover(self):
        found = set(self.api.devices())
        for path in found - self.devices:
            self.api.load(path, self.preferred if self.allowed else "gamepad")
            # Without an overlay consumer, PASS would swallow Guide and leave
            # the controller intercepted. Start with normal game delivery.
            self.api.intercept(path, 0)
        self.devices = found

    def event(self, target, action, value):
        # Recheck logind at the action boundary, including a lock signal race.
        if not self.allowed or not self.api.active(self.session):
            return
        owner = None
        for path in self.devices:
            if target in self.api.properties(path).get("DbusDevices", []):
                owner = path
                break
        if owner is None:
            return
        properties = self.api.properties(owner)
        if properties.get("InterceptMode") != 0:
            # An overlay owns interception until it restores normal delivery.
            return
        key = (target, action)
        if value <= 0:
            self.pressed.discard(key)
            return
        if key in self.pressed:
            return
        self.pressed.add(key)
        mode = current_mode(properties)
        if action == "omarchy_mode" and mode in MODES:
            self.preferred = "gamepad" if mode == "desktop" else "desktop"
            self.api.load(owner, self.preferred)
            launch(["omarchy-notification-send", "Controller mode", self.preferred.title()])
        elif mode == "desktop":
            if action == "omarchy_power":
                launch(["omarchy-shell", "shell", "toggle", "omarchy.power"])
            elif action == "omarchy_menu":
                launch(["omarchy-menu"])

    def cleanup(self):
        # Do not overwrite a profile subsequently selected by another owner.
        for path in self.devices:
            try:
                if current_mode(self.api.properties(path)) == "desktop":
                    self.api.load(path, "gamepad")
            except GLib.Error as error:
                print(f"Ally cleanup: {error}", file=sys.stderr, flush=True)


def watch(api):
    if not desktop_session():
        raise ValueError("watch requires the Hyprland desktop session")
    bridge = Bridge(api, api.session())
    bridge.refresh_session()

    def guarded(callback):
        def run(*args):
            try:
                callback(*args)
            except (GLib.Error, ValueError) as error:
                print(f"Ally input: {error}", file=sys.stderr, flush=True)
        return run

    def objects_changed(*_args):
        bridge.discover()

    def event(_bus, _sender, path, _iface, _member, parameters, _data):
        action, value = parameters.unpack()
        # Ignore ordinary overlay/navigation events at the subscription boundary.
        if action in ("omarchy_mode", "omarchy_power", "omarchy_menu"):
            bridge.event(path, action, value)

    def session_changed(*_args):
        bridge.refresh_session()

    api.bus.signal_subscribe(BUS, OBJECTS, None, ROOT, None,
                             Gio.DBusSignalFlags.NONE, guarded(objects_changed), None)
    api.bus.signal_subscribe(BUS, "org.shadowblip.Input.DBusDevice", "InputEvent",
                             None, None, Gio.DBusSignalFlags.NONE, guarded(event), None)
    api.bus.signal_subscribe("org.freedesktop.login1", PROPERTIES, "PropertiesChanged",
                             bridge.session, None, Gio.DBusSignalFlags.NONE,
                             guarded(session_changed), None)
    # Service restarts and hotplug are events, not periodic rediscovery.
    def owner_vanished(*_args):
        bridge.devices.clear()
        bridge.pressed.clear()

    Gio.bus_watch_name_on_connection(api.bus, BUS, Gio.BusNameWatcherFlags.NONE,
                                    guarded(objects_changed), owner_vanished)
    loop = GLib.MainLoop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, lambda: (loop.quit(), False)[1])
    try:
        loop.run()
    finally:
        bridge.cleanup()


def main(args):
    action = args[0] if args else "status"
    if action not in (*MODES, "toggle", "status", "capabilities", "intercept", "watch"):
        raise ValueError("unknown action; use --help")
    if action == "intercept":
        if len(args) != 2 or args[1] not in ("none", "all"):
            raise ValueError("intercept requires none or all")
    elif len(args) > 1:
        raise ValueError("too many arguments; use --help")
    api = API()
    if action == "watch":
        watch(api)
        return
    paths = api.devices()
    if len(paths) != 1:
        raise ValueError(f"expected exactly one upstream RC71L composite, found {len(paths)}")
    path = paths[0]
    props = api.properties(path)
    if action in (*MODES, "toggle"):
        mode = ("gamepad" if current_mode(props) == "desktop" else "desktop") if action == "toggle" else action
        if mode == "desktop" and not (desktop_session() and api.active(api.session())):
            raise ValueError("desktop mode requires the active unlocked Hyprland session")
        api.load(path, mode)
        api.intercept(path, 0)
        print(f"Requested {mode}; verify current profile with status.")
    elif action == "intercept":
        api.intercept(path, 2 if args[1] == "all" else 0)
    else:
        keys = ("Name", "ProfileName", "ProfilePath", "TargetDevices", "InterceptMode")
        if action == "capabilities":
            keys = ("Capabilities", "TargetCapabilities", "OutputCapabilities", "SourceDevicePaths")
        print(json.dumps({key: props.get(key) for key in keys}, indent=2))


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (GLib.Error, ValueError) as error:
        sys.exit(f"Ally input: {error}")
