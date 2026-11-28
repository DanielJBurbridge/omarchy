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
grep -q '^ExecStart=/usr/bin/omarchy-ally-pointer$' \
  "$ROOT/default/systemd/system/omarchy-ally-pointer.service" ||
  fail "the greeter unit calls the helper"
grep -q '^Before=display-manager.service$' \
  "$ROOT/default/systemd/system/omarchy-ally-pointer.service" ||
  fail "the greeter unit stays before the display manager"
grep -q 'omarchy-ally-pointer-load\|CompositeDevice0\|LoadProfilePath' \
  "$ROOT/default/systemd/system/omarchy-ally-pointer.service" &&
  fail "the greeter unit still names the old pointer loader"
grep -q '^BusName=org.omarchy.InputPlumberProfile$' \
  "$ROOT/default/systemd/system/omarchy-inputplumber-profile.service" ||
  fail "the switch service owns its bus name"

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
vhci_migration=$ROOT/migrations/1795442196.sh
[[ $(stat -c %a -- "$vhci_migration") == 644 ]] || fail "the vhci migration is mode 0644"
[[ $(head -1 "$vhci_migration") != '#!'* ]] || fail "the vhci migration has no shebang"
grep -q '^echo "Load vhci_hcd on the ROG Ally' "$vhci_migration" || fail "the vhci migration says what it does"
grep -q 'omarchy-hw-rog-ally' "$vhci_migration" || fail "the vhci migration is gated on the Ally"
grep -q 'install-vhci$' "$vhci_migration" || fail "the vhci migration calls install-vhci"
grep -q 'omarchy-hw-rog-ally' "$ROOT/install/hardware/asus/inputplumber.sh" || fail "the hardware leaf is gated on the Ally"
grep -q 'install-service' "$ROOT/install/hardware/asus/inputplumber.sh" && fail "the hardware leaf installs the profile service"
grep -q 'omarchy-pkg-present omarchy-gaming-session' "$ROOT/install/hardware/asus/gaming-session.sh" || fail "the gaming session leaf is opt-in"
grep -q 'install-service' "$ROOT/packages/omarchy-gaming-session/omarchy-gaming-session.install" || fail "the package installs the profile service"
grep -q 'remove-service' "$ROOT/packages/omarchy-gaming-session/omarchy-gaming-session.install" || fail "removing the package removes the profile service"

if setpriv --reuid=1 --regid=1 --clear-groups "$helper" install-greeter; then
  fail "install as the desktop user is refused"
fi
if setpriv --reuid=1 --regid=1 --clear-groups "$helper" install-vhci; then
  fail "install-vhci as the desktop user is refused"
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
if [[ ${7:-} == "GetManagedObjects" ]]; then
  exec cat "${GREETER_SNAPSHOT:?}"
fi
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

