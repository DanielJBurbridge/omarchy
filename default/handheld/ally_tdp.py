"""RC71L sustained-power helper for Steam's session-bus TDP slider.

The shim owns com.steampowered.SteamOSManager1 on the user bus and implements
the public TdpLimit1 properties. Privileged writes go through
omarchy-ally-tdp-apply, which is the only PPT writer: it derives SPPT and
FPPT from the requested SPL, stays inside the current source's firmware
defaults on battery and the AC firmware ceiling, and never writes
platform_profile.

Property names follow the MIT-licensed SteamOS Manager interface
(com.steampowered.SteamOSManager1.TdpLimit1). This file does not vendor that
daemon.
"""

import json
import os
from pathlib import Path
import subprocess
import sys

BUS = "com.steampowered.SteamOSManager1"
OBJECT_PATH = "/com/steampowered/SteamOSManager1"
TDP_IFACE = BUS + ".TdpLimit1"
PROFILE_IFACE = BUS + ".PerformanceProfile1"
GPU_IFACE = BUS + ".GpuPerformanceLevel1"
MANAGER_IFACE = BUS + ".Manager2"
PROPS_IFACE = "org.freedesktop.DBus.Properties"

ATTRIBUTES = ("ppt_pl1_spl", "ppt_pl2_sppt", "ppt_pl3_fppt")
KEYS = {"ppt_pl1_spl": "spl", "ppt_pl2_sppt": "sppt", "ppt_pl3_fppt": "fppt"}
REAL_ARMOURY = "/sys/class/firmware-attributes/asus-armoury/attributes"
HANDHELD_VARIANT = "/var/lib/omarchy/variants/handheld"
AC_CAP = 30
PROFILE_NAME = "performance"
PPD_UNIT = "power-profiles-daemon.service"


class TdpError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


def emit(payload):
    sys.stdout.write(json.dumps(payload, sort_keys=True) + "\n")
    sys.stdout.flush()


def fail(status, message):
    print(f"ally-tdp: {message}", file=sys.stderr)
    emit({"error": message, "ok": False, "status": status})
    return 1


def armoury_root():
    return Path(os.environ.get("OMARCHY_ALLY_ARMOURY_PATH", REAL_ARMOURY))


def fixture_mode():
    return os.environ.get("OMARCHY_ALLY_TDP_FIXTURE") == "1"


def run_dir():
    return Path(os.environ.get("OMARCHY_ALLY_TDP_RUN_DIR", "/run/omarchy/ally-tdp"))


def state_dir():
    return Path(os.environ.get("OMARCHY_ALLY_TDP_STATE_DIR", "/var/lib/omarchy/ally-tdp"))


def supply_root():
    return Path(os.environ.get("OMARCHY_POWER_SUPPLY_PATH", "/sys/class/power_supply"))


def hwmon_root():
    return Path(os.environ.get("OMARCHY_ALLY_HWMON_PATH", "/sys/class/hwmon"))


def boot_id():
    override = os.environ.get("OMARCHY_ALLY_TDP_BOOT_ID")
    if override:
        return override
    try:
        return Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    except OSError:
        return "unknown"


def require_ally():
    try:
        result = subprocess.run(["omarchy-hw-rog-ally"], check=False)
    except OSError as error:
        raise TdpError("rejected", f"omarchy-hw-rog-ally could not run: {error}") from error
    if result.returncode != 0:
        raise TdpError("rejected", "this TDP path is only for the original ROG Ally RC71L")


def handheld_variant_installed():
    flag = os.environ.get("OMARCHY_ALLY_TDP_HANDHELD")
    if flag == "1":
        return True
    if flag == "0":
        return False
    return Path(os.environ.get("OMARCHY_HANDHELD_VARIANT_PATH", HANDHELD_VARIANT)).is_file()


def writer_installed():
    flag = os.environ.get("OMARCHY_ALLY_TDP_WRITER_INSTALLED")
    if flag == "1":
        return True
    if flag == "0":
        return False
    candidates = []
    root = os.environ.get("OMARCHY_PATH")
    if root:
        candidates.append(Path(root) / "bin" / "omarchy-ally-tdp-apply")
    candidates.append(Path("/usr/bin/omarchy-ally-tdp-apply"))
    return any(path.is_file() and os.access(path, os.X_OK) for path in candidates)


def require_owner():
    """Hardware gate plus the install gate. Writes and the PPD mask both use it."""
    require_ally()
    if not handheld_variant_installed():
        raise TdpError("rejected", "the handheld variant is not installed")
    if not writer_installed():
        raise TdpError("rejected", "the Ally TDP writer is not installed")


