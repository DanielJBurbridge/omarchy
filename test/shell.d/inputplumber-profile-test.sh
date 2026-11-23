#!/bin/bash
# The Ally profile helper: allowlist, O_NOFOLLOW, exact composite match,
# ProfileName Default, and the D-Bus policy for omarchy-inputplumber-profile.

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
[[ ! -e $ROOT/bin/omarchy-ally-pointer-load ]] || fail "the old pointer loader is still shipped"
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
  fail "the greeter unit still names the old pointer loader"
grep -q '^BusName=org.omarchy.InputPlumberProfile$' \
  "$ROOT/default/systemd/system/omarchy-inputplumber-profile.service" ||
  fail "the switch service owns its bus name"
grep -q '^ExecCondition=/usr/bin/omarchy-hw-rog-ally$' \
  "$ROOT/default/systemd/system/omarchy-inputplumber-profile.service" ||
  fail "the switch service is gated on the Ally"

migration=$ROOT/migrations/1794902400.sh
[[ $(stat -c %a -- "$migration") == 644 ]] || fail "the migration is mode 0644"
[[ $(head -1 "$migration") != '#!'* ]] || fail "the migration has no shebang"
grep -q '^echo "Point the Ally greeter' "$migration" || fail "the migration says what it does"
grep -q 'omarchy-inputplumber-profile" install-greeter$' "$migration" || fail "the migration rewrites the greeter unit"
grep -q 'install-service' "$migration" && fail "the greeter migration installs the profile service"
grep -q 'pkexec\|NOPASSWD' "$migration" && fail "the migration uses pkexec or NOPASSWD"
service_migration=$ROOT/migrations/1794988800.sh
[[ $(stat -c %a -- "$service_migration") == 644 ]] || fail "the service migration is mode 0644"
grep -q 'omarchy-pkg-present omarchy-gaming-session' "$service_migration" || fail "the service migration requires the gaming session package"
grep -q 'install-service$' "$service_migration" || fail "the service migration installs the profile service"
grep -q 'install-greeter' "$ROOT/install/hardware/asus/inputplumber.sh" || fail "the hardware leaf installs the greeter unit"
grep -q 'install-service' "$ROOT/install/hardware/asus/inputplumber.sh" && fail "the hardware leaf installs the profile service"
grep -q 'omarchy-pkg-present omarchy-gaming-session' "$ROOT/install/hardware/asus/gaming-session.sh" || fail "the gaming session leaf is opt-in"
grep -q 'install-service' "$ROOT/packages/omarchy-gaming-session/omarchy-gaming-session.install" || fail "the package installs the profile service"
grep -q 'remove-service' "$ROOT/packages/omarchy-gaming-session/omarchy-gaming-session.install" || fail "removing the package removes the profile service"

if setpriv --reuid=1 --regid=1 --clear-groups "$helper" install-greeter; then
  fail "install as the desktop user is refused"
fi
pass "the greeter calls omarchy-inputplumber-profile and install is root-only"

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
  "gaming.yaml": ("Omarchy Ally gaming", ["deck", "mouse", "keyboard"]),
}
for filename, expected in shipped.items():
  text = (profiles / filename).read_text()
  check(mod.profile_meta(text) == expected, f"{filename} meta is {expected}")
  check("KeyLeftAlt" not in text and "KeyDelete" not in text, f"{filename} has no ctrl-alt-delete chord")
  check("LeftPaddle" not in text and "RightPaddle" not in text, f"{filename} maps no grip")

