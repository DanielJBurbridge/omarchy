"""Fixture tests for the RC71L TDP writer and the Steam session-bus shim."""

import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import textwrap
import threading
import time

ROOT = Path(os.environ["OMARCHY_TEST_ROOT"])
APPLY = ROOT / "bin" / "omarchy-ally-tdp-apply"
PROBE = ROOT / "bin" / "omarchy-ally-tdp-probe"
SHIM = ROOT / "bin" / "omarchy-ally-tdp-shim"
PREPARE = ROOT / "bin" / "omarchy-ally-tdp-prepare"
BUS = "com.steampowered.SteamOSManager1"
PATH = "/com/steampowered/SteamOSManager1"
TDP = BUS + ".TdpLimit1"


def ok(description):
    print(f"ok - {description}")


def fail(description, detail=""):
    if detail:
        print(detail)
    print(f"not ok - {description}")
    raise SystemExit(1)


def write_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def limit(directory, name, current, low, high, default):
    base = directory / name
    base.mkdir(parents=True, exist_ok=True)
    (base / "current_value").write_text(f"{current}\n")
    (base / "min_value").write_text(f"{low}\n")
    (base / "max_value").write_text(f"{high}\n")
    (base / "default_value").write_text(f"{default}\n")


def currents(directory):
    return tuple(int((directory / name / "current_value").read_text()) for name in ("ppt_pl1_spl", "ppt_pl2_sppt", "ppt_pl3_fppt"))


def rc71_ac(directory):
    limit(directory, "ppt_pl1_spl", 30, 7, 30, 30)
    limit(directory, "ppt_pl2_sppt", 43, 15, 43, 43)
    limit(directory, "ppt_pl3_fppt", 53, 15, 53, 53)


def rc71_dc(directory, current=(15, 20, 25)):
    limit(directory, "ppt_pl1_spl", current[0], 7, 25, 15)
    limit(directory, "ppt_pl2_sppt", current[1], 15, 30, 20)
    limit(directory, "ppt_pl3_fppt", current[2], 15, 35, 25)


def layout(root, product="ROG Ally RC71L_RC71L", board="RC71L", vendor="ASUSTeK COMPUTER INC.", online="1"):
    dmi = root / "dmi"
    write_text(dmi / "sys_vendor", vendor + "\n")
    write_text(dmi / "product_name", product + "\n")
    write_text(dmi / "board_name", board + "\n")
    write_text(root / "supply" / "ADP" / "type", "Mains\n")
    write_text(root / "supply" / "ADP" / "online", online + "\n")
    write_text(root / "platform_profile", "quiet\n")
    armoury = root / "armoury"
    armoury.mkdir(parents=True, exist_ok=True)
    return armoury


def environment(root, **extra):
    handheld = extra.pop("handheld", True)
    variant = root / "variant" / "handheld"
    if handheld:
        write_text(variant, "handheld\n")
    env = {
        "PATH": f"{ROOT / 'bin'}:/usr/bin:/bin",
        "OMARCHY_PATH": str(ROOT),
        "OMARCHY_ALLY_TDP_FIXTURE": "1",
        "OMARCHY_ALLY_ARMOURY_PATH": str(root / "armoury"),
        "OMARCHY_POWER_SUPPLY_PATH": str(root / "supply"),
        "OMARCHY_ALLY_HWMON_PATH": str(root / "hwmon"),
        "OMARCHY_ALLY_TDP_STATE_DIR": str(root / "state"),
        "OMARCHY_ALLY_TDP_RUN_DIR": str(root / "run"),
        "OMARCHY_ALLY_TDP_BOOT_ID": extra.pop("boot_id", "boot-1"),
        "OMARCHY_HANDHELD_VARIANT_PATH": str(variant),
        "OMARCHY_DMI_SYS_VENDOR_PATH": str(root / "dmi" / "sys_vendor"),
        "OMARCHY_DMI_PRODUCT_NAME_PATH": str(root / "dmi" / "product_name"),
        "OMARCHY_DMI_BOARD_NAME_PATH": str(root / "dmi" / "board_name"),
        "HOME": str(root / "home"),
        "XDG_STATE_HOME": str(root / "home" / ".local" / "state"),
    }
    env.update(extra)
    return env


def run(cmd, env, check=False):
    result = subprocess.run(cmd, env=env, text=True, capture_output=True, check=False)
    if check and result.returncode != 0:
        fail(f"{Path(cmd[0]).name} succeeds", result.stderr + result.stdout)
    return result


def payload_of(result):
    for line in reversed(result.stdout.splitlines()):
        if line.startswith("{"):
            return json.loads(line)
    return None


