#!/usr/bin/python
"""RC71L session actions using InputPlumber's public system D-Bus API.

Input translation stays in InputPlumber. This process only reacts to device,
session and button signals; it never reads evdev or runs a refresh timer.
"""

import json
import os
from pathlib import Path
import signal
import subprocess
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
DEFAULT_PROFILE = "/usr/share/inputplumber/profiles/default.yaml"


class API:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

    def call(self, path, interface, method, signature=None, args=(), destination=BUS):
        parameters = GLib.Variant(signature, args) if signature else None
        flags = (Gio.DBusCallFlags.NO_AUTO_START if destination == BUS
                 else Gio.DBusCallFlags.NONE)
        return self.bus.call_sync(destination, path, interface, method, parameters,
                                  None, flags, 5000, None).unpack()

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

    def desktop_unlocked(self):
        # LockedHint is advisory: Omarchy's actual lock is WlSessionLock.
        # Query the trusted lock service and compositor only at state/action
        # boundaries, never on an idle timer. Unknown or a crashed locker fails
        # closed, including a compositor-held lock surviving a shell restart.
        try:
            lock = subprocess.run(["omarchy-shell", "lock", "isLocked"],
                                  capture_output=True, text=True, timeout=3)
            if lock.returncode != 0 or lock.stdout.strip() != "false":
                return False
            compositor = subprocess.run(["omarchy-hyprland-session-locked"],
                                        capture_output=True, timeout=3)
            return compositor.returncode == 1
        except (OSError, subprocess.TimeoutExpired):
            return False


def current_mode(properties):
    name = properties.get("ProfileName", "")
    for mode in MODES:
        if name == f"Omarchy Ally {mode}":
            return mode
    return "custom"


def owns_profile(properties, bootstrap=False):
    if properties.get("InterceptMode") != 0:
        return False
    mode = current_mode(properties)
    if mode in MODES:
        return properties.get("ProfilePath") == str(PROFILE_DIR / f"{mode}.yaml")
    return (bootstrap and properties.get("ProfileName") == "Default"
            and properties.get("ProfilePath") == DEFAULT_PROFILE)


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
        self.locked = None  # Actual lock producer has not supplied a snapshot.
        self.pressed = set()

    def refresh_session(self):
        allowed = (self.locked is False and self.api.active(self.session)
                   and self.api.desktop_unlocked())
        if allowed != self.allowed:
            owned = {path for path in self.devices
                     if owns_profile(self.api.properties(path))}
            if self.allowed:
                for path in owned:
                    mode = current_mode(self.api.properties(path))
                    if mode in MODES:
                        self.preferred = mode
            self.allowed = allowed
            self.pressed.clear()
            for path in owned:
                # Recheck just before writing; an overlay may have taken over.
                if owns_profile(self.api.properties(path)):
                    self.api.load(path, self.preferred if allowed else "gamepad")
        elif not allowed:
            # An overlay may release interception after the lock transition.
            # Reconcile only our desktop profile; never change its owner.
            for path in self.devices:
                properties = self.api.properties(path)
                if owns_profile(properties) and current_mode(properties) == "desktop":
                    self.api.load(path, "gamepad")

    def discover(self):
        self.refresh_session()
        found = set(self.api.devices())
        for path in found - self.devices:
            if owns_profile(self.api.properties(path), bootstrap=True):
                self.api.load(path, self.preferred if self.allowed else "gamepad")
            # Discovery never clears interception or replaces an overlay's
            # custom profile. Claim only our own profile or upstream bootstrap.
        self.devices = found

    def event(self, target, action, value):
        # Recheck the real lock, including a signal still waiting in this loop.
        if (not self.allowed or self.locked is not False
                or not self.api.active(self.session) or not self.api.desktop_unlocked()):
            return
        owner = None
        for path in self.devices:
            if target in self.api.properties(path).get("DbusDevices", []):
                owner = path
                break
        if owner is None:
            return
        properties = self.api.properties(owner)
        if not owns_profile(properties):
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
                properties = self.api.properties(path)
                if owns_profile(properties) and current_mode(properties) == "desktop":
                    self.api.load(path, "gamepad")
            except GLib.Error as error:
                print(f"Ally cleanup: {error}", file=sys.stderr, flush=True)