(
  controller=/org/shadowblip/InputPlumber/CompositeDevice1
  usb=/devices/pci0000:00/0000:00:08.1/0000:09:00.3/usb1
  ally_path="$usb/1-3/1-3:1.0/input/input18/event7"
  pad_path="$usb/1-2/1-2:1.0/input/input19/event13"
  mkdir -p "$work/sys${pad_path}" "$work/sys${ally_path}" "$work/pointer-bin"
  mount --bind "$work/sys" /sys
  trap 'umount /sys' EXIT
  printf '#!/bin/bash\nexit 0\n' >"$work/pointer-bin/sleep"
  chmod +x "$work/pointer-bin/sleep"

  check_pad() (
    local name=$1 load=$2 sysfs=$3 phys=$4 properties=$5 ally_properties=${6:-'{"ID_INTEGRATION":"internal"}'}
    export GREETER_SNAPSHOT="$work/$name.json" BUSCTL_LOG="$work/busctl-$name"
    jq -n --arg path "$controller" --arg ally "$ally_path" --arg sysfs "$sysfs" \
      --arg phys "$phys" --argjson properties "$properties" --argjson ally_properties "$ally_properties" '
      "org.shadowblip.Input.Source.UdevDevice" as $source
      | {data: [{
          "/org/shadowblip/InputPlumber/devices/source/event7": {($source): {
            DevicePath: {data: "/dev/input/event7"}, IdVendor: {data: "0b05"}, IdProduct: {data: "1abe"},
            SysfsPath: {data: $ally}, Properties: {data: $ally_properties}
          }},
          "/org/shadowblip/InputPlumber/devices/source/event13": {($source): {
            DevicePath: {data: "/dev/input/event13"}, IdVendor: {data: "045e"}, IdProduct: {data: "028e"},
            SysfsPath: {data: $sysfs}, PhysPath: {data: $phys}, Properties: {data: $properties}
          }},
          ($path): {"org.shadowblip.Input.CompositeDevice": {
            Name: {data: "ASUS ROG Ally"},
            SourceDevicePaths: {data: ["/dev/input/event7", "/dev/input/event13"]}
          }}
        }]}' >"$GREETER_SNAPSHOT"
    : >"$BUSCTL_LOG"
    local status=0
    PATH="$work/pointer-bin:$work/bin:$PATH" "$ROOT/bin/omarchy-ally-pointer" || status=$?
    if [[ $load == "yes" ]]; then
      local profile="$ROOT/default/inputplumber/profiles/omarchy-ally-pointer.yaml"
      (( status == 0 )) &&
        [[ $(<"$BUSCTL_LOG") == "--timeout=1s call org.shadowblip.InputPlumber $controller org.shadowblip.Input.CompositeDevice LoadProfilePath s $profile" ]] ||
        fail "$name loads the pointer profile"
    else
      (( status == 1 )) && [[ ! -s $BUSCTL_LOG ]] || fail "$name refuses the pointer profile"
    fi
    pass "$name"
  )

  external='{"ID_VENDOR_ID":"045e","ID_MODEL_ID":"028e","ID_INTEGRATION":"external"}'
  stale='{"ID_VENDOR_ID":"046d","ID_MODEL_ID":"c534","ID_INTEGRATION":"external","ID_PATH":"pci-0000:0b:00.3-usb-0:1.3.4:1.1","ID_MODEL":"USB_Receiver"}'
  wrong_path='{"ID_VENDOR_ID":"045e","ID_MODEL_ID":"028e","ID_INTEGRATION":"internal","DEVPATH":"/devices/unrelated"}'
  result=0
  check_pad "built-in pad with Logitech properties" yes "$pad_path" "usb-0000:09:00.3-2/input0" "$stale" || result=1
  check_pad "built-in ASUS source with Logitech properties" yes "$pad_path" "" '{}' "$stale" || result=1
  check_pad "external pad with matching properties" no "$pad_path" "" "$external" || result=1
  check_pad "external pad on another USB controller" no "" "usb-0000:0b:00.3-1/input0" "$wrong_path" || result=1
  check_pad "external pad behind a hub on the same controller" no "$usb/1-1.3/1-1.3:1.0/input/event13" "" '{}' || result=1
  printf 'fixed\n' >"$work/sys$usb/1-2/removable"
  check_pad "fixed USB device overrides InputPlumber" yes "$pad_path" "" "$external" || result=1
  printf 'removable\n' >"$work/sys$usb/1-2/removable"
  check_pad "removable USB device overrides InputPlumber" no "$pad_path" "" '{"ID_INTEGRATION":"internal"}' || result=1
  (( result == 0 ))
)

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
import configparser
import importlib.util
import io
import os
import subprocess
import sys
import time
from importlib.machinery import SourceFileLoader
from pathlib import Path

root = Path(os.environ["ROOT"])
work = Path(os.environ["WORK"])
unit = configparser.ConfigParser()
unit.read(root / "default/systemd/system/omarchy-inputplumber-profile.service")
assert unit["Service"].get("ExecCondition") == "/usr/bin/omarchy-hw-rog-ally"
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
  "omarchy-ally-pointer.yaml": ("Omarchy Ally boot pointer", ["xbox-elite", "mouse", "keyboard"]),
  "desktop.yaml": ("Omarchy Ally desktop v2", ["xbox-elite", "mouse", "keyboard"]),
  "osk.yaml": ("Omarchy Ally osk v2", ["xbox-elite", "mouse", "keyboard"]),
  "gaming.yaml": ("Omarchy Ally gaming v2", ["deck-uhid", "mouse", "keyboard"]),
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
for filename in ("omarchy-ally-pointer.yaml", "desktop.yaml", "osk.yaml"):
  other = (profiles / filename).read_text()
  check("deck" not in other and "ds5-edge" not in other, f"{filename} stays on xbox-elite")