def start_bus():
    result = subprocess.run(
        ["dbus-daemon", "--session", "--fork", "--print-address=1", "--print-pid=2"],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        fail("private bus starts", result.stderr)
    return result.stdout.strip(), int(result.stderr.strip())


def test_rejects_without_writes(root, armoury, env, args, description):
    before = currents(armoury)
    result = run([str(APPLY), *args], env)
    after = currents(armoury)
    body = payload_of(result) or {}
    if result.returncode == 0 or after != before or body.get("status") not in ("rejected", "rolled_back", "partial"):
        fail(description, f"code={result.returncode} before={before} after={after} out={result.stdout} err={result.stderr}")
    if (root / "platform_profile").read_text() != "quiet\n":
        fail(description + " leaves platform profile alone")
    ok(description)


def policy_cases():
    with tempfile.TemporaryDirectory(prefix="ally-tdp-") as temporary:
        root = Path(temporary)
        armoury = layout(root)
        rc71_ac(armoury)
        env = environment(root)

        result = run([str(APPLY), "--set", "15"], env, check=True)
        body = payload_of(result)
        if currents(armoury) != (15, 22, 27) or body.get("requested_spl") != 15:
            fail("15 W on AC derives the stock 43/30 and 53/30 bursts", f"{currents(armoury)} {body}")
        ok("15 W on AC derives the stock 43/30 and 53/30 bursts")

        result = run([str(APPLY), "--set", "10"], env, check=True)
        if currents(armoury) != (10, 15, 18):
            fail("10 W on AC lifts bursts to the firmware floor", str(currents(armoury)))
        ok("10 W on AC lifts bursts to the firmware floor")

        result = run([str(APPLY), "--set", "30"], env, check=True)
        if currents(armoury) != (30, 43, 53):
            fail("30 W on AC restores the stock AC tuple", str(currents(armoury)))
        ok("30 W on AC restores the stock AC tuple")

        for args, description in (
            (["--set", "31"], "31 W on AC is rejected"),
            (["--set", "6"], "a value below the firmware minimum is rejected"),
            (["--set", "-1"], "a negative limit is rejected"),
            (["--set", "15.5"], "a fractional limit is rejected"),
            (["--set", "1e1"], "scientific notation is rejected"),
            (["--set", "+15"], "an explicit plus sign is rejected"),
            (["--set", "015"], "leading zeros are rejected"),
            (["--set", "15", "extra"], "an extra argument is rejected"),
            (["--set"], "a missing watt value is rejected"),
            (["--write", "15"], "a generic write verb is rejected"),
        ):
            test_rejects_without_writes(root, armoury, env, args, description)

        # Ceiling is frozen at the first successful read for this boot.
        for name, default, high in (("ppt_pl2_sppt", 99, 99), ("ppt_pl3_fppt", 99, 99)):
            (armoury / name / "default_value").write_text(f"{default}\n")
            (armoury / name / "max_value").write_text(f"{high}\n")
        result = run([str(APPLY), "--set", "30"], env, check=True)
        if currents(armoury) != (30, 43, 53):
            fail("a later firmware max cannot raise the boot ceiling", str(currents(armoury)))
        ok("a later firmware max cannot raise the boot ceiling")

        raised = environment(root, boot_id="boot-2")
        result = run([str(APPLY), "--set", "30"], raised, check=True)
        if currents(armoury) != (30, 99, 99):
            fail("a new boot reads the firmware defaults again", str(currents(armoury)))
        ok("a new boot reads the firmware defaults again")

    with tempfile.TemporaryDirectory(prefix="ally-tdp-dc-") as temporary:
        root = Path(temporary)
        armoury = layout(root, online="0")
        rc71_dc(armoury, current=(15, 20, 25))
        env = environment(root)
        result = run([str(APPLY), "--set", "15"], env, check=True)
        body = payload_of(result)
        if currents(armoury) != (15, 20, 25) or body.get("source") != "battery" or body.get("effective_max") != 20:
            fail("15 W on battery stays under the ordering cap", f"{currents(armoury)} {result.stdout}")
        ok("15 W on battery stays under the ordering cap")
        result = run([str(APPLY), "--set", "16"], env, check=True)
        if currents(armoury) != (16, 20, 25):
            fail("16 W on battery clamps the bursts to the DC defaults", str(currents(armoury)))
        ok("16 W on battery clamps the bursts to the DC defaults")
        result = run([str(APPLY), "--set", "20"], env, check=True)
        if currents(armoury) != (20, 20, 25) or payload_of(result).get("effective_max") != 20:
            fail("20 W on battery is the ordering cap", f"{currents(armoury)} {result.stdout}")
        ok("20 W on battery is the ordering cap")
        result = run([str(APPLY), "--set", "25"], env, check=True)
        preference = json.loads((root / "state" / "preference.json").read_text())
        if currents(armoury) != (20, 20, 25) or preference.get("requested_spl") != 25:
            fail("25 W on battery clamps to 20/20/25", f"{currents(armoury)} {preference}")
        ok("25 W on battery clamps to 20/20/25")
        test_rejects_without_writes(root, armoury, env, ["--set", "26"], "26 W on battery is outside the absolute window")
        result = run([str(APPLY), "--set", "14"], env, check=True)
        if currents(armoury) != (14, 19, 23):
            fail("14 W on battery derives bursts under the DC defaults", str(currents(armoury)))
        ok("14 W on battery derives bursts under the DC defaults")

        for name, default, high in (("ppt_pl1_spl", 20, 25), ("ppt_pl2_sppt", 30, 40), ("ppt_pl3_fppt", 35, 45)):
            (armoury / name / "default_value").write_text(f"{default}\n")
            (armoury / name / "max_value").write_text(f"{high}\n")
        result = run([str(APPLY), "--set", "21"], env, check=True)
        if currents(armoury) != (20, 20, 25):
            fail("a later DC default cannot raise this boot's battery cap", str(currents(armoury)))
        ok("a later DC default cannot raise this boot's battery cap")
        raised = environment(root, boot_id="boot-dc-2")
        result = run([str(APPLY), "--set", "21"], raised, check=True)
        if currents(armoury) != (21, 30, 35):
            fail("a new boot reads the DC defaults again", str(currents(armoury)))
        ok("a new boot reads the DC defaults again")

    with tempfile.TemporaryDirectory(prefix="ally-tdp-dc-tight-") as temporary:
        root = Path(temporary)
        armoury = layout(root, online="0")
        limit(armoury, "ppt_pl1_spl", 12, 7, 25, 12)
        limit(armoury, "ppt_pl2_sppt", 16, 15, 30, 16)
        limit(armoury, "ppt_pl3_fppt", 20, 15, 35, 20)
        env = environment(root)
        shown = run([str(APPLY), "--show"], env, check=True)
        if payload_of(shown).get("effective_max") != 16:
            fail("the battery cap is the highest SPL that keeps order", shown.stdout)
        ok("the battery cap is the highest SPL that keeps order")
        result = run([str(APPLY), "--set", "16"], env, check=True)
        if currents(armoury) != (16, 16, 20):
            fail("the battery tuple follows a non-stock DC default", str(currents(armoury)))
        ok("the battery tuple follows a non-stock DC default")
        test_rejects_without_writes(root, armoury, env, ["--set", "26"], "a watt above the battery absolute window is rejected")

    with tempfile.TemporaryDirectory(prefix="ally-tdp-ratio-") as temporary:
        root = Path(temporary)
        armoury = layout(root)
        limit(armoury, "ppt_pl1_spl", 10, 5, 20, 10)
        limit(armoury, "ppt_pl2_sppt", 20, 5, 40, 20)
        limit(armoury, "ppt_pl3_fppt", 40, 5, 80, 40)
        env = environment(root)
        result = run([str(APPLY), "--set", "15"], env, check=True)
        if currents(armoury) != (15, 30, 60):
            fail("burst ratio comes from the fixture defaults", str(currents(armoury)))
        ok("burst ratio comes from the fixture defaults")

    with tempfile.TemporaryDirectory(prefix="ally-tdp-rollback-") as temporary:
        root = Path(temporary)
        armoury = layout(root)
        rc71_ac(armoury)
        env = environment(root)
        target = armoury / "ppt_pl2_sppt" / "current_value"
        target.chmod(0o444)
        result = run([str(APPLY), "--set", "15"], env)
        target.chmod(0o644)
        body = payload_of(result) or {}
        if result.returncode == 0 or currents(armoury) != (30, 43, 53) or body.get("status") != "rolled_back":
            fail("a failed burst write restores the original tuple", f"{currents(armoury)} {result.stdout} {result.stderr}")
        ok("a failed burst write restores the original tuple")

    with tempfile.TemporaryDirectory(prefix="ally-tdp-ppd-") as temporary:
        root = Path(temporary)
        armoury = layout(root)
        rc71_ac(armoury)
        env = environment(root, OMARCHY_ALLY_TDP_PPD_STATE="active")
        test_rejects_without_writes(root, armoury, env, ["--set", "15"], "an active power-profiles-daemon blocks writes")

    for product, board, vendor, description in (
        ("ROG Strix G16", "GU605CX", "ASUSTeK COMPUTER INC.", "a ROG laptop is not given a TDP writer"),
        ("ROG Ally X RC72LA", "RC72LA", "ASUSTeK COMPUTER INC.", "the Ally X is not given this writer"),
        ("ROG Ally RC71L", "RC71L", "LENOVO", "another vendor is not given this writer"),
    ):
        with tempfile.TemporaryDirectory(prefix="ally-tdp-gate-") as temporary:
            root = Path(temporary)
            armoury = layout(root, product=product, board=board, vendor=vendor)
            rc71_ac(armoury)
            env = environment(root)
            test_rejects_without_writes(root, armoury, env, ["--set", "15"], description)

    with tempfile.TemporaryDirectory(prefix="ally-tdp-novariant-") as temporary:
        root = Path(temporary)
        armoury = layout(root)
        rc71_ac(armoury)
        env = environment(root, handheld=False)
        test_rejects_without_writes(root, armoury, env, ["--set", "15"], "an RC71L without the handheld variant is not given a TDP writer")

    with tempfile.TemporaryDirectory(prefix="ally-tdp-source-") as temporary:
        root = Path(temporary)
        armoury = layout(root)
        rc71_ac(armoury)
        env = environment(root)
        run([str(APPLY), "--set", "30"], env, check=True)
        rc71_dc(armoury, current=(30, 43, 53))
        (root / "supply" / "ADP" / "online").write_text("0\n")
        result = run([str(APPLY), "--reassert"], env, check=True)
        preference = json.loads((root / "state" / "preference.json").read_text())
        if currents(armoury) != (20, 20, 25) or preference.get("requested_spl") != 30:
            fail("unplug reasserts the saved request inside the battery cap", f"{currents(armoury)} {preference}")
        ok("unplug reasserts the saved request inside the battery cap")
        rc71_ac(armoury)
        (armoury / "ppt_pl1_spl" / "current_value").write_text("25\n")
        (root / "supply" / "ADP" / "online").write_text("1\n")
        result = run([str(APPLY), "--reassert"], env, check=True)
        if currents(armoury) != (30, 43, 53):
            fail("replug restores the saved 30 W request", str(currents(armoury)))
        ok("replug restores the saved 30 W request")

    with tempfile.TemporaryDirectory(prefix="ally-tdp-unknown-") as temporary:
        root = Path(temporary)
        armoury = layout(root)
        rc71_ac(armoury)
        env = environment(root)
        (root / "supply" / "ADP" / "type").write_text("Battery\n")
        test_rejects_without_writes(root, armoury, env, ["--set", "15"], "a missing mains supply refuses the write")


def probe_and_prepare():
    with tempfile.TemporaryDirectory(prefix="ally-tdp-probe-") as temporary:
        root = Path(temporary)
        armoury = layout(root)
        rc71_ac(armoury)
        write_text(root / "hwmon" / "hwmon0" / "name", "amdgpu\n")
        write_text(root / "hwmon" / "hwmon0" / "power1_label", "PPT\n")
        write_text(root / "hwmon" / "hwmon0" / "power1_input", "28000000\n")
        write_text(armoury / "mcu_powersave" / "current_value", "0\n")
        env = environment(root, OMARCHY_ALLY_TDP_ASUSD_STATE="active", OMARCHY_ALLY_TDP_PPD_STATE="inactive")
        result = run([str(PROBE), "--json"], env, check=True)
        body = payload_of(result)
        sample = body["hwmon"][0]
        if body["limits"]["spl"]["current"] != 30 or sample["microwatts"] != 28000000 or sample["watts"] != 28.0:
            fail("the probe records PPT integers and hwmon microwatts", result.stdout)
        if body["mcu_powersave"] != 0 or body["asusd_active"] is not True:
            fail("the probe reports asusd and mcu_powersave without writing them", result.stdout)
        if currents(armoury) != (30, 43, 53):
            fail("the probe does not write PPT limits")
        ok("the probe records PPT integers and hwmon microwatts")

        laptop = environment(root)
        write_text(root / "dmi" / "product_name", "ROG Strix G16\n")
        write_text(root / "dmi" / "board_name", "GU605CX\n")
        refused = run([str(PROBE)], laptop)
        if refused.returncode == 0:
            fail("the probe refuses a laptop")
        ok("the probe refuses a laptop")

    with tempfile.TemporaryDirectory(prefix="ally-tdp-prepare-") as temporary:
        root = Path(temporary)
        armoury = layout(root)
        rc71_ac(armoury)
        log = root / "systemctl.log"
        stub = root / "bin"
        stub.mkdir()
        (stub / "systemctl").write_text(
            textwrap.dedent(
                """\
                #!/bin/bash
                printf '%s\\n' "$*" >> "$SYSTEMCTL_LOG"
                if [[ $1 == is-enabled ]]; then
                  echo enabled
                  exit 0
                fi
                if [[ $1 == is-active && $3 == asusd.service ]]; then
                  exit 0
                fi
                if [[ $1 == is-active ]]; then
                  exit 3
                fi
                exit 0
                """
            )
        )
        (stub / "systemctl").chmod(0o755)
        env = environment(root, handheld=False)
        env["PATH"] = f"{stub}:{env['PATH']}"
        env["SYSTEMCTL_LOG"] = str(log)
        result = run([str(PREPARE)], env, check=True)
        if log.exists() and log.read_text().strip():
            fail("prepare on an RC71L without the handheld variant leaves PPD untouched", log.read_text())
        if "unchanged" not in result.stderr:
            fail("prepare on an RC71L without the handheld variant leaves PPD untouched", result.stderr)
        ok("prepare on an RC71L without the handheld variant leaves PPD untouched")

        write_text(root / "variant" / "handheld", "handheld\n")
        env["OMARCHY_ALLY_TDP_WRITER_INSTALLED"] = "0"
        log.write_text("")
        result = run([str(PREPARE)], env, check=True)
        if log.read_text().strip():
            fail("prepare without the TDP writer leaves PPD untouched", log.read_text())
        ok("prepare without the TDP writer leaves PPD untouched")
        del env["OMARCHY_ALLY_TDP_WRITER_INSTALLED"]

        log.write_text("")
        result = run([str(PREPARE)], env, check=True)
        logged = log.read_text()
        if "mask --now power-profiles-daemon.service" not in logged:
            fail("prepare masks power-profiles-daemon when the handheld variant and the writer are installed", logged)
        if "mask --now asusd" in logged or "mask asusd" in logged:
            fail("prepare does not mask asusd", logged)
        if "asusd is active" not in result.stderr:
            fail("prepare tells the operator that asusd is still active", result.stderr)
        if not (root / "run" / "ceilings.json").is_file():
            fail("prepare snapshots the boot ceilings before masking")
        if not (root / "state" / "ppd-mask.json").is_file():
            fail("prepare records the PPD mask it owns")
        ok("prepare masks power-profiles-daemon when the handheld variant and the writer are installed")

        (root / "variant" / "handheld").unlink()
        log.write_text("")
        result = run([str(PREPARE)], env, check=True)
        logged = log.read_text()
        if "unmask power-profiles-daemon.service" not in logged or "enable --now power-profiles-daemon.service" not in logged:
            fail("prepare unmasks power-profiles-daemon when the handheld variant is removed", logged)
        if "mask --now" in logged:
            fail("prepare unmasks power-profiles-daemon when the handheld variant is removed", logged)
        if (root / "state" / "ppd-mask.json").exists():
            fail("prepare drops the PPD mask record after unmasking")
        ok("prepare unmasks power-profiles-daemon when the handheld variant is removed")

        write_text(root / "dmi" / "board_name", "RC72LA\n")
        write_text(root / "dmi" / "product_name", "ROG Ally X RC72LA\n")
        log.write_text("")
        result = run([str(PREPARE)], env, check=True)
        if log.read_text().strip():
            fail("prepare on a non-Ally does not call systemctl", log.read_text())
        ok("prepare on a non-Ally does not call systemctl")


def policy_file():
    text = (ROOT / "default/handheld/org.omarchy.ally.set-tdp.policy").read_text()
    if text.count("<action ") != 1 or 'id="org.omarchy.ally.set-tdp"' not in text:
        fail("polkit defines one fixed action")
    if "<allow_any>no</allow_any>" not in text or "<allow_inactive>no</allow_inactive>" not in text:
        fail("polkit denies inactive and remote callers")
    if "<allow_active>yes</allow_active>" not in text:
        fail("polkit allows the active seat")
    if "/usr/bin/omarchy-ally-tdp-apply" not in text:
        fail("polkit executes only the Ally TDP helper")
    if "firmware-attributes" in text or "sysfs" in text:
        fail("polkit action does not name a sysfs path")
    resume = (ROOT / "default/handheld/omarchy-ally-tdp-resume.service").read_text()
    prepare = (ROOT / "default/handheld/omarchy-ally-tdp-prepare.service").read_text()
    shim = (ROOT / "default/handheld/omarchy-ally-tdp-shim.service").read_text()
    if "omarchy-ally-tdp-apply --reassert" not in resume or "asus-armoury" not in resume:
        fail("resume unit reasserts through the same writer and only when asus-armoury exists")
    if "RestartPreventExitStatus=2" not in shim:
        fail("the shim unit does not restart when the bus name is taken")
    rules = (ROOT / "default/handheld/99-omarchy-ally-tdp.rules").read_text()
    source = (ROOT / "default/handheld/omarchy-ally-tdp-source.service").read_text()
    if 'SUBSYSTEM=="power_supply"' not in rules or "omarchy-ally-tdp-source.service" not in rules:
        fail("the udev rule runs the root writer on a power_supply change")
    if "omarchy-ally-tdp-source" not in source:
        fail("the power-supply unit runs the root writer")
    if "omarchy-ally-tdp-prepare" not in prepare or "omarchy-ally-tdp-shim" not in shim:
        fail("units point at the Ally TDP commands")
    script = (ROOT / "bin/omarchy-ally-tdp-prepare").read_text()
    if "mask --now asusd" in script or "mask asusd" in script:
        fail("prepare script does not mask asusd")
    ok("polkit is one active-seat action and the units share the writer")


def wait_ready(process, log, ready):
    def reader():
        for line in process.stderr:
            log.append(line)
            if "ready" in line:
                ready.set()

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    return thread


def shim_cases():
    import dbus
    import dbus.mainloop.glib
    from gi.repository import GLib

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    with tempfile.TemporaryDirectory(prefix="ally-tdp-shim-") as temporary:
        root = Path(temporary)
        armoury = layout(root)
        rc71_ac(armoury)
        session_address, session_pid = start_bus()
        system_address, system_pid = start_bus()
        env = environment(root)
        env["DBUS_SESSION_BUS_ADDRESS"] = session_address
        env["DBUS_SYSTEM_BUS_ADDRESS"] = system_address
        env["OMARCHY_ALLY_TDP_WATCH_SYSTEM"] = "1"
        log = []
        ready = threading.Event()
        process = subprocess.Popen(
            [str(SHIM)],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        buses = (session_pid, system_pid)
        try:
            wait_ready(process, log, ready)
            if not ready.wait(5):
                fail("shim owns the session bus", "".join(log) + (process.stdout.read() if process.stdout else ""))
            if process.poll() is not None:
                fail("shim stays running after it is ready", "".join(log))
            os.environ["DBUS_SESSION_BUS_ADDRESS"] = session_address
            os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = system_address
            bus = dbus.SessionBus(private=True)
            proxy = bus.get_object(BUS, PATH)
            props = dbus.Interface(proxy, "org.freedesktop.DBus.Properties")
            intro = dbus.Interface(proxy, "org.freedesktop.DBus.Introspectable").Introspect()
            if 'name="TdpLimit"' not in intro or 'type="u"' not in intro:
                fail("introspection advertises TdpLimit as a uint32", intro)
            if props.Get(TDP, "TdpLimitMax") != 30 or props.Get(TDP, "TdpLimit") != 30:
                fail("shim advertises the AC range from the firmware fixture")
            changed = threading.Event()
            loop = GLib.MainLoop()

            def on_changed(interface, values, _invalidated):
                if interface == TDP and "TdpLimit" in values and int(values["TdpLimit"]) == 15:
                    changed.set()
                    if loop.is_running():
                        loop.quit()

            bus.add_signal_receiver(
                on_changed,
                signal_name="PropertiesChanged",
                dbus_interface="org.freedesktop.DBus.Properties",
                path=PATH,
            )
            props.Set(TDP, "TdpLimit", dbus.UInt32(15))
            if currents(armoury) != (15, 22, 27):
                fail("Steam's TdpLimit set writes the derived tuple", str(currents(armoury)))
            if not changed.is_set():
                GLib.timeout_add(2000, loop.quit)
                loop.run()
            if not changed.is_set():
                fail("shim signals PropertiesChanged only after the write")
            if props.Get(TDP, "TdpLimit") != 15:
                fail("TdpLimit reads back the applied watts")
            try:
                props.Set(TDP, "TdpLimit", dbus.UInt32(99))
            except dbus.exceptions.DBusException:
                pass
            else:
                fail("an out-of-range slider value is a D-Bus error")
            if currents(armoury) != (15, 22, 27):
                fail("a rejected slider value writes nothing", str(currents(armoury)))
            try:
                props.Set(BUS + ".GpuPerformanceLevel1", "ManualGpuClock", dbus.UInt32(2200))
            except dbus.exceptions.DBusException:
                pass
            else:
                fail("manual GPU clock is refused")
            if (root / "platform_profile").read_text() != "quiet\n":
                fail("the profile stub does not write platform_profile")
            props.Set(BUS + ".PerformanceProfile1", "PerformanceProfile", "performance")
            ok("Steam's TdpLimit property drives the capped writer")

            # Resume signal uses the same reassert path.
            run([str(APPLY), "--set", "30"], env, check=True)
            rc71_dc(armoury, current=currents(armoury))
            (root / "supply" / "ADP" / "online").write_text("0\n")
            system = dbus.bus.BusConnection(system_address)
            message = dbus.lowlevel.SignalMessage(
                "/org/freedesktop/login1",
                "org.freedesktop.login1.Manager",
                "PrepareForSleep",
            )
            message.append(False)
            system.send_message(message)
            deadline = time.time() + 3
            while time.time() < deadline and currents(armoury) != (20, 20, 25):
                time.sleep(0.05)
            if currents(armoury) != (20, 20, 25):
                fail("PrepareForSleep(false) reasserts inside the battery cap", f"{currents(armoury)} {''.join(log)}")
            ok("PrepareForSleep(false) reasserts inside the battery cap")
        finally:
            if process.poll() is None:
                process.send_signal(signal.SIGTERM)
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()
            for pid in buses:
                os.kill(pid, signal.SIGTERM)

    with tempfile.TemporaryDirectory(prefix="ally-tdp-shim-off-") as temporary:
        root = Path(temporary)
        layout(root, product="ROG Strix G16", board="GU605CX")
        address, pid = start_bus()
        env = environment(root)
        env["DBUS_SESSION_BUS_ADDRESS"] = address
        result = run([str(SHIM)], env)
        os.kill(pid, signal.SIGTERM)
        if result.returncode != 0 or "only for the original ROG Ally" not in result.stderr:
            fail("the shim exits quietly on a laptop", result.stderr)
        ok("the shim exits quietly on a laptop")


def ordered(lines):
    for line in lines:
        values = [int(part) for part in line.split()]
        if len(values) != 3 or not (values[0] <= values[1] <= values[2]):
            return False
    return True


def review_cases():
    with tempfile.TemporaryDirectory(prefix="ally-tdp-order-") as temporary:
        root = Path(temporary)
        armoury = layout(root)
        rc71_ac(armoury)
        env = environment(root)
        trace = root / "trace"
        env["OMARCHY_ALLY_TDP_TRACE"] = str(trace)
        run([str(APPLY), "--set", "10"], env, check=True)
        trace.write_text("")
        run([str(APPLY), "--set", "30"], env, check=True)
        raised = [line for line in trace.read_text().splitlines() if line.strip()]
        if raised != ["10 15 53", "10 43 53", "30 43 53"] or not ordered(raised):
            fail("raising writes FPPT, then SPPT, then SPL", "\n".join(raised))
        ok("raising writes FPPT, then SPPT, then SPL")
        trace.write_text("")
        run([str(APPLY), "--set", "10"], env, check=True)
        lowered = [line for line in trace.read_text().splitlines() if line.strip()]
        if lowered != ["10 43 53", "10 15 53", "10 15 18"] or not ordered(lowered):
            fail("lowering writes SPL, then SPPT, then FPPT", "\n".join(lowered))
        ok("lowering writes SPL, then SPPT, then FPPT")

    with tempfile.TemporaryDirectory(prefix="ally-tdp-flip-") as temporary:
        root = Path(temporary)
        armoury = layout(root)
        rc71_ac(armoury)
        env = environment(root, OMARCHY_ALLY_TDP_FLIP_SOURCE="1")
        result = run([str(APPLY), "--set", "30"], env, check=True)
        preference = json.loads((root / "state" / "preference.json").read_text())
        if (root / "supply" / "ADP" / "online").read_text().strip() != "0":
            fail("the writer re-reads the power source after the write")
        if currents(armoury) == (30, 43, 53) or preference.get("requested_spl") != 30 or payload_of(result).get("source") != "battery":
            fail("a source change during the write is re-planned under the lock", f"{currents(armoury)} {preference}")
        ok("a source change during the write is re-planned under the lock")

    with tempfile.TemporaryDirectory(prefix="ally-tdp-lock-") as temporary:
        root = Path(temporary)
        armoury = layout(root)
        rc71_ac(armoury)
        env = environment(root)
        run([str(APPLY), "--set", "30"], env, check=True)
        rc71_dc(armoury, current=(30, 43, 53))
        (root / "supply" / "ADP" / "online").write_text("0\n")
        trace = root / "trace"
        env["OMARCHY_ALLY_TDP_TRACE"] = str(trace)
        env["OMARCHY_ALLY_TDP_WRITE_DELAY"] = "0.05"
        first = subprocess.Popen([str(APPLY), "--reassert"], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        second = subprocess.Popen([str(APPLY), "--reassert"], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        first.wait(timeout=10)
        second.wait(timeout=10)
        lines = [line for line in trace.read_text().splitlines() if line.strip()]
        if first.returncode != 0 or second.returncode != 0 or not ordered(lines) or currents(armoury) != (20, 20, 25):
            fail("two reasserts keep SPL <= SPPT <= FPPT on every step", f"{currents(armoury)} {lines}")
        ok("two reasserts keep SPL <= SPPT <= FPPT on every step")

    with tempfile.TemporaryDirectory(prefix="ally-tdp-held-") as temporary:
        root = Path(temporary)
        armoury = layout(root)
        rc71_ac(armoury)
        env = environment(root)
        (root / "run").mkdir()
        import fcntl

        descriptor = os.open(root / "run" / "lock", os.O_CREAT | os.O_RDWR)
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = run([str(APPLY), "--set", "15"], env)
        os.close(descriptor)
        if result.returncode == 0 or currents(armoury) != (30, 43, 53) or "lock" not in result.stderr:
            fail("a held lock rejects the write", result.stderr)
        ok("a held lock rejects the write")

    with tempfile.TemporaryDirectory(prefix="ally-tdp-tamper-") as temporary:
        root = Path(temporary)
        armoury = layout(root, online="0")
        rc71_dc(armoury, current=(15, 20, 25))
        env = environment(root)
        run([str(APPLY), "--set", "15"], env, check=True)
        ceilings = json.loads((root / "run" / "ceilings.json").read_text())
        ceilings["sources"]["battery"]["spl"]["default"] = 1
        (root / "run" / "ceilings.json").write_text(json.dumps(ceilings))
        test_rejects_without_writes(root, armoury, env, ["--set", "14"], "a tampered ceilings snapshot is rejected")

    with tempfile.TemporaryDirectory(prefix="ally-tdp-symlink-") as temporary:
        root = Path(temporary)
        armoury = layout(root)
        rc71_ac(armoury)
        real = root / "real-state"
        real.mkdir()
        (root / "state").symlink_to(real)
        (real / "sentinel").write_text("keep\n")
        env = environment(root)
        result = run([str(APPLY), "--set", "15"], env)
        if result.returncode == 0 or currents(armoury) != (30, 43, 53) or (real / "sentinel").read_text() != "keep\n":
            fail("a symlinked state directory is refused", result.stderr)
        ok("a symlinked state directory is refused")

    with tempfile.TemporaryDirectory(prefix="ally-tdp-mode-") as temporary:
        root = Path(temporary)
        armoury = layout(root)
        rc71_ac(armoury)
        state = root / "state"
        state.mkdir()
        os.chmod(state, 0o777)
        env = environment(root)
        result = run([str(APPLY), "--set", "15"], env)
        os.chmod(state, 0o755)
        if result.returncode == 0 or currents(armoury) != (30, 43, 53):
            fail("a world-writable state directory is refused", result.stderr)
        ok("a world-writable state directory is refused")

    for variable in (
        "OMARCHY_ALLY_TDP_ASUSD_STATE",
        "OMARCHY_ALLY_TDP_HHD_STATE",
        "OMARCHY_ALLY_TDP_TUNED_STATE",
        "OMARCHY_ALLY_TDP_GAMEMODE_STATE",
    ):
        with tempfile.TemporaryDirectory(prefix="ally-tdp-conflict-") as temporary:
            root = Path(temporary)
            armoury = layout(root)
            rc71_ac(armoury)
            env = environment(root, **{variable: "active"})
            test_rejects_without_writes(root, armoury, env, ["--set", "15"], f"{variable} active refuses the write")

    with tempfile.TemporaryDirectory(prefix="ally-tdp-config-") as temporary:
        root = Path(temporary)
        saved = {key: os.environ.get(key) for key in (
            "OMARCHY_PATH",
            "OMARCHY_ALLY_TDP_STATE_DIR",
            "OMARCHY_ALLY_TDP_PPD_STATE",
            "OMARCHY_ALLY_TDP_FIXTURE",
            "OMARCHY_DMI_PRODUCT_NAME_PATH",
        )}
        os.environ["OMARCHY_PATH"] = "/tmp/not-the-tree"
        os.environ["OMARCHY_ALLY_TDP_STATE_DIR"] = str(root / "state")
        os.environ["OMARCHY_ALLY_TDP_PPD_STATE"] = "active"
        os.environ["OMARCHY_ALLY_TDP_FIXTURE"] = "1"
        os.environ["OMARCHY_DMI_PRODUCT_NAME_PATH"] = str(root / "fake")
        import importlib.util

        spec = importlib.util.spec_from_file_location("ally_tdp_config", ROOT / "default/handheld/ally_tdp.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        config = module.effective_config(0)
        if (
            config["omarchy_path"] != "/usr/share/omarchy"
            or config["state_dir"] != "/var/lib/omarchy/ally-tdp"
            or config["ppd_state"] is not None
            or config["fixture"]
            or config["dmi_overrides"]
        ):
            fail("root ignores environment overrides", str(config))
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        ok("root ignores environment overrides")

    with tempfile.TemporaryDirectory(prefix="ally-tdp-missing-") as temporary:
        root = Path(temporary)
        layout(root)
        log = root / "systemctl.log"
        stub = root / "bin"
        stub.mkdir()
        (stub / "systemctl").write_text("#!/bin/bash\nprintf '%s\\n' \"$*\" >> \"$SYSTEMCTL_LOG\"\nexit 0\n")
        (stub / "systemctl").chmod(0o755)
        env = environment(root)
        env["PATH"] = f"{stub}:{env['PATH']}"
        env["SYSTEMCTL_LOG"] = str(log)
        result = run([str(PREPARE)], env)
        logged = log.read_text() if log.exists() else ""
        if result.returncode == 0 or "mask" in logged:
            fail("prepare does not mask PPD when the armoury snapshot fails", f"{result.returncode} {logged} {result.stderr}")
        ok("prepare does not mask PPD when the armoury snapshot fails")

    source = ROOT / "bin" / "omarchy-ally-tdp-source"
    with tempfile.TemporaryDirectory(prefix="ally-tdp-udev-") as temporary:
        root = Path(temporary)
        layout(root, product="ROG Strix G16", board="GU605CX")
        env = environment(root)
        result = run([str(source)], env, check=True)
        if result.returncode != 0:
            fail("the power-supply helper is quiet when the owner gate is closed", result.stderr)
        ok("the power-supply helper is quiet when the owner gate is closed")


def start_shim(env):
    log = []
    ready = threading.Event()
    process = subprocess.Popen(
        [str(SHIM)],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    wait_ready(process, log, ready)
    return process, log, ready


def stop_shim(process):
    if process.poll() is None:
        process.send_signal(signal.SIGTERM)
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()


def shim_review():
    import dbus
    import dbus.mainloop.glib
    from gi.repository import GLib

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    with tempfile.TemporaryDirectory(prefix="ally-tdp-seed-") as temporary:
        root = Path(temporary)
        armoury = layout(root, online="0")
        rc71_dc(armoury, current=(15, 20, 25))
        write_text(root / "state" / "preference.json", json.dumps({"requested_spl": 30}) + "\n")
        address, pid = start_bus()
        env = environment(root)
        env["DBUS_SESSION_BUS_ADDRESS"] = address
        process, log, ready = start_shim(env)
        try:
            if not ready.wait(5):
                fail("a battery start with a stored request becomes ready", "".join(log))
            stored = json.loads((root / "state" / "preference.json").read_text())
            if stored.get("requested_spl") != 30 or currents(armoury) != (20, 20, 25):
                fail("a battery start keeps the stored 30 W request and clamps the tuple", f"{stored} {currents(armoury)}")
            bus = dbus.bus.BusConnection(address)
            props = dbus.Interface(bus.get_object(BUS, PATH), "org.freedesktop.DBus.Properties")
            if props.Get(TDP, "TdpLimitMax") != 20 or props.Get(TDP, "TdpLimit") != 20:
                fail("TdpLimitMax is 20 on battery")
            ok("a battery start keeps the stored 30 W request and reports TdpLimitMax 20")
        finally:
            stop_shim(process)
            os.kill(pid, signal.SIGTERM)

    with tempfile.TemporaryDirectory(prefix="ally-tdp-squat-") as temporary:
        root = Path(temporary)
        layout(root)
        rc71_ac(root / "armoury")
        address, pid = start_bus()
        env = environment(root)
        env["DBUS_SESSION_BUS_ADDRESS"] = address
        owner, log, ready = start_shim(env)
        try:
            if not ready.wait(5):
                fail("the first shim owns the name", "".join(log))
            second = subprocess.run([str(SHIM)], env=env, text=True, capture_output=True)
            if second.returncode != 2 or "already owned" not in second.stderr:
                fail("a second shim exits 2 when the name is taken", f"{second.returncode} {second.stderr}")
            shown = run([str(APPLY), "--show"], env, check=True)
            if not (payload_of(shown).get("bus_owner") or {}).get("name"):
                fail("show reports the current bus owner", shown.stdout)
            ok("a second shim exits 2 and show reports the owner")
        finally:
            stop_shim(owner)
            os.kill(pid, signal.SIGTERM)

    with tempfile.TemporaryDirectory(prefix="ally-tdp-bounds-") as temporary:
        root = Path(temporary)
        armoury = layout(root, online="0")
        rc71_dc(armoury, current=(15, 20, 25))
        write_text(
            root / "state" / "preference.json",
            json.dumps({"requested_spl": 15, "applied_spl": 15, "applied_sppt": 20, "applied_fppt": 25, "source": "battery"}) + "\n",
        )
        session_address, session_pid = start_bus()
        system_address, system_pid = start_bus()
        env = environment(root)
        env["DBUS_SESSION_BUS_ADDRESS"] = session_address
        env["DBUS_SYSTEM_BUS_ADDRESS"] = system_address
        env["OMARCHY_ALLY_TDP_WATCH_SYSTEM"] = "1"
        process, log, ready = start_shim(env)
        try:
            if not ready.wait(5):
                fail("bounds shim becomes ready", "".join(log))
            bus = dbus.bus.BusConnection(session_address, mainloop=dbus.mainloop.glib.DBusGMainLoop())
            props = dbus.Interface(bus.get_object(BUS, PATH), "org.freedesktop.DBus.Properties")
            if props.Get(TDP, "TdpLimitMax") != 20 or props.Get(TDP, "TdpLimit") != 15:
                fail("battery TdpLimit stays 15 with max 20", f"{props.Get(TDP, 'TdpLimit')} {props.Get(TDP, 'TdpLimitMax')}")
            rc71_ac(armoury)
            (armoury / "ppt_pl1_spl" / "current_value").write_text("15\n")
            (root / "supply" / "ADP" / "online").write_text("1\n")
            seen = {}
            got = threading.Event()

            def on_changed(interface, values, _invalidated):
                if interface == TDP and "TdpLimitMax" in values:
                    seen["max"] = int(values["TdpLimitMax"])
                    seen["limit"] = int(values.get("TdpLimit", -1))
                    got.set()

            bus.add_signal_receiver(
                on_changed,
                signal_name="PropertiesChanged",
                dbus_interface="org.freedesktop.DBus.Properties",
                path=PATH,
            )
            system = dbus.bus.BusConnection(system_address)
            message = dbus.lowlevel.SignalMessage(
                "/org/freedesktop/UPower",
                "org.freedesktop.DBus.Properties",
                "PropertiesChanged",
            )
            message.append("org.freedesktop.UPower", {"OnBattery": False}, dbus.Array([], signature="s"))
            system.send_message(message)
            loop = GLib.MainLoop()

            def pump():
                if got.is_set() or time.time() > deadline:
                    loop.quit()
                    return False
                return True

            deadline = time.time() + 3
            GLib.timeout_add(50, pump)
            loop.run()
            if seen.get("max") != 30 or currents(armoury)[0] != 15:
                fail("a source change signals TdpLimitMax when SPL stays 15", f"{seen} {currents(armoury)} {''.join(log)}")
            ok("a source change signals TdpLimitMax when SPL stays 15")
        finally:
            stop_shim(process)
            os.kill(session_pid, signal.SIGTERM)
            os.kill(system_pid, signal.SIGTERM)


def main():
    policy_cases()
    probe_and_prepare()
    policy_file()
    review_cases()
    shim_cases()
    shim_review()


if __name__ == "__main__":
    main()
