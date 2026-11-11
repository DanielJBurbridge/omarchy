"""Optional RC71L desktop geometry; preserve unrelated TOML and back up changes."""

import copy
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tomllib


def run(*args):
  return subprocess.check_output(args, text=True).strip()


def upsert_bar(text, values):
  lines = text.splitlines(keepends=True)
  result, section, written = [], None, set()

  def missing():
    for key, value in values.items():
      if key not in written:
        result.append(f"{key} = {value}\n")
        written.add(key)

  for line in lines:
    header = re.match(r"\s*\[([^]]+)\]\s*(?:#.*)?$", line)
    if header:
      if section == "bar":
        missing()
      section = header[1]
    key = re.match(r"\s*([\w-]+)\s*=", line)
    if section == "bar" and key and key[1] in values:
      result.append(f"{key[1]} = {values[key[1]]}\n")
      written.add(key[1])
    else:
      result.append(line if line.endswith("\n") else line + "\n")
  if section == "bar":
    missing()
  if not written:
    result.append("\n[bar]\n")
    missing()
  updated = "".join(result)
  # The line editor supports the shell's simple TOML subset, but must not
  # interpret text inside a multiline string as a real section or setting.
  expected = copy.deepcopy(tomllib.loads(text))
  expected.setdefault("bar", {}).update({key: False if value == "false" else value for key, value in values.items()})
  if tomllib.loads(updated) != expected:
    raise ValueError("Unsupported shell TOML layout; no changes made.")
  return updated


def atomic_write(path, data):
  path.parent.mkdir(parents=True, exist_ok=True)
  temporary = path.with_name(path.name + ".ally-tmp")
  temporary.write_bytes(data)
  temporary.replace(path)


def main():
  action = sys.argv[1]
  if action not in ("apply", "reset"):
    raise ValueError("Use touch-preset [reset].")
  home = Path.home()
  state_home = Path(os.environ.get("XDG_STATE_HOME") or home / ".local/state")
  backup = state_home / "omarchy/rog-ally-display/touch-preset"
  paths = {
    "shell.toml": home / ".config/omarchy/shell.toml",
    "settings": state_home / "omarchy/monitors/settings",
  }
  if action == "reset":
    if not backup.exists():
      print("No Ally touch preset to restore.")
      return
    # A full backup makes rollback reviewable. Refuse to overwrite any changes
    # made since the preset, including dock layouts saved in the same file.
    for name, path in paths.items():
      current = path.read_bytes() if path.exists() else b""
      if current != (backup / (name + ".applied")).read_bytes():
        raise ValueError(f"{path} changed after setup. Merge {backup / (name + '.before')} manually; preserved current settings.")
    for name, path in paths.items():
      if (backup / (name + ".absent")).exists():
        path.unlink(missing_ok=True)
      else:
        atomic_write(path, (backup / (name + ".before")).read_bytes())
    run("omarchy-restart-hyprctl")
    for path in backup.iterdir():
      path.unlink()
    backup.rmdir()
    print("Restored the previous shell overrides and monitor settings.")
    return
  if backup.exists():
    print("Ally touch preset already saved; reset it before applying again.")
    return

  # Parse first; malformed user TOML must remain untouched. Theme values are
  # inherited before user overrides, matching the shell's token precedence.
  shell = paths["shell.toml"]
  text = shell.read_text() if shell.exists() else ""
  user = tomllib.loads(text)
  # Color.qml reads user overrides from HOME/.config and theme from state_home.
  theme_path = state_home / "omarchy/current/theme/shell.toml"
  theme = tomllib.loads(theme_path.read_text()) if theme_path.exists() else {}
  bar = dict(theme.get("bar", {})) | user.get("bar", {})
  font = dict(theme.get("font", {})) | user.get("font", {})
  factor = max(1, int(font.get("base-size", 12))) / 12 if bar.get("scale-with-font", True) else 1
  values = {key: max(44, math.ceil(int(bar.get(key, default)) * factor)) for key, default in (("size-horizontal", 26), ("size-vertical", 28))}
  values["scale-with-font"] = "false"
  applied = upsert_bar(text, values)
  tomllib.loads(applied)
  internal = run("omarchy-hyprland-monitor-laptop")
  if not re.fullmatch(r"(?:eDP|LVDS|DSI)-[A-Za-z0-9._-]+", internal):
    raise ValueError("No safe internal monitor; preset was not applied.")

  backup.mkdir(parents=True, mode=0o700)
  for name, path in paths.items():
    (backup / (name + ".before")).write_bytes(path.read_bytes() if path.exists() else b"")
    if not path.exists():
      (backup / (name + ".absent")).touch()
  try:
    run("omarchy-hyprland-monitor-scaling", "--monitor", internal, "1.5")
    atomic_write(shell, applied.encode())
  except Exception:
    for name, path in paths.items():
      if (backup / (name + ".absent")).exists():
        path.unlink(missing_ok=True)
      else:
        atomic_write(path, (backup / (name + ".before")).read_bytes())
    for path in backup.iterdir():
      path.unlink()
    backup.rmdir()
    run("omarchy-restart-hyprctl")
    raise
  for name, path in paths.items():
    (backup / (name + ".applied")).write_bytes(path.read_bytes() if path.exists() else b"")
  print(f"Internal scale: 1.5; bar: at least 44 logical pixels. Rollback backup: {backup}")


if __name__ == "__main__":
  try:
    main()
  except (ValueError, OSError, subprocess.CalledProcessError) as error:
    print(error, file=sys.stderr)
    sys.exit(1)
