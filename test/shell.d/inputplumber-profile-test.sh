#!/bin/bash
# The Ally profile helper: allowlist, O_NOFOLLOW, exact composite match,
# ProfileName Default, and the D-Bus policy that replaces the #48 loader.

set -uo pipefail

if [[ ${PROFILE_NS:-} != 1 ]]; then
  exec unshare --user --map-auto --map-root-user --mount --propagation private \
    env PROFILE_NS=1 bash "$0"
fi

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$here/base-test.sh"
set -euo pipefail

helper=$ROOT/bin/omarchy-inputplumber-profile
[[ -x $helper ]] || fail "the profile helper is executable"
[[ ! -e $ROOT/bin/omarchy-ally-pointer-load ]] || fail "the #48 loader is gone"
grep -q '^ExecStart=/usr/bin/omarchy-inputplumber-profile load pointer$' \
  "$ROOT/default/systemd/system/omarchy-ally-pointer.service" ||
  fail "the greeter unit calls the helper"
grep -q '^Before=display-manager.service$' \
  "$ROOT/default/systemd/system/omarchy-ally-pointer.service" ||
  fail "the greeter unit stays before the display manager"
grep -q '^ExecCondition=/usr/bin/omarchy-hw-rog-ally$' \
  "$ROOT/default/systemd/system/omarchy-ally-pointer.service" ||
  fail "the greeter unit is gated on the Ally"
grep -q 'omarchy-ally-pointer-load\|CompositeDevice0\|LoadProfilePath' \
  "$ROOT/default/systemd/system/omarchy-ally-pointer.service" &&
  fail "the greeter unit still names the #48 loader"
grep -q '^BusName=org.omarchy.InputPlumberProfile$' \
  "$ROOT/default/systemd/system/omarchy-inputplumber-profile.service" ||
  fail "the switch service owns its bus name"
grep -q '^ExecCondition=/usr/bin/omarchy-hw-rog-ally$' \
  "$ROOT/default/systemd/system/omarchy-inputplumber-profile.service" ||
  fail "the switch service is gated on the Ally"

migration=$ROOT/migrations/1794902400.sh
[[ $(stat -c %a -- "$migration") == 644 ]] || fail "the migration is mode 0644"
[[ $(head -1 "$migration") != '#!'* ]] || fail "the migration has no shebang"
grep -q '^echo "Replace the Ally pointer loader' "$migration" || fail "the migration says what it does"
grep -q 'omarchy-inputplumber-profile" install$' "$migration" || fail "the migration calls the helper"
grep -q 'pkexec\|NOPASSWD' "$migration" && fail "the migration uses pkexec or NOPASSWD"

if setpriv --reuid=1 --regid=1 --clear-groups "$helper" install; then
  fail "install as the desktop user is refused"
fi
pass "the #48 loader is gone and install is root-only"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cat > "$work/bin/omarchy-hw-rog-ally" <<'EOF'
#!/bin/bash
if [[ ${HW:-ally} == ally ]]; then
  exit 0
fi
exit 1
EOF
cat > "$work/bin/busctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${BUSCTL_LOG:?}"
exit 0
EOF
cat > "$work/bin/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${SYSTEMCTL_LOG:?}"
if [[ $1 == is-active ]]; then
  if [[ ${SERVICE:-inactive} == active ]]; then
    exit 0
  fi
  exit 3
fi
exit 0
EOF
chmod +x "$work/bin/"*

BUSCTL_LOG=$work/busctl.log SYSTEMCTL_LOG=$work/systemctl.log HW=laptop \
  PATH="$work/bin:$PATH" "$ROOT/bin/omarchy-gaming-input-profile"
[[ ! -s $work/busctl.log ]] || fail "gaming load does nothing off the Ally" "$(cat "$work/busctl.log")"
: > "$work/busctl.log"
BUSCTL_LOG=$work/busctl.log SYSTEMCTL_LOG=$work/systemctl.log HW=ally SERVICE=inactive \
  PATH="$work/bin:$PATH" "$ROOT/bin/omarchy-gaming-input-profile"
