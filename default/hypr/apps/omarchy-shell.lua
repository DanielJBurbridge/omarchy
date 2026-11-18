-- Window and layer rules for the Omarchy Quickshell surfaces. The
-- shell-wide bar / menu / popouts are layer-shell.

-- Keep the bar instant: no layer-shell fade/slide animation.
hl.layer_rule({ match = { namespace = "omarchy-bar" }, no_anim = true, animation = "none" })

-- Launcher, image selector, emojis, clipboard overlays, the OSD, reminders, the
-- Wi-Fi QR code and keyboard-driven panels should pop without compositor layer
-- animations. Overlays open as soon as their scale is ready, without a
-- compositor fade or slide. Panels keep their own QML opacity transition
-- for normal open/close, and skip it for panel handoff.
hl.layer_rule({ match = { namespace = "^(omarchy-menu|omarchy-image-selector|omarchy-emojis|omarchy-clipboard|omarchy-keyboard-panel|omarchy-osd|omarchy-reminders|omarchy-network-panel|omarchy-network-qr|omarchy-dock|omarchy-dock-apps)$" }, no_anim = true, animation = "none" })

-- The Ally Wi-Fi panel already selects a namespace on the built-in screen.
hl.layer_rule({ match = { namespace = "^omarchy-network-panel$" }, order = 1 })

local paths = require("default.hypr.paths")
if o.shell_succeeds(o.shell_quote(paths.omarchy_path .. "/bin/omarchy-hw-rog-ally")) then
  -- Keep each panel on the same Wayland layer and leave the keyboard's own
  -- order alone. Menu and Apps have separate rules because either surface can
  -- stay open while another monitor gains focus.
  local panel_rules = {}
  for _, namespace in ipairs({ "omarchy-menu", "omarchy-dock-apps" }) do
    panel_rules[namespace] = hl.layer_rule({
      name = namespace .. "-ally-keyboard-order",
      match = { namespace = "^" .. namespace .. "$" },
      order = 1,
      enabled = false,
    })
  end

  local function panel_monitor(namespace, focused, closing)
    -- An unplaced panel uses the focused monitor. Once its layer is allocated,
    -- use its actual output, including before the first buffer is mapped and
    -- Hyprland applies its exclusive keyboard mode.
    for _, layer in ipairs(hl.get_layers({ namespace = namespace })) do
      if layer ~= closing and (layer.mapped or layer.keyboard_interactivity == 0) then
        return layer.monitor
      end
    end
    return focused
  end

  local function sync_panel_order(focused, closing)
    local keyboard_monitor
    for _, layer in ipairs(hl.get_layers({ namespace = "wvkbd" })) do
      local monitor = layer.monitor
      if layer ~= closing and layer.mapped and monitor and monitor.name:match("^eDP%-%d+$") then
        keyboard_monitor = monitor
        break
      end
    end
    for namespace, rule in pairs(panel_rules) do
      local enabled = keyboard_monitor ~= nil and panel_monitor(namespace, focused, closing) == keyboard_monitor
      if rule:is_enabled() ~= enabled then rule:set_enabled(enabled) end
    end
  end

  local function panel_or_keyboard(layer)
    return panel_rules[layer.namespace] ~= nil or layer.namespace == "wvkbd"
  end

  sync_panel_order(hl.get_active_monitor())
  hl.on("monitor.focused", sync_panel_order)
  hl.on("layer.opened", function(layer)
    if panel_or_keyboard(layer) then sync_panel_order(hl.get_active_monitor()) end
  end)
  hl.on("layer.closed", function(layer)
    if panel_or_keyboard(layer) then sync_panel_order(hl.get_active_monitor(), layer) end
  end)
end

-- A boot intro hands the desktop between OWE's video layer and the shell's
-- background layer. The media fades itself, so a compositor fade on either
-- layer only dips the screen toward the empty desktop during the handoff.
hl.layer_rule({ match = { namespace = "^(omarchy-background|owe-background)$" }, no_anim = true, animation = "none" })

-- Dev gallery is the main shell workbench; open it maximized like
-- SUPER+ALT+F so component previews have the whole workspace.
o.window({ class = "^org.quickshell$", title = "^Omarchy shell – dev gallery$" }, { maximize = true })
