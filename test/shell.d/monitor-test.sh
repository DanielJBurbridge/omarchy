#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const monitor = requireFromRoot('shell/plugins/panels/monitor/Model.js')

assertEqual(monitor.clampBrightness(0), 1, 'monitor clamps minimum brightness')
assertEqual(monitor.clampBrightness(101), 100, 'monitor clamps maximum brightness')
assertEqual(monitor.clampBrightness(42.4), 42, 'monitor rounds brightness')
assertEqual(monitor.clampBrightness('nope'), 1, 'monitor rejects invalid brightness')

assertEqual(monitor.normalizeScale('1.250'), '1.25', 'monitor normalizes fractional scale')
assertEqual(monitor.normalizeScale('nope'), '', 'monitor rejects invalid scale')
assertEqual(monitor.cleanScale(3, 1280, 800), '3.2', 'monitor matches clean VM scale')
assertEqual(monitor.cleanScale(1.25, 1280, 800), '1.25', 'monitor preserves an already clean scale')
assertEqual(monitor.cleanScale(1.25, 6016, 3384), '1.33', 'monitor matches clean physical display scale')
assertEqual(monitor.cleanScale(1.6, 0, 800), '', 'monitor rejects a missing display mode')
assertEqual(
  monitor.matchingScaleIndex(['1', '1.25', '1.6', '2', '3', '4'], 3.2, 1280, 800),
  4,
  'monitor selects an approximated VM scale'
)
assertEqual(
  monitor.matchingScaleIndex(['1', '1.25', '1.6', '2', '3', '4'], 4, 4, 4),
  5,
  'monitor selects an exact preset'
)
assertDeepEqual(
  monitor.availableScales(['1', '1.25', '1.6', '2', '3', '4'], 1280, 800),
  ['1', '1.25', '1.6', '2', '3', '4'],
  'monitor keeps distinct approximated VM scales'
)
assertDeepEqual(
  monitor.availableScales(['1', '1.25', '1.6', '2', '3', '4'], 6016, 3384),
  ['1', '1.25', '1.6', '2', '3', '4'],
  'monitor keeps distinct approximated physical display scales'
)
assertDeepEqual(
  monitor.availableScales(['1', '1.25', '1.6', '2', '3', '4'], 1280, 804),
  ['1', '1.25', '2', '4'],
  'monitor collapses presets with duplicate effective scales'
)
assertDeepEqual(
  monitor.availableScales(['1', '1.25', '1.6', '2', '3', '4'], 5968, 3230),
  ['1', '2'],
  'monitor hides presets the current mode cannot reach'
)
assertDeepEqual(
  monitor.availableScales(['1', '1.25', '1.6', '2', '3', '4'], 0, 0),
  ['1', '1.25', '1.6', '2', '3', '4'],
  'monitor keeps presets until display dimensions are known'
)

// A 6K panel also advertises a tiled half-width mode and legacy sizes.
const sixK = ['6016x3384@60.00Hz', '3840x2160@60.00Hz', '6016x3384@59.94Hz', '5120x2880@60.00Hz',
  '2560x2880@60.00Hz', '2560x1440@60.00Hz', '1920x1080@60.00Hz', '1280x720@60.00Hz', '1024x768@60.00Hz']
assertDeepEqual(
  monitor.resolutionOptions(sixK, 6016, 3384),
  ['1920x1080', '2560x1440', '3840x2160', '5120x2880', '6016x3384'],
  'monitor offers the native resolution and its same-shape modes, capped'
)
assertDeepEqual(
  monitor.resolutionOptions(sixK, 1024, 768),
  ['1024x768', '1920x1080', '2560x1440', '3840x2160', '5120x2880', '6016x3384'],
  'monitor keeps an odd current resolution in the list'
)
assertDeepEqual(
  monitor.resolutionOptions(['3840x2160@60.00Hz', '2560x1440@60.00Hz', '1920x1080@60.00Hz', '1600x900@60.00Hz', '1280x720@60.00Hz'], 3840, 2160),
  ['1920x1080', '2560x1440', '3840x2160'],
  'monitor offers nothing below 1080p'
)
assertDeepEqual(monitor.resolutionOptions(undefined, 0, 0), [], 'monitor offers no resolutions without modes')
assertEqual(monitor.resolutionLabel('6016x3384'), '6K', 'monitor names 6K')
assertEqual(monitor.resolutionLabel('3840x2160'), '4K', 'monitor names 4K')
assertEqual(monitor.resolutionLabel('2560x1440'), '1440p', 'monitor names smaller modes by height')

