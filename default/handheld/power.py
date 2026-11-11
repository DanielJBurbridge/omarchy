"""RC71L policy client for SteamOS Manager's public session D-Bus API.

No sysfs writes, privilege elevation or polling. Hardware access belongs to Manager.
See docs/rog-ally-power.md for the pinned API and deployment boundary.
"""

import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

BUS = "com.steampowered.SteamOSManager1"
PATH = "/com/steampowered/SteamOSManager1"
PROPS = "org.freedesktop.DBus.Properties"
UP_BUS = "org.freedesktop.UPower"
UP_PATH = "/org/freedesktop/UPower"
CONFLICTS = ("power-profiles-daemon", "powerstation", "hhd*", "adjustor", "asusd", "tlp", "auto-cpufreq", "tuned")
# control: (interface suffix, value property, signature, optional choices property)
CONTROLS = {
    "profile": ("PerformanceProfile1", "PerformanceProfile", "s", "AvailablePerformanceProfiles"),
    "tdp": ("TdpLimit1", "TdpLimit", "u", None),
    "boost": ("CpuBoost1", "CpuBoostState", "u", None),
    "governor": ("CpuScaling1", "CpuScalingGovernor", "s", "AvailableCpuScalingGovernors"),
    "gpu-level": ("GpuPerformanceLevel1", "GpuPerformanceLevel", "s", "AvailableGpuPerformanceLevels"),
    "gpu-clock": ("GpuPerformanceLevel1", "ManualGpuClock", "u", None),
    "charge": ("BatteryChargeLimit1", "MaxChargeLevel", "i", None),
}
UNAVAILABLE = {
    "burst": "Manager sets SPL/SPPT/FPPT together; independent boost watts are unavailable.",
    "cpu-frequency": "No CPU frequency limit API; use a supported governor.",
    "smt": "No SMT/core control API.",
    "fan": "No RC71L fan curve API; firmware retains fan control.",
    "bypass": "No charge inhibition/bypass API; a charge threshold is not bypass.",
    "temperature": "No temperature telemetry API; battery discharge watts are not APU watts.",
}


def state_dir():
    return Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "omarchy/ally-power"


def load(name):
    try:
        return json.loads((state_dir() / name).read_text())
    except FileNotFoundError:
        return {}


def save(name, value):
    directory = state_dir()
    directory.mkdir(parents=True, exist_ok=True)
    temporary = directory / (name + f".{os.getpid()}.tmp")
    temporary.write_text(json.dumps(value) + "\n")
    temporary.replace(directory / name)


@contextlib.contextmanager
def lock(name="policy.lock", blocking=True):
    state_dir().mkdir(parents=True, exist_ok=True)
    with (state_dir() / name).open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        yield


def hardware_guard():
    if subprocess.run(["omarchy-hw-rog-ally"], check=False).returncode:
        raise RuntimeError("This power client supports the original ASUS ROG Ally RC71L only.")


def conflicts():
    result = subprocess.run(
        ["systemctl", "list-units", "--state=active", "--no-legend", "--plain", *[s + ".service" for s in CONFLICTS]],
        text=True, capture_output=True, check=True,
    )
    active = [line.split()[0] for line in result.stdout.splitlines() if line.strip()]
    # GameMode can be D-Bus activated without a system unit. NameHasOwner does
    # not activate it; a live owner can otherwise change the same CPU governor.
    game_mode = subprocess.run(
        ["busctl", "--user", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
         "org.freedesktop.DBus", "NameHasOwner", "s", "com.feralinteractive.GameMode"],
        text=True, capture_output=True, check=True,
    )
    if game_mode.stdout.strip() == "b true":
        active.append("gamemoded")
    return active


