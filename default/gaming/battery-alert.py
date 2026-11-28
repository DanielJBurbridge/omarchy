"""Forward the system battery's low warning while the Gaming notifier owns the bus."""

import subprocess
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

UPOWER = "org.freedesktop.UPower"
NOTIFICATIONS = "org.freedesktop.Notifications"
LOW_BATTERY_PERCENT = 10
DISCHARGING = 2


def main():
    notifier_pid = int(sys.argv[1])
    battery = Gio.DBusProxy.new_for_bus_sync(
        Gio.BusType.SYSTEM, Gio.DBusProxyFlags.NONE, None, UPOWER,
        "/org/freedesktop/UPower/devices/DisplayDevice", UPOWER + ".Device", None,
    )
    notified = False
    gaming_notifier = False

    def check(*_args):
        nonlocal notified
        present = battery.get_cached_property("IsPresent")
        percentage = battery.get_cached_property("Percentage")
        state = battery.get_cached_property("State")
        if not present or not present.get_boolean() or percentage is None or state is None:
            return
        value = percentage.get_double()
        if not 0 <= value <= 100:
            return
        level = int(value + 0.5)
        if level > LOW_BATTERY_PERCENT:
            notified = False
        elif gaming_notifier and not notified and state.get_uint32() == DISCHARGING:
            notified = True
            subprocess.run(["omarchy-battery-low", str(level)], check=False)

    def notifier_appeared(connection, _name, owner):
        nonlocal gaming_notifier
        try:
            pid, = connection.call_sync(
                "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                "GetConnectionUnixProcessID", GLib.Variant("(s)", (owner,)),
                GLib.VariantType.new("(u)"), Gio.DBusCallFlags.NONE, 1000, None,
            ).unpack()
        except GLib.Error:
            return
        gaming_notifier = pid == notifier_pid
        check()

    def notifier_vanished(*_args):
        nonlocal gaming_notifier
        gaming_notifier = False

    battery.connect("g-properties-changed", check)
    battery.connect("notify::g-name-owner", check)
    Gio.bus_watch_name(
        Gio.BusType.SESSION, NOTIFICATIONS, Gio.BusNameWatcherFlags.NONE,
        notifier_appeared, notifier_vanished,
    )
    GLib.MainLoop().run()


if __name__ == "__main__":
    try:
        main()
    except GLib.Error as error:
        print(f"Gaming battery warning is unavailable: {error.message}", file=sys.stderr)