for filename, (_name, targets) in shipped.items():
  check(targets is not None and any(target in gamepads for target in targets), f"{filename} keeps a gamepad target")
desktop = (profiles / "desktop.yaml").read_text()
osk = (profiles / "osk.yaml").read_text()
def mapping_targets(text, button):
  lines = text.splitlines()
  for index, line in enumerate(lines):
    if line != f'        button: "{button}"':
      continue
    chunk = []
    for later in lines[index + 1:]:
      if later.startswith("  - name:"):
        break
      chunk.append(later)
    return "\n".join(chunk)
  return ""

check(not mapping_targets(gaming, "QuickAccess"), "Armoury short stays unmapped so QAM passes through")
check('button: "QuickAccess"' in mapping_targets(gaming, "QuickAccess2"),
      "Armoury long sends QAM to the virtual controller")
check('keyboard: "KeyBackspace"' in mapping_targets(osk, "East"), "osk east is backspace")
check("mouse:" not in mapping_targets(osk, "East"), "osk east is not a mouse button")
# The embedded stock xpad reports the labelled X as BTN_NORTH and Y as BTN_WEST.
check('button: "Right"' in mapping_targets(desktop, "East"), "desktop B is right-click")
check('button: "Middle"' in mapping_targets(desktop, "North"), "desktop X is middle-click")
check('keyboard: "KeySpace"' in mapping_targets(osk, "North"), "keyboard X is Space")
for name, profile in (("desktop", desktop), ("keyboard", osk)):
  check('keyboard: "KeyEnter"' in mapping_targets(profile, "West"), f"{name} Y is Enter")
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

  def __call__(self, args, deadline=None):
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

for name in ("desktop", "osk"):
  bus.reset()
  prop(c1, "ProfileName", f's "Omarchy Ally {name}"')
  check(mod.load(name) == 0 and bus.methods() == ["LoadProfileFromYaml"], f"{name} replaces the previous X/Y mapping")
  loaded = [call for call in bus.calls if call[0] == "call"]
  if loaded:
    applied, _ = mod.profile_meta(loaded[0][-1])
    prop(c1, "ProfileName", f's "{applied}"')
  bus.reset()
  check(mod.load(name) == 0 and not bus.methods(), f"{name} keeps the applied mapping on a repeated request")

bus.reset()
prop(c1, "ProfileName", 's "Default"')
check(mod.load("desktop") == 0 and bus.methods() == ["LoadProfileFromYaml"], "Default is not treated as ours")

bus.reset()
prop(c1, "ProfileName", f's "{mod.profile_meta(desktop_yaml)[0]}"')
prop(c1, "TargetDevices", f'as 1 "{keyboard}"')
check(mod.load("desktop") == 0 and bus.methods() == ["LoadProfileFromYaml"], "a missing mouse target is reloaded")
prop(c1, "TargetDevices", f'as 3 "{mouse}" "{keyboard}" "{xbox}"')

bus.reset()
prop(c1, "ProfileName", 's "Omarchy Ally pointer"')
check(mod.load("pointer") == 0 and bus.methods() == ["LoadProfileFromYaml"], "pointer replaces the cached profile with inert stick axes")
prop(c1, "ProfileName", 's "Omarchy Ally boot pointer"')
bus.reset()
check(mod.load("pointer") == 0 and bus.methods() == [], "the corrected pointer stays loaded on a repeated request")
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
check(mod.load("gaming") == 1 and bus.methods() == [], "Ally X product 1b4c is not the RC71L")
prop(hidraw, "IdProduct", 's "1abe"')
prop(event, "IdProduct", 's "1abe"')

bus.reset()
prop(hidraw, "IdVendor", 's "0x0b05"')
prop(event, "IdVendor", 's "0B05"')
check(mod.load("gaming") == 1 and bus.methods() == [], "vendor text must be lowercase four digits")
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

