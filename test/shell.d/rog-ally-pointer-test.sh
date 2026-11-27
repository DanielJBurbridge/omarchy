#!/bin/bash

set -euo pipefail

# shellcheck source=base-test.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export PATH="$tmp/bin:$ROOT/bin:$PATH"
export SYSTEM_ROOT="$tmp/system" CALLS="$tmp/calls"
mkdir -p "$tmp/bin"

cat >"$tmp/bin/omarchy-hw-rog-ally" <<'SH'
#!/bin/bash
[[ $MODEL == "RC71L" ]]
SH

cat >"$tmp/bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'install %s\n' "$*" >>"$CALLS"
SH

cat >"$tmp/bin/systemctl" <<'SH'
#!/bin/bash
if [[ $1 == "start" ]]; then
  printf '%s\n' "$*" >>"$CALLS"
else
  exec /usr/bin/systemctl --root="$SYSTEM_ROOT" "$@"
fi
SH

cat >"$tmp/bin/busctl" <<'SH'
#!/bin/bash
[[ $1 == "--system" ]] || exit 2
shift
case "${6}:${7}" in
  *:GetManagedObjects) cat "$SNAPSHOT" ;;
  LoadProfileFromYaml:s)
    printf '%s\n' "$4" >"$LOAD_PATH"
    printf '%s' "$8" >"$LOADED"
    new_profile='Omarchy Ally pointer'
    ;;
  LoadProfilePath:s)
    printf '%s\n' "$4" >"$LOAD_PATH"
    printf '%s' "$8" >"$LOADED"
    new_profile=Default
    ;;
  *) exit 2 ;;
esac
if [[ -n ${PROFILE_CHANGES:-} && -n ${new_profile:-} ]]; then
  jq --arg name "$new_profile" --arg path "$4" \
    '.data[0][$path]["org.shadowblip.Input.CompositeDevice"].ProfileName.data = $name' \
    "$SNAPSHOT" >"$SNAPSHOT.new"
  mv "$SNAPSHOT.new" "$SNAPSHOT"
  printf '%s\n' "$new_profile" >>"$PROFILE_CHANGES"
fi
SH

cat >"$tmp/bin/systemd-notify" <<'SH'
#!/bin/bash
[[ $1 == "--ready" ]] || exit 2
touch "$WATCH_READY"
SH
chmod +x "$tmp/bin/"*

export MODEL=RC71L
unit=omarchy-ally-pointer.service
package_unit="/usr/share/omarchy/default/systemd/system/$unit"
install -Dm644 "$ROOT/default/systemd/system/$unit" "$SYSTEM_ROOT$package_unit"
mkdir -p "$SYSTEM_ROOT/usr/lib/systemd/system"
printf '[Unit]\nDescription=Graphical Target\n' >"$SYSTEM_ROOT/usr/lib/systemd/system/graphical.target"

# Redirect only the root-owned install paths. systemctl acts on the same tree.
sed -e "s|/var/lib/omarchy/|$SYSTEM_ROOT/var/lib/omarchy/|" \
  -e "s|/etc/systemd/system/|$SYSTEM_ROOT/etc/systemd/system/|" \
  "$ROOT/install/hardware/asus/rog-ally-pointer.sh" >"$tmp/install.sh"

run_setup() (
  export OMARCHY_PATH=/usr/share/omarchy OMARCHY_INSTALL="$ROOT/install"
  # all.sh calls this function when sourced below.
  # shellcheck disable=SC2329
  run_logged() {
    if [[ $1 == "$OMARCHY_INSTALL/hardware/asus/rog-ally-pointer.sh" ]]; then
      # shellcheck source=/dev/null
      source "$tmp/install.sh"
    fi
  }
  # shellcheck source=/dev/null
  source "$OMARCHY_INSTALL/hardware/all.sh"
)

: >"$CALLS"
MODEL=G614J run_setup
MODEL=Other run_setup
[[ ! -s $CALLS && ! -e $SYSTEM_ROOT/etc ]] || fail 'other hardware skips the Ally pointer setup'
pass 'other hardware skips the Ally pointer setup'

install -Dm644 "$SYSTEM_ROOT$package_unit" "$SYSTEM_ROOT/etc/systemd/system/$unit"
run_setup
[[ ! -s $CALLS && $(systemctl is-enabled "$unit") == "disabled" ]] || fail 'an existing disabled unit is left alone'
rm -- "$SYSTEM_ROOT/etc/systemd/system/$unit"
systemctl mask "$unit"
run_setup
[[ ! -s $CALLS && $(systemctl is-enabled "$unit") == "masked" ]] || fail 'a masked unit is left alone'
systemctl unmask "$unit"
pass 'existing disabled and masked units are left alone'

