import QtQuick
import QtQuick.VirtualKeyboard.Styles

KeyPanel {
  id: root
  property string label: control ? (control.uppercased ? control.displayText.toUpperCase() : control.displayText) : ""
  property bool selected: false
  Rectangle {
    anchors.fill: parent
    anchors.margins: 3
    radius: Theme.radius
    color: Theme.alpha(Theme.foreground, root.control && root.control.pressed ? 0.22 : (root.selected ? 0.18 : 0.04))
    border.width: 1
    border.color: root.selected ? Theme.accent : Theme.alpha(Theme.foreground, 0.4)
    opacity: root.control && !root.control.enabled ? 0.4 : 1
    Text {
      anchors.fill: parent
      anchors.margins: 3
      text: root.label
      textFormat: Text.PlainText
      color: Theme.foreground
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      fontSizeMode: Text.Fit
      minimumPixelSize: 10
    }
    Text {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 4
      text: root.control ? root.control.smallText : ""
      visible: root.control && root.control.smallTextVisible
      color: Theme.alpha(Theme.foreground, 0.66)
      font.family: Theme.fontFamily
      font.pixelSize: 10
    }
  }
}
