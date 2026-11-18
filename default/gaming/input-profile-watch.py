"""Keep a managed desktop's InputPlumber profile across device recreation."""

import sys

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLibUnix", "2.0")
from gi.repository import Gio, GLib, GLibUnix


INPUTPLUMBER = "org.shadowblip.InputPlumber"
INPUTPLUMBER_PATH = "/org/shadowblip/InputPlumber"
COMPOSITE = "org.shadowblip.Input.CompositeDevice"
BROKER = "org.omarchy.InputPlumberProfile"
BROKER_PATH = "/org/omarchy/InputPlumberProfile"
DBUS = "org.freedesktop.DBus"
PROPERTIES = "org.freedesktop.DBus.Properties"


def watch(profile):
  bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
  loop = GLib.MainLoop()
  pending = True
  loaded = False

  def request(name):
    try:
      bus.call_sync(
        BROKER, BROKER_PATH, BROKER, "Load", GLib.Variant("(s)", (name,)),
        None, Gio.DBusCallFlags.NO_AUTO_START, 3000, None,
      )
    except GLib.Error as error:
      print(f"Ally controller profile {name}: {error.message}", file=sys.stderr)
      return False
    return True

  def load():
    nonlocal loaded, pending
    pending = False
    loaded = request(profile) or loaded
    return GLib.SOURCE_REMOVE

  def first_load():
    load()
    print("ready", flush=True)
    return GLib.SOURCE_REMOVE

  def refresh():
    nonlocal pending
    if not pending:
      pending = True
      GLib.idle_add(load)

  def owner_changed(_bus, _sender, _path, _interface, _signal, params):
    _name, _old_owner, new_owner = params.unpack()
    if new_owner:
      refresh()

  def interfaces_added(_bus, _sender, _manager_path, _interface, _signal, params):
    _object_path, interfaces = params.unpack()
    composite = interfaces.get(COMPOSITE)
    # The signal can omit protected properties. The broker checks identity.
    if composite is not None and composite.get("Name", "ASUS ROG Ally") == "ASUS ROG Ally":
      refresh()

  def properties_changed(_bus, _sender, _path, _interface, _signal, params):
    _interface, changed, invalidated = params.unpack()
    if "SourceDevicePaths" in changed or "SourceDevicePaths" in invalidated:
      refresh()

  for name in (INPUTPLUMBER, BROKER):
    bus.signal_subscribe(DBUS, DBUS, "NameOwnerChanged", "/org/freedesktop/DBus", name,
                         Gio.DBusSignalFlags.NONE, owner_changed)
  bus.signal_subscribe(INPUTPLUMBER, "org.freedesktop.DBus.ObjectManager", "InterfacesAdded",
                       INPUTPLUMBER_PATH, None, Gio.DBusSignalFlags.NONE, interfaces_added)
  bus.signal_subscribe(INPUTPLUMBER, PROPERTIES, "PropertiesChanged", None, COMPOSITE,
                       Gio.DBusSignalFlags.NONE, properties_changed)

  def stop(_fd, _condition):
    loop.quit()
    return GLib.SOURCE_REMOVE

  # Only the session supervisor holds the write end. EOF also stops the
  # observer if the supervisor dies while the desktop is running.
  GLibUnix.fd_add_full(GLib.PRIORITY_DEFAULT, sys.stdin.fileno(), GLib.IO_HUP | GLib.IO_ERR, stop)
  GLib.idle_add(first_load)
  try:
    loop.run()
  finally:
    # Send the restore after any in-flight load on this same bus connection.
    if loaded:
      request("pointer")


if __name__ == "__main__":
  if len(sys.argv) != 2 or sys.argv[1] not in ("desktop", "osk"):
    sys.exit("Expected the managed desktop or osk profile")
  watch(sys.argv[1])
