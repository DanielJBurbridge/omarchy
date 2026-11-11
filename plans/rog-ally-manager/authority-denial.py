"""DENIAL-ONLY private-bus credential proof. No grant issuer, policy or power writer.

Run as an ordinary user. Both buses are explicitly isolated. This demonstrates
real broker credentials/name loss, not a successful SDDM/logind/Polkit binding.
"""

import json
import os
from pathlib import Path
import select
import subprocess
import sys
import threading

from gi.repository import Gio, GLib

FLAGS = Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION
NAME = "org.omarchy.DenialFixture"
PATH = "/org/omarchy/DenialFixture"
IFACE = NAME + "1"
DBUS = "org.freedesktop.DBus"
DENIED = NAME + ".Denied"
XML = f"""<node><interface name="{IFACE}">
  <method name="GetCapabilityIdentity"><arg type="b" direction="out"/></method>
  <method name="RequestGrant"><arg type="s" direction="in"/></method>
  <method name="CaptureProfilePpt1"><arg type="ay" direction="in"/></method>
  <method name="ApplySustained1"><arg type="ay" direction="in"/></method>
  <method name="RestoreProfilePpt1"><arg type="ay" direction="in"/></method>
  <method name="GetTransaction1"><arg type="ay" direction="in"/></method>
</interface></node>"""


def connect(address):
    return Gio.DBusConnection.new_for_address_sync(address, FLAGS, None, None)


def broker(connection, method, signature, values):
    return connection.call_sync(DBUS, "/org/freedesktop/DBus", DBUS, method,
                                GLib.Variant(signature, values), None,
                                Gio.DBusCallFlags.NO_AUTO_START, 3000, None).unpack()


class Denial(Exception):
    pass


def credentials(connection, unique):
    if not Gio.dbus_is_unique_name(unique):
        raise Denial("UniqueNameRequired")
    try:
        values = broker(connection, "GetConnectionCredentials", "(s)", (unique,))[0]
    except GLib.Error as error:
        raise Denial("PeerGone") from error
    uid, pid = values.get("UnixUserID"), values.get("ProcessID")
    if type(uid) is not int or uid < 0 or type(pid) is not int or pid <= 0:
        raise Denial("IncompleteCredentials")
    return unique, uid, pid


class DenialEndpoint:
    """This fixture has no successful issuance path or hardware access code."""
    def __init__(self, connection):
        self.connection = connection
        self.observations = []
        self.lost = set()
        self.loss = threading.Event()

    def name_changed(self, connection, sender, path, interface, member, parameters):
        name, old, new = parameters.unpack()
        if Gio.dbus_is_unique_name(name) and old and not new:
            self.lost.add(name)
            self.loss.set()

    def request(self, connection, sender, path, interface, method, parameters, invocation):
        try:
            if method == "GetCapabilityIdentity":
                invocation.return_value(GLib.Variant("(b)", (False,)))
                return
            actor = credentials(connection, invocation.get_sender())
            # Audit data only; it cannot confer authority or affect host state.
            self.observations.append((method, actor))
            if method == "RequestGrant":
                proxy = credentials(connection, parameters.unpack()[0])
                if proxy[1] != actor[1]:
                    raise Denial("ProxyUidMismatch")
                try:
                    owner = broker(connection, "GetNameOwner", "(s)", ("org.freedesktop.login1",))[0]
                except GLib.Error as error:
                    raise Denial("NoTrustedLogind") from error
                if credentials(connection, owner)[1] != 0:
                    raise Denial("UntrustedLogindOwner")
                # Even UID 0 on a private fixture is not target login evidence.
                raise Denial("TargetSessionEvidenceUnavailable")
            # Unknown grants cannot enter capture/transaction/status paths.
            # No positive grant store or fake active-session evidence exists.
            raise Denial("UnknownGrant")
        except Denial as error:
            invocation.return_dbus_error(DENIED, str(error))


def client(address):
    connection = connect(address)
    print(json.dumps({"name": connection.get_unique_name(), "uid": os.getuid(), "pid": os.getpid()}), flush=True)
    for line in sys.stdin:
        request = json.loads(line)
        method, argument = request["method"], request.get("argument")
        value = GLib.Variant("(s)", (argument,)) if method == "RequestGrant" else GLib.Variant("(ay)", (bytes(16),))
        try:
            connection.call_sync(NAME, PATH, IFACE, method, value, None,
                                 Gio.DBusCallFlags.NO_AUTO_START, 3000, None)
            print(json.dumps({"unexpected_success": True}), flush=True)
        except GLib.Error as error:
            print(json.dumps({"error": Gio.DBusError.get_remote_error(error), "message": error.message}), flush=True)
    connection.close_sync(None)


