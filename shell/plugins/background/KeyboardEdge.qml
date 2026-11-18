import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons as Commons

PanelWindow {
  id: edge
  anchors.bottom: true
  implicitWidth: Math.min(480, Math.round(screen.width / 2))
  implicitHeight: 36
  exclusiveZone: implicitHeight
  color: "transparent"
  WlrLayershell.namespace: "omarchy-keyboard-edge"
  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  // Keep the tile reservation stable while another surface owns the edge.
  mask: Region { item: touch.enabled ? touch : null }

  readonly property var client: ToplevelManager.activeToplevel
  readonly property bool available: layersClear && !!client && client.activated && !client.fullscreen
    && !!client.appId && !/gamescope/i.test(client.appId)
  property bool layersClear: false

  // Hyprland signals a layer's name but not its stack level. Read the stack
  // once on startup and again when it changes, including external surfaces.
  Process {
    id: layers
    property bool pending: false
    function refresh() {
      if (running) pending = true
      else running = true
    }
    command: ["hyprctl", "-j", "layers"]
    stdout: StdioCollector { id: snapshot; waitForEnd: true }
    onExited: code => {
      if (pending) {
        pending = false
        Qt.callLater(layers.refresh)
        return
      }
      try {
        const levels = JSON.parse(snapshot.text)[edge.screen.name].levels
        edge.layersClear = code === 0 && levels["2"].every(s => s.namespace === "omarchy-bar" || s.namespace === "omarchy-dock")
          && levels["3"].every(s => s.namespace === "omarchy-notifications")
      } catch (_) { edge.layersClear = false }
    }
    Component.onCompleted: refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "openlayer") edge.layersClear = false
      if (event.name === "openlayer" || event.name === "closelayer") layers.refresh()
    }
  }

  Connections {
    target: edge.screen
    function onGeometryChanged() { touch.tracking = false }
    function onOrientationChanged() { touch.tracking = false }
  }
  onDevicePixelRatioChanged: touch.tracking = false

  // A half-turn can leave Qt's screen geometry and orientation unchanged.
  // Read Hyprland's transform on contact and compare it with the release probe.
  Process {
    id: monitorAtPress
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector { id: monitors; waitForEnd: true }
  }

  Rectangle {
    visible: edge.available
    anchors.centerIn: parent
    width: 128
    height: 6
    radius: height / 2
    color: Commons.Color.foreground
    border.color: Commons.Color.background
  }

  MultiPointTouchArea {
    id: touch
    anchors.fill: parent
    enabled: edge.available
    z: 1
    mouseEnabled: false
    readonly property int maximumDrift: 36
    property int contacts: 0
    property bool tracking: false
    onEnabledChanged: if (!enabled) { tracking = false; contacts = 0 }

    onPressed: points => {
      contacts += points.length
      tracking = contacts === 1 && !monitorAtPress.running
      if (tracking) monitorAtPress.running = true
    }
    onUpdated: points => {
      for (const p of points) {
        if (Math.abs(p.x - p.startX) > maximumDrift || p.y > p.startY + 8) tracking = false
      }
    }
    onReleased: points => {
      const p = points[0]
      if (tracking && !monitorAtPress.running && p.startY - p.y >= 48 && Math.abs(p.x - p.startX) <= maximumDrift) {
        try {
          const start = JSON.parse(monitors.text)
          if (start.length === 1 && start[0].name === edge.screen.name && Number.isInteger(start[0].transform))
            Quickshell.execDetached(["omarchy-toggle-desktop-keyboard", "show-for-edge", String(start[0].transform)])
        } catch (_) { /* An unreadable output at contact cannot start a swipe. */ }
      }
      tracking = false
      contacts = Math.max(0, contacts - points.length)
    }
    onCanceled: { tracking = false; contacts = 0 }
  }
}
