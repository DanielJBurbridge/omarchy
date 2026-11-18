"""Exercise the desktop observer on an isolated D-Bus connection."""

import os
import queue
import subprocess
import sys
import threading

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib


INPUTPLUMBER = "org.shadowblip.InputPlumber"
INPUTPLUMBER_PATH = "/org/shadowblip/InputPlumber"
COMPOSITE = "org.shadowblip.Input.CompositeDevice"
BROKER = "org.omarchy.InputPlumberProfile"
DBUS = "org.freedesktop.DBus"


def main():
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
  env = os.environ | {"DBUS_SYSTEM_BUS_ADDRESS": address}

  for profile in ("desktop", "osk"):
    backend = start_backend()
    device.set()
    with subprocess.Popen([sys.executable, sys.argv[1], profile], env=env,
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as observer:
      try:
        observer_name = expect(profile, True)
        device.clear()
        backend.close_sync(None)
        backend = start_backend()
        expect(profile, False, observer_name)

        path = f"{INPUTPLUMBER_PATH}/CompositeDevice0"
        backend.emit_signal(None, INPUTPLUMBER_PATH, "org.freedesktop.DBus.ObjectManager", "InterfacesAdded",
                            GLib.Variant("(oa{sa{sv}})", (path, {COMPOSITE: {}})))
        expect(profile, False, observer_name)

        device.set()
        backend.emit_signal(None, path, "org.freedesktop.DBus.Properties", "PropertiesChanged",
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
  main()
