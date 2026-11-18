"""Exercise the desktop observer on an isolated D-Bus connection."""

import os
import queue
import socket
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib


INPUTPLUMBER = "org.shadowblip.InputPlumber"
INPUTPLUMBER_PATH = "/org/shadowblip/InputPlumber"
COMPOSITE = "org.shadowblip.Input.CompositeDevice"
INPUT_EVENTS = "org.shadowblip.Input.DBusDevice"
BROKER = "org.omarchy.InputPlumberProfile"
DBUS = "org.freedesktop.DBus"
PROPERTIES = "org.freedesktop.DBus.Properties"


def make_desktop_fixture(root):
  fake_bin = root / "bin"
  fake_bin.mkdir()
  (root / "omarchy-gaming-test").mkdir()
  active = root / "omarchy-gaming-test/active"
  active.write_text("desktop\n")
  state = root / "state"
  state.write_text("ready\n")
  actions = root / "actions"
  actions.touch()
  tools = fake_bin / "desktop-test-command"
  tools.write_text(r"""#!/bin/bash
read -r state < "$DESKTOP_TEST_ROOT/state"
command=${0##*/}
case $command in
  loginctl)
    [[ $* == '--no-pager show-session self '* ]] || exit 2
    printf '%s\n' Id=test "User=$UID" Class=user Remote=no Seat=seat0 State=active Type=wayland Service=sddm
    if [[ $state == inactive ]]; then printf '%s\n' Active=no; else printf '%s\n' Active=yes; fi
    ;;
  systemctl)
    [[ $* == '--user show-environment' ]] || exit 2
    if [[ $state == stale ]]; then session=other; else session=test; fi
    printf '%s\n' "OMARCHY_HANDHELD_SESSION=$session" HYPRLAND_INSTANCE_SIGNATURE=test-hypr WAYLAND_DISPLAY=wayland-5
    ;;
  omarchy-hyprland-session-locked)
    [[ $state != stranded ]] || exit 0
    [[ $state != unknown ]] || exit 2
    exit 1
    ;;
  omarchy-menu|omarchy-shell)
    if [[ $* == 'lock isLocked' ]]; then
      [[ $state != locked ]] || { echo true; exit 0; }
      echo false
      exit 0
    fi
    printf '%s %s via %s %s\n' "$command" "$*" "$HYPRLAND_INSTANCE_SIGNATURE" "$WAYLAND_DISPLAY" >> "$DESKTOP_TEST_ROOT/actions"
    ;;
esac
""")
  tools.chmod(0o755)
  for name in ("loginctl", "systemctl", "omarchy-hyprland-session-locked", "omarchy-menu", "omarchy-shell"):
    (fake_bin / name).symlink_to(tools)
  env = os.environ | {"PATH": f"{fake_bin}:{os.environ['PATH']}", "XDG_RUNTIME_DIR": str(root),
                      "XDG_SESSION_ID": "test", "DESKTOP_TEST_ROOT": str(root)}
  return active, state, actions, env


