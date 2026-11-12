import QtQuick
import QtQuick.Controls.Basic as Controls

Controls.ComboBox {
  id: root
  signal inputRequested()
  implicitHeight: 44
  focusPolicy: Qt.NoFocus
  hoverEnabled: true
  font.family: Theme.fontFamily
  font.pixelSize: Theme.fontSize
  leftPadding: 14
  rightPadding: 34
  opacity: enabled ? 1 : 0.45
  contentItem: TextInput {
    text: root.editable ? root.editText : root.displayText
    font: root.font
    color: Theme.foreground
    selectionColor: Theme.alpha(Theme.accent, 0.35)
    selectedTextColor: Theme.foreground
    verticalAlignment: TextInput.AlignVCenter
    enabled: root.editable
    readOnly: !root.editable
    autoScroll: root.editable
    clip: true
    selectByMouse: root.editable
    onTextEdited: root.editText = text
    TapHandler { onTapped: if (root.editable) root.inputRequested() }
  }
  indicator: Text {
    x: root.width - width - 14
    anchors.verticalCenter: parent.verticalCenter
    text: "⌄"
    font: root.font
    color: Theme.foreground
  }
  background: Rectangle {
    radius: Theme.radius
    color: Theme.alpha(Theme.foreground, root.hovered || root.popup.visible ? 0.08 : 0.04)
    border.width: 1
    border.color: Theme.alpha(Theme.foreground, root.popup.visible ? 1 : 0.4)
  }
  delegate: Controls.ItemDelegate {
    required property int index
    width: root.width - 2
    height: 44
    highlighted: root.highlightedIndex === index
    contentItem: Text {
      text: root.textAt(index)
      textFormat: Text.PlainText
      color: Theme.foreground
      font: root.font
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }
    background: Rectangle { color: Theme.alpha(Theme.foreground, parent.highlighted ? 0.18 : 0) }
  }
  popup: Controls.Popup {
    y: root.height + 4
    width: root.width
    padding: 1
    // Available space above/below is resolved by Qt's popup positioning.
    implicitHeight: Math.min(contentItem.implicitHeight + 2, 220)
    contentItem: ListView {
      clip: true
      implicitHeight: contentHeight
      model: root.popup.visible ? root.delegateModel : null
      currentIndex: root.highlightedIndex
      Controls.ScrollIndicator.vertical: Controls.ScrollIndicator {}
    }
    background: Rectangle {
      color: Theme.background
      border.color: Theme.foreground
      border.width: 1
      radius: Theme.radius
    }
  }
}
