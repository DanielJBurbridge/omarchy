import json
import os
from pathlib import Path
import subprocess
import tempfile


repo = Path(os.environ["OMARCHY_TEST_ROOT"])
sunshine = repo / "bin/omarchy-games-sunshine"

with tempfile.TemporaryDirectory(prefix="gaming-sunshine-") as temp:
    root = Path(temp)
    fake_bin = root / "bin"
    fake_bin.mkdir()

    def stub(name, content):
        executable = fake_bin / name
        executable.write_text("#!/bin/bash\n" + content + "\n")
        executable.chmod(0o755)

    stub("omarchy-hw-rog-ally", '[[ ${NOT_ALLY:-0} == 0 ]]')
    stub("omarchy-pkg-present", '[[ $1 == omarchy-gaming-session || ${UNINSTALLED:-0} == 0 ]]')
    stub("getcap", 'printf "%s %s\\n" "$1" "${CAPS:-cap_sys_admin,cap_sys_nice=p}"')
    stub("pgrep", '[[ ${HOST_RUNNING:-0} == 1 ]]')
    stub("systemctl", 'echo "${SERVICE_STATE:-inactive}"; [[ ${SERVICE_STATE:-inactive} == active ]]')
    stub("sunshine", 'printf "%s:%s\\n" "$*" "${SUNSHINE_MIGRATE_CONFIG-unset}" >> "$ACTIONS"')

    config_dir = root / "config/sunshine"
    config_dir.mkdir(parents=True)
    config = config_dir / "sunshine.conf"
    config.write_text("# A user's existing config\nfile_state = state with spaces.json\n"
                      "credentials_file = separate-credentials.json\ncapture = portal\n")
    credentials = config_dir / "separate-credentials.json"
    credentials.write_text(json.dumps(dict(username="fixture", password="hash", salt="fixture")))
    pairings = config_dir / "state with spaces.json"
    clients = dict(root=dict(uniqueid="fixture", named_devices=[dict(cert="fixture", enabled="false")]))
    pairings.write_text(json.dumps(clients))

    runtime = root / "run/omarchy-gaming-c1"
    runtime.mkdir(parents=True)
    os.mkfifo(runtime / "ready")
    env = dict(os.environ, HOME=temp, OMARCHY_PATH=str(repo), PATH=f"{fake_bin}:/usr/bin:/bin",
               XDG_CONFIG_HOME=str(config_dir.parent), XDG_STATE_HOME=str(root / "state"),
               XDG_RUNTIME_DIR=str(runtime.parent), XDG_SESSION_ID="c1", XDG_CURRENT_DESKTOP="gamescope",
               DISPLAY=":54", OMARCHY_GAMING_RUNTIME=str(runtime), ACTIONS=str(root / "actions"),
               SUNSHINE_MIGRATE_CONFIG="1")
    for name in ("CONFIGURATION_DIRECTORY", "OMARCHY_HANDHELD_SESSION"):
        env.pop(name, None)
    actions = root / "actions"
    setting = root / "state/omarchy/gaming-session/sunshine"

    def run(action, code=0, **overrides):
        result = subprocess.run([str(sunshine), action], env=dict(env, **overrides),
                                capture_output=True, text=True, timeout=5)
        assert result.returncode == code, (action, result)
        return result.stdout + result.stderr

    run("run")
    assert not actions.exists() and not setting.exists()
    assert "off" in run("status")
    assert "Pair a Moonlight client" in run("on", 1)
    assert not setting.exists()
    clients["root"]["named_devices"][0]["enabled"] = "true"
    pairings.write_text(json.dumps(clients))
    assert "does not support KMS" in run("on", 1, CAPS="cap_sys_nice=p")
    assert not setting.exists()
    assert "original ROG Ally" in run("on", 1, NOT_ALLY="1")

    unchanged = [path.read_bytes() for path in (config, credentials, pairings)]
    assert "next Gaming login" in run("on")
    run("run", XDG_CURRENT_DESKTOP="Hyprland")
    run("run", OMARCHY_GAMING_RUNTIME=str(root / "unrelated"))
    assert "already running" in run("run", 1, HOST_RUNNING="1")
    assert "already running" in run("run", 1, SERVICE_STATE="activating")
    assert not actions.exists()
    run("run")
    assert actions.read_text() == "capture=kms:unset\n"
    assert [path.read_bytes() for path in (config, credentials, pairings)] == unchanged

    run("off", UNINSTALLED="1")
    run("run", UNINSTALLED="1")
    assert actions.read_text() == "capture=kms:unset\n"
    print("PASS opt-in Sunshine starts KMS only in the managed Gaming session with a paired host")