bus.reset()
bus.tree_codes = [1]
check(mod.load("desktop") == 1 and bus.methods() == [], "a missing InputPlumber daemon fails the desktop profile request")

check(mod.load("nope") == 1, "an unknown name is an error")
check(mod.intercept(1) == 1 and mod.intercept(3) == 1, "intercept rejects values other than 0 and 2")
bus.reset()
check(mod.intercept(2) == 0, "intercept 2 is accepted")
sets = [call for call in bus.calls if call[0] == "set-property"]
check(len(sets) == 1 and sets[0][2] == c1 and sets[0][4:] == ["InterceptMode", "u", "2"], "intercept sets mode on the RC71L composite")

deck = "/org/shadowblip/InputPlumber/devices/target/gamepad2"
prop(deck, "DeviceType", 's "deck-uhid"')
usb_deck = "/org/shadowblip/InputPlumber/devices/target/gamepad3"
prop(usb_deck, "DeviceType", 's "deck"')
gaming_on_disk = (prefix / "gaming.yaml").read_text()
probes = []

def fake_modprobe(module):
  probes.append(module)
  return cp(1, "", "modprobe failed")

mod.run_modprobe = fake_modprobe

def load_logged(name):
  err = io.StringIO()
  saved = sys.stderr
  sys.stderr = err
  try:
    code = mod.load(name)
  finally:
    sys.stderr = saved
  return code, err.getvalue()

def sent_profiles():
  loads = [call for call in bus.calls if len(call) > 4 and call[0] == "call" and call[4] == "LoadProfileFromYaml"]
  return [call[-1] for call in loads]

def sent_yaml():
  profiles = sent_profiles()
  check(len(profiles) == 1, f"one profile load, got {len(profiles)}")
  return profiles[0] if profiles else ""

absent = work / "no-vhci"
os.environ["OMARCHY_VHCI_SYS"] = str(absent)
mod.UHID_DEVICE = work / "no-uhid"
mod.HID_DEVICES = work / "hid"
hidraw_deck = mod.HID_DEVICES / "0003:28DE:12FD.0001/hidraw/hidraw1"

def surface_pad_after_load(_seconds):
  prop(c1, "TargetDevices", f'as 3 "{mouse}" "{keyboard}" "{edge}"')

bus.reset()
prop(c1, "ProfileName", 's "Default"')
mod.pause = surface_pad_after_load
fallback_yaml = gaming_on_disk.replace('\n  - "deck-uhid"\n', '\n  - "ds5-edge"\n')
code, err = load_logged("gaming")
check(code == 0 and sent_yaml() == fallback_yaml, "missing /dev/uhid tries the Edge fallback")
check("/dev/uhid is unavailable; gaming falls back to ds5-edge" in err, "the fallback reason is logged")

bus.reset()
prop(c1, "ProfileName", 's "Omarchy Ally gaming"')
code, err = load_logged("gaming")
check(code == 0 and sent_yaml() == fallback_yaml,
      "a live Edge with the older Armoury map receives the new profile")

bus.reset()
prop(c1, "ProfileName", f's "{mod.profile_meta(gaming_on_disk)[0]}"')
code, err = load_logged("gaming")
check(code == 0 and bus.methods() == [], "a live Edge is kept while UHID remains unavailable")

mod.UHID_DEVICE = Path("/dev/null")
bus.reset()
prop(c1, "TargetDevices", f'as 3 "{mouse}" "{keyboard}" "{usb_deck}"')

def attach_deck_uhid(_seconds):
  prop(c1, "TargetDevices", f'as 3 "{mouse}" "{keyboard}" "{deck}"')
  hidraw_deck.mkdir(parents=True, exist_ok=True)

mod.pause = attach_deck_uhid
code, err = load_logged("gaming")
check(code == 0 and sent_yaml() == gaming_on_disk and "falls back" not in err,
      "a previously loaded USB/IP Deck is replaced with the attached UHID pad")
check(hidraw_deck.is_dir(), "the load waits for the UHID pad's hidraw device")

bus.reset()
code, err = load_logged("gaming")
check(code == 0 and bus.methods() == [], "an attached UHID pad is kept on repeat loads")

