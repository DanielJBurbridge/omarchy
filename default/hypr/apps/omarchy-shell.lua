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

  local menu_buttons = {}
  local menu_buttons_enabled = false
  local navigation_cursor
  if os.getenv("OMARCHY_HANDHELD_SESSION") then
    -- A, RT and R3 share left click. B and LT share right click on this
    -- virtual pointer. Only its clicks in the built-in menu become actions.
    local function menu_button(code, action)
      local bind = hl.bind(code, function()
        if action == "select" then
          local cursor = hl.get_cursor_pos()
          if navigation_cursor and (math.abs(cursor.x - navigation_cursor.x) > 1 or
              math.abs(cursor.y - navigation_cursor.y) > 1) then
            navigation_cursor = nil
          end
          -- Preserve normal click delivery to search, rows and header buttons
          -- after aiming with the stick. Hyprland also forwards its release.
          if not navigation_cursor then return { pass_event = true } end
        end
        local monitor = hl.get_active_monitor()
        if monitor and monitor.name:match("^eDP%-%d+$") then
          hl.dispatch(hl.dsp.event("omarchy-ally-menu-" .. action .. ":" .. monitor.name))
        end
      end, { click = action == "back", device = { list = { "inputplumber-mouse" } } })
      bind:set_enabled(false)
      return bind
    end

    menu_buttons = {
      menu_button("mouse:272", "select"),
      menu_button("mouse:273", "back"),
    }

    -- Hyprland reports XKB keycodes. The controller's D-pad sends these
    -- arrows through its existing keyboard map.
    local arrows = { [111] = true, [113] = true, [114] = true, [116] = true }
    hl.on("input.keyboard.key", function(keycode, _, state)
      if menu_buttons_enabled and state ~= 0 and arrows[keycode] then
        navigation_cursor = hl.get_cursor_pos()
      end
    end)
  end

  local function sync_menu_buttons(focused, closing, keyboard_monitor)
    if #menu_buttons == 0 then return end
    local enabled = false
    if focused and focused.name:match("^eDP%-%d+$") and keyboard_monitor ~= focused then
      for _, layer in ipairs(hl.get_layers({ namespace = "omarchy-menu" })) do
        if layer ~= closing and layer.mapped and layer.monitor == focused then
          enabled = true
          break
        end
      end
    end
    if enabled == menu_buttons_enabled then return end
    menu_buttons_enabled = enabled
    navigation_cursor = enabled and hl.get_cursor_pos() or nil
    for _, bind in ipairs(menu_buttons) do
      if tostring(bind) ~= "HL.Keybind(expired)" then bind:set_enabled(enabled) end
    end
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
    sync_menu_buttons(focused, closing, keyboard_monitor)
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