def owner_status():
    try:
        require_owner()
    except TdpError as error:
        text = str(error)
        if "not installed" in text and "variant" in text:
            return "variant"
        if "writer" in text:
            return "writer"
        return "hardware"
    return "open"


def assert_write_allowed():
    root = armoury_root().resolve()
    real = Path(REAL_ARMOURY).resolve()
    if fixture_mode():
        if root == real or str(root).startswith("/sys/"):
            raise TdpError("rejected", "fixture mode refuses the real firmware-attribute sysfs tree")
        return
    if os.geteuid() != 0:
        raise TdpError("rejected", "setting the Ally TDP limit must run as root")


def canonical_watts(text):
    if not isinstance(text, str) or not text.isascii() or not text.isdigit():
        raise TdpError("rejected", "the sustained limit must be a whole number of watts")
    if text != str(int(text)):
        raise TdpError("rejected", "the sustained limit must be a whole number of watts")
    return int(text)


def read_int_file(path):
    try:
        text = path.read_text().strip()
    except OSError as error:
        raise TdpError("rejected", f"cannot read {path.name}: {error}") from error
    if not text.isascii() or not text.isdigit() or text != str(int(text)):
        raise TdpError("rejected", f"{path.parent.name}/{path.name} is not a whole number")
    return int(text)


def attr_file(name, leaf):
    if name not in ATTRIBUTES and name != "mcu_powersave":
        raise TdpError("rejected", "unknown firmware attribute")
    root = armoury_root().resolve()
    path = (root / name / leaf).resolve()
    if path.parent.parent != root:
        raise TdpError("rejected", "firmware attribute path escapes the armoury directory")
    return path


def read_limit(name):
    current = read_int_file(attr_file(name, "current_value"))
    low = read_int_file(attr_file(name, "min_value"))
    high = read_int_file(attr_file(name, "max_value"))
    default_path = attr_file(name, "default_value")
    if default_path.is_file():
        default = read_int_file(default_path)
    else:
        default = high
    if low < 0 or high < low or default < 0:
        raise TdpError("rejected", f"{name} firmware range is unusable")
    return {"current": current, "default": default, "max": high, "min": low}


def read_live():
    try:
        return {KEYS[name]: read_limit(name) for name in ATTRIBUTES}
    except TdpError:
        raise
    except OSError as error:
        raise TdpError("rejected", f"asus-armoury PPT attributes are missing: {error}") from error


def power_source():
    root = supply_root()
    if not root.is_dir():
        raise TdpError("rejected", "power supply sysfs is missing; refusing to guess AC")
    saw_mains = False
    online = False
    try:
        supplies = sorted(root.iterdir())
    except OSError as error:
        raise TdpError("rejected", f"cannot read power supplies: {error}") from error
    for supply in supplies:
        type_file = supply / "type"
        online_file = supply / "online"
        if not type_file.is_file() or not online_file.is_file():
            continue
        try:
            kind = type_file.read_text().strip()
            state = online_file.read_text().strip()
        except OSError as error:
            raise TdpError("rejected", f"cannot read {supply.name}: {error}") from error
        if kind not in ("Mains", "USB"):
            continue
        saw_mains = True
        if state == "1":
            online = True
    if not saw_mains:
        raise TdpError("rejected", "no mains power supply; refusing to guess AC")
    return "ac" if online else "battery"


def load_json(path):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return None
    except (OSError, json.JSONDecodeError) as error:
        raise TdpError("rejected", f"cannot read {path.name}: {error}") from error


def save_json(path, payload):
    try:
        path.parent.mkdir(parents=True, mode=0o755, exist_ok=True)
        temporary = path.with_suffix(path.suffix + f".{os.getpid()}.tmp")
        temporary.write_text(json.dumps(payload, sort_keys=True) + "\n")
        os.chmod(temporary, 0o644)
        temporary.replace(path)
    except OSError as error:
        raise TdpError("rejected", f"cannot record {path.name}: {error}") from error


def ceilings_for(source, live, persist):
    path = run_dir() / "ceilings.json"
    stored = load_json(path) if path.is_file() else None
    if not isinstance(stored, dict) or stored.get("boot_id") != boot_id():
        stored = {"boot_id": boot_id(), "sources": {}}
    sources = stored.setdefault("sources", {})
    if source in sources:
        snapshot = sources[source]
        frozen = True
    else:
        snapshot = {key: {"default": live[key]["default"], "max": live[key]["max"], "min": live[key]["min"]} for key in live}
        sources[source] = snapshot
        frozen = False
        if persist:
            save_json(path, stored)
    for key in ("spl", "sppt", "fppt"):
        if key not in snapshot:
            raise TdpError("rejected", "stored PPT ceiling is incomplete")
    return snapshot, frozen