if hidraw_deck.exists():
  hidraw_deck.rmdir()
bus.reset()
clock = [0.0]
monotonic = mod.time.monotonic
mod.time.monotonic = lambda: clock[0]

def wait_without_hidraw(seconds):
  clock[0] += seconds
  if len(sent_profiles()) == 2:
    surface_pad_after_load(seconds)

mod.pause = wait_without_hidraw
code, err = load_logged("gaming")
check(code == 0 and sent_profiles() == [gaming_on_disk, fallback_yaml],
      "a D-Bus Deck target without a hidraw device is replaced with Edge")
check("deck-uhid target did not attach" in err, "the attach failure is logged")

# Both targets use UHID. A kernel without working UHID cannot attach either pad.
bus.reset()
prop(c1, "TargetDevices", f'as 2 "{mouse}" "{keyboard}"')
mod.UHID_DEVICE = work / "no-uhid"

def advance(seconds):
  clock[0] += seconds

mod.pause = advance
code, err = load_logged("gaming")
check(code == 1 and sent_yaml() == fallback_yaml and "ds5-edge target did not attach" in err,
      "a successful D-Bus call without a fallback pad is a failed load")
mod.time.monotonic = monotonic
mod.pause = lambda _seconds: None
check((prefix / "gaming.yaml").read_text() == gaming_on_disk, "the fallbacks leave gaming.yaml intact")
check(probes == [], "gaming never loads the USB/IP module")

bus.reset()
probes.clear()
prop(c1, "ProfileName", 's "Default"')
prop(c1, "TargetDevices", f'as 3 "{mouse}" "{keyboard}" "{xbox}"')
code, err = load_logged("desktop")
check(code == 0 and sent_yaml() == desktop_yaml, "desktop still sends its own profile")
check(probes == [], "desktop does not load vhci_hcd")
check("falls back" not in err, "desktop does not log a gaming fallback")

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
mod.run_busctl = lambda args, deadline=None: cp(0, "")
dest = work / "root"
user_conf = dest / "etc/sddm.conf.d/omarchy-handheld-user.conf"
user_conf.parent.mkdir(parents=True)
user_conf.write_text("[OmarchyHandheld]\nUser=daniel\n")
os.chmod(user_conf, 0o644)
os.environ["OMARCHY_PATH"] = str(root)
check(mod.install_service_into(dest) == 0, "the service install writes the Ally policy")
rule = (dest / "etc/polkit-1/rules.d/50-omarchy-inputplumber-profile.rules").read_text()
check('subject.user == "sddm"' in rule and "polkit.Result.NO" in rule, "the rule refuses sddm")
check("subject.active && subject.local && subject.user == \"daniel\"" in rule, "the rule allows the handheld user")
check("NOPASSWD" not in rule and "pkexec" not in rule, "the rule is not a sudoers grant")
check(all(not line.strip().startswith("polkit") or "shadowblip" not in line for line in rule.splitlines()), "the rule does not grant InputPlumber")
check(["enable", "omarchy-inputplumber-profile.service"] in system, "a missing profile service is enabled")
policy = (dest / "usr/share/dbus-1/system.d/org.omarchy.InputPlumberProfile.conf").read_text()
check('<allow own="org.omarchy.InputPlumberProfile"/>' in policy, "root may own the profile bus name")
check('<deny own="org.omarchy.InputPlumberProfile"/>' in policy, "other users may not own the profile bus name")
check("org.shadowblip" not in policy.split("-->", 1)[-1], "the bus policy grants no InputPlumber name")

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

pointer_mask = dest / "etc/systemd/system/omarchy-ally-pointer.service"
pointer_mask.symlink_to("/dev/null")

service_paths = [dest / rel for rel in mod.SERVICE_FILES]
check(mod.remove_service_into(dest) == 0, "removing the gaming session drops the profile service")
check(all(not path.exists() for path in service_paths), "the service, policy and rule are removed")
check(os.readlink(pointer_mask) == "/dev/null", "removing the profile service leaves a pointer mask")