// A gaming monitor advertises several rates at its resolution, and others at
// smaller ones and below 60Hz.
const gaming = ['2560x1440@143.98Hz', '2560x1440@120.00Hz', '2560x1440@59.95Hz', '2560x1440@60.00Hz',
  '2560x1440@50.00Hz', '1920x1080@240.00Hz']
assertDeepEqual(
  monitor.refreshOptions(gaming, 2560, 1440),
  [{ label: '60', rate: '60' }, { label: '120', rate: '120' }, { label: '144', rate: '143.98' }],
  'monitor offers its resolution\'s rates from 60Hz up, one per whole rate, keeping the exact one'
)
assertDeepEqual(
  monitor.refreshOptions(['3840x2160@60.00Hz', '3840x2160@59.94Hz', '3840x2160@30.00Hz'], 3840, 2160),
  [],
  'monitor offers no rates when none is faster than 60Hz'
)

assertEqual(monitor.displayTitle({ name: 'eDP-1', make: 'LG Display', model: '0x0804' }), 'Built-in Display', 'monitor names the built-in panel by what it is')
assertEqual(monitor.displayTitle({ name: 'DP-1', make: 'Apple Computer Inc', model: 'ProDisplayXDR' }), 'ProDisplayXDR', 'monitor names an external display by its model')
assertEqual(monitor.displayTitle({ name: 'HDMI-A-1', make: 'Dell Inc.', model: '0x40F3' }), 'Dell Inc.', 'monitor falls back to the make when the model is a code')

assertDeepEqual(
  monitor.logicalRect({ name: 'DP-1', x: 1280, y: 0, width: 6016, height: 3384, scale: 2, transform: 1 }),
  { name: 'DP-1', x: 1280, y: 0, w: 1692, h: 3008 },
  'monitor lays out a rotated display by its scaled, turned size'
)

// A laptop at 1280x800 with a 6K at 3008x1692 to its right, tops aligned.
const desk = [{ name: 'eDP-1', x: 0, y: 0, w: 1280, h: 800 }, { name: 'DP-1', x: 1280, y: 0, w: 3008, h: 1692 }]
assertDeepEqual(
  monitor.dropDisplay(desk, 'eDP-1', 1000, 1650, 40),
  [{ name: 'eDP-1', x: 0, y: 1692, w: 1280, h: 800 }, { name: 'DP-1', x: 280, y: 0, w: 3008, h: 1692 }],
  'monitor drops a display against the nearest side and starts the layout at 0x0'
)
assertDeepEqual(
  monitor.dropDisplay(desk, 'eDP-1', 2120, 1700, 40).find((r) => r.name === 'eDP-1'),
  { name: 'eDP-1', x: 864, y: 1692, w: 1280, h: 800 },
  'monitor snaps a dropped display to the center of the one it lands against'
)
assertDeepEqual(
  monitor.placeDisplay(desk, 'eDP-1', 'right'),
  [{ name: 'eDP-1', x: 3008, y: 446, w: 1280, h: 800 }, { name: 'DP-1', x: 0, y: 0, w: 3008, h: 1692 }],
  'monitor moves a display to the right of the rest, centered'
)
assert(monitor.sameLayout(monitor.normalizeLayout(desk), desk), 'monitor sees an unmoved layout as the same')

assertEqual(
  monitor.displaySpecs({ width: 1920, height: 1200, physicalWidth: 300, physicalHeight: 190, refreshRate: 119.94 }),
  '1920×1200 · 120 Hz · 161 ppi',
  'monitor describes a display by resolution, rounded refresh rate, and pixel density'
)
assertEqual(
  monitor.displaySpecs({ width: 1920, height: 1080, physicalWidth: 0, physicalHeight: 0, refreshRate: 60 }),
  '1920×1080 · 60 Hz',
  'monitor leaves out the density of a display that reports no size'
)
assertEqual(
  monitor.displaySpecs({ width: 1920, height: 1080, physicalWidth: 600, physicalHeight: 150, refreshRate: 60 }),
  '1920×1080 · 60 Hz',
  'monitor leaves out the density of a display whose size disagrees with its shape'
)
assertEqual(
  monitor.displaySpecs({ width: 3840, height: 2160, physicalWidth: 16000, physicalHeight: 9000, refreshRate: 60 }),
  '3840×2160 · 60 Hz',
  'monitor leaves out the density of a display that reports an implausible size'
)