gaming = (profiles / "gaming.yaml").read_text()
_, gaming_targets = mod.profile_meta(gaming)
check(gaming_targets == ["deck", "mouse", "keyboard"], "gaming presents the Steam Deck (28de:1205)")
check(not any(name in gaming_targets for name in ("ds5-edge", "xbox-elite", "xbox-series", "deck-uhid")), "gaming is not an Edge, Elite, Series or uhid target")
check(any(target in gamepads for target in gaming_targets), "gaming mode includes a gamepad Steam recognises")
check(set(gaming_targets) - {"mouse", "keyboard"}, "gaming is not a mouse and keyboard target list")
check("motion:" not in gaming, "gaming does not map a stick to the pointer")
check('button: "Guide"' in gaming and 'button: "West"' in gaming, "gaming keeps Guide then West")
check('button: "QuickAccess"' not in gaming, "Armoury short stays unmapped so QAM passes through")
check('button: "QuickAccess2"' in gaming and 'dbus: "omarchy_overlay"' in gaming, "Armoury long stays the overlay")
for filename in ("omarchy-ally-pointer.yaml", "desktop.yaml", "osk.yaml"):
  other = (profiles / filename).read_text()
  check("deck" not in other and "ds5-edge" not in other, f"{filename} stays on xbox-elite")
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
hidden = real / "profiles"
hidden.mkdir()
os.chmod(hidden, 0o755)
behind = hidden / "desktop.yaml"
behind.write_text(desktop_yaml)
os.chmod(behind, 0o644)
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
os.environ["OMARCHY_PATH"] = str(root)
check(mod.install_greeter_into(dest) == 0, "the greeter install rewrites the pointer unit")
check(mod.install_service_into(dest) == 0, "the service install writes the Ally policy")
unit = (dest / "etc/systemd/system/omarchy-ally-pointer.service").read_text()
check("omarchy-inputplumber-profile load pointer" in unit, "install ships the helper unit")
check("omarchy-ally-pointer-load" not in unit, "install does not keep the old loader")
rule = (dest / "etc/polkit-1/rules.d/50-omarchy-inputplumber-profile.rules").read_text()
check('subject.user == "sddm"' in rule and "polkit.Result.NO" in rule, "the rule refuses sddm")
check("subject.active && subject.local && subject.user == \"daniel\"" in rule, "the rule allows the handheld user")
check("NOPASSWD" not in rule and "pkexec" not in rule, "the rule is not a sudoers grant")
check(all(not line.strip().startswith("polkit") or "shadowblip" not in line for line in rule.splitlines()), "the rule does not grant InputPlumber")
check(["enable", "omarchy-ally-pointer.service"] in system, "a missing greeter unit is enabled")
check(["enable", "omarchy-inputplumber-profile.service"] in system, "a missing profile service is enabled")
policy = (dest / "usr/share/dbus-1/system.d/org.omarchy.InputPlumberProfile.conf").read_text()
check('<allow own="org.omarchy.InputPlumberProfile"/>' in policy, "root may own the profile bus name")
check('<deny own="org.omarchy.InputPlumberProfile"/>' in policy, "other users may not own the profile bus name")
check("org.shadowblip" not in policy.split("-->", 1)[-1], "the bus policy grants no InputPlumber name")

system.clear()
systemctl_state["value"] = "disabled"
check(mod.install_greeter_into(dest) == 0, "install updates a disabled unit")
check(not any(call[0] == "enable" for call in system), "a disabled pointer unit stays disabled")

kept_pointer = (dest / "etc/systemd/system/omarchy-ally-pointer.service").read_text()
system.clear()
systemctl_state["value"] = "masked"
masked = dest / "etc/systemd/system/omarchy-ally-pointer.service"
masked.unlink()
masked.symlink_to("/dev/null")
check(mod.install_greeter_into(dest) == 0, "a masked pointer unit does not fail the greeter install")
check(masked.is_symlink() and os.path.realpath(masked) == os.path.realpath("/dev/null"), "the mask symlink stays")
check(not any(call[0] == "enable" for call in system), "a masked unit is not enabled")
check(mod.install_service_into(dest) == 0, "a masked greeter unit does not block the profile service")
check((dest / "etc/polkit-1/rules.d/50-omarchy-inputplumber-profile.rules").is_file(), "the profile service still installs its rule")
masked.unlink()
systemctl_state["value"] = "not-found"
check(mod.install_greeter_into(dest) == 0, "the greeter unit can be installed again after the mask is removed")
check((dest / "etc/systemd/system/omarchy-ally-pointer.service").read_text() == kept_pointer, "removing the mask installs the helper unit")

