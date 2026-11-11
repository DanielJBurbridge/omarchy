import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One control at a time keeps the complete panel usable on the Ally's screen.
// D-pad up/down chooses a control; left/right chooses an action; A/Return applies.
Column {
  id: root
  property var state: ({})
  property var bar: null
  property bool busy: false
  property bool cursorActive: false
  property string error: ""
  property int controlIndex: 0
  property int actionIndex: 0
  readonly property var names: ["profile", "tdp", "boost", "governor", "gpu-level", "gpu-clock", "charge"]
  readonly property var labels: ["Platform profile", "APU sustained limit", "CPU boost", "CPU governor", "GPU mode", "GPU clock", "Charge limit"]
  readonly property string control: names[controlIndex]
  readonly property var cap: (state.controls || {})[control] || ({ available: false })
  readonly property string units: control === "tdp" ? " W" : control === "gpu-clock" ? " MHz" : control === "charge" ? "%" : ""
  readonly property var actions: {
    if (!state.configured || !cap.available || (state.conflicts || []).length) return []
    if (cap.choices) return cap.choices.map(function(v) { return { label: v, value: v } })
    if (control === "boost") return [{ label: "Off", value: 0 }, { label: "On", value: 1 }]
    var values = control === "tdp" ? [cap.value - 1, 10, 15, 25, cap.value + 1]
      : control === "charge" ? [-1, cap.value - 5, 80, 100, cap.value + 5]
      : [cap.value - 100, cap.value + 100]
    return values.filter(function(v, i) { return ((root.control === "charge" && v === -1) || (v >= cap.min && v <= cap.max)) && values.indexOf(v) === i })
      .map(function(v) { return { label: root.control === "charge" && v === -1 ? "Default" : String(v) + root.units, value: v } })
  }
  signal requested(string control, string value)
  spacing: Style.space(8)

  function move(dx, dy) {
    if (dy) {
      controlIndex = Math.max(0, Math.min(names.length - 1, controlIndex + dy))
      actionIndex = 0
    } else actionIndex = Math.max(0, Math.min(actions.length - 1, actionIndex + dx))
  }
  function activate() {
    if (!busy && actions[actionIndex]) requested(control, String(actions[actionIndex].value))
  }
  onActionsChanged: actionIndex = Math.max(0, Math.min(actions.length - 1, actionIndex))

  Row {
    width: parent.width
    spacing: Style.space(6)
    Button {
      text: "‹"
      width: Style.space(48)
      implicitHeight: Style.space(48)
      foreground: root.bar.foreground
      enabled: root.controlIndex > 0
      onClicked: root.move(0, -1)
    }
    Text {
      width: parent.width - Style.space(108)
      anchors.verticalCenter: parent.verticalCenter
      text: root.labels[root.controlIndex]
      textFormat: Text.PlainText
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
    Button {
      text: "›"
      width: Style.space(48)
      implicitHeight: Style.space(48)
      foreground: root.bar.foreground
      enabled: root.controlIndex < root.names.length - 1
      onClicked: root.move(0, 1)
    }
  }
  Text {
    width: parent.width
    text: root.cap.available ? (root.control === "charge" && root.cap.value === -1 ? "Default" : String(root.cap.value) + root.units) + (root.cap.min !== undefined ? " · " + root.cap.min + "–" + root.cap.max + root.units : "")
      : root.control === "tdp" ? "Unavailable. Select performance; the kernel must expose asus-armoury TDP."
      : "Unavailable from this backend/device."
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
  Flow {
    width: parent.width
    spacing: Style.space(4)
    Repeater {
      model: root.actions
      Button {
        required property var modelData
        required property int index
        width: (root.width - Style.space(8)) / 3
        implicitHeight: Style.space(48)
        text: modelData.label
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        fontSize: Style.font.bodySmall
        bordered: true
        enabled: !root.busy
        active: root.cap.value === modelData.value
        hasCursor: root.cursorActive && root.actionIndex === index
        onClicked: root.requested(root.control, String(modelData.value))
        onHovered: function(h) { if (h) root.actionIndex = index }
      }
    }
  }
  Text {
    width: parent.width
    text: root.error || root.state.error || (!root.state.configured ? "Power controls need reviewed-package setup."
      : (root.state.conflicts || []).length ? "Competing power writer: " + root.state.conflicts.join(", ")
      : root.busy ? "Applying; waiting for readback…" : "SteamOS Manager · " + (root.state.source || "unknown source") + "\nD-pad ↑↓ control · ←→ action · A applies")
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.caption
  }
}