assertDeepEqual(
  monitor.parseDisplays(JSON.stringify([
    { name: 'eDP-1', enabled: true, focused: false, width: 1920, height: 1080 },
    { name: 'HDMI-A-1', enabled: false, focused: false, width: 0, height: 0 },
    { name: 'DP-1', enabled: true, focused: true, width: 1280, height: 800 }
  ])),
  {
    displays: [
      { name: 'eDP-1', enabled: true, focused: false, width: 1920, height: 1080 },
      { name: 'HDMI-A-1', enabled: false, focused: false, width: 0, height: 0 },
      { name: 'DP-1', enabled: true, focused: true, width: 1280, height: 800 }
    ],
    enabledDisplayCount: 2
  },
  'monitor parses display state'
)

assertDeepEqual(monitor.parseDisplays('{'), { displays: [], enabledDisplayCount: 0 }, 'monitor handles invalid display JSON')
JS

# RC71L boundary: request VRR from capability, never from the currently active
# state. HDR must be external, advertised, and effective before reporting success.
require_command jq
require_command lua
require_command python
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/drm"
export ALLY_TEST_TMP="$tmp"
cat >"$tmp/bin/hyprctl" <<'SH'
#!/bin/bash
case $1 in
monitors) cat "$ALLY_TEST_TMP/monitors" ;;
devices) printf '%s\n' '{"touch":[{"name":"ally-touch"}]}' ;;
eval|dispatch) printf '%s\n' "$2" >>"$ALLY_TEST_TMP/eval" ;;
esac
SH
cat >"$tmp/bin/gamescope" <<'SH'
#!/bin/bash
printf '%s\n' '--prefer-output'
SH
cat >"$tmp/bin/omarchy-restart-hyprctl" <<'SH'
#!/bin/bash
printf 'reload\n' >>"$ALLY_TEST_TMP/eval"
SH
for tool in omarchy-hyprland-monitor-internal omarchy-hyprland-monitor-internal-mirror; do
  printf '#!/bin/bash\nexit 0\n' >"$tmp/bin/$tool"
done
chmod +x "$tmp/bin/"*
printf 'ASUSTeK COMPUTER INC.\n' >"$tmp/vendor"
printf 'ROG Ally RC71L_RC71L\n' >"$tmp/product"
printf 'RC71L\n' >"$tmp/board"
ally() {
  HOME="$tmp/home" XDG_STATE_HOME="$tmp/home/.local/state" OMARCHY_DRM_PATH="$tmp/drm" \
    OMARCHY_DMI_SYS_VENDOR_PATH="$tmp/vendor" OMARCHY_DMI_PRODUCT_NAME_PATH="$tmp/product" OMARCHY_DMI_BOARD_NAME_PATH="$tmp/board" \
    PATH="$tmp/bin:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-display-rog-ally" "$@"
}
cat >"$tmp/monitors" <<'JSON'
[{"name":"eDP-1","width":1920,"height":1080,"scale":1.5,"transform":0,"x":0,"y":0,"disabled":false,"vrr":false,"hardwareDetails":{"vrrCapable":true}},
 {"name":"DP-1","width":3840,"height":2160,"scale":2,"transform":0,"x":1280,"y":0,"disabled":false,"vrr":true,"hardwareDetails":{}}]
