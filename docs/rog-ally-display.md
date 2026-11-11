# RC71L display and presentation

This optional increment targets the original ROG Ally RC71L through `omarchy-hw-rog-ally`. It changes no defaults on laptops, desktops, Ally X or Xbox Ally. It adds no package, monitor daemon, kernel parameter, firmware update or system service. Source checks do not establish installed or physical acceptance.

## Hardware and upstream boundaries

ASUS specifies a landscape 1920×1080, 120 Hz, 10-point touch panel with FreeSync Premium for RC71L. The internal panel is SDR; this implementation refuses internal HDR. Do not force rotation merely because other handhelds have portrait-native panels. The advertised modes and current transform, rather than a copied distribution quirk, settle the configuration.

Primary references checked 11 November 2026:

- [ASUS RC71L specifications](https://rog.asus.com/bd/gaming-handhelds/rog-ally/rog-ally-2023/spec/).
- [Hyprland monitor JSON](https://github.com/hyprwm/Hyprland/blob/main/src/ipc/s1/Commands.cpp): `hardwareDetails.vrrCapable`, `hdr` and `bt2020` are capability evidence; `vrr` means currently active adaptive sync. Older compositors without these capability fields fail closed for enable requests.
- [Hyprland Lua monitor objects](https://github.com/hyprwm/Hyprland/blob/main/src/config/lua/objects/LuaMonitor.cpp), [monitor modes](https://wiki.hypr.land/configuring/core/monitors/modes/) and [colour modes](https://wiki.hypr.land/configuring/core/monitors/colors/).
- [Hyprland input configuration](https://github.com/hyprwm/Hyprland/blob/main/src/managers/input/InputManager.cpp) and [touch routing](https://github.com/hyprwm/Hyprland/blob/main/src/managers/input/Touch.cpp): unbound input can follow the focused monitor. A disabled internal output must not send its touch events to a dock screen.
- [Gamescope command options](https://github.com/ValveSoftware/gamescope/blob/master/src/main.cpp): SESSION owns game render size, frame limit and scaling filters. Native game upscaling and Gamescope FSR/NIS are separate choices; neither guarantees improved frame pacing or image quality.

These are existing upstream interfaces; no upstream implementation is copied. Hyprland 0.57.1-2 on the source host exposes the capability fields. The installed Ally build still needs checking.

## Install and configure

The integration owner must package these files through the existing Omarchy package/source deployment route. No companion fixed-system package or new dependency is required: Bash, jq, Python 3.11+ (`tomllib`), Lua Hyprland, brightnessctl and the existing Omarchy helpers are supplied by the baseline. Gamescope remains an optional SESSION dependency. Do not copy a worktree over `/usr/share/omarchy` or refresh user configs wholesale.

From the installed Hyprland desktop, as the desktop user:

```bash
omarchy display rog ally status
omarchy display rog ally native 60
# Request 120 only when status advertises it; a missing rate chooses the fastest advertised 1080p mode.
omarchy display rog ally native 120
# Optional readable desktop geometry, preserving larger existing bar dimensions:
omarchy display rog ally touch-preset
# Select the actual built-in device name from status (do not select an external touchscreen):
omarchy display rog ally touch DEVICE_NAME
```

`native` delegates advertised-mode validation and persistence to `omarchy-hyprland-monitor-resolution`. It keeps the current scale, and does not invent 720p/900p physical modes. The ordinary monitor panel and `omarchy hyprland monitor scaling --monitor eDP-1 1.5` remain the scale controls. Rotation uses the ordinary panel or `omarchy hyprland monitor rotate --monitor eDP-1 90`; the optional touch mapping follows compositor layout events and applies the same transform. It disables the selected touch device while the internal panel is unavailable, then restores it when the panel returns, respecting the existing touchscreen-disable flag. This mapping is for the Hyprland desktop; SDDM/lock and direct Gamescope own their input surfaces separately.

The optional touch preset selects 1.5× internal scale (1280×720 logical pixels at 1080p) and sets horizontal/vertical bar thickness to at least 44 logical pixels. It leaves unrelated shell tokens, widget layout and external display scales alone. It preserves larger effective bar dimensions, accounts for the current theme and font scale, and writes a machine override so later theme switches retain the target size. It is a recommendation requiring geometry checks on the device, including portrait mode and the wvkbd keyboard. It does not install a keyboard or add a bar button.

The TOUCH increment `bdb732d94` configures wvkbd to 264 logical pixels in both orientations for its six full-layout rows. Keep the optional Desktop Keyboard button on the top bar so it remains reachable to hide the keyboard; the keyboard can cover a bottom bar. This placement is independent of the display preset. Physical geometry and text focus remain unverified.

The preset backs up the original shell override and monitor settings under `$XDG_STATE_HOME/omarchy/rog-ally-display/touch-preset` (default `~/.local/state`). Apply it before further monitor layout changes if you intend to use automatic rollback. Reapplying keeps the first backup.

## Dock profiles, brightness, VRR and HDR

```bash
# Arrange two active displays side by side, internal left, and focus the external:
omarchy display rog ally dock DP-1
# Restore/focus the internal screen and clear Omarchy mirroring:
omarchy display rog ally handheld
# Existing optional external-only profile; generic recovery handles unplug:
omarchy hyprland monitor internal off
# Explicit internal brightness works even while the dock display is focused:
omarchy brightness display --monitor eDP-1 50%
# Supported outputs only; these requests last until desktop config reload:
omarchy display rog ally vrr eDP-1 fullscreen
omarchy display rog ally vrr eDP-1 off
omarchy display rog ally hdr DP-1 on
omarchy display rog ally hdr DP-1 off
```

Use connector names reported by `status`, not these illustrative names. The dock command keeps the internal touch surface usable and requires exactly two active displays. Larger arrangements use the existing monitor panel. Mode, scale, rotation and position are saved by Omarchy's existing physical-monitor identity and reapplied on hotplug, including connector changes. External-only mode and undock recovery use the existing monitor watcher and recovery service. Audio routing belongs to RELIABILITY.

VRR enable requests require affirmative compositor capability data. Fullscreen policy can remain inactive until eligible content presents; `status` distinguishes active VRR from capability. External HDR requires advertised HDR metadata plus BT2020, then compositor validation of PQ and a successful 10-bit HDR modeset. If it does not become effective within two seconds, the command requests the previous colour mode/depth and reports failure. Inspect the display after either outcome; a reported mode is not proof of correct luminance, cable bandwidth or game HDR. `hdr off` explicitly requests 8-bit sRGB; a config reload restores user-configured colour settings. No `supports_hdr` override, SDR conversion trick, HDMI FRL/DSC quirk or kernel change is applied.

VRR/HDR are deliberately transient. Redetect after docking or changing cables, and enable only on a path that works. Persistent custom policy can remain in the user's monitor config; the command never edits that file.

## SESSION contract

```bash
omarchy display rog ally gaming-output auto
omarchy display rog ally gaming-output internal
omarchy display rog ally gaming-output DP-1
omarchy-display-rog-ally gamescope-args
```

`gaming-output` stores only an output preference, not a launcher or session configuration. External choices use an EDID SHA256 so connector renames do not select a different screen. The helper resolves connected DRM outputs without a running Hyprland session. Empty/short EDIDs are refused; identical EDIDs on multiple connected screens are refused as ambiguous. The default is `auto`, which lets Gamescope choose its native output/mode.

`gamescope-args` stdout is argv, one argument per line without shell quotes, and contains only `--prefer-output` followed by a connected connector name. It does not supply `-w`, `-h`, `-W`, `-H`, `-r`, filters, frame limits, HDR or orientation. Automatic or disconnected selection produces no arguments with exit 0; disconnection has a diagnostic on stderr. Invalid configuration, non-RC71L hardware or an incompatible Gamescope build returns non-zero before emitting arguments. SESSION calls it only when installed, captures its exit status before using `mapfile`, and owns failure policy. Do not `eval` this output or depend on process substitution to propagate a command failure.

SESSION provides independent 720p/900p/1080p/native game render size, `--framerate-limit` and `-F linear|nearest|fsr|nis`. Verify the chosen game actually renders at that size and measure pacing with the performance tools; advertised refresh alone proves neither. SESSION must handle Gamescope's own dock/undock events. The desktop monitor watcher is not a gaming-session recovery daemon.

## Capture and sharing checks

`status` reports capture tool presence and queries the desktop ScreenCast portal's source mask without recording, opening a chooser or granting capture permission. Presence is diagnostic information, not a successful frame or a claim that desktop tools run in direct Gamescope.

For the deployment owner, in the Hyprland desktop:

```bash
omarchy capture screenshot fullscreen save
OMARCHY_SCREENRECORD_DEBUG=true omarchy screenrecord --fullscreen --with-desktop-audio
# Exercise a short moving scene, then:
omarchy screenrecord --stop-recording
# Test the existing alternative when ordinary capture fails or external HDR needs it:
OMARCHY_SCREENRECORD_USE_PORTAL=true OMARCHY_SCREENRECORD_DEBUG=true omarchy screenrecord --fullscreen
omarchy screenrecord --stop-recording
```

Review the saved screenshot and video for correct screen, orientation, colours, cursor, motion and audio. Portal recording can have DMA-BUF import limits; keep the existing recorder fallback and debug log. Test browser screen sharing by choosing the internal screen, then the dock screen; the recipient must confirm moving frames and audio where supported, then stop sharing and verify its indicator disappears. Do not commit personal captures/logs.

For direct Gamescope, use Steam screenshots and Gamescope's supported screenshot route; validate an actual saved image. Desktop Omasnap/slurp and Hyprland portal IPC are not promised there. The SESSION/GAMES owners must verify Steam Remote Play and any optional Sunshine capture backend with actual client video/audio/controller traffic. Do not weaken capture permissions, grant broad DRM privileges or install an extra portal backend merely to make a status check green. Gaming capture/sharing remains pending until those paths are exercised.

## Rollback

```bash
# While the optional preset's shell and monitor files are still unchanged:
omarchy display rog ally touch-preset reset
omarchy display rog ally touch reset
omarchy display rog ally gaming-output auto
omarchy display rog ally handheld
# Clears transient VRR/HDR and reloads saved mode/scale/layout configuration:
omarchy restart hyprctl
```

Preset reset restores the previous shell override and monitor settings, removing files that were originally absent. It refuses to overwrite later edits; in that case merge the `.before` backups manually, retaining later widget/theme/monitor choices. The touch reset removes only this feature's data and static loader; normal input config resumes after reload. Native mode and dock layout selections remain ordinary monitor-panel choices: restore their previous mode/scale/layout from your pre-change baseline in the panel, or restore the backed-up monitor settings and reload. `handheld` turns the internal panel on; it does not erase external display profiles or restore an earlier focus choice. Restore the previous Omarchy package through the integrator's package rollback after removing this optional touch loader, so it cannot refer to a missing module.

## Pending physical acceptance and evidence

The sole Ally rollout owner runs these serially; feature workers do not mutate the device. Record the source/package version, baseline status, monitor-settings and shell-token backups, commands, outcomes and private evidence locations. No physical acceptance has been established by this source increment.

1. Confirm RC71L and advertised modes. At 60 and 120 Hz, check an actual moving game/desktop scene and return to the previous mode. Confirm no orientation override is needed at native landscape.
2. Enable the optional touch preset and select the built-in touchscreen. Tap all four corners and the centre at landscape and each chosen portrait rotation, with both internal and external monitor focus. Check bar button hit targets, panel clipping, the 264-logical-pixel wvkbd keyboard's six rows and real text focus. Confirm the top-bar Desktop Keyboard button remains reachable to hide the keyboard in both orientations. Return to the starting rotation.
3. Dock with the panel active, choose mode/scale and side-by-side layout; unplug/replug through the same and another connector. Check saved identity/profile, workspace placement and pointer reachability. In external-only mode, verify internal touch stops, undock restores visible internal output and touch returns. Test one suspend/resume while docked with RELIABILITY.
4. On a known VRR-capable display and eligible fullscreen game, compare capability and active state; measure pacing at the SESSION-selected cap. On an actually capable external HDR display, test successful 10-bit HDR, SDR return and a non-HDR/insufficient-bandwidth dock path. Internal HDR must always be refused. Without the relevant display/dock, record this as hardware unavailable.
5. Validate desktop and gaming screenshots/recordings separately, desktop browser screen sharing, then the selected Remote Play host/client path with GAMES and SESSION. Inspect the actual files/receiver, not just process status.
6. Exercise rollback, including refusal after a later config edit; retain edits. Confirm no errors on reload and an unsupported model cannot apply this feature. Leave the normal installed desktop/session running.