OMARCHY_IMAGE_DEFERRED_HARDWARE=1 run_setup
systemctl is-enabled --quiet "$unit" || fail 'the original Ally enables the pointer'
[[ $(<"$CALLS") == $'install inputplumber\nstart --no-block omarchy-ally-pointer.service' ]] ||
  fail 'the original Ally installs InputPlumber and queues the pointer on deferred first boot'
pass 'the original Ally installs InputPlumber and enables the pointer for first boot'

systemctl disable "$unit"
: >"$CALLS"
OMARCHY_IMAGE_DEFERRED_HARDWARE=1 run_setup
if [[ -s $CALLS ]] || systemctl is-enabled --quiet "$unit"; then
  fail 'hardware setup preserves a deliberate disable of the packaged unit'
fi
pass 'hardware setup preserves a deliberate disable of the packaged unit'

ln -s "$package_unit" "$SYSTEM_ROOT/etc/systemd/system/$unit"
OMARCHY_IMAGE_DEFERRED_HARDWARE=1 run_setup
[[ ! -s $CALLS ]] || fail 'deferred setup does not start a linked but disabled unit'
rm -- "$SYSTEM_ROOT/etc/systemd/system/$unit"

install -Dm644 "$SYSTEM_ROOT$package_unit" "$SYSTEM_ROOT/etc/systemd/system/$unit"
systemctl enable "$unit"
OMARCHY_IMAGE_DEFERRED_HARDWARE=1 run_setup
[[ ! -s $CALLS ]] || fail 'deferred setup does not start an administrator replacement'
pass 'deferred setup only starts the enabled packaged unit'

controller=/org/shadowblip/InputPlumber/CompositeDevice1
profile="$ROOT/default/inputplumber/profiles/omarchy-ally-pointer.yaml"
write_snapshot() {
  jq -n --arg path "$controller" --arg name "$1" --arg product "$2" --arg device "$3" \
    --arg profile "${4:-Default}" '
    {data: [{
      "/org/shadowblip/InputPlumber/devices/source": {
        "org.shadowblip.Input.Source.UdevDevice": {
          DevicePath: {data: "/dev/input/event7"},
          IdVendor: {data: "0b05"},
          IdProduct: {data: $product}
        }
      },
      ($path): {
        "org.shadowblip.Input.CompositeDevice": {
          Name: {data: $name},
          ProfileName: {data: $profile},
          SourceDevicePaths: {data: [$device]}
        }
      }
    }]}'
}

export SNAPSHOT="$tmp/original" LOADED="$tmp/loaded" LOAD_PATH="$tmp/load-path"
write_snapshot 'ASUS ROG Ally' 1abe /dev/input/event7 >"$SNAPSHOT"
"$ROOT/bin/omarchy-ally-pointer" load
if [[ $(<"$LOAD_PATH") != "$controller" ]] || ! cmp -s "$profile" "$LOADED"; then
  fail 'only the exact original Ally composite receives the packaged YAML'
fi
pass 'the original Ally composite receives the packaged YAML'

