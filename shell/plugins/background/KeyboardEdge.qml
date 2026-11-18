import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons as Commons

PanelWindow {
  anchors.bottom: true
  implicitWidth: 192
  implicitHeight: 8
  exclusiveZone: implicitHeight
  color: "transparent"
  WlrLayershell.namespace: "omarchy-keyboard-edge"
  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  Rectangle {
    anchors.centerIn: parent
    width: 52
    height: 4
    radius: 2
    color: Commons.Color.foreground
    border.color: Commons.Color.background
  }

  MultiPointTouchArea {
    anchors.fill: parent
    z: 1
    mouseEnabled: false
    property int contacts: 0
    property bool tracking: false

    onPressed: points => {
      contacts += points.length
      tracking = contacts === 1
    }
    onUpdated: points => {
      for (const p of points) {
        if (Math.abs(p.x - p.startX) > 24 || p.y > p.startY + 8) tracking = false
      }
    }
    onReleased: points => {
      const p = points[0]
      if (tracking && p.startY - p.y >= 64 && Math.abs(p.x - p.startX) <= 24)
        Quickshell.execDetached(["omarchy-toggle-desktop-keyboard", "show-for-edge"])
      tracking = false
      contacts -= points.length
    }
    onCanceled: { tracking = false; contacts = 0 }
  }
}
