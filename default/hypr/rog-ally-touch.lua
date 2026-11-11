-- Bind only the explicitly selected built-in touchscreen. Other touch devices
-- and non-Ally hosts keep their ordinary configuration. No process or timer
-- runs on layout changes: monitor events carry the new orientation directly.
local paths = require("default.hypr.paths")
if not o.shell_succeeds("omarchy-hw-rog-ally") then
  return
end
local file = io.open(paths.state_home .. "/omarchy/rog-ally-display/touch-device", "r")
if not file then return end
local name = file:read("*l")
file:close()
if not name or name == "" then return end

local previous
local function sync()
  local internal
  for _, monitor in ipairs(hl.get_monitors()) do
    if monitor.name:match("^eDP%-") or monitor.name:match("^LVDS%-") or monitor.name:match("^DSI%-") then
      internal = monitor
      break
    end
  end
  -- With the panel off Hyprland falls back to the focused external monitor for
  -- touch. Disable this selected device until the internal display returns.
  local enabled = internal ~= nil
  local disabled = io.open(paths.home .. "/.local/state/omarchy/toggles/hypr/touchscreen-disabled-name", "r")
  if disabled then
    enabled = enabled and disabled:read("*l") ~= name
    disabled:close()
  end
  local transform = internal and internal.transform or 0
  local output = internal and internal.name or ""
  local key = output .. ":" .. transform .. ":" .. tostring(enabled)
  if previous ~= key then
    hl.device({ name = name, output = output, transform = transform, enabled = enabled })
    previous = key
  end
end
sync()
hl.on("monitor.added", sync)
hl.on("monitor.removed", sync)
hl.on("monitor.layout_changed", sync)