(
  usb=/devices/pci0000:00/0000:00:08.1/0000:09:00.3/usb1
  ally_path="$usb/1-3/1-3:1.0/input/input18/event7"
  pad_path="$usb/1-2/1-2:1.0/input/input19/event13"
  # Redirect the kernel lookup to a fixture while exercising the load command.
  sed "s|^SYSFS_ROOT = Path(\"/sys\")$|SYSFS_ROOT = Path(\"$tmp/sys\")|" \
    "$ROOT/bin/omarchy-ally-pointer" >"$tmp/pointer"
  mkdir -p "$tmp/sys${pad_path}" "$tmp/sys${ally_path}"
  write_snapshot 'ASUS ROG Ally' 1abe /dev/input/event7 >"$tmp/base-sources"

  check_pad() (
    local name=$1 load=$2 sysfs=$3 phys=$4 properties=$5 ally_properties=${6:-'{"ID_INTEGRATION":"internal"}'}
    export SNAPSHOT="$tmp/$name.json" LOADED="$tmp/loaded-$name"
    jq --arg path "$controller" --arg ally "$ally_path" --arg sysfs "$sysfs" \
      --arg phys "$phys" --argjson properties "$properties" --argjson ally_properties "$ally_properties" '
      "org.shadowblip.Input.Source.UdevDevice" as $source
      | .data[0]["/org/shadowblip/InputPlumber/devices/source"][$source] += {
          SysfsPath: {data: $ally}, Properties: {data: $ally_properties}
        }
      | .data[0]["/org/shadowblip/InputPlumber/devices/source/event13"][$source] = {
          DevicePath: {data: "/dev/input/event13"}, IdVendor: {data: "045e"}, IdProduct: {data: "028e"},
          SysfsPath: {data: $sysfs}, PhysPath: {data: $phys}, Properties: {data: $properties}
        }
      | .data[0][$path]["org.shadowblip.Input.CompositeDevice"].SourceDevicePaths.data += ["/dev/input/event13"]
    ' "$tmp/base-sources" >"$SNAPSHOT"
    /usr/bin/python3 "$tmp/pointer" load || fail "$name can identify the composite"
    if [[ $load == "yes" ]]; then
      cmp -s "$profile" "$LOADED" || fail "$name loads the pointer profile"
    else
      [[ ! -e $LOADED ]] || fail "$name defers the pointer profile"
    fi
    pass "$name"
  )

  external='{"ID_VENDOR_ID":"045e","ID_MODEL_ID":"028e","ID_INTEGRATION":"external"}'
  stale='{"ID_VENDOR_ID":"046d","ID_MODEL_ID":"c534","ID_INTEGRATION":"external","ID_PATH":"pci-0000:0b:00.3-usb-0:1.3.4:1.1","ID_MODEL":"USB_Receiver"}'
  wrong_path='{"ID_VENDOR_ID":"045e","ID_MODEL_ID":"028e","ID_INTEGRATION":"internal","DEVPATH":"/devices/unrelated"}'
  result=0
  check_pad 'built-in pad with Logitech properties' yes "$pad_path" 'usb-0000:09:00.3-2/input0' "$stale" || result=1
  check_pad 'built-in ASUS source with Logitech properties' yes "$pad_path" '' '{}' "$stale" || result=1
  check_pad 'external pad with matching properties' no "$pad_path" '' "$external" || result=1
  check_pad 'external pad on another USB controller' no '' 'usb-0000:0b:00.3-1/input0' "$wrong_path" || result=1
  check_pad 'external pad behind a hub on the same controller' no "$usb/1-1.3/1-1.3:1.0/input/event13" '' '{}' || result=1
  printf 'fixed\n' >"$tmp/sys$usb/1-2/removable"
  check_pad 'fixed USB device overrides InputPlumber' yes "$pad_path" '' "$external" || result=1
  printf 'removable\n' >"$tmp/sys$usb/1-2/removable"
  check_pad 'removable USB device overrides InputPlumber' no "$pad_path" '' '{"ID_INTEGRATION":"internal"}' || result=1
  (( result == 0 ))
)

default_profile=/usr/share/inputplumber/profiles/default.yaml
write_snapshot 'ASUS ROG Ally' 1abe /dev/input/event7 'Omarchy Ally pointer' >"$SNAPSHOT"
jq --arg path "$controller" '
  .data[0]["/org/shadowblip/InputPlumber/devices/external"]["org.shadowblip.Input.Source.UdevDevice"] = {
    DevicePath: {data: "/dev/input/event8"},
    IdVendor: {data: "045e"},
    IdProduct: {data: "028e"},
    Properties: {data: {ID_INTEGRATION: "external"}}
  }
  | .data[0][$path]["org.shadowblip.Input.CompositeDevice"].SourceDevicePaths.data += ["/dev/input/event8"]
' "$SNAPSHOT" >"$tmp/with-external-pad"
SNAPSHOT="$tmp/with-external-pad" "$ROOT/bin/omarchy-ally-pointer" restore
[[ $(<"$LOAD_PATH") == "$controller" && $(<"$LOADED") == "$default_profile" ]] ||
  fail 'restore loads the vendor default even when an external pad joined the Ally composite'
rm "$LOADED"
if "$ROOT/bin/omarchy-ally-pointer" /tmp/arbitrary-profile.yaml; then
  fail 'arbitrary profile paths are rejected'
fi
write_snapshot 'ASUS ROG Ally' 1abe /dev/input/event7 'Custom gamepad' >"$SNAPSHOT"
"$ROOT/bin/omarchy-ally-pointer" restore
[[ ! -e $LOADED ]] || fail 'restore only replaces the Omarchy pointer profile'
pass 'restore only replaces the Omarchy pointer profile with the vendor default'

(
  export PROFILE_CHANGES="$tmp/profile-changes" WATCH_READY="$tmp/watch-ready"
  write_snapshot 'ASUS ROG Ally' 1abe /dev/input/event7 >"$SNAPSHOT"
  # Exercise the service entry point with real D-Bus property changes on a
  # private bus. InputPlumber is represented by the busctl fixture above.
  dbus-run-session -- python3 - "$ROOT/bin/omarchy-ally-pointer" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import time

from gi.repository import Gio, GLib

login = "org.freedesktop.login1"
seat = "/org/freedesktop/login1/seat/seat0"
seat_interface = login + ".Seat"
props = "org.freedesktop.DBus.Properties"
active = GLib.Variant("(so)", ("", "/"))
os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = os.environ["DBUS_SESSION_BUS_ADDRESS"]
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
              "RequestName", GLib.Variant("(su)", (login, 0)), None, Gio.DBusCallFlags.NONE, 1000)


