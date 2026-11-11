"""Private trusted-lock process selection, identity and lock/status client.

No operation accepts passwords, unlock requests, code or application commands
from a socket. Configuration and role files are data, never imported/executed.
"""
import fcntl
import json
import os
from pathlib import Path
import re
import socket
import struct
import subprocess
import sys
import tempfile

UNIT = "omarchy-lock-host.service"
PROTOCOL = 1


def paths():
  runtime = Path(os.environ["XDG_RUNTIME_DIR"])
  instance = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
  if not runtime.is_absolute() or not re.fullmatch(r"[A-Za-z0-9_.-]+", instance):
    raise ValueError("invalid graphical-session identity")
  info = runtime.stat()
  if info.st_uid != os.getuid() or info.st_mode & 0o077:
    raise ValueError("runtime directory is not private to this user")
  return runtime, instance


def session_path(kind):
  runtime, instance = paths()
  return runtime / f"omarchy-lock-{kind}-{instance}"


def preference():
  state = Path.home() / ".local/state"
  return state / "omarchy/lock-host-enabled"


def mode(initialize=False):
  path = session_path("mode")
  if initialize and not path.exists():
    # Publish a complete immutable selection atomically. Two simultaneous
    # launchers must never read an empty file between O_EXCL and write().
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".init.", dir=path.parent)
    try:
      with os.fdopen(fd, "w") as output:
        output.write("host\n" if preference().is_file() else "shell\n")
      try:
        os.link(temporary, path, follow_symlinks=False)
      except FileExistsError:
        pass
    finally:
      os.unlink(temporary)
  if path.is_symlink():
    raise ValueError("invalid session lock mode symlink")
  with path.open() as source:
    value = source.read(16).strip()
  if value not in ("host", "shell") or path.stat().st_uid != os.getuid():
    raise ValueError("invalid session lock mode")
  return value


def start_time(pid):
  # comm may contain spaces or parentheses; fields after its final ')' start at 3.
  return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[19]


def write_role(role):
  path = session_path(role + ".json")
  payload = {"protocol": PROTOCOL, "pid": os.getpid(), "start": start_time(os.getpid()), "role": role,
             "instance": paths()[1], "root": str(Path(os.environ["OMARCHY_PATH"]).resolve())}
  temporary = path.with_name(path.name + f".{os.getpid()}.new")
  with temporary.open("w") as output:
    os.chmod(temporary, 0o600)
    json.dump(payload, output)
  os.replace(temporary, path)


def role_pid(role):
  data = json.loads(session_path(role + ".json").read_text())
  pid = data["pid"]
  if type(data.get("protocol")) is not int or data["protocol"] != PROTOCOL:
    raise ValueError("owner runtime protocol does not match this release")
  if type(pid) is not int or pid <= 1 or data["role"] != role or data["instance"] != paths()[1]:
    raise ValueError("invalid owner role")
  proc = Path(f"/proc/{pid}")
  if proc.stat().st_uid != os.getuid() or data["start"] != start_time(pid):
    raise ValueError("stale owner role")
  root = str(Path(os.environ["OMARCHY_PATH"]).resolve())
  if data["root"] != root or proc.joinpath("exe").resolve() != Path("/usr/bin/quickshell").resolve():
    raise ValueError("wrong owner executable")
  args = proc.joinpath("cmdline").read_bytes().split(b"\0")
  expected = root + ("/shell/lock-host.qml" if role == "host" else "/shell")
  if args.count(b"-p") != 1:
    raise ValueError("wrong owner configuration")
  position = args.index(b"-p") + 1
  if position >= len(args) or Path(os.fsdecode(args[position])).resolve() != Path(expected):
    raise ValueError("wrong owner configuration")
  return pid


def unit_pid():
  result = subprocess.run(["/usr/bin/systemctl", "--user", "show", UNIT, "--property=MainPID", "--value"],
                          capture_output=True, text=True, timeout=1, check=True)
  return int(result.stdout.strip())