def anchor(limit):
    if limit["default"] > 0:
        return limit["default"]
    return limit["max"]


def round_div(numer, denom):
    if denom <= 0:
        raise TdpError("rejected", "firmware SPL default is zero")
    return (numer + denom // 2) // denom


def limit_ceiling(source, live, snapshot):
    """Highest integer this limit may be written as.

    Battery stays at or under the boot-captured firmware default. AC keeps the
    boot-captured maximum, which is also the default when the AC table has none.
    """
    if source == "battery":
        ceiling = snapshot["default"] if snapshot["default"] > 0 else snapshot["max"]
    else:
        ceiling = snapshot["max"]
    return min(ceiling, live["max"], snapshot["max"])


def spl_window(source, snapshot, live):
    spl_min = live["spl"]["min"]
    if source == "battery":
        spl_max = limit_ceiling(source, live["spl"], snapshot["spl"])
    else:
        spl_max = min(AC_CAP, live["spl"]["max"], snapshot["spl"]["max"])
    if spl_min > spl_max:
        raise TdpError("rejected", "the firmware SPL range does not overlap the Ally cap")
    return spl_min, spl_max


def commit_plan(requested, source, snapshot, live):
    spl_min, spl_max = spl_window(source, snapshot, live)
    if requested < spl_min or requested > spl_max:
        raise TdpError(
            "rejected",
            f"sustained limit {requested} W is outside {spl_min}–{spl_max} W on {source}",
        )
    spl_anchor = anchor(snapshot["spl"])
    derived = {
        "sppt": round_div(requested * anchor(snapshot["sppt"]), spl_anchor),
        "fppt": round_div(requested * anchor(snapshot["fppt"]), spl_anchor),
    }
    planned = {}
    for key in ("sppt", "fppt"):
        ceiling = limit_ceiling(source, live[key], snapshot[key])
        floor = live[key]["min"]
        if floor > ceiling:
            raise TdpError("rejected", "a burst limit floor is above its firmware ceiling")
        value = derived[key]
        if value > ceiling:
            noun = "defaults" if source == "battery" else "ceiling"
            raise TdpError("rejected", f"derived {key.upper()} {value} W is above the firmware {noun}")
        if value < floor:
            value = floor
        planned[key] = value
    if planned["sppt"] < requested or planned["fppt"] < planned["sppt"]:
        raise TdpError("rejected", "derived burst limits cannot stay inside the firmware ceiling")
    return requested, planned["sppt"], planned["fppt"]


def plan_targets(requested, source, snapshot, live, clamp):
    spl_min, spl_max = spl_window(source, snapshot, live)
    if clamp:
        requested = min(max(requested, spl_min), spl_max)
        for candidate in range(requested, spl_min - 1, -1):
            try:
                return commit_plan(candidate, source, snapshot, live)
            except TdpError:
                continue
        raise TdpError("rejected", "no sustained limit fits the firmware defaults")
    return commit_plan(requested, source, snapshot, live)


def effective_bounds(source, snapshot, live):
    spl_min, spl_max = spl_window(source, snapshot, live)
    for candidate in range(spl_max, spl_min - 1, -1):
        try:
            commit_plan(candidate, source, snapshot, live)
        except TdpError:
            continue
        return spl_min, candidate
    raise TdpError("rejected", "no sustained limit fits the firmware ceiling and the Ally cap")


def ppd_active():
    state = os.environ.get("OMARCHY_ALLY_TDP_PPD_STATE")
    if state == "active":
        return True
    if state == "inactive":
        return False
    if state is not None:
        raise TdpError("rejected", "unrecognised power-profiles-daemon state override")
    if fixture_mode():
        return False
    try:
        result = subprocess.run(
            ["systemctl", "is-active", "--quiet", "power-profiles-daemon.service"],
            check=False,
        )
    except OSError as error:
        raise TdpError("rejected", f"could not check power-profiles-daemon: {error}") from error
    return result.returncode == 0


def unit_active(unit, env_name):
    state = os.environ.get(env_name)
    if state == "active":
        return True
    if state == "inactive":
        return False
    if fixture_mode():
        return False
    try:
        result = subprocess.run(["systemctl", "is-active", "--quiet", unit], check=False)
    except OSError:
        return False
    return result.returncode == 0


def preference_path():
    return state_dir() / "preference.json"


def load_preference():
    payload = load_json(preference_path())
    if payload is None:
        return None
    requested = payload.get("requested_spl")
    if not isinstance(requested, int) or isinstance(requested, bool) or requested < 0:
        raise TdpError("rejected", "stored TDP request is unusable")
    return payload


def read_currents():
    return {name: read_int_file(attr_file(name, "current_value")) for name in ATTRIBUTES}


def write_current(name, value):
    path = attr_file(name, "current_value")
    path.write_text(f"{value}\n")
    got = read_int_file(path)
    if got != value:
        raise OSError(f"{name} read back {got} after writing {value}")


def restore_currents(original):
    unrestored = []
    for name, value in original.items():
        path = attr_file(name, "current_value")
        try:
            path.write_text(f"{value}\n")
        except OSError:
            pass
        try:
            got = read_int_file(path)
        except TdpError:
            unrestored.append(name)
            continue
        if got != value:
            unrestored.append(name)
    return unrestored


def apply_spl(requested, clamp, remember):
    require_owner()
    assert_write_allowed()
    if ppd_active():
        raise TdpError("rejected", "power-profiles-daemon is active; it still owns platform power")
    source = power_source()
    live = read_live()
    snapshot, frozen = ceilings_for(source, live, persist=True)
    spl, sppt, fppt = plan_targets(requested, source, snapshot, live, clamp=clamp)
    targets = {"ppt_pl1_spl": spl, "ppt_pl2_sppt": sppt, "ppt_pl3_fppt": fppt}
    original = read_currents()
    written = []
    try:
        for name in ATTRIBUTES:
            write_current(name, targets[name])
            written.append(name)
    except (OSError, TdpError) as error:
        unrestored = restore_currents(original)
        status = "rolled_back" if not unrestored else "partial"
        detail = str(error)
        raise TdpError(status, f"PPT write failed ({detail}); status {status}") from error
    readback = read_currents()
    if readback != targets:
        unrestored = restore_currents(original)
        status = "rolled_back" if not unrestored else "partial"
        raise TdpError(status, f"PPT readback did not match the derived limits; status {status}")
    requested_spl = requested if remember else load_requested(default=requested)
    save_json(
        preference_path(),
        {
            "applied_fppt": fppt,
            "applied_spl": spl,
            "applied_sppt": sppt,
            "requested_spl": requested_spl,
            "source": source,
        },
    )
    low, high = effective_bounds(source, snapshot, read_live())
    return {
        "ceilings_frozen": frozen,
        "effective_max": high,
        "effective_min": low,
        "fppt": fppt,
        "ok": True,
        "requested_spl": requested_spl,
        "source": source,
        "spl": spl,
        "sppt": sppt,
        "status": "applied",
    }


def load_requested(default):
    current = load_preference()
    if current is None:
        return default
    return current["requested_spl"]


def show_payload():
    source = power_source()
    live = read_live()
    snapshot, frozen = ceilings_for(source, live, persist=False)
    low, high = effective_bounds(source, snapshot, live)
    preference = load_preference() if preference_path().is_file() else None
    return {
        "asusd_active": unit_active("asusd.service", "OMARCHY_ALLY_TDP_ASUSD_STATE"),
        "cap": high,
        "ceilings_frozen": frozen,
        "current_fppt": live["fppt"]["current"],
        "current_spl": live["spl"]["current"],
        "current_sppt": live["sppt"]["current"],
        "effective_max": high,
        "effective_min": low,
        "fppt": live["fppt"],
        "ok": True,
        "ppd_active": ppd_active(),
        "preference": preference,
        "source": source,
        "spl": live["spl"],
        "sppt": live["sppt"],
        "status": "shown",
    }


def command_show():
    require_ally()
    emit(show_payload())
    return 0


def command_snapshot():
    require_owner()
    assert_write_allowed()
    source = power_source()
    live = read_live()
    ceilings_for(source, live, persist=True)
    emit({"ok": True, "source": source, "status": "snapshotted"})
    return 0


def command_set(argv):
    require_owner()
    if len(argv) != 1:
        raise TdpError("rejected", "set takes one whole-number watt argument and nothing else")
    requested = canonical_watts(argv[0])
    emit(apply_spl(requested, clamp=False, remember=True))
    return 0


def command_reassert():
    require_owner()
    preference = load_preference()
    if preference is None:
        emit({"ok": True, "status": "unchanged"})
        return 0
    result = apply_spl(preference["requested_spl"], clamp=True, remember=False)
    result["status"] = "reasserted"
    emit(result)
    return 0


def ppd_stamp_path():
    return state_dir() / "ppd-mask.json"


def run_systemctl(args):
    try:
        return subprocess.run(["systemctl", *args], check=False, text=True, capture_output=True)
    except OSError as error:
        raise TdpError("rejected", f"systemctl {' '.join(args)} failed: {error}") from error


def prepare_main(_argv):
    if _argv:
        raise TdpError("rejected", "prepare takes no arguments")
    if os.geteuid() != 0 and not fixture_mode():
        print("omarchy-ally-tdp-prepare must run as root.", file=sys.stderr)
        return 1
    status = owner_status()
    stamp = ppd_stamp_path()
    if status != "open":
        if stamp.is_file():
            payload = load_json(stamp) or {}
            previous = payload.get("previous")
            unmask = run_systemctl(["unmask", PPD_UNIT])
            if unmask.returncode != 0:
                raise TdpError("rejected", "could not unmask power-profiles-daemon")
            if previous in ("enabled", "enabled-runtime"):
                restore = run_systemctl(["enable", "--now", PPD_UNIT])
                if restore.returncode != 0:
                    raise TdpError("rejected", "could not restore power-profiles-daemon")
            try:
                stamp.unlink()
            except OSError as error:
                raise TdpError("rejected", f"could not clear the PPD mask record: {error}") from error
            print("power-profiles-daemon mask removed because the Ally TDP owner gate no longer applies.", file=sys.stderr)
        elif status == "hardware":
            print("Not an original ROG Ally RC71L; power-profiles-daemon is unchanged.", file=sys.stderr)
        elif status == "variant":
            print("Handheld variant is not installed; power-profiles-daemon is unchanged.", file=sys.stderr)
        else:
            print("Ally TDP writer is not installed; power-profiles-daemon is unchanged.", file=sys.stderr)
        return 0

    command_snapshot()
    asusd = run_systemctl(["is-active", "--quiet", "asusd.service"])
    if asusd.returncode == 0:
        print(
            "asusd is active. This command does not mask it. PPT limits can be overwritten until the Ally asusd mask task does.",
            file=sys.stderr,
        )
    if not stamp.is_file():
        enabled = run_systemctl(["is-enabled", PPD_UNIT])
        previous = enabled.stdout.strip().split()[0] if enabled.stdout.strip() else "unknown"
        if previous in ("masked", "masked-runtime"):
            print("power-profiles-daemon is already masked; leaving that mask alone.", file=sys.stderr)
            return 0
        save_json(stamp, {"previous": previous})
    masked = run_systemctl(["mask", "--now", PPD_UNIT])
    if masked.returncode != 0:
        try:
            stamp.unlink()
        except OSError:
            pass
        raise TdpError("rejected", "could not mask power-profiles-daemon")
    return 0


def apply_main(argv):
    if len(argv) == 1 and argv[0] == "--show":
        return command_show()
    if len(argv) == 1 and argv[0] == "--snapshot":
        return command_snapshot()
    if len(argv) == 1 and argv[0] == "--reassert":
        return command_reassert()
    if len(argv) >= 1 and argv[0] == "--set":
        return command_set(argv[1:])
    raise TdpError("rejected", "use --show, --snapshot, --set WATTS, or --reassert")


def hwmon_samples():
    root = hwmon_root()
    samples = []
    if not root.is_dir():
        return samples
    for device in sorted(root.glob("hwmon*")):
        try:
            name = (device / "name").read_text().strip() if (device / "name").is_file() else ""
        except OSError:
            continue
        for sensor in sorted(device.glob("power*_input")):
            label_path = device / (sensor.name.replace("_input", "_label"))
            try:
                label = label_path.read_text().strip() if label_path.is_file() else ""
                raw = sensor.read_text().strip()
            except OSError:
                continue
            if not raw.isascii() or not raw.isdigit():
                continue
            microwatts = int(raw)
            samples.append(
                {
                    "label": label,
                    "microwatts": microwatts,
                    "name": name,
                    "path": str(sensor),
                    "watts": microwatts / 1_000_000,
                }
            )
    return samples


def optional_int(name):
    path = armoury_root() / name / "current_value"
    if not path.is_file():
        return None
    try:
        return read_int_file(attr_file(name, "current_value"))
    except (TdpError, OSError):
        return None


def probe_main(_argv):
    require_ally()
    live = read_live()
    source = power_source()
    samples = hwmon_samples()
    payload = {
        "asusd_active": unit_active("asusd.service", "OMARCHY_ALLY_TDP_ASUSD_STATE"),
        "hwmon": samples,
        "limits": live,
        "mcu_powersave": optional_int("mcu_powersave"),
        "ok": True,
        "ppd_active": ppd_active(),
        "source": source,
    }
    if "--json" in _argv:
        if len(_argv) != 1:
            raise TdpError("rejected", "probe accepts only --json")
        emit(payload)
        return 0
    if _argv:
        raise TdpError("rejected", "probe accepts only --json")
    print("ROG Ally RC71L TDP probe (read-only; this command writes nothing)")
    print(f"source: {source}")
    for name in ATTRIBUTES:
        limit = live[KEYS[name]]
        print(
            f"{name} current/min/max/default: "
            f"{limit['current']}/{limit['min']}/{limit['max']}/{limit['default']}"
        )
    if payload["mcu_powersave"] is None:
        print("mcu_powersave: absent")
    else:
        print(f"mcu_powersave: {payload['mcu_powersave']} (read-only; suspend task owns changes)")
    print(f"power-profiles-daemon: {'active' if payload['ppd_active'] else 'inactive'}")
    print(f"asusd: {'active' if payload['asusd_active'] else 'inactive'}")
    if not samples:
        print("hwmon power*_input: none found")
    for sample in samples:
        label = sample["label"] or "(no label)"
        print(
            f"hwmon {sample['name'] or '(no name)'} {label} "
            f"{sample['path']}: {sample['microwatts']} uW ({sample['watts']:.3f} W)"
        )
    print(
        "Compare a package power sensor under sustained CPU+GPU load with ppt_pl1_spl current. "
        "power*_input is microwatts. If that sensor settles near the SPL integer, the integer is watts. "
        "amdgpu power1_input is often the GPU rail alone and can sit below the package limit. "
        "An idle sample does not confirm the unit."
    )
    return 0


def run_apply(args, privileged):
    if fixture_mode():
        binary = os.environ.get("OMARCHY_ALLY_TDP_APPLY")
        if not binary:
            root = os.environ.get("OMARCHY_PATH")
            if not root:
                raise TdpError("rejected", "OMARCHY_PATH is not set")
            binary = str(Path(root) / "bin" / "omarchy-ally-tdp-apply")
        command = [binary, *args]
    else:
        binary = "/usr/bin/omarchy-ally-tdp-apply"
        command = ["pkexec", binary, *args] if privileged else [binary, *args]
    try:
        result = subprocess.run(command, check=False, text=True, capture_output=True)
    except OSError as error:
        raise TdpError("rejected", f"cannot run the TDP helper: {error}") from error
    line = ""
    for candidate in reversed(result.stdout.splitlines()):
        if candidate.startswith("{"):
            line = candidate
            break
    if not line:
        detail = result.stderr.strip() or "the TDP helper returned no result"
        raise TdpError("rejected", detail)
    try:
        payload = json.loads(line)
    except json.JSONDecodeError as error:
        raise TdpError("rejected", f"the TDP helper returned invalid JSON: {error}") from error
    if result.returncode != 0 or not payload.get("ok"):
        raise TdpError(payload.get("status", "rejected"), payload.get("error", "TDP helper failed"))
    return payload


class Shim:
    def __init__(self):
        self.spl = 0
        self.spl_min = 0
        self.spl_max = 0
        self.profile = PROFILE_NAME
        self.gpu_level = "auto"

    def refresh_from(self, payload):
        if "current_spl" in payload:
            self.spl = int(payload["current_spl"])
        elif "spl" in payload and not isinstance(payload["spl"], dict):
            self.spl = int(payload["spl"])
        self.spl_min = int(payload["effective_min"])
        self.spl_max = int(payload["effective_max"])

    def seed(self):
        shown = run_apply(["--show"], privileged=False)
        self.refresh_from(shown)
        preference = shown.get("preference") or {}
        requested = preference.get("requested_spl")
        if not isinstance(requested, int):
            requested = self.spl
        legal = self.spl_min <= requested <= self.spl_max
        if preference.get("requested_spl") is None or not legal or requested != self.spl:
            clamped = min(max(requested, self.spl_min), self.spl_max)
            applied = run_apply(["--set", str(clamped)], privileged=True)
            self.refresh_from(applied)
        return shown


def shim_main(_argv):
    try:
        require_owner()
    except TdpError as error:
        print(f"ally-tdp-shim: {error}", file=sys.stderr)
        return 0
    import dbus
    import dbus.mainloop.glib
    from dbus.service import BusName, Object, method, signal
    from gi.repository import GLib

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    state = Shim()
    try:
        state.seed()
    except TdpError as error:
        print(f"ally-tdp-shim: TDP is visible but writes are refused ({error})", file=sys.stderr)

    bus = dbus.SessionBus()
    try:
        # BusName releases the well-known name when the object is collected.
        # The local has to stay referenced until the main loop returns.
        owned_name = BusName(BUS, bus, allow_replacement=False, replace_existing=False, do_not_queue=True)
    except dbus.exceptions.NameExistsException:
        print("ally-tdp-shim: com.steampowered.SteamOSManager1 is already owned", file=sys.stderr)
        return 1

    class Service(Object):
        def __init__(self):
            super().__init__(bus, OBJECT_PATH)

        @method(dbus.INTROSPECTABLE_IFACE, in_signature="", out_signature="s", path_keyword="object_path", connection_keyword="connection")
        def Introspect(self, object_path, connection):
            base = Object.Introspect(self, object_path, connection)
            manager = f'  <interface name="{MANAGER_IFACE}">\n'
            device = '    <property name="DeviceModel" type="(ss)" access="read"/>\n'
            if manager in base:
                base = base.replace(manager, manager + device, 1)
            extra = f"""  <interface name="{TDP_IFACE}">
    <property name="TdpLimit" type="u" access="readwrite"/>
    <property name="TdpLimitMin" type="u" access="read"/>
    <property name="TdpLimitMax" type="u" access="read"/>
  </interface>
  <interface name="{PROFILE_IFACE}">
    <property name="AvailablePerformanceProfiles" type="as" access="read"/>
    <property name="PerformanceProfile" type="s" access="readwrite"/>
    <property name="SuggestedDefaultPerformanceProfile" type="s" access="read"/>
  </interface>
  <interface name="{GPU_IFACE}">
    <property name="AvailableGpuPerformanceLevels" type="as" access="read"/>
    <property name="GpuPerformanceLevel" type="s" access="readwrite"/>
    <property name="ManualGpuClock" type="u" access="readwrite"/>
    <property name="ManualGpuClockMin" type="u" access="read"/>
    <property name="ManualGpuClockMax" type="u" access="read"/>
  </interface>
"""
            return base.replace("</node>\n", extra + "</node>\n")

        @signal(PROPS_IFACE, signature="sa{sv}as")
        def PropertiesChanged(self, interface, changed, invalidated):
            pass

        def _changed(self, interface, values):
            wrapped = dbus.Dictionary({}, signature="sv")
            for key, value in values.items():
                wrapped[key] = value
            self.PropertiesChanged(interface, wrapped, dbus.Array([], signature="s"))

        def _tdp_values(self):
            return {
                "TdpLimit": dbus.UInt32(state.spl),
                "TdpLimitMax": dbus.UInt32(state.spl_max),
                "TdpLimitMin": dbus.UInt32(state.spl_min),
            }

        def _get(self, interface, prop):
            if interface == TDP_IFACE:
                values = self._tdp_values()
                if prop not in values:
                    raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.UnknownProperty", prop)
                return values[prop]
            if interface == PROFILE_IFACE:
                if prop == "AvailablePerformanceProfiles":
                    return dbus.Array([PROFILE_NAME], signature="s")
                if prop in ("PerformanceProfile", "SuggestedDefaultPerformanceProfile"):
                    return dbus.String(state.profile)
                raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.UnknownProperty", prop)
            if interface == GPU_IFACE:
                if prop == "AvailableGpuPerformanceLevels":
                    return dbus.Array(["auto"], signature="s")
                if prop == "GpuPerformanceLevel":
                    return dbus.String(state.gpu_level)
                if prop in ("ManualGpuClock", "ManualGpuClockMin", "ManualGpuClockMax"):
                    return dbus.UInt32(0)
                raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.UnknownProperty", prop)
            if interface == MANAGER_IFACE and prop == "DeviceModel":
                return dbus.Struct((dbus.String("rog_ally"), dbus.String("RC71L")), signature="ss")
            raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.UnknownProperty", prop)

        @method(PROPS_IFACE, in_signature="ss", out_signature="v")
        def Get(self, interface, prop):
            return self._get(interface, prop)

        @method(PROPS_IFACE, in_signature="s", out_signature="a{sv}")
        def GetAll(self, interface):
            if interface == TDP_IFACE:
                return dbus.Dictionary(self._tdp_values(), signature="sv")
            if interface == PROFILE_IFACE:
                return dbus.Dictionary(
                    {
                        "AvailablePerformanceProfiles": dbus.Array([PROFILE_NAME], signature="s"),
                        "PerformanceProfile": dbus.String(state.profile),
                        "SuggestedDefaultPerformanceProfile": dbus.String(PROFILE_NAME),
                    },
                    signature="sv",
                )
            if interface == GPU_IFACE:
                return dbus.Dictionary(
                    {
                        "AvailableGpuPerformanceLevels": dbus.Array(["auto"], signature="s"),
                        "GpuPerformanceLevel": dbus.String("auto"),
                        "ManualGpuClock": dbus.UInt32(0),
                        "ManualGpuClockMax": dbus.UInt32(0),
                        "ManualGpuClockMin": dbus.UInt32(0),
                    },
                    signature="sv",
                )
            if interface == MANAGER_IFACE:
                return dbus.Dictionary(
                    {"DeviceModel": dbus.Struct((dbus.String("rog_ally"), dbus.String("RC71L")), signature="ss")},
                    signature="sv",
                )
            raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.UnknownInterface", interface)

        @method(PROPS_IFACE, in_signature="ssv", out_signature="")
        def Set(self, interface, prop, value):
            if interface == TDP_IFACE and prop == "TdpLimit":
                if isinstance(value, bool) or not isinstance(value, int):
                    raise dbus.exceptions.DBusException(
                        "org.freedesktop.DBus.Error.InvalidArgs",
                        "TdpLimit is a whole number of watts",
                    )
                try:
                    applied = run_apply(["--set", str(int(value))], privileged=True)
                except TdpError as error:
                    raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs", str(error)) from error
                state.refresh_from(applied)
                self._changed(TDP_IFACE, {"TdpLimit": dbus.UInt32(state.spl)})
                return
            if interface == PROFILE_IFACE and prop == "PerformanceProfile":
                if str(value) != PROFILE_NAME:
                    raise dbus.exceptions.DBusException(
                        "org.freedesktop.DBus.Error.InvalidArgs",
                        "only the performance profile is advertised, and platform_profile is not written",
                    )
                return
            if interface == GPU_IFACE and prop == "GpuPerformanceLevel":
                if str(value) != "auto":
                    raise dbus.exceptions.DBusException(
                        "org.freedesktop.DBus.Error.NotSupported",
                        "manual GPU clocks are not provided",
                    )
                return
            if interface == GPU_IFACE and prop == "ManualGpuClock":
                raise dbus.exceptions.DBusException(
                    "org.freedesktop.DBus.Error.NotSupported",
                    "manual GPU clocks are not provided",
                )
            raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.UnknownProperty", prop)

        @method(MANAGER_IFACE, in_signature="", out_signature="")
        def ReloadConfig(self):
            try:
                shown = run_apply(["--show"], privileged=False)
                state.refresh_from(shown)
            except TdpError as error:
                print(f"ally-tdp-shim: reload failed ({error})", file=sys.stderr)

    service = Service()
    service.name_owner = owned_name

    def reassert_on_wake(asleep=False):
        if asleep:
            return
        try:
            applied = run_apply(["--reassert"], privileged=True)
        except TdpError as error:
            print(f"ally-tdp-shim: resume reassert failed ({error})", file=sys.stderr)
            return
        if applied.get("status") == "unchanged":
            return
        previous = state.spl
        state.refresh_from(applied)
        if state.spl != previous:
            service._changed(TDP_IFACE, self_tdp(state))

    def self_tdp(current):
        return {
            "TdpLimit": dbus.UInt32(current.spl),
            "TdpLimitMax": dbus.UInt32(current.spl_max),
            "TdpLimitMin": dbus.UInt32(current.spl_min),
        }

    if (not fixture_mode()) or os.environ.get("OMARCHY_ALLY_TDP_WATCH_SYSTEM") == "1":
        try:
            system = dbus.SystemBus()
            system.add_signal_receiver(
                reassert_on_wake,
                signal_name="PrepareForSleep",
                dbus_interface="org.freedesktop.login1.Manager",
                path="/org/freedesktop/login1",
            )

            def power_changed(_iface, changed, _invalidated):
                if "OnBattery" not in changed:
                    return
                reassert_on_wake(False)

            system.add_signal_receiver(
                power_changed,
                signal_name="PropertiesChanged",
                dbus_interface=PROPS_IFACE,
                path="/org/freedesktop/UPower",
            )
        except Exception as error:
            print(f"ally-tdp-shim: not watching resume or AC ({error})", file=sys.stderr)

    print("ally-tdp-shim: ready", file=sys.stderr, flush=True)
    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        return 0
    return 0


def main(argv):
    if len(argv) < 2:
        return fail("rejected", "missing mode")
    mode = argv[1]
    try:
        if mode == "apply":
            return apply_main(argv[2:])
        if mode == "prepare":
            return prepare_main(argv[2:])
        if mode == "probe":
            return probe_main(argv[2:])
        if mode == "shim":
            return shim_main(argv[2:])
        return fail("rejected", f"unknown mode {mode}")
    except TdpError as error:
        return fail(error.status, str(error))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
