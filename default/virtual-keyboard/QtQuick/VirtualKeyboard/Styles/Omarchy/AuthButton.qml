import QtQuick
import QtQuick.Controls.Basic as Controls

// The same quiet outline and foreground wash as Ui.Button, without importing
// the desktop shell into SDDM's process.
Controls.Button {
  id: root
  property bool selected: false
  implicitHeight: 48
  focusPolicy: Qt.TabFocus
  hoverEnabled: true
  font.family: Theme.fontFamily
  font.pixelSize: Theme.fontSize
  opacity: enabled ? 1 : 0.45
  contentItem: Text {
    text: root.text
    textFormat: Text.PlainText
    color: Theme.foreground
    font: root.font
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
  }
  background: Rectangle {
    radius: Theme.radius
    color: Theme.alpha(Theme.foreground, root.down ? 0.22 : (root.hovered || root.selected || root.activeFocus ? 0.08 : 0.04))
    border.width: 1
    border.color: Theme.alpha(Theme.foreground, root.selected || root.activeFocus ? 1 : 0.4)
  }
}