bare = work / "bare"
mod.INSTALL_ROOT = bare
mod.gaming_session_installed = lambda: False
systemctl_state["value"] = "not-found"
system.clear()
check(mod.install_service() == 0, "an Ally without the package does not install the service")
check(all(not (bare / rel).exists() for rel in mod.SERVICE_FILES), "an Ally without the package gets no service, policy or rule")

hookroot = work / "hookroot"
mod.INSTALL_ROOT = hookroot
mod.gaming_session_installed = lambda: True
hook_sddm = hookroot / "etc/sddm.conf.d"
hook_sddm.mkdir(parents=True)
(hook_sddm / "autologin.conf").write_text("[Autologin]\nUser=daniel\n")
hook_bin = work / "hookbin"
hook_bin.mkdir()
(hook_bin / "omarchy-cmd-present").symlink_to(root / "bin/omarchy-cmd-present")
(hook_bin / "omarchy-hw-rog-ally").symlink_to(work / "bin/omarchy-hw-rog-ally")
hook_tdp = hook_bin / "omarchy-ally-tdp-install"
hook_tdp.write_text("#!/bin/bash\nexit 0\n")
hook_tdp.chmod(0o755)
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
  "loader = SourceFileLoader('hooked_profile', os.environ['HOOK_HELPER'])\n"
  "spec = spec_from_loader('hooked_profile', loader)\n"
  "hooked = module_from_spec(spec)\n"
  "loader.exec_module(hooked)\n"
  "hooked.run_systemctl = lambda args: subprocess.CompletedProcess(['systemctl'], 0, 'not-found\\n' if args[0] == 'is-enabled' else '', '')\n"
  "hooked.run_busctl = lambda args, deadline=None: subprocess.CompletedProcess(['busctl'], 0, '', '')\n"
  "dest = Path(os.environ['HOOK_ROOT'])\n"
  "if sys.argv[1] == 'install-greeter':\n"
  "    raise SystemExit(0)\n"
  "if sys.argv[1] == 'install-service':\n"
  "    raise SystemExit(hooked.install_service_into(dest))\n"
  "raise SystemExit(hooked.remove_service_into(dest))\n"
)
os.chmod(hook_stub, 0o755)
hook_env = os.environ.copy()
hook_env["PATH"] = str(hook_bin) + os.pathsep + hook_env.get("PATH", "")
hook_env["HOOK_CALLS"] = str(hook_calls)
hook_env["HOOK_HELPER"] = str(helper)
hook_env["HOOK_ROOT"] = str(hookroot)
hook_env["OMARCHY_SDDM_CONF_DIR"] = str(hook_sddm)
hook_env["OMARCHY_SDDM_STATE"] = str(hookroot / "var/lib/sddm/state.conf")
hook_env["HOOK_USER_HELPER"] = str(root / "default/gaming/sddm-user.sh")
hook_env["HOOK_HW"] = str(hook_bin / "omarchy-hw-rog-ally")
hook_source = root / "packages/omarchy-gaming-session/omarchy-gaming-session.install"
hook_script = work / "omarchy-gaming-session.install"
# Redirect the package paths while running the SDDM helper unchanged.
hook_script.write_text(hook_source.read_text()
  .replace("/usr/bin/omarchy-setup-handheld-dirs", '"$HOOK_ROOT/usr/bin/omarchy-setup-handheld-dirs"')
  .replace("/usr/bin/omarchy-hw-rog-ally", '"$HOOK_HW"')
  .replace("/usr/lib/omarchy-gaming-session/sddm-user.sh", '"$HOOK_USER_HELPER"')
  .replace("/usr/share/omarchy/default/gaming/sddm-user.sh", '"$HOOK_USER_HELPER"'))

def run_hook(function):
  hook_calls.write_text("")
  proc = subprocess.run(
    ["bash", "-c", 'source "$1"; "$2"', "_", str(hook_script), function],
    env=hook_env,
    text=True,
    capture_output=True,
  )
  check(proc.returncode == 0, f"{function} exits 0")
  return hook_calls.read_text().split()

