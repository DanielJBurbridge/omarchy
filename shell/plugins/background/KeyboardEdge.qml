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
    function onGeometryChanged() { touch.cancel() }
    function onOrientationChanged() { touch.cancel() }
  }
  onDevicePixelRatioChanged: touch.cancel()
  onClientChanged: touch.cancel()

  // A half-turn can leave Qt's screen geometry and orientation unchanged.
  // Read Hyprland's transform on contact and compare it with the release probe.
  Process {
    id: monitorAtPress
    property int transform: -1
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector { id: monitors; waitForEnd: true }
    onExited: code => {
      const expected = touch.pendingTapTransform
      touch.pendingTapTransform = -1
      if (code !== 0) return
      try {
        const start = JSON.parse(monitors.text)
        if (start.length !== 1 || start[0].name !== edge.screen.name || !Number.isInteger(start[0].transform)) return
        transform = start[0].transform
        if (expected >= 0) {
          if (expected === transform && edge.available) touch.show(transform)
          else Hyprland.refreshMonitors()
        }
      } catch (_) { /* An unreadable output at contact cannot open the keyboard. */ }
    }
  }

  Rectangle {
    id: handle
    visible: edge.available
    anchors.centerIn: parent
    width: 128
    height: 6
    radius: height / 2
    color: touch.tracking && touch.tapCandidate ? Commons.Color.accent : Commons.Color.foreground
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
    property bool tapCandidate: false
    property double pressTime: 0

    property int cachedTransform: -1
    property int pendingTapTransform: -1

    function cancel() {
      tracking = false
      pendingTapTransform = -1
    }

    function show(transform) {
      Quickshell.execDetached(["omarchy-toggle-desktop-keyboard", "show-for-edge", String(transform)])
    }

    function withinTapDistance(p) {
      return Math.hypot(p.x - p.startX, p.y - p.startY) <= Application.styleHints.startDragDistance
    }
    onEnabledChanged: if (!enabled) { cancel(); contacts = 0 }

    onPressed: points => {
      cancel()
      contacts += points.length
      tracking = contacts === 1 && !monitorAtPress.running
      if (tracking) {
        const p = points[0]
        // Pad the visible pill for a fingertip; the wider strip is swipe-only.
        tapCandidate = Math.abs(p.x - width / 2) <= handle.width / 2 + 12
        pressTime = Date.now()
        cachedTransform = Hyprland.monitorFor(edge.screen)?.lastIpcObject?.transform ?? -1
        monitorAtPress.transform = -1
        monitorAtPress.running = true
      }
    }
    onUpdated: points => {
      for (const p of points) {
        if (!withinTapDistance(p)) tapCandidate = false
        if (Math.abs(p.x - p.startX) > maximumDrift || p.y > p.startY + 8) tracking = false
      }
    }
    onReleased: points => {
      const p = points[0]
      const tapped = tapCandidate && withinTapDistance(p) && Date.now() - pressTime < Application.styleHints.mousePressAndHoldInterval
      const swiped = p.startY - p.y >= 48 && Math.abs(p.x - p.startX) <= maximumDrift
      if (tracking && (tapped || swiped)) {
        if (monitorAtPress.transform >= 0) show(monitorAtPress.transform)
        // A quick tap can lift before the press query returns. Only complete it
        // when that query also agrees with the monitor state cached at contact.
        else if (tapped && monitorAtPress.running) pendingTapTransform = cachedTransform
      }
      tracking = false
      contacts = Math.max(0, contacts - points.length)
    }
    onCanceled: { cancel(); contacts = 0 }
  }
}
