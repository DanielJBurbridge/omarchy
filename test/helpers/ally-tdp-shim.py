"""Exercise the real Steam shim and writer on a private D-Bus and firmware fixture."""

import os
import subprocess
from pathlib import Path

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

BUS = "com.steampowered.SteamOSManager1"
OBJECT = "/com/steampowered/SteamOSManager1"
TDP = BUS + ".TdpLimit1"
PROFILE = BUS + ".PerformanceProfile1"
MANAGER = BUS + ".Manager2"
SYSTEMD = "org.freedesktop.systemd1"
PROPS = "org.freedesktop.DBus.Properties"
DBUS = "org.freedesktop.DBus"
DBUS_PATH = "/org/freedesktop/DBus"
SYSTEMD_PATH = "/org/freedesktop/systemd1"
UNIT = "asusd.service"
UNIT_PATH = f"{SYSTEMD_PATH}/unit/{Gio.dbus_escape_object_path(UNIT)}"


class Events:
    def __init__(self):
        self.loop = GLib.MainLoop()
        self.pending = []
        self.wanted = None

    def put(self, event):
        self.pending.append(event)
        if event == self.wanted:
            self.loop.quit()

    def expect(self, event):
        if event not in self.pending:
            self.wanted = event
            timer = GLib.timeout_add_seconds(5, self.expire)
            self.loop.run()
            self.wanted = None
            assert event in self.pending, f"Missing {event!r}. Received {self.pending!r}."
            GLib.source_remove(timer)
        self.pending.remove(event)

    def expire(self):
        self.loop.quit()
        return GLib.SOURCE_REMOVE


env = os.environ.copy()
root = Path(env["OMARCHY_PATH"])
apply = root / "bin/omarchy-ally-tdp-apply"
lock = Path(env["OMARCHY_ALLY_TDP_LOCK"])
request = Path(env["OMARCHY_ALLY_TDP_STATE"]) / "request"
ac = Path(env["OMARCHY_ALLY_TDP_POWER"]) / "ADP1/online"
fppt = Path(env["OMARCHY_ALLY_TDP_ARMOURY"]) / "ppt_pl3_fppt/current_value"
owner = lock.with_name(lock.name + ".owner")
env.update(
    OMARCHY_ALLY_TDP_APPLY=str(apply),
    TEST_OWNER_STARTED=str(owner),
    DBUS_SYSTEM_BUS_ADDRESS=env["DBUS_SESSION_BUS_ADDRESS"],
)

events = Events()
connection = Gio.bus_get_sync(Gio.BusType.SESSION)


def call(bus, path, interface, method, params=None):
    return connection.call_sync(bus, path, interface, method, params, None, Gio.DBusCallFlags.NONE, 5000, None)


def set_property(interface, name, value):
    call(BUS, OBJECT, PROPS, "Set", GLib.Variant("(ssv)", (interface, name, value)))


call(DBUS, DBUS_PATH, DBUS, "RequestName", GLib.Variant("(su)", (SYSTEMD, 0)))
manager_node = Gio.DBusNodeInfo.new_for_xml(f'''<node>
  <interface name="{SYSTEMD}.Manager"><method name="Subscribe"/></interface>
</node>''')


def subscribed(_connection, _sender, _path, _interface, method, _params, invocation):
    events.put(method)
    invocation.return_value(None)


connection.register_object(SYSTEMD_PATH, manager_node.interfaces[0], subscribed, None, None)


def set_owner(active):
    if active:
        owner.touch()
    else:
        owner.unlink(missing_ok=True)
    signals = {"ActiveState": GLib.Variant("s", "active" if active else "inactive")}
    connection.emit_signal(None, UNIT_PATH, PROPS, "PropertiesChanged", GLib.Variant("(sa{sv}as)", (
        SYSTEMD + ".Unit", signals, [],
    )))


def run_writer(*args):
    subprocess.run([str(apply), *args], env=env, check=True, stdout=subprocess.DEVNULL)


def start_shim():
    shim = subprocess.Popen([str(root / "bin/omarchy-ally-tdp-shim")], env=env)
    try:
        events.expect("Subscribe")
        appeared = Gio.bus_watch_name_on_connection(
            connection, BUS, Gio.BusNameWatcherFlags.NONE,
            lambda *_args: events.put("owned"), None,
        )
        try:
            events.expect("owned")
        finally:
            Gio.bus_unwatch_name(appeared)
        return shim
    except BaseException:
        stop_shim(shim)
        raise


def stop_shim(shim):
    if shim.poll() is None:
        shim.terminate()
    shim.wait(timeout=5)


def properties_changed(_client, _object, proxy, changed, _invalidated):
    if proxy.get_interface_name() in (TDP, PROFILE):
        for name, value in changed.unpack().items():
            events.put((name, value))


def manager_client():
    client = Gio.DBusObjectManagerClient.new_sync(
        connection, Gio.DBusObjectManagerClientFlags.DO_NOT_AUTO_START, BUS, "/", None, None, None,
    )
    client.connect("interface-added", lambda _client, _object, proxy: events.put(("added", proxy.get_interface_name())))
    client.connect("interface-removed", lambda _client, _object, proxy: events.put(("removed", proxy.get_interface_name())))
    client.connect("interface-proxy-properties-changed", properties_changed)
    model = client.get_interface(OBJECT, MANAGER).get_cached_property("DeviceModel")
    assert model.unpack() == ("rog_ally", "RC71L")
    assert client.get_interface(OBJECT, BUS + ".GpuPerformanceLevel1") is None
    return client


