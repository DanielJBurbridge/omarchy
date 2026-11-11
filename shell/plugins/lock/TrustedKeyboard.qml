import QtQuick
import QtQuick.VirtualKeyboard

// Application integration: this item is parented to the trusted lock surface.
// Never turn it into a Window or expose its InputContext through plugin facades.
InputPanel {
  LayoutMirroring.enabled: false
  LayoutMirroring.childrenInherit: true
  visible: Qt.inputMethod.visible
}