check(run_hook("post_install") == ["install-greeter", "install-service"], "post_install installs the profile service")
hook_rule = hookroot / "etc/polkit-1/rules.d/50-omarchy-inputplumber-profile.rules"
check('subject.user == "daniel"' in hook_rule.read_text(), "the first package install authorizes the recorded handheld user")
check(run_hook("post_upgrade") == ["install-greeter", "install-service"], "post_upgrade installs the profile service")
check(all((hookroot / rel).is_file() for rel in mod.SERVICE_FILES), "the service files are present before removal")
hook_pointer = hookroot / "etc/systemd/system/omarchy-ally-pointer.service"
hook_pointer.touch()
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
vhci_root = work / "vhci-root"
mod.INSTALL_ROOT = vhci_root
check(mod.install_vhci() == 0, "install-vhci is a no-op off the Ally")
check(not (vhci_root / mod.VHCI_CONF).exists(), "off the Ally writes no modules-load.d entry")
mod.ally = lambda: True
os.environ["OMARCHY_VHCI_SYS"] = str(absent)
probes.clear()
check(mod.install_vhci() == 0, "install-vhci writes the entry when the module does not load")
conf = vhci_root / mod.VHCI_CONF
check(conf.read_text() == "vhci_hcd\n", "the modules-load.d entry names vhci_hcd")
check((conf.stat().st_mode & 0o777) == 0o644, "the modules-load.d entry is mode 0644")
check(probes == ["vhci_hcd"], "install-vhci tries to load the module")
conf.unlink()
conf.symlink_to("/tmp/not-our-modules")
check(mod.install_vhci_into(vhci_root) == 1, "install-vhci refuses a symlink")
conf.unlink()
check(mod.install_vhci_into(vhci_root) == 0, "install-vhci writes again after the symlink is removed")
check(conf.read_text() == "vhci_hcd\n", "the rewritten entry is still vhci_hcd")

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
code, log = run_cli("install-vhci", hw="laptop")
check(code == 0 and log == "", "install-vhci does nothing off the Ally")
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
[[ $(cat "$work/warn-calls") == $'install-greeter\ninstall-service' ]] ||
  fail "post_install still runs the profile install" "$(cat "$work/warn-calls")"
grep -F 'warning: InputPlumber profile service install failed; re-run: omarchy-inputplumber-profile install-service' \
  "$work/warn.err" ||
  fail "post_install names the failed step and the re-run command" "$(cat "$work/warn.err")"
: > "$work/warn-calls"
if ! PATH="$warn_bin:$PATH" WARN_CALLS=$work/warn-calls \
  OMARCHY_SDDM_CONF_DIR=$work/warn-sddm \
  post_remove >"$work/warn-remove.out" 2>"$work/warn-remove.err"; then
  fail "a failed profile removal still lets post_remove return"
fi
grep -F 'warning: InputPlumber profile service removal failed; re-run: omarchy-inputplumber-profile remove-service' \
  "$work/warn-remove.err" ||
  fail "post_remove names the failed step and the re-run command" "$(cat "$work/warn-remove.err")"
pass "a failed profile scriptlet warns and still returns"

pkg=$work/pkg
mkdir -p "$pkg/usr/bin" "$pkg/usr/share/omarchy/bin" "$pkg/usr/share/omarchy/default" \
  "$pkg/usr/share/omarchy/install/hardware/asus" "$pkg/etc/systemd/system" \
  "$pkg/dbus" "$pkg/polkit-actions" "$pkg/polkit-rules" "$pkg/modules-load.d"
cp "$ROOT/install/hardware/asus/inputplumber.sh" "$pkg/usr/share/omarchy/install/hardware/asus/"
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
ln -s omarchy-pkg-present "$pkg/usr/bin/omarchy-pkg-add"
cat > "$pkg/usr/bin/omarchy-pkg-missing" <<'EOF'
#!/bin/bash
exit 1
EOF
cat > "$pkg/usr/bin/systemctl" <<'EOF'
#!/bin/bash
case $1 in
  enable)
    if [[ $2 == /* ]]; then
      ln -sfn -- "$2" "/etc/systemd/system/${2##*/}"
    fi
    ;;
  is-enabled)
    unit="/etc/systemd/system/$2"
    if [[ -L $unit ]]; then
      case $(readlink -- "$unit") in
        /dev/null) printf 'masked\n'; exit 1 ;;
        *) printf 'enabled\n' ;;
      esac
    elif [[ -f $unit ]]; then
      printf 'disabled\n'
      exit 1
    else
      printf 'not-found\n'
      exit 4
    fi
    ;;