os.chmod(user_conf, 0o666)
systemctl_state["value"] = "enabled"
mod.install_service_into(dest)
loose = (dest / "etc/polkit-1/rules.d/50-omarchy-inputplumber-profile.rules").read_text()
check("polkit.Result.YES" not in loose, "a writable user file does not become a YES rule")
os.chmod(user_conf, 0o644)
user_conf.write_text("[Autologin]\nUser=sddm\n")
mod.install_service_into(dest)
sddm_rule = (dest / "etc/polkit-1/rules.d/50-omarchy-inputplumber-profile.rules").read_text()
check("polkit.Result.YES" not in sddm_rule, "sddm is never the YES user")
user_conf.write_text("[Autologin]\nUser=daniel\n")
check(mod.install_service_into(dest) == 0, "installing the service again reads the new user")
refreshed = (dest / "etc/polkit-1/rules.d/50-omarchy-inputplumber-profile.rules").read_text()
check('subject.user == "daniel"' in refreshed, "a later user file becomes the YES user")

linked = dest / "etc/systemd/system/omarchy-ally-pointer.service"
linked.unlink()
linked.symlink_to("/tmp/not-our-unit")
check(mod.install_greeter_into(dest) == 1, "install refuses a symlinked unit")
linked.unlink()

service_paths = [dest / rel for rel in mod.SERVICE_FILES]
check(mod.remove_service_into(dest) == 0, "removing the gaming session drops the profile service")
check(all(not path.exists() for path in service_paths), "the service, policy and rule are removed")
check(not (dest / "etc/systemd/system/omarchy-ally-pointer.service").exists(), "the greeter unit was already unlinked for the symlink test")

bare = work / "bare"
mod.INSTALL_ROOT = bare
mod.gaming_session_installed = lambda: False
systemctl_state["value"] = "not-found"
system.clear()
check(mod.install_greeter() == 0, "an Ally without the package still installs the greeter")
check((bare / "etc/systemd/system/omarchy-ally-pointer.service").is_file(), "the greeter unit is the only unit")
check(mod.install_service() == 0, "an Ally without the package does not install the service")
check(all(not (bare / rel).exists() for rel in mod.SERVICE_FILES), "an Ally without the package gets no service, policy or rule")

hookroot = work / "hookroot"
mod.INSTALL_ROOT = hookroot
mod.gaming_session_installed = lambda: True
systemctl_state["value"] = "not-found"
check(mod.install_greeter() == 0 and mod.install_service() == 0, "the package hook has a greeter and a service")
hook_bin = work / "hookbin"
hook_bin.mkdir()
hook_calls = work / "hook-calls"
hook_stub = hook_bin / "omarchy-inputplumber-profile"
hook_stub.write_text(
  "#!/usr/bin/python3\n"
  "import os, sys\n"
  "from importlib.machinery import SourceFileLoader\n"
  "from importlib.util import module_from_spec, spec_from_loader\n"
  "from pathlib import Path\n"
  "import subprocess\n"
  "calls = Path(os.environ['HOOK_CALLS'])\n"
  "with calls.open('a') as handle:\n"
  "    handle.write(sys.argv[1] + '\\n')\n"
  "if sys.argv[1] != 'remove-service':\n"
  "    raise SystemExit(0)\n"
  "loader = SourceFileLoader('hooked_profile', os.environ['HOOK_HELPER'])\n"
  "spec = spec_from_loader('hooked_profile', loader)\n"
  "hooked = module_from_spec(spec)\n"
  "loader.exec_module(hooked)\n"
  "hooked.run_systemctl = lambda args: subprocess.CompletedProcess(['systemctl'], 0, '', '')\n"
  "hooked.run_busctl = lambda args: subprocess.CompletedProcess(['busctl'], 0, '', '')\n"
  "raise SystemExit(hooked.remove_service_into(Path(os.environ['HOOK_ROOT'])))\n"
)
os.chmod(hook_stub, 0o755)
hook_env = os.environ.copy()
hook_env["PATH"] = str(hook_bin) + os.pathsep + hook_env.get("PATH", "")
hook_env["HOOK_CALLS"] = str(hook_calls)
hook_env["HOOK_HELPER"] = str(helper)
hook_env["HOOK_ROOT"] = str(hookroot)
hook_env["OMARCHY_SDDM_CONF_DIR"] = str(work / "hook-sddm")
hook_script = root / "packages/omarchy-gaming-session/omarchy-gaming-session.install"