def read_line(child):
    if not select.select([child.stdout], [], [], 5)[0]:
        raise AssertionError("Private client response timed out")
    return json.loads(child.stdout.readline())


def main():
    if os.getuid() == 0:
        raise SystemExit("Run this unprivileged fixture as an ordinary user")
    bus = Gio.TestDBus.new(Gio.TestDBusFlags.NONE)
    bus.up()
    address = bus.get_bus_address()
    os.environ["DBUS_SESSION_BUS_ADDRESS"] = address
    os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = address
    connection = connect(address)
    endpoint = DenialEndpoint(connection)
    loop = GLib.MainLoop()
    broker(connection, "RequestName", "(su)", (NAME, 0))
    registration = connection.register_object(PATH, Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0], endpoint.request, None, None)
    subscription = connection.signal_subscribe(DBUS, DBUS, "NameOwnerChanged", "/org/freedesktop/DBus", None,
                                                 Gio.DBusSignalFlags.NONE, endpoint.name_changed)
    thread = threading.Thread(target=loop.run)
    thread.start()
    children = []

    def spawn():
        # Bogus routing environment never reaches the broker-derived identity.
        env = dict(os.environ, XDG_SESSION_ID="not-an-authority", OMARCHY_HANDHELD_SESSION="not-an-authority")
        child = subprocess.Popen([sys.executable, "-B", str(Path(__file__).resolve()), "--client", address],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        children.append(child)
        return child, read_line(child)

    def denied(child, identity, method, reason, argument=None):
        child.stdin.write(json.dumps({"method": method, "argument": argument}) + "\n")
        child.stdin.flush()
        result = read_line(child)
        assert result.get("error") == DENIED and reason in result["message"], result
        assert endpoint.observations[-1][1] == (identity["name"], identity["uid"], identity["pid"])
        print("PASS: " + method + " " + reason + "; actual broker PID/UID verified", flush=True)

    try:
        first, identity = spawn()
        second, other = spawn()
        assert identity["pid"] == first.pid and other["pid"] == second.pid and first.pid != second.pid
        assert identity["uid"] == other["uid"] == os.getuid()
        denied(first, identity, "RequestGrant", "NoTrustedLogind", other["name"])
        denied(first, identity, "RequestGrant", "UniqueNameRequired", "com.steampowered.SteamOSManager1")
        # A private-bus peer owning a trusted-looking name is still not root.
        broker(connection, "RequestName", "(su)", ("org.freedesktop.login1", 0))
        denied(first, identity, "RequestGrant", "UntrustedLogindOwner", other["name"])
        for method in ("CaptureProfilePpt1", "ApplySustained1", "RestoreProfilePpt1", "GetTransaction1"):
            denied(second, other, method, "UnknownGrant")
        for method in ("SetDefaultSession", "SetWifiBackend", "UpdateBios", "FormatDevice", "InhibitDs"):
            second.stdin.write(json.dumps({"method": method}) + "\n")
            second.stdin.flush()
            result = read_line(second)
            assert result.get("error") == "org.freedesktop.DBus.Error.UnknownMethod", result
        print("PASS: non-power login/network/BIOS/storage/input methods absent from private endpoint", flush=True)
        endpoint.loss.clear()
        first.stdin.close()
        assert first.wait(timeout=5) == 0
        assert endpoint.loss.wait(5) and identity["name"] in endpoint.lost
        try:
            credentials(connection, identity["name"])
        except Denial as error:
            assert str(error) == "PeerGone"
        else:
            raise AssertionError("Disconnected unique name remained usable")
        print("PASS: real NameOwnerChanged and broker credentials reject disconnected peer", flush=True)
        denied(second, other, "RequestGrant", "PeerGone", identity["name"])
        print("BOUNDARY: no target logind/Polkit/session/grant issuance or hardware behaviour proved", flush=True)
    finally:
        for child in children:
            if child.poll() is None:
                child.terminate()
                child.wait(timeout=5)
        loop.quit()
        thread.join(timeout=5)
        connection.signal_unsubscribe(subscription)
        connection.unregister_object(registration)
        connection.close_sync(None)
        bus.down()


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--client":
        client(sys.argv[2])
    else:
        main()
