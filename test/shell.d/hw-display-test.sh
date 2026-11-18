#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

write_backlights() {
  rm -rf "$tmp_dir/backlight"
  mkdir -p "$tmp_dir/backlight"

  local device
  for device in "$@"; do
    mkdir -p "$tmp_dir/backlight/$device"
  done
}

# A copy of the command reads its platform file from a fixture root: none
# unless a case writes one, whatever the machine running the suite has installed.
platform_root="$tmp_dir/platform"
mkdir -p "$platform_root" "$tmp_dir/bin"
platform_root_copy "$ROOT/bin/omarchy-hw-display" "$tmp_dir/bin/omarchy-hw-display" "$platform_root"

write_displays_conf() {
  printf '%s\n' "$@" >"$platform_root/displays.conf"
}

hw_display() {
  OMARCHY_BACKLIGHT_PATH="$tmp_dir/backlight" "$tmp_dir/bin/omarchy-hw-display"
}

write_backlights intel_backlight
device=$(hw_display)
[[ $device == "intel_backlight" ]] || fail "the only backlight is used" "actual: $device"
pass "the only backlight is used"

write_backlights acpi_video0 amdgpu_bl1
device=$(hw_display)
[[ $device == "amdgpu_bl1" ]] || fail "globbed candidates beat the alphabetical fallback" "actual: $device"
pass "globbed candidates beat the alphabetical fallback"

write_backlights acpi_video0 intel_backlight
device=$(hw_display)
[[ $device == "intel_backlight" ]] || fail "the candidate order is honored" "actual: $device"
pass "the candidate order is honored"

write_backlights nvidia_wmi_ec_backlight
device=$(hw_display)
[[ $device == "nvidia_wmi_ec_backlight" ]] || fail "an unknown backlight falls back to the first device" "actual: $device"
pass "an unknown backlight falls back to the first device"

write_backlights appletb_backlight gmux_backlight
device=$(hw_display)
[[ $device == "gmux_backlight" ]] || fail "a T2 Mac uses gmux instead of the Touch Bar" "actual: $device"
pass "a T2 Mac uses gmux instead of the Touch Bar"

write_backlights appletb_backlight
if hw_display >/dev/null 2>&1; then
  fail "the T2 Touch Bar is never used as the display backlight"
fi
pass "the T2 Touch Bar is never used as the display backlight"

write_backlights acpi_video0 amdgpu_bl0 appletb_backlight gmux_backlight intel_backlight
device=$(hw_display)
[[ $device == "gmux_backlight" ]] || fail "gmux outranks the GPU backlights on dual-GPU Macs" "actual: $device"
pass "gmux outranks the GPU backlights on dual-GPU Macs"

write_backlights
if hw_display >/dev/null 2>&1; then
  fail "no backlight device reports failure"
fi
pass "no backlight device reports failure"

# An empty platform file changes nothing.
: >"$platform_root/displays.conf"
write_backlights acpi_video0 amdgpu_bl1
device=$(hw_display)
[[ $device == "amdgpu_bl1" ]] || fail "an empty platform file keeps the candidate order" "actual: $device"
write_backlights nvidia_wmi_ec_backlight
device=$(hw_display)
[[ $device == "nvidia_wmi_ec_backlight" ]] || fail "an empty platform file keeps the fallback" "actual: $device"
pass "an empty platform file changes nothing"

write_displays_conf '# accessory panels' 'backlight-skip accessory-pipe' 'backlight-skip *.dsi.0' 'backlight-prefer panel-bl'
write_backlights 1000.dsi.0 accessory-pipe
if hw_display >/dev/null 2>&1; then
  fail "a skipped backlight is never the fallback"
fi
write_backlights 1000.dsi.0 accessory-pipe zz-other
device=$(hw_display)
[[ $device == "zz-other" ]] || fail "the fallback passes over skipped backlights" "actual: $device"
pass "a platform's skipped backlights are never the fallback"

