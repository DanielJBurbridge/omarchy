"""Keep a managed session's InputPlumber profile and handle Desktop OEM buttons."""

import os
import re
import subprocess
import sys
from pathlib import Path

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLibUnix", "2.0")
from gi.repository import Gio, GLib, GLibUnix


INPUTPLUMBER = "org.shadowblip.InputPlumber"
INPUTPLUMBER_PATH = "/org/shadowblip/InputPlumber"
COMPOSITE = "org.shadowblip.Input.CompositeDevice"
ALLY_SOURCE_INTERFACES = ("org.shadowblip.Input.Source.HIDRawDevice", "org.shadowblip.Input.Source.EventDevice")
INPUT_EVENTS = "org.shadowblip.Input.DBusDevice"
BROKER = "org.omarchy.InputPlumberProfile"
BROKER_PATH = "/org/omarchy/InputPlumberProfile"
DBUS = "org.freedesktop.DBus"
PROPERTIES = "org.freedesktop.DBus.Properties"

DESKTOP_ACTIONS = {
  "omarchy_menu": ("menu-toggle",),
  "omarchy_power": ("power-prepare", "power-toggle"),
}


def run(command, env=None, timeout=1):
  return subprocess.run(command, env=env, capture_output=True, text=True, timeout=timeout)


def active_desktop_login(session):
  expected = (f"Id={session}", f"User={os.getuid()}", "Active=yes", "Class=user",
              "Remote=no", "Seat=seat0", "State=active", "Type=wayland")
  result = run(["loginctl", "--no-pager", "show-session", "self",
                "-p", "Id", "-p", "User", "-p", "Active", "-p", "Class",
                "-p", "Remote", "-p", "Seat", "-p", "State", "-p", "Type", "-p", "Service"])
  properties = set(result.stdout.splitlines())
  return (result.returncode == 0 and properties.issuperset(expected)
          and bool(properties & {"Service=sddm", "Service=sddm-autologin"}))


def unlocked_desktop_env():
  session = os.environ.get("XDG_SESSION_ID", "")
  runtime = os.environ.get("XDG_RUNTIME_DIR", "")
  if not re.fullmatch(r"[a-zA-Z0-9_-]+", session) or not runtime:
    return
  if (Path(runtime) / f"omarchy-gaming-{session}/active").read_text().strip() != "desktop":
    return
  if not active_desktop_login(session):
    return
  # UWSM knows the managed compositor. Never infer it from an arbitrary
  # Wayland socket in the runtime directory.
  manager_env = run(["systemctl", "--user", "show-environment"])
  if manager_env.returncode:
    return
  manager = dict(line.split("=", 1) for line in manager_env.stdout.splitlines() if "=" in line)
  signature = manager.get("HYPRLAND_INSTANCE_SIGNATURE", "")
  display = manager.get("WAYLAND_DISPLAY", "")
  if (manager.get("OMARCHY_HANDHELD_SESSION") != session
      or not re.fullmatch(r"[a-zA-Z0-9_.-]+", signature)
      or not re.fullmatch(r"wayland-[a-zA-Z0-9_.-]+", display)
      or not (Path(runtime) / display).is_socket()):
    return
  env = os.environ | {"HYPRLAND_INSTANCE_SIGNATURE": signature, "WAYLAND_DISPLAY": display}
  if run(["omarchy-hyprland-session-locked"], env).returncode != 1:
    return
  lock = run(["omarchy-shell", "lock", "isLocked"], env)
  if lock.returncode == 0 and lock.stdout.strip() == "false":
    return env


def desktop_action(steps):
  try:
    output = "current"
    for step in steps:
      # Closing the menu can take long enough for the desktop to lock or yield the seat.
      env = unlocked_desktop_env()
      if env is None:
        return
      # The shell verifies focus and owns both the menu and the anchored bar
      # widget. Pass its confirmed output back to fence the next step.
      result = run(["omarchy-shell", "shell", "handheldAction", step, output,
                    env["HYPRLAND_INSTANCE_SIGNATURE"]], env, timeout=3)
      output = result.stdout.strip()
      if result.returncode or not re.fullmatch(r"eDP-[0-9]+", output):
        return
  except (OSError, ValueError, subprocess.TimeoutExpired):
    # Login, display and lock state are required even when a probe fails.
    return


def watch(profile):
  bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
  loop = GLib.MainLoop()
  pending = True
  loaded = False
  profile_active = False

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
    nonlocal loaded, pending, profile_active
    pending = False
    profile_active = request(profile)
    loaded = profile_active or loaded
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
    # InputPlumber registers sources and composites in separate tasks. A
    # matching source can become visible after the first composite request.
    for interface in ALLY_SOURCE_INTERFACES:
      source = interfaces.get(interface, {})
      if (source.get("IdVendor"), source.get("IdProduct")) == ("0b05", "1abe"):
        refresh()

  def properties_changed(_bus, _sender, _path, _interface, _signal, params):
    _interface, changed, invalidated = params.unpack()
    if "SourceDevicePaths" in changed or "SourceDevicePaths" in invalidated:
      refresh()

  def input_event(_bus, _sender, path, _interface, _signal, params):
    if pending or not profile_active or params.get_type_string() != "(sd)":
      return
    if not re.fullmatch(rf"{INPUTPLUMBER_PATH}/devices/target/dbus[0-9]+", path):
      return
    action, value = params.unpack()
    if value == 1.0 and action in DESKTOP_ACTIONS:
      desktop_action(DESKTOP_ACTIONS[action])

  for name in (INPUTPLUMBER, BROKER):
    bus.signal_subscribe(DBUS, DBUS, "NameOwnerChanged", "/org/freedesktop/DBus", name,
                         Gio.DBusSignalFlags.NONE, owner_changed)
  bus.signal_subscribe(INPUTPLUMBER, "org.freedesktop.DBus.ObjectManager", "InterfacesAdded",
                       INPUTPLUMBER_PATH, None, Gio.DBusSignalFlags.NONE, interfaces_added)
  bus.signal_subscribe(INPUTPLUMBER, PROPERTIES, "PropertiesChanged", None, COMPOSITE,
                       Gio.DBusSignalFlags.NONE, properties_changed)
  if profile in ("desktop", "osk"):
    # InputPlumber emits these custom actions from the desktop and OSK maps.
    # Releases are separate events.
    for action in DESKTOP_ACTIONS:
      bus.signal_subscribe(INPUTPLUMBER, INPUT_EVENTS, "InputEvent", None, action,
                           Gio.DBusSignalFlags.NONE, input_event)

  def stop(_fd, _condition):
    loop.quit()
    return GLib.SOURCE_REMOVE

  # Only the session supervisor holds the write end. EOF also stops the
  # observer if the supervisor dies while the session is running.
  GLibUnix.fd_add_full(GLib.PRIORITY_DEFAULT, sys.stdin.fileno(), GLib.IO_HUP | GLib.IO_ERR, stop)
  GLib.idle_add(first_load)
  try:
    loop.run()
  finally:
    # Send the restore after any in-flight load on this same bus connection.
    if loaded:
      request("pointer")


if __name__ == "__main__":
  if len(sys.argv) != 2 or sys.argv[1] not in ("desktop", "osk", "gaming"):
    sys.exit("Expected the desktop, osk or gaming profile")
  watch(sys.argv[1])