def register(path, interface, properties, getter):
  xml = f"<node><interface name='{interface}'>" + "".join(
    f"<property name='{name}' type='{signature}' access='read'/>"
    for name, signature in properties.items()
  ) + "</interface></node>"
  bus.register_object(path, Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0],
                      None, lambda *args: getter(args[-1]), None)


register(seat, seat_interface, {"ActiveSession": "(so)"}, lambda _: active)


def activate(session, session_class, session_type):
  global active
  path = f"/org/freedesktop/login1/session/{session}"
  values = {"Class": session_class, "Type": session_type}
  register(path, login + ".Session", {"Class": "s", "Type": "s"},
           lambda name: GLib.Variant("s", values[name]))
  active = GLib.Variant("(so)", (session, path))
  bus.emit_signal(None, seat, props, "PropertiesChanged",
                  GLib.Variant("(sa{sv}as)", (seat_interface, {"ActiveSession": active}, [])))


def wait_for(condition):
  context = GLib.MainContext.default()
  deadline = time.monotonic() + 8
  while not condition():
    if watcher.poll() is not None or time.monotonic() >= deadline:
      raise AssertionError("the pointer watcher did not switch profile")
    context.iteration(False)
    time.sleep(0.01)


ready = Path(os.environ["WATCH_READY"])
changes = Path(os.environ["PROFILE_CHANGES"])
watcher = subprocess.Popen([sys.argv[1], "watch"])
try:
  wait_for(ready.exists)
  assert changes.read_text().splitlines() == ["Omarchy Ally pointer"]
  activate("greeter", "greeter", "wayland")
  activate("desktop", "user", "wayland")
  wait_for(lambda: changes.read_text().splitlines()[-1] == "Default")
  subprocess.run([sys.argv[1], "load"], check=True)
  activate("console", "user", "tty")
  assert changes.read_text().splitlines() == ["Omarchy Ally pointer", "Default", "Omarchy Ally pointer"]
  subprocess.run([sys.argv[1], "restore"], check=True)
  activate("next_greeter", "greeter", "wayland")
  wait_for(lambda: changes.read_text().splitlines()[-1] == "Omarchy Ally pointer")
  assert changes.read_text().splitlines() == ["Omarchy Ally pointer", "Default", "Omarchy Ally pointer",
                                             "Default", "Omarchy Ally pointer"]
finally:
  watcher.terminate()
  watcher.wait(timeout=5)
PY
)
pass 'the seat watcher loads before sign-in, restores on desktop login and reloads on return to the greeter'

pids=()
for fixture in ally-x wrong-name unrelated-source missing-composite; do
  (
    fixture_snapshot="$tmp/$fixture"
    fixture_loaded="$tmp/loaded-$fixture"
    case $fixture in
      ally-x) write_snapshot 'ASUS ROG Ally' 1b4c /dev/input/event7 >"$fixture_snapshot" ;;
      wrong-name) write_snapshot 'ASUS ROG Ally X' 1abe /dev/input/event7 >"$fixture_snapshot" ;;
      unrelated-source) write_snapshot 'ASUS ROG Ally' 1abe /dev/input/event8 >"$fixture_snapshot" ;;
      missing-composite) printf '{"data":[{}]}\n' >"$fixture_snapshot" ;;
    esac
    if SNAPSHOT="$fixture_snapshot" LOADED="$fixture_loaded" "$ROOT/bin/omarchy-ally-pointer" ||
      [[ -e $fixture_loaded ]]; then
      fail "$fixture must not receive the pointer profile"
    fi
  ) &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
pass 'Ally X, wrong names, unrelated sources and missing composites never receive the profile'

mkdir -p "$tmp/unsafe/default/inputplumber/profiles"
ln -s "$profile" "$tmp/unsafe/default/inputplumber/profiles/${profile##*/}"
write_snapshot 'ASUS ROG Ally' 1abe /dev/input/event7 >"$SNAPSHOT"
if OMARCHY_PATH="$tmp/unsafe" LOADED="$tmp/unsafe-loaded" "$ROOT/bin/omarchy-ally-pointer" ||
  [[ -e $tmp/unsafe-loaded ]]; then
  fail 'a symlink cannot supply the pointer profile'
fi
pass 'a symlink cannot supply the pointer profile'