def run_hook(function):
  hook_calls.write_text("")
  proc = subprocess.run(
    ["bash", "-c", f"source {hook_script}; {function}"],
    env=hook_env,
    text=True,
    capture_output=True,
  )
  check(proc.returncode == 0, f"{function} exits 0")
  return hook_calls.read_text().split()

check(run_hook("post_install") == ["install-service"], "post_install installs the profile service")
check(run_hook("post_upgrade") == ["install-service"], "post_upgrade installs the profile service")
check(all((hookroot / rel).is_file() for rel in mod.SERVICE_FILES), "the service files are present before removal")
check(run_hook("post_remove") == ["remove-service"], "post_remove removes the profile service")
check(all(not (hookroot / rel).exists() for rel in mod.SERVICE_FILES), "post_remove deletes the service, policy and rule")
check((hookroot / "etc/systemd/system/omarchy-ally-pointer.service").is_file(), "post_remove leaves the greeter unit")

laptop = work / "laptop"
mod.INSTALL_ROOT = laptop
mod.ally = lambda: False
mod.gaming_session_installed = lambda: True
system.clear()
check(mod.install_greeter() == 0 and mod.install_service() == 0, "install does nothing off the Ally")
check(not laptop.exists(), "a laptop gets no unit, policy or rule")
mod.ally = lambda: True

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

warn_bin=$work/warnbin
mkdir -p "$warn_bin" "$work/warn-sddm"
cat > "$warn_bin/omarchy-inputplumber-profile" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${WARN_CALLS:?}"
exit 1
EOF
chmod 755 "$warn_bin/omarchy-inputplumber-profile"
# shellcheck source=/dev/null
source "$ROOT/packages/omarchy-gaming-session/omarchy-gaming-session.install"
: > "$work/warn-calls"
if ! PATH="$warn_bin:$PATH" WARN_CALLS=$work/warn-calls \
  OMARCHY_SDDM_CONF_DIR=$work/warn-sddm \
  post_install >"$work/warn.out" 2>"$work/warn.err"; then
  fail "a failed profile install still lets post_install return"
fi
[[ $(cat "$work/warn-calls") == install-service ]] ||
  fail "post_install still runs the profile install" "$(cat "$work/warn-calls")"
grep -F 'warning: InputPlumber profile service install failed; re-run: omarchy-inputplumber-profile install-service' \
  "$work/warn.err" ||
  fail "post_install names the failed step and the re-run command" "$(cat "$work/warn.err")"
printf '[Autologin]\nUser=daniel\n' > "$work/warn-sddm/omarchy-handheld-user.conf"
: > "$work/warn-calls"
if ! PATH="$warn_bin:$PATH" WARN_CALLS=$work/warn-calls \
  OMARCHY_SDDM_CONF_DIR=$work/warn-sddm \
  post_remove >"$work/warn-remove.out" 2>"$work/warn-remove.err"; then
  fail "a failed profile removal still lets post_remove return"
fi
grep -F 'warning: InputPlumber profile service removal failed; re-run: omarchy-inputplumber-profile remove-service' \
  "$work/warn-remove.err" ||
  fail "post_remove names the failed step and the re-run command" "$(cat "$work/warn-remove.err")"