class Manager:
    def __init__(self):
        from gi.repository import Gio, GLib
        self.Gio, self.GLib = Gio, GLib
        self.session = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.system = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

    def call(self, connection, bus, path, interface, method, args, signature=None):
        result = connection.call_sync(bus, path, interface, method, args,
                                      self.GLib.VariantType.new(signature) if signature else None,
                                      self.Gio.DBusCallFlags.NONE, 5000, None)
        return result.unpack()

    def get(self, suffix, prop):
        return self.call(self.session, BUS, PATH, PROPS, "Get",
                         self.GLib.Variant("(ss)", (BUS + "." + suffix, prop)), "(v)")[0]

    def on_battery(self):
        return self.call(self.system, UP_BUS, UP_PATH, PROPS, "Get",
                         self.GLib.Variant("(ss)", (UP_BUS, "OnBattery")), "(v)")[0]

    def source(self):
        # Failure must never be guessed as AC: that could enable a larger limit.
        return "battery" if self.on_battery() else "ac"

    def set(self, suffix, prop, signature, value):
        # Some setters (notably charging) acknowledge before their queued write
        # finishes. Subscribe first so even a fast completion cannot be missed.
        loop = self.GLib.MainLoop()

        def changed(connection, sender, path, interface, member, parameters):
            iface, values, invalidated = parameters.unpack()
            if iface == BUS + "." + suffix and (prop in values or prop in invalidated):
                loop.quit()

        subscription = self.session.signal_subscribe(BUS, PROPS, "PropertiesChanged", PATH, None,
                                                       self.Gio.DBusSignalFlags.NONE, changed)
        timer = self.GLib.timeout_add(1500, lambda: (loop.quit(), False)[1])
        try:
            self.call(self.session, BUS, PATH, PROPS, "Set",
                      self.GLib.Variant("(ssv)", (BUS + "." + suffix, prop, self.GLib.Variant(signature, value))))
            if self.get(suffix, prop) != value:
                loop.run()
        finally:
            self.session.signal_unsubscribe(subscription)
            if self.GLib.MainContext.default().find_source_by_id(timer):
                self.GLib.source_remove(timer)

    def wait_tdp(self):
        # Profile changes register TdpLimit1 asynchronously. Wait for its native
        # InterfacesAdded signal, with one final read on timeout; no polling.
        loop = self.GLib.MainLoop()
        subscription = self.session.signal_subscribe(
            BUS, "org.freedesktop.DBus.ObjectManager", "InterfacesAdded", None, None,
            self.Gio.DBusSignalFlags.NONE, lambda *args: loop.quit())
        timer = self.GLib.timeout_add(1500, lambda: (loop.quit(), False)[1])
        try:
            try:
                self.get("TdpLimit1", "TdpLimitMin")
            except Exception:
                loop.run()
            return self.get("TdpLimit1", "TdpLimitMin")
        finally:
            self.session.signal_unsubscribe(subscription)
            if self.GLib.MainContext.default().find_source_by_id(timer):
                self.GLib.source_remove(timer)


def capability(manager, name, source):
    suffix, prop, signature, choices = CONTROLS[name]
    try:
        value = manager.get(suffix, prop)
        result = {"available": True, "value": value}
        if choices:
            result["choices"] = manager.get(suffix, choices)
            if value not in result["choices"]:
                raise ValueError("Current value is absent from backend choices")
        if name in ("tdp", "gpu-clock"):
            low, high = (("TdpLimitMin", "TdpLimitMax") if name == "tdp" else ("ManualGpuClockMin", "ManualGpuClockMax"))
            result["min"] = manager.get(suffix, low)
            result["max"] = manager.get(suffix, high)
            if not (0 < result["min"] <= result["max"]):
                raise ValueError("Backend returned no valid range")
            if name == "tdp":
                # Conservative RC71L ceiling, intersected with the firmware range.
                result["max"] = min(result["max"], 25 if source == "battery" else 30)
                if result["min"] > result["max"] or value <= 0:
                    raise ValueError("TDP limit/range is unavailable")
        if name == "boost" and value not in (0, 1):
            raise ValueError("Unknown boost state")
        if name == "charge":
            result["min"] = max(1, manager.get(suffix, "SuggestedMinimumLimit"))
            result["max"] = 100
            if not (value == -1 or 1 <= value <= 100) or result["min"] > 100:
                raise ValueError("Unknown charging threshold")
        return result
    except Exception as error:
        return {"available": False, "reason": str(error)}


def snapshot(manager):
    try:
        source = manager.source()
        settings = {name: capability(manager, name, source) for name in CONTROLS}
        result = {"backend": "SteamOS Manager", "source": source, "controls": settings,
                  "unavailable": UNAVAILABLE, "conflicts": conflicts(),
                  "configured": (state_dir() / "enabled").exists()}
        if not any(cap["available"] for cap in settings.values()):
            result["error"] = "No readable Manager controls; check the package, services and kernel interfaces."
        return result
    except Exception as error:
        # Do not retain stale controls when the service or power-source read fails.
        return {"backend": "SteamOS Manager", "controls": {}, "error": str(error), "unavailable": UNAVAILABLE}