class LockMonitor:
    """Read-only AUTH stream: snapshot/changes; a dead peer means unknown."""

    def __init__(self, bridge):
        self.bridge = bridge
        self.path = str(Path(os.environ["XDG_RUNTIME_DIR"]) /
                        f"omarchy-lock-{os.environ['HYPRLAND_INSTANCE_SIGNATURE']}.sock")
        self.connection = None
        self.connecting = False
        self.replaced = False
        self.cancel = Gio.Cancellable.new()
        self.client = Gio.SocketClient.new()
        # Subscribe before connecting so creation/replacement during startup
        # cannot leave a missing producer mistaken for an unlocked desktop.
        self.monitor = Gio.File.new_for_path(str(Path(self.path).parent)).monitor_directory(
            Gio.FileMonitorFlags.WATCH_MOVES, None)
        self.monitor.connect("changed", self.changed)
        self.connect()

    def changed(self, _monitor, file, other_file, _event):
        if any(item and item.get_path() == self.path for item in (file, other_file)):
            if self.connection is not None or self.connecting:
                self.replaced = True
            else:
                self.connect()

    def connect(self):
        if self.connection is None and not self.connecting and not self.cancel.is_cancelled():
            self.connecting = True
            self.client.connect_async(Gio.UnixSocketAddress.new(self.path), self.cancel,
                                      self.connected)

    def connected(self, client, result):
        self.connecting = False
        try:
            connection = client.connect_finish(result)
            if connection.get_socket().get_credentials().get_unix_user() != os.getuid():
                connection.close(None)
                raise ValueError("lock stream is not owned by this user")
            self.connection = connection
            self.replaced = False
            self.stream = Gio.DataInputStream.new(connection.get_input_stream())
            self.stream.read_line_async(GLib.PRIORITY_DEFAULT, self.cancel, self.read)
        except (GLib.Error, ValueError):
            self.lost()

    def snapshot(self, line):
        message = json.loads(line)
        locked = message.get("locked") if isinstance(message, dict) else None
        if type(locked) is not bool:
            raise ValueError("invalid lock-state snapshot")
        self.bridge.locked = locked
        self.bridge.refresh_session()

    def read(self, stream, result):
        try:
            line, _size = stream.read_line_finish_utf8(result)
            if line is None:
                self.lost()
                return
            self.snapshot(line)
            stream.read_line_async(GLib.PRIORITY_DEFAULT, self.cancel, self.read)
        except (GLib.Error, ValueError):
            self.lost()

    def lost(self):
        reconnect = self.replaced
        self.replaced = False
        self.bridge.locked = None
        if self.connection:
            try:
                self.connection.close(None)
            except GLib.Error:
                pass
            self.connection = None
        try:
            self.bridge.refresh_session()
        except GLib.Error as error:
            print(f"Ally lock-state loss: {error}", file=sys.stderr, flush=True)
        # A replacement can be announced while the old peer is still alive.
        # Reconnect once for that event; failed connects never start a timer.
        if reconnect:
            self.connect()

    def stop(self):
        self.cancel.cancel()
        self.monitor.cancel()
        if self.connection:
            self.connection.close(None)


def watch(api):
    if not desktop_session():
        raise ValueError("watch requires the Hyprland desktop session")
    bridge = Bridge(api, api.session())
    bridge.refresh_session()
    lock_monitor = LockMonitor(bridge)

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

    def profile_changed(_bus, _sender, _path, _iface, _member, parameters, _data):
        interface, _changed, _invalidated = parameters.unpack()
        if interface == COMPOSITE:
            bridge.refresh_session()

    api.bus.signal_subscribe(BUS, OBJECTS, None, ROOT, None,
                             Gio.DBusSignalFlags.NONE, guarded(objects_changed), None)
    api.bus.signal_subscribe(BUS, "org.shadowblip.Input.DBusDevice", "InputEvent",
                             None, None, Gio.DBusSignalFlags.NONE, guarded(event), None)
    api.bus.signal_subscribe("org.freedesktop.login1", PROPERTIES, "PropertiesChanged",
                             bridge.session, None, Gio.DBusSignalFlags.NONE,
                             guarded(session_changed), None)
    api.bus.signal_subscribe(BUS, PROPERTIES, "PropertiesChanged", None, None,
                             Gio.DBusSignalFlags.NONE, guarded(profile_changed), None)
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
        lock_monitor.stop()
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
        if mode == "desktop" and not (desktop_session() and api.active(api.session())
                                       and api.desktop_unlocked()):
            raise ValueError("desktop mode requires the active unlocked Hyprland session")
        if props.get("InterceptMode") != 0:
            raise ValueError("an overlay owns input interception; close it before changing profile")
        api.load(path, mode)
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