def checked_peer(connection):
  pid, uid, _gid = struct.unpack("3i", connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
  if uid != os.getuid() or pid != role_pid("host") or pid != unit_pid():
    raise ValueError("untrusted lock-host peer")


def request(method):
  if method not in ("lock", "status", "isLocked"):
    raise ValueError("only lock/status requests are permitted")
  if mode() != "host":
    raise ValueError("trusted host is not the session owner")
  runtime, instance = paths()
  with socket.socket(socket.AF_UNIX) as connection:
    connection.settimeout(0.7)
    connection.connect(str(runtime / f"omarchy-lock-control-{instance}.sock"))
    checked_peer(connection)
    stream = connection.makefile("rb")
    data = stream.readline(8193)
    if not data.endswith(b"\n") or len(data) > 8192:
      raise ValueError("invalid host snapshot")
    initial = validate_status(json.loads(data))
    if method == "lock":
      if not initial["ready"]:
        raise ValueError("lock host is not ready")
      connection.sendall(b'{"method":"lock"}\n')
      data = stream.readline(8193)
      if not data.endswith(b"\n") or len(data) > 8192:
        raise ValueError("invalid host acknowledgement")
      initial = validate_status(json.loads(data))
      if not initial["requested"] and not initial["secure"]:
        raise ValueError("host refused lock request")
    return initial


def validate_status(data):
  if not isinstance(data, dict) or data.get("owner") != "trusted-host" or type(data.get("protocol")) is not int or data["protocol"] != PROTOCOL:
    raise ValueError("invalid host status")
  for key in ("ready", "locked", "requested", "secure"):
    if type(data.get(key)) is not bool:
      raise ValueError("invalid host state")
  if (data["secure"] or data["requested"]) and not data["locked"]:
    raise ValueError("inconsistent host state")
  # Whitelist scalar state rather than returning arbitrary peer properties.
  return {key: data[key] for key in ("protocol", "ready", "locked", "requested", "secure", "owner")}


def run(role, command):
  if role == "shell" and not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
    os.execvpe(command[0], command, dict(os.environ, OMARCHY_LOCK_HOST="0"))
  selected = mode(initialize=True)
  if role == "host" and selected != "host":
    return 0
  actual_role = "broker" if role == "shell" and selected == "host" else role
  lease = "broker.lock" if actual_role == "broker" else "owner.lock"
  fd = os.open(session_path(lease), os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
  try:
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
  except BlockingIOError:
    os.close(fd)
    if actual_role == "broker":
      return 0  # Existing desktop already owns the single broker role.
    raise
  os.set_inheritable(fd, True)
  write_role(actual_role)
  environment = dict(os.environ)
  environment["OMARCHY_LOCK_HOST"] = "1" if selected == "host" else "0"
  if role == "host":
    for name in ("QML_IMPORT_PATH", "QML2_IMPORT_PATH", "QT_PLUGIN_PATH", "LD_PRELOAD", "LD_LIBRARY_PATH", "BASH_ENV", "ENV", "PYTHONPATH", "PYTHONHOME", "QT_QPA_PLATFORM_PLUGIN_PATH", "QT_QUICK_CONTROLS_CONF", "QT_QUICK_CONTROLS_STYLE_PATH", "QML_DISK_CACHE_PATH"):
      environment.pop(name, None)
    for name in list(environment):
      # Qt has several independent native/QML plugin selectors, including
      # generic plugins and keyboard styles. Use only this host's fixed ones.
      if name.startswith(("BASH_FUNC_", "QT_", "QML_", "QV4_", "QS_", "LD_")):
        environment.pop(name)
    environment["PATH"] = os.environ["OMARCHY_PATH"] + "/bin:/usr/bin:/bin"
    environment.update(QT_IM_MODULE="qtvirtualkeyboard", QT_IM_MODULES="qtvirtualkeyboard",
                       QT_VIRTUALKEYBOARD_DESKTOP_DISABLE="1", QT_QPA_PLATFORM="wayland", QT_QPA_PLATFORMTHEME="",
                       QT_QUICK_CONTROLS_STYLE="Basic", QML_DISABLE_DISK_CACHE="1", QS_DISABLE_FILE_WATCHER="1",
                       QS_NO_RELOAD_POPUP="1")
  try:
    os.execvpe(command[0], command, environment)
  finally:
    # Only reached on failed exec (or a test's intercepted exec).
    os.close(fd)


def stranded(own_pid):
  try:
    return inspect_stranded(own_pid)
  except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
    # Exit 1 specifically means a proven unlocked compositor to Service.qml.
    # A probe/identity/parse failure must never accidentally mean unlocked.
    return 2


def inspect_stranded(own_pid):
  result = subprocess.run([os.environ["OMARCHY_PATH"] + "/bin/omarchy-hyprland-session-locked"])
  if result.returncode != 0:
    return result.returncode if result.returncode in (1, 2) else 2
  try:
    if own_pid != role_pid("host") or own_pid != unit_pid() or mode() != "host":
      return 2
  except (OSError, ValueError, KeyError, subprocess.SubprocessError):
    return 2
  try:
    broker = role_pid("broker")
  except (OSError, ValueError, KeyError):
    # An absent/stale broker is never a reason to exempt another process.
    broker = None
  result = subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", "quickshell|qs|hyprlock"],
                          capture_output=True, text=True)
  if result.returncode not in (0, 1):
    return 2
  others = {int(pid) for pid in result.stdout.split()} - {own_pid}
  if broker is not None:
    others.discard(broker)
  return 2 if others else 0


def setup(action):
  if action == "status":
    try:
      current = mode()
    except FileNotFoundError:
      current = "no graphical owner selected"
    print("Current session: " + current + "; next session: " + ("host" if preference().is_file() else "shell"))
    return 0
  if action not in ("enable", "disable"):
    raise ValueError("expected enable, disable or status")
  # Two independent proofs before staging a future ownership change.
  state = subprocess.run([os.environ["OMARCHY_PATH"] + "/bin/omarchy-shell", "lock", "status"],
                         capture_output=True, text=True, timeout=2, check=True)
  data = json.loads(state.stdout)
  if any(data.get(key) is not False for key in ("locked", "requested", "secure")):
    raise ValueError("refusing ownership change without a known unlocked owner")
  if data.get("owner") == "trusted-host" and data.get("ready") is not True:
    raise ValueError("refusing ownership change while the trusted host is unready")
  if subprocess.run([os.environ["OMARCHY_PATH"] + "/bin/omarchy-hyprland-session-locked"]).returncode != 1:
    raise ValueError("compositor is locked or undetermined")
  unit = subprocess.run(["/usr/bin/systemctl", "--user", "show", UNIT, "--property=FragmentPath", "--value"],
                        capture_output=True, text=True, timeout=2, check=True).stdout.strip()
  if unit != "/usr/lib/systemd/user/" + UNIT:
    raise ValueError("install the reviewed packaged unit; user replacement units are not overwritten")
  overrides = subprocess.run(["/usr/bin/systemctl", "--user", "show", UNIT, "--property=DropInPaths", "--value"],
                             capture_output=True, text=True, timeout=2, check=True).stdout.strip()
  if overrides:
    raise ValueError("review/remove custom unit drop-ins before staging an owner change")
  subprocess.run(["/usr/bin/systemctl", "--user", action, UNIT], timeout=5, check=True)
  path = preference()
  if action == "enable":
    path.parent.mkdir(parents=True, exist_ok=True)
    path.touch(mode=0o600)
  else:
    path.unlink(missing_ok=True)
  print("Staged for the next graphical session; the current owner was not restarted or stopped.")
  return 0


def main():
  action, *args = sys.argv[1:]
  if action == "setup" and len(args) == 1:
    return setup(args[0])
  if action == "mode":
    print(mode(initialize=args == ["--initialize"]))
  elif action in ("run-shell", "run-host") and not args:
    root = os.environ["OMARCHY_PATH"]
    host = action == "run-host"
    command = ["/usr/bin/quickshell" if host else "quickshell", "-n", "-p", root + ("/shell/lock-host.qml" if host else "/shell")]
    return run("host" if host else "shell", command)
  elif action == "stranded" and len(args) == 1:
    return stranded(int(args[0]))
  elif not args and action in ("lock", "status", "isLocked"):
    state = request(action)
    print("ok" if action == "lock" else ("true" if state["locked"] or not state["ready"] else "false") if action == "isLocked" else json.dumps(state))
  else:
    raise ValueError("unsupported lock-host operation")
  return 0


if __name__ == "__main__":
  try:
    sys.exit(main())
  except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
    print("omarchy-lock-host: " + str(error), file=sys.stderr)
    sys.exit(1)