def validate(name, raw, cap):
    if not cap.get("available"):
        raise ValueError(cap.get("reason", "Control unavailable"))
    if CONTROLS[name][2] == "s":
        if raw not in cap["choices"]:
            raise ValueError("Choose one of: " + ", ".join(cap["choices"]))
        return raw
    # Documented public sentinel; RootManager maps -1 to the driver's default.
    if name == "charge" and str(raw) in ("default", "-1"):
        return -1
    # Reject fractions, signs, nonfinite values and scientific notation before D-Bus.
    if not str(raw).isascii() or not str(raw).isdecimal():
        raise ValueError("Use a whole number")
    value = int(raw)
    low, high = (0, 1) if name == "boost" else (cap["min"], cap["max"])
    if not low <= value <= high:
        raise ValueError(f"Allowed range: {low}–{high}")
    return value


def write_control(manager, name, raw):
    source = manager.source()
    cap = capability(manager, name, source)
    value = validate(name, raw, cap)
    if name == "gpu-clock" and manager.get("GpuPerformanceLevel1", "GpuPerformanceLevel") != "manual":
        raise ValueError("Select the manual GPU level before setting its clock")
    suffix, prop, signature, _ = CONTROLS[name]
    manager.set(suffix, prop, signature, value)
    # TdpLimit's getter is queued after its setter in Manager. This is a real
    # hardware read, not an optimistic echo of Properties.Set's success.
    actual = manager.get(suffix, prop)
    if actual != value:
        raise RuntimeError(f"{name}: requested {value}, backend read back {actual}; preference not saved")
    if name == "profile" and value == "performance":
        try:
            manager.wait_tdp()
        except Exception:
            pass  # Profile can work even when the kernel lacks the TDP attributes.
    return value


def require_owner():
    if not (state_dir() / "enabled").exists():
        raise RuntimeError("Run the reviewed-package power setup first; no power owner has been selected.")
    active = conflicts()
    if active:
        raise RuntimeError("Competing power writer active: " + ", ".join(active))


def remember(manager, name, raw):
    require_owner()
    with lock():
        original = load("original.json")
        if not original.get("controls", {}).get(name, {}).get("available"):
            # A capability may appear after setup (for example a later driver
            # load). Capture its first actual value before allowing a change.
            before = capability(manager, name, manager.source())
            if not before.get("available"):
                raise ValueError(before.get("reason", "Control unavailable"))
            original.setdefault("controls", {})[name] = before
            save("original.json", original)
        value = write_control(manager, name, raw)
        policy = load("preferences.json")
        source = manager.source()
        policy.setdefault(source, {})[name] = value
        # Quiet/balanced must not retain a hidden custom TDP preference.
        if name == "profile" and value != "performance":
            policy[source].pop("tdp", None)
        save("preferences.json", policy)
    return snapshot(manager)


def apply_values(manager, values, clamp=False):
    # Profile first (registers TDP); level before manual clock.
    errors = []
    for name in CONTROLS:
        if name in values:
            try:
                value = values[name]
                if name == "tdp" and clamp:
                    cap = capability(manager, name, manager.source())
                    if cap.get("available"):
                        value = max(cap["min"], min(cap["max"], value))
                write_control(manager, name, str(value))
            except Exception as error:
                errors.append(f"{name}: {error}")
    return errors


def override_values():
    try:
        with lock("game.lock", blocking=False):
            return {}  # No live holder: ignore a file left by SIGKILL.
    except BlockingIOError:
        return load("game.json")


def restore(manager):
    require_owner()
    with lock():
        values = load("preferences.json").get(manager.source(), {})
        values.update(override_values())
        errors = apply_values(manager, values, clamp=True)
    status = snapshot(manager)
    if errors:
        status["error"] = "; ".join(errors)
    return status