JSON
: >"$tmp/eval"
ally vrr eDP-1 fullscreen >/dev/null
grep -q 'vrr = 2' "$tmp/eval" || fail 'Ally can request supported VRR before it is active'
: >"$tmp/eval"
if ally vrr DP-1 on >"$tmp/out" 2>&1; then fail 'active VRR alone is not capability evidence'; fi
if ally hdr eDP-1 on >"$tmp/out" 2>&1; then fail 'Ally refuses internal HDR'; fi
if ally hdr DP-1 on >"$tmp/out" 2>&1; then fail 'unknown external HDR capability is refused'; fi
[[ ! -s $tmp/eval ]] || fail 'unsupported requests leave outputs untouched'
pass 'Ally VRR/HDR guards distinguish supported, active, unknown and internal SDR'
jq '.[1].hardwareDetails = {hdr:true,bt2020:true} | .[1].colorManagementPreset="srgb" | .[1].currentFormat="XRGB8888"' "$tmp/monitors" >"$tmp/new"
mv "$tmp/new" "$tmp/monitors"
if ally hdr DP-1 on >"$tmp/out" 2>&1; then fail 'HDR candidate rejected by compositor is not reported as effective'; fi
grep -q 'bitdepth = 10, cm = "hdr"' "$tmp/eval" || fail 'external HDR candidate is submitted without forcing capabilities'
tail -n 1 "$tmp/eval" | grep -q 'bitdepth = 8, cm = "srgb"' || fail 'ineffective HDR restores previous depth and colour'
pass 'Ally restores colour settings when compositor declines HDR'
# Known-good modes still use the generic validation/persistence implementation.
jq '.[0].availableModes = ["1920x1080@60.00Hz", "1920x1080@120.00Hz"] | .[0].refreshRate = 120' "$tmp/monitors" >"$tmp/new"
mv "$tmp/new" "$tmp/monitors"
ally native 60
: >"$tmp/eval"
if ally native 75 >"$tmp/out" 2>&1; then fail 'unadvertised Ally refresh is refused'; fi
[[ ! -s $tmp/eval ]] || fail 'invalid native mode cannot change the output'
ally dock DP-1 >/dev/null
grep -q 'hl.dsp.focus({ monitor = "DP-1" })' "$tmp/eval" || fail 'dock profile focuses with the supported dispatcher'
ally handheld >/dev/null
grep -q 'hl.dsp.focus({ monitor = "eDP-1" })' "$tmp/eval" || fail 'handheld restores internal focus'
pass 'Ally native mode validates advertised rates and dock profile uses generic persistence'

# The same EDID comes back on another dock connector; unplugged preferences
# must produce no argv, rather than force an absent output or a made-up mode.
mkdir -p "$tmp/drm/card1-DP-1"
printf 'connected\n' >"$tmp/drm/card1-DP-1/status"
python -c 'import sys; sys.stdout.buffer.write(bytes(range(128)))' >"$tmp/drm/card1-DP-1/edid"
ally gaming-output DP-1
mv "$tmp/drm/card1-DP-1" "$tmp/drm/card2-DP-3"
ally gamescope-args >"$tmp/argv"
[[ $(cat "$tmp/argv") == $'--prefer-output\nDP-3' ]] || fail 'gaming output follows EDID to a renamed connector'
printf 'disconnected\n' >"$tmp/drm/card2-DP-3/status"
ally gamescope-args >"$tmp/argv" 2>"$tmp/diagnostic"
[[ ! -s $tmp/argv ]] || fail 'disconnected gaming output falls back to native selection'
ally gaming-output auto
ally gamescope-args >"$tmp/argv"
[[ ! -s $tmp/argv ]] || fail 'auto gaming output supplies no overrides'
printf 'connected\n' >"$tmp/drm/card2-DP-3/status"
ally gaming-output DP-3
mkdir -p "$tmp/drm/card3-DP-4"
cp "$tmp/drm/card2-DP-3/"* "$tmp/drm/card3-DP-4/"
if ally gamescope-args >"$tmp/argv" 2>"$tmp/diagnostic"; then fail 'identical EDIDs are ambiguous'; fi
[[ ! -s $tmp/argv ]] || fail 'ambiguous EDID emitted no partial argv'
pass 'Ally gaming argv follows a renamed dock and fails safely for unplugged or ambiguous outputs'