[[ ! -s $work/busctl.log ]] || fail "gaming load does nothing while the service is down" "$(cat "$work/busctl.log")"
: > "$work/busctl.log"
BUSCTL_LOG=$work/busctl.log SYSTEMCTL_LOG=$work/systemctl.log HW=ally SERVICE=active \
  PATH="$work/bin:$PATH" "$ROOT/bin/omarchy-gaming-input-profile"
[[ $(cat "$work/busctl.log") == "call org.omarchy.InputPlumberProfile /org/omarchy/InputPlumberProfile org.omarchy.InputPlumberProfile Load s gaming" ]] ||
  fail "gaming load asks the service for the gaming name" "$(cat "$work/busctl.log")"
grep -q 'LoadProfilePath\|CompositeDevice' "$work/busctl.log" &&
  fail "gaming load walks composites or passes a path" "$(cat "$work/busctl.log")"
pass "gaming load asks the service for one allowlisted name"

ROOT="$ROOT" WORK="$work" python3 - <<'PY'
import importlib.util
import os
import subprocess
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

root = Path(os.environ["ROOT"])
work = Path(os.environ["WORK"])
helper = root / "bin" / "omarchy-inputplumber-profile"
loader = SourceFileLoader("inputplumber_profile", str(helper))
spec = importlib.util.spec_from_loader("inputplumber_profile", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

problems = []

def check(condition, message):
  if not condition:
    problems.append(message)

def cp(code, stdout="", stderr=""):
  return subprocess.CompletedProcess(["busctl"], code, stdout, stderr)

profiles = root / "default/inputplumber/profiles"
gamepads = {"ds5", "ds5-edge", "deck", "deck-uhid", "xbox-elite"}
shipped = {
  "omarchy-ally-pointer.yaml": ("Omarchy Ally pointer", ["xbox-elite", "mouse", "keyboard"]),
  "desktop.yaml": ("Omarchy Ally desktop", ["xbox-elite", "mouse", "keyboard"]),
  "osk.yaml": ("Omarchy Ally osk", ["xbox-elite", "mouse", "keyboard"]),
  "gaming.yaml": ("Omarchy Ally gaming", ["ds5-edge", "mouse", "keyboard"]),
}
for filename, expected in shipped.items():
  text = (profiles / filename).read_text()
  check(mod.profile_meta(text) == expected, f"{filename} meta is {expected}")
  check("KeyLeftAlt" not in text and "KeyDelete" not in text, f"{filename} has no ctrl-alt-delete chord")
  check("LeftPaddle" not in text and "RightPaddle" not in text, f"{filename} maps no grip")

gaming = (profiles / "gaming.yaml").read_text()
_, gaming_targets = mod.profile_meta(gaming)
check(any(target in gamepads for target in gaming_targets), "gaming mode includes a gamepad Steam recognises")
check(set(gaming_targets) - {"mouse", "keyboard"}, "gaming is not a mouse and keyboard target list")
check("motion:" not in gaming, "gaming does not map a stick to the pointer")
check('button: "Guide"' in gaming and 'button: "West"' in gaming, "gaming keeps Guide then West")
for filename, (_name, targets) in shipped.items():
  check(targets is not None and any(target in gamepads for target in targets), f"{filename} keeps a gamepad target")
desktop = (profiles / "desktop.yaml").read_text()
osk = (profiles / "osk.yaml").read_text()
check('button: "Right"' in desktop and 'button: "Middle"' in desktop, "desktop keeps right and middle click")
def mapping_targets(text, button):
  lines = text.splitlines()
  for index, line in enumerate(lines):
    if line.strip() != f'button: "{button}"':
      continue
    chunk = []
    for later in lines[index + 1:]:
      if later.startswith("  - name:"):
        break
      chunk.append(later)
    return "\n".join(chunk)
  return ""

check('keyboard: "KeyBackspace"' in mapping_targets(osk, "East"), "osk east is backspace")
check("mouse:" not in mapping_targets(osk, "East"), "osk east is not a mouse button")
check('keyboard: "KeySpace"' in mapping_targets(osk, "West"), "osk west is space")
check("mouse:" not in mapping_targets(osk, "West"), "osk west is not a mouse button")
check(mod.ALLOWLIST["gamepad"] == "gamepad.yaml" and mod.ALLOWLIST["dualsense"] == "dualsense.yaml", "gamepad and dualsense stay allowlisted")
for bad in ("../etc/passwd", "pointer/../../tmp/evil", "Desktop", "desktop.yaml", "", "pointer "):
  try:
    mod.filename_for(bad)
    check(False, f"{bad!r} was accepted")
  except mod.ProfileError:
    pass

prefix = work / "profiles"
prefix.mkdir()
os.chmod(prefix, 0o755)
for filename in ("omarchy-ally-pointer.yaml", "desktop.yaml", "osk.yaml", "gaming.yaml"):
  dest = prefix / filename
  dest.write_bytes((profiles / filename).read_bytes())
  os.chmod(dest, 0o644)
mod.PREFIX = str(prefix)
mod.ally = lambda: True
mod.pause = lambda _seconds: None
mod.POINTER_ATTEMPTS = 3
mod.POINTER_INTERVAL = 0

class Bus:
  def __init__(self):
    self.calls = []
    self.tree = ""
    self.props = {}
    self.tree_codes = None

  def reset(self):
    self.calls = []

  def methods(self):
    return [call[4] for call in self.calls if call[0] in {"call", "set-property"}]

  def __call__(self, args):
    self.calls.append(list(args))
    if args[0] == "tree":
      if self.tree_codes:
        code = self.tree_codes.pop(0)
        if code != 0:
          return cp(code, "", "down")
      return cp(0, self.tree)
    if args[0] == "get-property":
      key = (args[2], args[4])
      if key not in self.props:
        return cp(1, "", "missing")
      return cp(0, self.props[key])
    return cp(0, "")

bus = Bus()
mod.run_busctl = bus

def prop(path, name, value):
  bus.props[(path, name)] = value

hidraw = "/org/shadowblip/InputPlumber/devices/source/hidraw0"
event = "/org/shadowblip/InputPlumber/devices/source/event3"
xpad = "/org/shadowblip/InputPlumber/devices/source/event4"
dock = "/org/shadowblip/InputPlumber/devices/source/hidraw9"
ally_x = "/org/shadowblip/InputPlumber/devices/source/hidraw8"
mouse = "/org/shadowblip/InputPlumber/devices/target/mouse0"
keyboard = "/org/shadowblip/InputPlumber/devices/target/keyboard0"
xbox = "/org/shadowblip/InputPlumber/devices/target/xbox0"
edge = "/org/shadowblip/InputPlumber/devices/target/edge0"
c0 = "/org/shadowblip/InputPlumber/CompositeDevice0"
c1 = "/org/shadowblip/InputPlumber/CompositeDevice1"
c2 = "/org/shadowblip/InputPlumber/CompositeDevice2"

bus.tree = "\n".join([c0, c1, c2, hidraw, event, xpad, dock, ally_x])
prop(hidraw, "DevPath", 's "/dev/hidraw0"')
prop(hidraw, "IdVendor", 's "0b05"')
prop(hidraw, "IdProduct", 's "1abe"')
prop(event, "DevicePath", 's "/dev/input/event3"')
prop(event, "IdVendor", 's "0b05"')
prop(event, "IdProduct", 's "1abe"')
prop(xpad, "DevicePath", 's "/dev/input/event4"')
prop(xpad, "IdVendor", 's "045e"')
prop(xpad, "IdProduct", 's "028e"')
prop(dock, "DevPath", 's "/dev/hidraw9"')
prop(dock, "IdVendor", 's "045e"')
prop(dock, "IdProduct", 's "028e"')
prop(ally_x, "DevPath", 's "/dev/hidraw8"')
prop(ally_x, "IdVendor", 's "0b05"')
prop(ally_x, "IdProduct", 's "1b4c"')
prop(c0, "Name", 's "USB Gamepad"')
prop(c0, "SourceDevicePaths", 'as 1 "/dev/hidraw9"')
prop(c1, "Name", 's "ASUS ROG Ally"')
prop(c1, "SourceDevicePaths", 'as 3 "/dev/hidraw0" "/dev/input/event3" "/dev/input/event4"')
prop(c1, "ProfileName", 's "Default"')
prop(c1, "TargetDevices", f'as 3 "{mouse}" "{keyboard}" "{xbox}"')
prop(c2, "Name", 's "ASUS ROG Ally X"')
prop(c2, "SourceDevicePaths", 'as 1 "/dev/hidraw8"')
prop(mouse, "DeviceType", 's "mouse"')
prop(keyboard, "DeviceType", 's "keyboard"')
prop(xbox, "DeviceType", 's "xbox-elite"')
prop(edge, "DeviceType", 's "ds5-edge"')

desktop_yaml = (prefix / "desktop.yaml").read_text()
check(mod.load("desktop") == 0, "desktop loads over ProfileName Default")
load_calls = [call for call in bus.calls if call[0] == "call"]
check(len(load_calls) == 1, f"one load call, got {len(load_calls)}")
if load_calls:
  check(load_calls[0][2] == c1, "the load hits the RC71L composite, not CompositeDevice0")
  check(load_calls[0][4] == "LoadProfileFromYaml", "the load uses LoadProfileFromYaml")
  check(load_calls[0][-1] == desktop_yaml, "the load sends the file bytes")
check("LoadProfilePath" not in bus.methods() and "SetTargetDevices" not in bus.methods(), "no path load and no SetTargetDevices")

bus.reset()
prop(c1, "ProfileName", 's "Omarchy Ally desktop"')
check(mod.load("desktop") == 0, "a matching desktop profile is skipped")
check(bus.methods() == [], "a skip does not call the daemon")

bus.reset()
prop(c1, "ProfileName", 's "Default"')
check(mod.load("desktop") == 0 and bus.methods() == ["LoadProfileFromYaml"], "Default is not treated as ours")

bus.reset()
prop(c1, "ProfileName", 's "Omarchy Ally desktop"')
prop(c1, "TargetDevices", f'as 1 "{keyboard}"')
check(mod.load("desktop") == 0 and bus.methods() == ["LoadProfileFromYaml"], "a missing mouse target is reloaded")
prop(c1, "TargetDevices", f'as 3 "{mouse}" "{keyboard}" "{xbox}"')

bus.reset()
prop(c1, "ProfileName", 's "Omarchy Ally pointer"')
check(mod.load("pointer") == 0 and bus.methods() == [], "pointer skips when the name matches and a target is live")
bus.reset()
prop(c1, "TargetDevices", "as 0")
check(mod.load("pointer") == 0 and bus.methods() == ["LoadProfileFromYaml"], "pointer reloads when no target is live")
prop(c1, "TargetDevices", f'as 3 "{mouse}" "{keyboard}" "{xbox}"')
prop(c1, "ProfileName", 's "Default"')

bus.reset()
prop(c2, "Name", 's "ASUS ROG Ally"')
prop(ally_x, "IdProduct", 's "1abe"')
check(mod.load("gaming") == 1 and bus.methods() == [], "two Ally composites are not loaded")
prop(c2, "Name", 's "ASUS ROG Ally X"')
prop(ally_x, "IdProduct", 's "1b4c"')

bus.reset()
prop(hidraw, "IdProduct", 's "1b4c"')
prop(event, "IdProduct", 's "1b4c"')
check(mod.load("gaming") == 0 and bus.methods() == [], "Ally X product 1b4c is not the RC71L")
prop(hidraw, "IdProduct", 's "1abe"')
prop(event, "IdProduct", 's "1abe"')

bus.reset()
prop(hidraw, "IdVendor", 's "0x0b05"')
prop(event, "IdVendor", 's "0B05"')
check(mod.load("gaming") == 0 and bus.methods() == [], "vendor text must be lowercase four digits")
prop(hidraw, "IdVendor", 's "0b05"')
prop(event, "IdVendor", 's "0b05"')

bus.reset()
saved = prefix / "desktop.yaml"
evil = work / "evil.yaml"
evil.write_text("name: evil\n")
os.chmod(evil, 0o644)
saved.unlink()
saved.symlink_to(evil)
check(mod.load("desktop") == 1 and bus.calls == [], "a symlink profile is not opened or loaded")
saved.unlink()
saved.write_text(desktop_yaml)
os.chmod(saved, 0o644)

os.chown(saved, 1, 1)
bus.reset()
check(mod.load("desktop") == 1 and bus.calls == [], "a profile owned by the desktop user is refused")
os.chown(saved, 0, 0)
os.chmod(saved, 0o666)
check(mod.load("desktop") == 1 and bus.calls == [], "a group-writable profile is refused")
os.chmod(saved, 0o644)

os.chmod(prefix, 0o777)
check(mod.load("desktop") == 1 and bus.calls == [], "a writable profile directory is refused")
os.chmod(prefix, 0o755)

link = work / "link"
real = work / "real"
real.mkdir()
os.chmod(real, 0o755)
link.symlink_to(real, target_is_directory=True)
(real / "profiles").mkdir()
os.chmod(real / "profiles", 0o755)
mod.PREFIX = str(link / "profiles")
check(mod.load("desktop") == 1 and bus.calls == [], "a symlink in the profile prefix is not followed")
mod.PREFIX = str(prefix)

bus.reset()
bus.tree_codes = [1, 1, 0]
check(mod.load("pointer", wait=True) == 0, "pointer waits out a down daemon")
check(sum(1 for call in bus.calls if call[0] == "tree") == 3, "pointer retries the daemon")
check(bus.methods() == ["LoadProfileFromYaml"], "pointer loads once the composite appears")

bus.reset()
bus.tree_codes = [1, 1, 1]
check(mod.load("pointer", wait=True) == 0 and bus.methods() == [], "pointer gives up without failing the greeter")

check(mod.load("nope") == 1, "an unknown name is an error")
check(mod.intercept(1) == 1 and mod.intercept(3) == 1, "intercept rejects values other than 0 and 2")
bus.reset()
check(mod.intercept(2) == 0, "intercept 2 is accepted")
sets = [call for call in bus.calls if call[0] == "set-property"]
check(len(sets) == 1 and sets[0][2] == c1 and sets[0][4:] == ["InterceptMode", "u", "2"], "intercept sets mode on the RC71L composite")

mod.ally = lambda: False
bus.reset()
check(mod.load("desktop") == 0 and bus.calls == [], "load does nothing off the Ally")
mod.ally = lambda: True

system = []

def fake_systemctl(args):
  system.append(list(args))
  if args[0] == "is-enabled":
    state = systemctl_state["value"]
    code = 0 if state in {"enabled", "alias"} else 1
    return cp(code, state + "\n")
  return cp(0, "")

systemctl_state = {"value": "not-found"}
mod.run_systemctl = fake_systemctl
mod.run_busctl = lambda args: cp(0, "")
dest = work / "root"
user_conf = dest / "etc/sddm.conf.d/omarchy-handheld-user.conf"
user_conf.parent.mkdir(parents=True)
user_conf.write_text("[Autologin]\nUser=daniel\n")
os.chmod(user_conf, 0o644)
check(mod.install_into(dest) == 0, "install writes the Ally policy")
unit = (dest / "etc/systemd/system/omarchy-ally-pointer.service").read_text()
check("omarchy-inputplumber-profile load pointer" in unit, "install ships the helper unit")
check("omarchy-ally-pointer-load" not in unit, "install does not keep the #48 ExecStart")
rule = (dest / "etc/polkit-1/rules.d/50-omarchy-inputplumber-profile.rules").read_text()
check('subject.user == "sddm"' in rule and "polkit.Result.NO" in rule, "the rule refuses sddm")
check("subject.active && subject.local && subject.user == \"daniel\"" in rule, "the rule allows the handheld user")
check("NOPASSWD" not in rule and "pkexec" not in rule, "the rule is not a sudoers grant")
check(all(not line.strip().startswith("polkit") or "shadowblip" not in line for line in rule.splitlines()), "the rule does not grant InputPlumber")
check(["enable", "omarchy-ally-pointer.service", "omarchy-inputplumber-profile.service"] in system, "a missing unit is enabled")
policy = (dest / "usr/share/dbus-1/system.d/org.omarchy.InputPlumberProfile.conf").read_text()
check('<allow own="org.omarchy.InputPlumberProfile"/>' in policy, "root may own the profile bus name")
check('<deny own="org.omarchy.InputPlumberProfile"/>' in policy, "other users may not own the profile bus name")
check("org.shadowblip" not in policy.split("-->", 1)[-1], "the bus policy grants no InputPlumber name")

system.clear()
systemctl_state["value"] = "disabled"
check(mod.install_into(dest) == 0, "install updates a disabled unit")
check(not any(call[0] == "enable" for call in system), "a disabled pointer unit stays disabled")

systemctl_state["value"] = "masked"
check(mod.install_into(dest) == 0 and not any(call[0] == "enable" for call in system), "a masked unit stays masked")

os.chmod(user_conf, 0o666)
systemctl_state["value"] = "enabled"
mod.install_into(dest)
loose = (dest / "etc/polkit-1/rules.d/50-omarchy-inputplumber-profile.rules").read_text()
check("polkit.Result.YES" not in loose, "a writable user file does not become a YES rule")
os.chmod(user_conf, 0o644)
user_conf.write_text("[Autologin]\nUser=sddm\n")
mod.install_into(dest)
sddm_rule = (dest / "etc/polkit-1/rules.d/50-omarchy-inputplumber-profile.rules").read_text()
check("polkit.Result.YES" not in sddm_rule, "sddm is never the YES user")

linked = dest / "etc/systemd/system/omarchy-ally-pointer.service"
linked.unlink()
linked.symlink_to("/tmp/not-our-unit")
check(mod.install_into(dest) == 1, "install refuses a symlinked unit")

mod.run_pkcheck = lambda args: cp(0 if args[1] == mod.LOAD_ACTION else 1)
check(mod.polkit_allowed(":1.9", mod.LOAD_ACTION), "pkcheck yes authorizes Load")
check(not mod.polkit_allowed(":1.9", mod.INTERCEPT_ACTION), "pkcheck no refuses intercept")
check(not mod.polkit_allowed("root", mod.LOAD_ACTION), "a sender that is not a unique name is refused")
check(not mod.polkit_allowed(":1.9", "org.shadowblip.Input.CompositeDevice.LoadProfilePath"), "InputPlumber actions are not ours")

env = os.environ.copy()
env["PATH"] = str(work / "bin") + os.pathsep + env.get("PATH", "")
env["HW"] = "ally"
env["BUSCTL_LOG"] = str(work / "cli-busctl.log")
def run_cli(*args, hw="ally"):
  env["HW"] = hw
  log = work / "cli-busctl.log"
  log.write_text("")
  proc = subprocess.run([str(helper), *args], env=env, text=True, capture_output=True)
  return proc.returncode, log.read_text()

code, log = run_cli("load", "../etc/passwd")
check(code == 1 and log == "", "the CLI rejects a path and does not call busctl")
code, log = run_cli("intercept", "1")
check(code == 1 and log == "", "the CLI rejects intercept 1")
code, log = run_cli("intercept", "00")
check(code == 1 and log == "", "the CLI rejects intercept 00")
code, log = run_cli("load", "pointer", hw="laptop")
check(code == 0 and log == "", "the CLI loads nothing off the Ally")
code, log = run_cli("load", "pointer")
check(code == 0 and log == "", "a missing pointer file does not retry the daemon")
code, _log = run_cli()
check(code == 2, "usage is exit 2")

if problems:
  print("\n".join(problems), file=sys.stderr)
  sys.exit(1)
print("ok - profile loads, skips and policy")
PY
pass "profile loads, skips and policy"