[[ ! -e $work/warn-sddm/omarchy-handheld-user.conf ]] ||
  fail "post_remove leaves the handheld User= file"
pass "a failed profile scriptlet warns and still returns"

pkg=$work/pkg
mkdir -p "$pkg/usr/bin" "$pkg/usr/share/omarchy/bin" "$pkg/usr/share/omarchy/default" \
  "$pkg/etc/systemd/system" "$pkg/dbus" "$pkg/polkit-actions" "$pkg/polkit-rules"
cp "$ROOT/bin/omarchy-inputplumber-profile" "$pkg/usr/bin/omarchy-inputplumber-profile"
chmod 755 "$pkg/usr/bin/omarchy-inputplumber-profile"
ln -s ../../../bin/omarchy-inputplumber-profile "$pkg/usr/share/omarchy/bin/omarchy-inputplumber-profile"
cp -a "$ROOT/default/systemd" "$ROOT/default/inputplumber" "$pkg/usr/share/omarchy/default/"
cat > "$pkg/usr/bin/omarchy-hw-rog-ally" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$pkg/usr/bin/omarchy-pkg-present" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$pkg/usr/bin/systemctl" <<'EOF'
#!/bin/bash
if [[ ${1:-} == is-enabled ]]; then
  printf 'not-found\n'
  exit 1
fi
exit 0
EOF
cat > "$pkg/usr/bin/busctl" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod 755 "$pkg/usr/bin/omarchy-hw-rog-ally" "$pkg/usr/bin/omarchy-pkg-present" \
  "$pkg/usr/bin/systemctl" "$pkg/usr/bin/busctl"

