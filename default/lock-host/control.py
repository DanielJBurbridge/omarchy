"""Private trusted-lock process selection, identity and lock/status client.

No operation accepts passwords, unlock requests, code or application commands
from a socket. Configuration and role files are data, never imported/executed.
"""
from contextlib import contextmanager
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
  if not path.exists() and not initialize:
    # The launcher that predates session selection never wrote this file.
    # The running shell still owns the generic lock. A lock or status query
    # must not create the file or latch the trusted host.
    return "shell"
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


def reviewed_unit():
  result = subprocess.run(["/usr/bin/systemctl", "--user", "show", UNIT, "--property=MainPID",
                           "--property=FragmentPath", "--property=DropInPaths", "--all"],
                          capture_output=True, text=True, timeout=1, check=True)
  lines = result.stdout.splitlines()
  data = dict(line.split("=", 1) for line in lines)
  if len(data) != len(lines) or set(data) != {"MainPID", "FragmentPath", "DropInPaths"}:
    raise ValueError("incomplete lock-host unit identity")
  if data["FragmentPath"] != "/usr/lib/systemd/user/" + UNIT or data["DropInPaths"]:
    raise ValueError("lock host requires the reviewed packaged unit without drop-ins")
  pid = int(data["MainPID"])
  if pid < 0:
    raise ValueError("invalid lock-host unit PID")
  return pid


def unit_pid():
  return reviewed_unit()


def checked_peer(connection):
  pid, uid, _gid = struct.unpack("3i", connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
  if uid != os.getuid() or pid != role_pid("host") or pid != unit_pid():
    raise ValueError("untrusted lock-host peer")


def wayland_display(runtime):
  display = os.environ.get("WAYLAND_DISPLAY", "")
  if display:
    return display
  # restart-shell recovers the compositor signature for a TTY or SSH caller
  # and then asks for context. The display is the socket of that same session.
  # The peer check below rejects a socket that belongs to a different compositor.
  candidates = []
  for path in runtime.glob("wayland-[0-9]*"):
    if not re.fullmatch(r"wayland-[0-9]+", path.name):
      continue
    if path.is_symlink() or not path.is_socket():
      continue
    candidates.append(path)
  if not candidates:
    raise ValueError("lock IPC requires the current Wayland display")
  candidates.sort(key=lambda path: path.stat().st_mtime, reverse=True)
  return candidates[0].name


def context():
  # Lock IPC never guesses a session from the newest socket or caller env
  # alone. Bind both endpoints to the same live system compositor and live owner.
  # A TTY or SSH restart may omit WAYLAND_DISPLAY after recovering the signature;
  # that display is taken from the matching socket, then checked like any other.
  selected = mode()
  runtime, instance = paths()
  display = wayland_display(runtime)
  if not display:
    raise ValueError("lock IPC requires the current Wayland display")
  display_path = Path(display) if display.startswith("/") else runtime / display
  if selected == "host":
    pid = role_pid("host")
    if pid != unit_pid():
      raise ValueError("trusted host is not the actual unit owner")
    owner_env = dict(entry.split(b"=", 1) for entry in Path(f"/proc/{pid}/environ").read_bytes().split(b"\0") if b"=" in entry)
    if owner_env.get(b"HYPRLAND_INSTANCE_SIGNATURE") != os.fsencode(instance):
      raise ValueError("owner belongs to another compositor instance")
    owner_display = os.fsdecode(owner_env.get(b"WAYLAND_DISPLAY", b""))
    owner_path = Path(owner_display) if owner_display.startswith("/") else runtime / owner_display
    if not owner_display or owner_path.resolve() != display_path.resolve():
      raise ValueError("caller display does not match the selected lock owner")
  # Generic owner death must not prevent querying/recovering its compositor
  # failsafe. The two verified compositor peers still bind that route exactly.
  peers = []
  for path in (display_path, runtime / "hypr" / instance / ".socket.sock"):
    with socket.socket(socket.AF_UNIX) as connection:
      connection.settimeout(0.7)
      connection.connect(str(path))
      peer_pid, uid, _gid = struct.unpack("3i", connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
      if uid != os.getuid() or Path(f"/proc/{peer_pid}/exe").resolve() != Path("/usr/bin/Hyprland").resolve():
        raise ValueError("lock IPC compositor peer is not trusted")
      peers.append(peer_pid)
  if peers[0] != peers[1]:
    raise ValueError("signature and display belong to different compositors")
  return selected


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
      # Explicit requests can re-arm an exhausted bounded orphan check. Send
      # even while unready; the reply must still prove requested/secure.
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


@contextmanager
def owner_lease(path):
  # The successful exec does not return, so the owner keeps this descriptor.
  # Every other exit, including a failed exec or a role write, closes it.
  fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
  try:
    try:
      fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
      os.close(fd)
      fd = -1
      raise
    os.set_inheritable(fd, True)
    yield fd
  finally:
    if fd >= 0:
      os.close(fd)


def run(role, command):
  if role == "shell" and not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
    os.execvpe(command[0], command, dict(os.environ, OMARCHY_LOCK_HOST="0"))
  selected = mode(initialize=True)
  if role == "host" and selected != "host":
    return 0
  if role == "host" and unit_pid() != os.getpid():
    raise ValueError("trusted host must launch as the reviewed unit MainPID")
  actual_role = "broker" if role == "shell" and selected == "host" else role
  lease = "broker.lock" if actual_role == "broker" else "owner.lock"
  try:
    with owner_lease(session_path(lease)):
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
      os.execvpe(command[0], command, environment)
  except BlockingIOError:
    if actual_role == "broker":
      return 0  # Existing desktop already owns the single broker role.
    raise


def stranded(own_pid):
  try:
    return inspect_stranded(own_pid)
  except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
    # Exit 1 specifically means a proven unlocked compositor to Service.qml.
    # A probe/identity/parse failure must never accidentally mean unlocked.
    return 2


def inspect_stranded(own_pid):
  try:
    if own_pid != role_pid("host") or own_pid != unit_pid() or mode() != "host":
      return 2
  except (OSError, ValueError, KeyError, subprocess.SubprocessError):
    return 2
  result = subprocess.run([os.environ["OMARCHY_PATH"] + "/bin/omarchy-hyprland-session-locked"])
  if result.returncode != 0:
    return result.returncode if result.returncode in (1, 2) else 2
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
  reviewed_unit()  # Same manifest proof used at launch, peer and recovery boundaries.
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
  elif action == "context" and not args:
    print(context())
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