write_backlights 1000.dsi.0 amdgpu_bl0 panel-bl
device=$(hw_display)
[[ $device == "panel-bl" ]] || fail "a preferred backlight beats the GPU backlights" "actual: $device"
printf 'backlight-prefer panel-bl\r\n' >"$platform_root/displays.conf"
device=$(hw_display)
[[ $device == "panel-bl" ]] || fail "a file saved with CRLF line ends reads the same" "actual: $device"
write_displays_conf '# accessory panels' 'backlight-skip accessory-pipe' 'backlight-skip *.dsi.0' 'backlight-prefer panel-bl'
write_backlights gmux_backlight panel-bl
device=$(hw_display)
[[ $device == "gmux_backlight" ]] || fail "gmux still beats a preferred backlight" "actual: $device"
pass "a platform's preferred backlight follows gmux and beats the GPU backlights"

write_displays_conf 'backlight-prefer second-bl' 'backlight-prefer first-bl'
write_backlights first-bl second-bl
device=$(hw_display)
[[ $device == "second-bl" ]] || fail "preferences are tried in file order" "actual: $device"
pass "preferences are tried in file order"

write_displays_conf 'backlight-skip intel_backlight' 'backlight-prefer panel-bl' 'backlight-skip panel-bl'
write_backlights acpi_video0 intel_backlight panel-bl
device=$(hw_display)
[[ $device == "acpi_video0" ]] || fail "a skip beats preferred and built-in candidates" "actual: $device"
write_displays_conf 'backlight-skip gmux_backlight'
write_backlights gmux_backlight intel_backlight
device=$(hw_display)
[[ $device == "intel_backlight" ]] || fail "a skip beats gmux" "actual: $device"
pass "a skip beats preferred and built-in candidates"

write_displays_conf 'backlight-prefer panel-*' 'backlight-prefer .' 'backlight-prefer ..'
write_backlights amdgpu_bl0 panel-bl
device=$(hw_display)
[[ $device == "amdgpu_bl0" ]] || fail "a preference is a literal name" "actual: $device"
pass "a preference is a literal name"

# Only whole directives count: an unknown one, a path, an extra word or a
# trailing comment leaves the line out; the last line needs no newline.
printf '%s\n' 'backlight-future panel-bl' 'backlight-prefer ../panel-bl' 'backlight-prefer panel-bl extra' \
  'backlight-skip acpi_video0 # comment' >"$platform_root/displays.conf"
printf 'backlight-prefer last-bl' >>"$platform_root/displays.conf"
write_backlights acpi_video0 last-bl panel-bl
device=$(hw_display)
[[ $device == "last-bl" ]] || fail "malformed directives are ignored and the last line is read" "actual: $device"
write_displays_conf 'backlight-skip acpi_video0 # comment'
write_backlights acpi_video0
device=$(hw_display)
[[ $device == "acpi_video0" ]] || fail "a directive with a trailing comment is ignored" "actual: $device"
pass "malformed directives are ignored and the last line is read"

# omarchy-hw-external-monitors: a connected connector that is not a built-in
# panel counts as an external display.
drm_path="$tmp_dir/drm"