pkg_mounts=()
pkg_cleanup() {
  local i
  for (( i=${#pkg_mounts[@]}-1; i>=0; i-- )); do
    umount "${pkg_mounts[i]}" || true
  done
  rm -rf "$work"
}
trap pkg_cleanup EXIT
mount --bind "$pkg/etc/systemd/system" /etc/systemd/system
pkg_mounts+=("/etc/systemd/system")
mount --bind "$pkg/dbus" /usr/share/dbus-1/system.d
pkg_mounts+=("/usr/share/dbus-1/system.d")
mount --bind "$pkg/polkit-actions" /usr/share/polkit-1/actions
pkg_mounts+=("/usr/share/polkit-1/actions")
mount --bind "$pkg/polkit-rules" /etc/polkit-1/rules.d
pkg_mounts+=("/etc/polkit-1/rules.d")

run_packaged() {
  env -i PATH="$pkg/usr/bin:/usr/bin:/bin" OMARCHY_PATH="$pkg/usr/share/omarchy" "$@"
}
if ! run_packaged "$pkg/usr/bin/omarchy-inputplumber-profile" install-greeter >"$pkg/greeter.out" 2>"$pkg/greeter.err"; then
  fail "install-greeter fails on the packaged layout" "$(cat "$pkg/greeter.err")"
fi
if ! run_packaged "$pkg/usr/share/omarchy/bin/omarchy-inputplumber-profile" install-service >"$pkg/service.out" 2>"$pkg/service.err"; then
  fail "install-service fails on the packaged layout" "$(cat "$pkg/service.err")"
fi
grep -q '^ExecStart=/usr/bin/omarchy-inputplumber-profile load pointer$' \
  /etc/systemd/system/omarchy-ally-pointer.service ||
  fail "the packaged greeter unit does not call the helper" "$(cat /etc/systemd/system/omarchy-ally-pointer.service)"
grep -q 'omarchy-ally-pointer-load' /etc/systemd/system/omarchy-ally-pointer.service &&
  fail "the packaged greeter unit names the old loader"
[[ -f /etc/systemd/system/omarchy-inputplumber-profile.service ]] || fail "the packaged install skips the profile service"
[[ -f /usr/share/dbus-1/system.d/org.omarchy.InputPlumberProfile.conf ]] || fail "the packaged install skips the bus policy"
[[ -f /usr/share/polkit-1/actions/org.omarchy.inputplumber-profile.policy ]] || fail "the packaged install skips the polkit action"
[[ -f /etc/polkit-1/rules.d/50-omarchy-inputplumber-profile.rules ]] || fail "the packaged install skips the polkit rule"
pass "a packaged layout installs the greeter unit and the profile service"

# sudo and pacman start this helper with OMARCHY_PATH unset. The files then
# come from /usr/share/omarchy, not from the directory that holds the binary.
printf '\n# package-root=/usr/share/omarchy\n' >> \
  "$pkg/usr/share/omarchy/default/systemd/system/omarchy-ally-pointer.service"
rm -f /etc/systemd/system/omarchy-ally-pointer.service \
  /etc/systemd/system/omarchy-inputplumber-profile.service \
  /usr/share/dbus-1/system.d/org.omarchy.InputPlumberProfile.conf \
  /usr/share/polkit-1/actions/org.omarchy.inputplumber-profile.policy \
  /etc/polkit-1/rules.d/50-omarchy-inputplumber-profile.rules
mount -t tmpfs tmpfs /usr/share
pkg_mounts+=("/usr/share")
mkdir -p /usr/share/omarchy /usr/share/dbus-1/system.d /usr/share/polkit-1/actions
mount --bind "$pkg/usr/share/omarchy" /usr/share/omarchy
pkg_mounts+=("/usr/share/omarchy")
mount --bind "$pkg/dbus" /usr/share/dbus-1/system.d
pkg_mounts+=("/usr/share/dbus-1/system.d")
mount --bind "$pkg/polkit-actions" /usr/share/polkit-1/actions
pkg_mounts+=("/usr/share/polkit-1/actions")
run_unset() {
  env -i PATH="$pkg/usr/bin:/usr/bin:/bin" "$@"
}
if ! run_unset "$pkg/usr/bin/omarchy-inputplumber-profile" install-greeter \
  >"$pkg/unset-greeter.out" 2>"$pkg/unset-greeter.err"; then
  fail "install-greeter fails when OMARCHY_PATH is unset" "$(cat "$pkg/unset-greeter.err")"
fi
if ! run_unset "$pkg/usr/bin/omarchy-inputplumber-profile" install-service \
  >"$pkg/unset-service.out" 2>"$pkg/unset-service.err"; then
  fail "install-service fails when OMARCHY_PATH is unset" "$(cat "$pkg/unset-service.err")"
fi
grep -q '^ExecStart=/usr/bin/omarchy-inputplumber-profile load pointer$' \
  /etc/systemd/system/omarchy-ally-pointer.service ||
  fail "an unset OMARCHY_PATH does not install the greeter unit" \
  "$(cat /etc/systemd/system/omarchy-ally-pointer.service)"
grep -q '^# package-root=/usr/share/omarchy$' \
  /etc/systemd/system/omarchy-ally-pointer.service ||
  fail "an unset OMARCHY_PATH does not read /usr/share/omarchy" \
  "$(cat /etc/systemd/system/omarchy-ally-pointer.service)"
[[ -f /etc/systemd/system/omarchy-inputplumber-profile.service ]] ||
  fail "an unset OMARCHY_PATH skips the profile service"
[[ -f /usr/share/dbus-1/system.d/org.omarchy.InputPlumberProfile.conf ]] ||
  fail "an unset OMARCHY_PATH skips the bus policy"
[[ -f /usr/share/polkit-1/actions/org.omarchy.inputplumber-profile.policy ]] ||
  fail "an unset OMARCHY_PATH skips the polkit action"
[[ -f /etc/polkit-1/rules.d/50-omarchy-inputplumber-profile.rules ]] ||
  fail "an unset OMARCHY_PATH skips the polkit rule"
pass "an unset OMARCHY_PATH reads /usr/share/omarchy"