def require_unsupported(client):
    introspect = call(BUS, OBJECT, DBUS + ".Introspectable", "Introspect").unpack()[0]
    for interface in (TDP, PROFILE):
        assert client.get_interface(OBJECT, interface) is None, f"ObjectManager still advertises {interface}"
        assert f'<interface name="{interface}">' not in introspect, f"{interface} still accepts direct calls"


def limits(client):
    proxy = client.get_interface(OBJECT, TDP)
    assert proxy is not None, "Steam discovery could not find TdpLimit1"
    return tuple(proxy.get_cached_property(name).get_uint32() for name in ("TdpLimit", "TdpLimitMin", "TdpLimitMax"))


def profile_proxy(client):
    proxy = client.get_interface(OBJECT, PROFILE)
    assert proxy is not None, "Steam discovery could not find PerformanceProfile1"
    assert proxy.get_cached_property("AvailablePerformanceProfiles").unpack() == [
        "low-power", "balanced", "performance", "custom",
    ]
    assert proxy.get_cached_property("SuggestedDefaultPerformanceProfile").unpack() == "balanced"
    return proxy


def test_foreign_owner():
    owner.touch()
    shim = start_shim()
    try:
        client = manager_client()
        require_unsupported(client)
        set_owner(False)
        events.expect(("added", TDP))
        events.expect(("added", PROFILE))
        assert limits(client) == (30, 7, 30)
        profile_proxy(client)
        set_owner(True)
        events.expect(("removed", TDP))
        events.expect(("removed", PROFILE))
        require_unsupported(client)
        set_owner(False)
        events.expect(("added", TDP))
        events.expect(("added", PROFILE))
        assert limits(client) == (30, 7, 30)
        profile_proxy(client)
        print("ok - external ownership removes and restores both Steam power interfaces")
    finally:
        stop_shim(shim)


test_foreign_owner()
shim = start_shim()
try:
    client = manager_client()
    assert limits(client) == (30, 7, 30)
    profile_proxy(client)
finally:
    stop_shim(shim)

fppt.rename(fppt.with_suffix(".missing"))
shim = start_shim()
try:
    client = manager_client()
    require_unsupported(client)
    fppt.with_suffix(".missing").rename(fppt)
    run_writer("--reassert")
    events.expect(("added", TDP))
    events.expect(("added", PROFILE))
    assert limits(client) == (30, 7, 30)
    profiles = profile_proxy(client)
    print("ok - initially absent firmware gains both power interfaces after the writer reports readiness")
    set_property(TDP, "TdpLimit", GLib.Variant("u", 30))
    assert request.read_text().splitlines() == ["30", "custom"]
    ac.write_text("0\n")
    run_writer("--reassert")
    events.expect(("TdpLimitMax", 20))
    events.expect(("TdpLimit", 20))
    assert limits(client) == (20, 7, 20)
    assert request.read_text().splitlines() == ["30", "custom"]

    set_property(PROFILE, "PerformanceProfile", GLib.Variant("s", "balanced"))
    events.expect(("PerformanceProfile", "balanced"))
    assert request.read_text().splitlines() == ["20", "balanced"]

    firmware = [
        fppt.parent.parent / attr / "current_value"
        for attr in ("ppt_pl1_spl", "ppt_pl2_sppt", "ppt_pl3_fppt")
    ]
    for path in firmware:
        os.utime(path, (1, 1))
    before_custom = [(path.read_text(), path.stat().st_mtime_ns) for path in firmware]
    set_property(PROFILE, "PerformanceProfile", GLib.Variant("s", "custom"))
    events.expect(("PerformanceProfile", "custom"))
    assert [(path.read_text(), path.stat().st_mtime_ns) for path in firmware] == before_custom
    assert request.read_text().splitlines() == ["20", "custom"]
    set_property(TDP, "TdpLimit", GLib.Variant("u", 18))
    events.expect(("TdpLimit", 18))
    set_property(TDP, "TdpLimit", GLib.Variant("u", 20))
    events.expect(("TdpLimit", 20))
    assert request.read_text().splitlines() == ["20", "custom"]
    assert profiles.get_cached_property("PerformanceProfile").unpack() == "custom"

    set_property(PROFILE, "PerformanceProfile", GLib.Variant("s", "low-power"))
    events.expect(("PerformanceProfile", "low-power"))
    events.expect(("TdpLimit", 7))
    assert request.read_text().splitlines() == ["7", "power-saver"]
    spl_min = firmware[0].with_name("min_value")
    spl_min.write_text("8\n")
    run_writer("--reassert")
    events.expect(("TdpLimit", 8))
    # The shim updates both interfaces together but sends separate signals.
    # An earlier marker event may have exposed Custom before the reassert.
    profile, = call(BUS, OBJECT, PROPS, "Get", GLib.Variant("(ss)", (PROFILE, "PerformanceProfile"))).unpack()
    assert profile == "low-power", profile
    spl_min.write_text("7\n")
    set_property(PROFILE, "PerformanceProfile", GLib.Variant("s", "performance"))
    events.expect(("PerformanceProfile", "performance"))
    events.expect(("TdpLimit", 20))
    assert request.read_text().splitlines() == ["30", "performance"]
    set_property(TDP, "TdpLimit", GLib.Variant("u", 20))
    assert request.read_text().splitlines() == ["30", "performance"], "Steam's slider echo discarded the preset"
    print("ok - Steam presets apply live TDP limits, and Custom keeps direct slider control")

    # A power change updates bounds even when no explicit request exists.
    request.unlink()
    ac.write_text("1\n")
    run_writer("--reassert")
    events.expect(("TdpLimitMax", 30))
    assert limits(client) == (20, 7, 30)
    print("ok - the Steam object manager receives current limits and bounds from external writer updates")
finally:
    stop_shim(shim)