write_connectors() {
  rm -rf "$drm_path"
  mkdir -p "$drm_path"

  local connector state
  while (( $# )); do
    connector="$1"
    state="$2"
    mkdir -p "$drm_path/card0-$connector"
    printf '%s\n' "$state" >"$drm_path/card0-$connector/status"
    shift 2
  done
}

has_external_monitor() {
  OMARCHY_DRM_PATH="$drm_path" "$ROOT/bin/omarchy-hw-external-monitors"
}

write_connectors
set +e
empty_error=$(has_external_monitor 2>&1 >/dev/null)
empty_status=$?
set -e

(( empty_status != 0 )) || fail "an empty DRM tree has no external display"
[[ -z $empty_error ]] || fail "an empty DRM tree is handled quietly" "$empty_error"
pass "physical monitor detection handles an empty DRM tree"

for connector in eDP-1 LVDS-1 DSI-1; do
  write_connectors "$connector" connected

  if has_external_monitor; then
    fail "$connector is treated as an internal display"
  fi
done
pass "physical monitor detection ignores common internal panel connectors"

write_connectors LVDS-1 connected DP-1 connected
has_external_monitor || fail "external display is found alongside an LVDS panel"
pass "physical monitor detection finds an external display alongside an LVDS panel"

write_connectors eDP-1 connected HDMI-A-1 disconnected
if has_external_monitor; then
  fail "a disconnected external display is not reported as connected"
fi
pass "physical monitor detection ignores disconnected external displays"

write_connectors DP-1 connected
has_external_monitor || fail "external-only systems still report a connected display"
pass "physical monitor detection still supports external-only systems"

printf '%s\n' 'ASUSTeK COMPUTER INC.' >"$tmp_dir/sys_vendor"
printf '%s\n' 'ROG Ally RC71L' >"$tmp_dir/product_name"
printf '%s\n' RC71L >"$tmp_dir/board_name"

gaming_output() {
  PATH="$ROOT/bin:$PATH" OMARCHY_DRM_PATH="$drm_path" XDG_STATE_HOME="$tmp_dir/state" \
    OMARCHY_DMI_SYS_VENDOR_PATH="$tmp_dir/sys_vendor" OMARCHY_DMI_PRODUCT_NAME_PATH="$tmp_dir/product_name" \
    OMARCHY_DMI_BOARD_NAME_PATH="$tmp_dir/board_name" "$ROOT/bin/omarchy-gaming-output" "$@"
}

write_connectors eDP-1 connected DP-1 connected HDMI-A-1 connected
head -c 128 /dev/zero >"$drm_path/card0-DP-1/edid"
mkdir -p "$drm_path/card1-DP-2"
cp "$drm_path/card0-DP-1/"{status,edid} "$drm_path/card1-DP-2/"
if gaming_output DP-2 2>/dev/null; then fail "a USB graphics connector on another card cannot be preferred"; fi
if gaming_output HDMI-A-1 2>/dev/null; then fail "a connector without an EDID cannot be preferred"; fi
[[ -z $(gaming_output gamescope-args) ]] || fail "without a preference Gamescope selects its own connector"
available=$(gaming_output)
[[ $available == *"Automatic"* && $available == *"DP-1"* && $available != *"DP-2"* &&
  $available != *"HDMI-A-1"* && ! -e $tmp_dir/state/omarchy/rog-ally-display/gamescope-output ]] ||
  fail "inspecting outputs lists selectable native displays without saving a preference" "$available"
gaming_output DP-1
mv "$drm_path/card0-DP-1" "$drm_path/card0-DP-3"
[[ $(gaming_output gamescope-args) == $'--prefer-output\nDP-3,eDP-1' ]] ||
  fail "an Ally native display follows its EDID after a connector rename, with the panel as fallback"
[[ $(gaming_output) == *"Next Gaming session: DP-3"* ]] || fail "the reported preference follows the renamed connector"

mkdir -p "$drm_path/card0-DP-4"
cp "$drm_path/card0-DP-3/"{status,edid} "$drm_path/card0-DP-4/"
if gaming_output DP-4 2>/dev/null; then fail "a duplicate EDID cannot replace the chosen display"; fi
available=$(gaming_output)
[[ $available == *"Next Gaming session: eDP-1"* && $available != *"DP-3"* && $available != *"DP-4"* ]] ||
  fail "duplicate display identities explain the internal fallback and cannot be selected" "$available"
[[ $(gaming_output gamescope-args) == $'--prefer-output\neDP-1' ]] ||
  fail "an ambiguous EDID safely falls back to the internal panel"
printf '%s\n' disconnected >"$drm_path/card0-DP-3/status"
printf '%s\n' disconnected >"$drm_path/card0-DP-4/status"
[[ $(gaming_output gamescope-args) == $'--prefer-output\neDP-1' ]] ||
  fail "unplugging a preferred display favours the panel over other connected outputs"

gaming_output internal
[[ $(gaming_output gamescope-args) == $'--prefer-output\neDP-1' ]] || fail "the internal panel can be preferred explicitly"
gaming_output auto
[[ -z $(gaming_output gamescope-args) ]] || fail "returning to auto removes connector priorities"
printf '%s\n' 'ROG Ally X RC72LA' >"$tmp_dir/product_name"
printf '%s\n' RC72LA >"$tmp_dir/board_name"
if gaming_output internal 2>/dev/null; then fail "the Ally X cannot change this original Ally preference"; fi
pass "Ally gaming output tracks EDID only on the native card, with a safe internal fallback"