def main(root):
  bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
  calls = queue.Queue()
  device = threading.Event()
  address = os.environ["DBUS_SESSION_BUS_ADDRESS"]

  def load(_bus, sender, _path, _iface, _method, params, invocation):
    ready = device.is_set()
    if ready:
      invocation.return_value(None)
    else:
      invocation.return_dbus_error(f"{BROKER}.Error", "Device not ready")
    calls.put((params.unpack()[0], ready, sender))

  def claim(connection, service):
    connection.call_sync(DBUS, "/org/freedesktop/DBus", DBUS, "RequestName",
                         GLib.Variant("(su)", (service, 0)), None, Gio.DBusCallFlags.NONE, 1000, None)

  def start_backend():
    flags = Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION
    connection = Gio.DBusConnection.new_for_address_sync(address, flags, None, None)
    claim(connection, INPUTPLUMBER)
    return connection

  def expect(profile, ready, observer_name=None):
    actual_profile, actual_ready, sender = calls.get(timeout=5)
    assert (actual_profile, actual_ready) == (profile, ready), (actual_profile, actual_ready)
    assert observer_name is None or observer_name == sender, sender
    return sender

  interface = Gio.DBusNodeInfo.new_for_xml(f"""
    <node><interface name="{BROKER}">
      <method name="Load"><arg name="name" type="s" direction="in"/></method>
    </interface></node>""").interfaces[0]
  bus.register_object("/org/omarchy/InputPlumberProfile", interface, load, None, None)
  claim(bus, BROKER)
  loop = GLib.MainLoop()
  threading.Thread(target=loop.run, daemon=True).start()
  active, state, actions, env = make_desktop_fixture(root)
  env["DBUS_SYSTEM_BUS_ADDRESS"] = address
  target = f"{INPUTPLUMBER_PATH}/devices/target/dbus0"
  expected = ("omarchy-menu toggle root via test-hypr wayland-5\n"
              "omarchy-menu close via test-hypr wayland-5\n"
              "omarchy-shell shell toggle omarchy.power via test-hypr wayland-5\n")

  def emit(backend, action, value=1.0, target_path=target):
    backend.emit_signal(None, target_path, INPUT_EVENTS, "InputEvent", GLib.Variant("(sd)", (action, value)))

  def sync_events(backend, observer_name):
    # A later signal from the same connection fences the preceding inputs.
    backend.emit_signal(None, f"{INPUTPLUMBER_PATH}/CompositeDevice0", PROPERTIES, "PropertiesChanged",
                        GLib.Variant("(sa{sv}as)", (COMPOSITE, {}, ["SourceDevicePaths"])))
    expect(profile, True, observer_name)

  for profile in ("desktop", "osk"):
    backend = start_backend()
    device.set()
    with subprocess.Popen([sys.executable, sys.argv[1], profile], env=env,
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as observer:
      try:
        observer_name = expect(profile, True)
        if profile == "desktop":
          emit(backend, "omarchy_menu")
          emit(backend, "omarchy_menu", 0.0)
          emit(backend, "omarchy_power")
          emit(backend, "omarchy_power", 0.0)
          emit(backend, "omarchy_overlay")
          emit(backend, "omarchy_menu", target_path=INPUTPLUMBER_PATH)
          sync_events(backend, observer_name)
          assert actions.read_text() == expected, actions.read_text()

          for blocked in ("inactive", "stale", "stranded", "unknown", "locked"):
            state.write_text(f"{blocked}\n")
            emit(backend, "omarchy_menu")
            sync_events(backend, observer_name)
            assert actions.read_text() == expected, blocked
          state.write_text("ready\n")
          active.write_text("gaming\n")
          emit(backend, "omarchy_menu")
          sync_events(backend, observer_name)
          assert actions.read_text() == expected, "gaming session"
          active.write_text("desktop\n")

          # An unrelated D-Bus client cannot impersonate the InputPlumber service.
          bus.emit_signal(None, target, INPUT_EVENTS, "InputEvent", GLib.Variant("(sd)", ("omarchy_menu", 1.0)))
          bus.flush_sync(None)
          sync_events(backend, observer_name)
          assert actions.read_text() == expected, "different signal sender"
        device.clear()
        backend.close_sync(None)
        backend = start_backend()
        expect(profile, False, observer_name)

        path = f"{INPUTPLUMBER_PATH}/CompositeDevice0"
        emit(backend, "omarchy_menu")
        backend.emit_signal(None, INPUTPLUMBER_PATH, "org.freedesktop.DBus.ObjectManager", "InterfacesAdded",
                            GLib.Variant("(oa{sa{sv}})", (path, {COMPOSITE: {}})))
        expect(profile, False, observer_name)
        assert actions.read_text() == expected, "profile is still unavailable"

        device.set()
        backend.emit_signal(None, path, PROPERTIES, "PropertiesChanged",
                            GLib.Variant("(sa{sv}as)", (COMPOSITE, {}, ["SourceDevicePaths"])))
        expect(profile, True, observer_name)

        output, errors = observer.communicate(timeout=5)
        assert observer.returncode == 0 and output == b"ready\n", (output, errors)
        expect("pointer", True, observer_name)
      finally:
        if observer.poll() is None:
          observer.kill()
        backend.close_sync(None)

  loop.quit()


if __name__ == "__main__":
  with tempfile.TemporaryDirectory(prefix="ally-oem-") as tmp, socket.socket(socket.AF_UNIX) as wayland:
    root = Path(tmp)
    wayland.bind(str(root / "wayland-5"))
    main(root)