def watch(manager):
    require_owner()
    loop = manager.GLib.MainLoop()
    pending = {"refresh": False, "restore": False, "dirty": False}

    def publish():
        applying = pending["restore"]
        pending["restore"] = False
        pending["dirty"] = False
        try:
            status = restore(manager) if applying else snapshot(manager)
        except Exception as error:
            status = snapshot(manager)
            status["error"] = str(error)
        save("status.json", status)
        if status.get("error"):
            print(status["error"], file=sys.stderr, flush=True)
        pending["refresh"] = False
        if pending["dirty"]:
            schedule()
        return False

    def schedule(apply=False):
        pending["restore"] = pending["restore"] or apply
        pending["dirty"] = True
        if not pending["refresh"]:
            pending["refresh"] = True
            manager.GLib.idle_add(publish)

    def upower(connection, sender, path, interface, member, parameters, data=None):
        interface, changed, invalidated = parameters.unpack()
        if interface == UP_BUS and ("OnBattery" in changed or "OnBattery" in invalidated):
            schedule(True)

    def resume(connection, sender, path, interface, member, parameters, data=None):
        if parameters.unpack() == (False,):
            schedule(True)

    def owner(connection, sender, path, interface, member, parameters, data=None):
        name, old, new = parameters.unpack()
        schedule(bool(new))

    flags = manager.Gio.DBusSignalFlags.NONE
    manager.system.signal_subscribe(UP_BUS, PROPS, "PropertiesChanged", UP_PATH, None, flags, upower)
    manager.system.signal_subscribe("org.freedesktop.login1", "org.freedesktop.login1.Manager", "PrepareForSleep",
                                    "/org/freedesktop/login1", None, flags, resume)
    manager.session.signal_subscribe(BUS, PROPS, "PropertiesChanged", PATH, None, flags, lambda *args: schedule())
    manager.session.signal_subscribe(BUS, "org.freedesktop.DBus.ObjectManager", None, None, None, flags, lambda *args: schedule())
    manager.session.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
                                     "/org/freedesktop/DBus", BUS, flags, owner)
    schedule(True)
    loop.run()


def run_game(manager, watts, command):
    require_owner()
    if not command:
        raise ValueError("Supply a game command after --")
    with lock("game.lock", blocking=False):
        before = snapshot(manager)
        if before.get("error") or not before["controls"]["profile"]["available"]:
            raise RuntimeError("Cannot safely snapshot the original platform profile")
        if before["controls"]["profile"]["value"] == "performance" and not before["controls"]["tdp"]["available"]:
            raise RuntimeError("Cannot safely snapshot the original TDP")
        values = {name: cap["value"] for name, cap in before["controls"].items() if cap["available"]}
        # Manual clock only has meaning in manual mode.
        if values.get("gpu-level") != "manual":
            values.pop("gpu-clock", None)
        try:
            with lock():
                write_control(manager, "profile", "performance")
                write_control(manager, "tdp", watts)
                save("game.json", {"profile": "performance", "tdp": int(watts)})
            child = subprocess.Popen(command)
            previous = {}
            for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
                previous[sig] = signal.signal(sig, lambda signum, frame: child.send_signal(signum))
            try:
                return child.wait()
            finally:
                for sig, handler in previous.items():
                    signal.signal(sig, handler)
        finally:
            with lock():
                (state_dir() / "game.json").unlink(missing_ok=True)
                errors = apply_values(manager, values, clamp=True)
                # If unplugged while gaming, the current source policy wins.
                errors.extend(apply_values(manager, load("preferences.json").get(manager.source(), {}), clamp=True))
            if errors:
                raise RuntimeError("Game exited; power restore failed: " + "; ".join(errors))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    for action in ("status", "restore", "watch", "rollback", "initialise"):
        sub.add_parser(action)
    setter = sub.add_parser("set")
    setter.add_argument("control", choices=CONTROLS)
    setter.add_argument("value")
    game = sub.add_parser("run")
    game.add_argument("watts")
    game.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    hardware_guard()
    manager = Manager()
    if args.action == "watch":
        watch(manager)
    elif args.action == "run":
        command = args.command[1:] if args.command[:1] == ["--"] else args.command
        return run_game(manager, args.watts, command)
    elif args.action == "initialise":
        if not (state_dir() / "preferences.json").exists():
            original = load("original.json")
            values = {name: cap["value"] for name, cap in original.get("controls", {}).items() if cap.get("available")}
            if values.get("gpu-level") != "manual":
                values.pop("gpu-clock", None)
            battery = dict(values)
            if "tdp" in battery:
                battery["tdp"] = min(25, battery["tdp"])
            save("preferences.json", {"ac": values, "battery": battery})
    elif args.action == "rollback":
        require_owner()
        with lock():
            original = load("original.json")
            values = {name: cap["value"] for name, cap in original.get("controls", {}).items() if cap.get("available")}
            if values.get("gpu-level") != "manual":
                values.pop("gpu-clock", None)
            errors = apply_values(manager, values)
            if errors:
                raise RuntimeError("Rollback readback failed: " + "; ".join(errors))
    else:
        status = snapshot(manager) if args.action == "status" else (restore(manager) if args.action == "restore" else remember(manager, args.control, args.value))
        print(json.dumps(status))
        return 1 if status.get("error") else 0
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