esac
EOF
cat > "$pkg/usr/bin/busctl" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$pkg/usr/bin/modprobe" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod 755 "$pkg/usr/bin/omarchy-hw-rog-ally" "$pkg/usr/bin/omarchy-pkg-present" \
  "$pkg/usr/bin/systemctl" "$pkg/usr/bin/busctl" "$pkg/usr/bin/modprobe" "$pkg/usr/bin/omarchy-pkg-missing"

pkg_mounts=()
pkg_cleanup() {
  local i
  for (( i=${#pkg_mounts[@]}-1; i>=0; i-- )); do
    umount "${pkg_mounts[i]}" || true
  done
  rm -rf "$work"
}
trap pkg_cleanup EXIT
mount -t tmpfs tmpfs /var/lib
pkg_mounts+=("/var/lib")
mount --bind "$pkg/etc/systemd/system" /etc/systemd/system
pkg_mounts+=("/etc/systemd/system")
mount --bind "$pkg/modules-load.d" /etc/modules-load.d
pkg_mounts+=("/etc/modules-load.d")
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
[[ -L /etc/systemd/system/omarchy-ally-pointer.service ]] || fail "the pointer unit follows package updates"
[[ ! -e /etc/modules-load.d/omarchy-rog-ally-vhci.conf ]] ||
  fail "packaged hardware setup loads the retired USB/IP module"
if ! run_packaged "$pkg/usr/share/omarchy/bin/omarchy-inputplumber-profile" install-service >"$pkg/service.out" 2>"$pkg/service.err"; then
  fail "install-service fails on the packaged layout" "$(cat "$pkg/service.err")"
fi
grep -q '^ExecStart=/usr/bin/omarchy-ally-pointer$' \
  /etc/systemd/system/omarchy-ally-pointer.service ||
  fail "the packaged greeter unit does not call the helper" "$(cat /etc/systemd/system/omarchy-ally-pointer.service)"
grep -q 'omarchy-ally-pointer-load' /etc/systemd/system/omarchy-ally-pointer.service &&
  fail "the packaged greeter unit names the old loader"
[[ -f /etc/systemd/system/omarchy-inputplumber-profile.service ]] || fail "the packaged install skips the profile service"
[[ -f /usr/share/dbus-1/system.d/org.omarchy.InputPlumberProfile.conf ]] || fail "the packaged install skips the bus policy"
[[ -f /usr/share/polkit-1/actions/org.omarchy.inputplumber-profile.policy ]] || fail "the packaged install skips the polkit action"
[[ -f /etc/polkit-1/rules.d/50-omarchy-inputplumber-profile.rules ]] || fail "the packaged install skips the polkit rule"
pass "a packaged layout installs the greeter unit and the profile service"

pointer_unit=/etc/systemd/system/omarchy-ally-pointer.service
rm -- "$pointer_unit"
ln -s /dev/null "$pointer_unit"
run_packaged "$pkg/usr/bin/omarchy-inputplumber-profile" install-greeter
[[ $(readlink -- "$pointer_unit") == /dev/null ]] || fail "packaged provisioning preserves the administrator's mask"
rm -- "$pointer_unit"
printf '[Unit]\nDescription=Administrator pointer\n' >"$pointer_unit"
run_packaged "$pkg/usr/bin/omarchy-inputplumber-profile" install-greeter
grep -Fxq 'Description=Administrator pointer' "$pointer_unit" || fail "packaged provisioning preserves a disabled administrator unit"

# sudo and pacman start this helper with OMARCHY_PATH unset. The files then
# come from /usr/share/omarchy, not from the directory that holds the binary.
printf '\n# package-root=/usr/share/omarchy\n' >> \
  "$pkg/usr/share/omarchy/default/systemd/system/omarchy-ally-pointer.service"
rm -f /var/lib/omarchy/handheld/ally-pointer-provisioned \
  /etc/systemd/system/omarchy-ally-pointer.service \
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
grep -q '^ExecStart=/usr/bin/omarchy-ally-pointer$' \
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