ally touch ally-touch
[[ $(cat "$tmp/home/.local/state/omarchy/rog-ally-display/touch-device") == 'ally-touch' ]] || fail 'selected touchscreen is stored as data'
# The Lua module uses a data name, follows orientation events, and disables the
# internal touchscreen when its output is off, preventing focus-based fallback.
HOME="$tmp/home" XDG_STATE_HOME="$tmp/home/.local/state" lua - <<'LUA'
package.path = os.getenv("ROOT") .. "/?.lua;" .. package.path
local calls, events = {}, {}
local monitors = {{ name = "eDP-1", transform = 0 }}
o = { shell_succeeds = function() return true end }
hl = {
  device = function(spec) calls[#calls + 1] = spec end,
  get_monitors = function() return monitors end,
  on = function(event, fn) events[event] = fn end,
}
require("default.hypr.rog-ally-touch")
assert(calls[1].name == "ally-touch" and calls[1].output == "eDP-1" and calls[1].enabled)
monitors[1].transform = 1
events["monitor.layout_changed"]()
assert(calls[2].transform == 1)
events["monitor.layout_changed"]()
assert(#calls == 2, "unchanged events are no-ops")
monitors = {{name = "DP-1", transform = 0}}
events["monitor.removed"]()
assert(not calls[3].enabled, "dark panel cannot send touches to a focused dock")
monitors = {{name = "eDP-1", transform = 0}}
events["monitor.added"]()
assert(calls[4].enabled and calls[4].transform == 0)
package.loaded["default.hypr.rog-ally-touch"] = nil
o.shell_succeeds = function() return false end
require("default.hypr.rog-ally-touch")
assert(#calls == 4, "a saved mapping must do nothing on a different machine")
LUA
pass 'Ally touch mapping follows layout events without polling and stays scoped to RC71L'
ally touch reset
[[ ! -e $tmp/home/.local/state/omarchy/toggles/hypr/rog-ally-touch.lua ]] || fail 'touch reset removes its own loader'
printf 'Other vendor\n' >"$tmp/vendor"
: >"$tmp/eval"
if ally native 60 >"$tmp/out" 2>&1; then fail 'non-Ally cannot configure the Ally display'; fi
[[ ! -s $tmp/eval ]] || fail 'non-Ally host is left untouched'
pass 'Ally display operations fail closed on other hardware'

# The preset edits only bar geometry, retains larger effective dimensions,
# backs up state and refuses rollback over subsequent user edits.
python - <<'PY'
import importlib.util
import os
import sys
sys.dont_write_bytecode = True
from pathlib import Path
spec = importlib.util.spec_from_file_location("touch_preset", Path(os.environ["ROOT"]) / "default/rog-ally/touch-preset.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
import tomllib
original = '# keep this comment\n[font]\nbase-size = 16\n[bar]\nsize-horizontal = 60\ntext = "red"\n[controls]\nnormal-fill-alpha = 0.1\n'
updated = module.upsert_bar(original, {"size-horizontal": 80, "size-vertical": 44, "scale-with-font": "false"})
parsed = tomllib.loads(updated)
assert parsed["bar"] == {"size-horizontal":80,"size-vertical":44,"scale-with-font":False,"text":"red"}
assert parsed["font"]["base-size"] == 16 and '# keep this comment' in updated
assert parsed["controls"]["normal-fill-alpha"] == 0.1
try:
  module.upsert_bar('[bar]\ntext = """first\nsize-horizontal = 80\nlast"""\n', {"size-horizontal":44})
except ValueError:
  pass
else:
  raise AssertionError("multiline TOML string was modified as a setting")
# In-process command boundary: test actual file writes and rollback, leaving
# monitor scaling's own logic to the existing scaling suite.
home = Path(os.environ["ALLY_TEST_TMP"]) / "preset-home"
config = home / ".config/omarchy/shell.toml"
config.parent.mkdir(parents=True)
config.write_text(original)
os.environ["HOME"] = str(home)
os.environ.pop("XDG_STATE_HOME", None)
module.run = lambda *args: "eDP-1" if args[0] == "omarchy-hyprland-monitor-laptop" else ""
import sys
sys.argv = ["touch-preset", "apply"]
module.main()
assert tomllib.loads(config.read_text())["bar"]["size-horizontal"] == 80
sys.argv[1] = "reset"
config.write_text(config.read_text() + '# subsequent edit\n')
try:
  module.main()
except ValueError:
  pass
else:
  raise AssertionError("rollback overwrote subsequent changes")
assert '# subsequent edit' in config.read_text()
config.write_bytes((home / ".local/state/omarchy/rog-ally-display/touch-preset/shell.toml.applied").read_bytes())
module.main()
assert config.read_text() == original
PY
pass 'Ally touch preset preserves unrelated settings, larger targets and later user changes'
