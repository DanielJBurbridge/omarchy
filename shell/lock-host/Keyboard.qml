import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.VirtualKeyboard
import QtQuick.VirtualKeyboard.Settings
import qs.Commons as Commons

Item {
  id: root
  signal focusRequested()
  implicitHeight: layoutChoice.height + panel.implicitHeight
  LayoutMirroring.enabled: false
  LayoutMirroring.childrenInherit: true

  Controls.ComboBox {
    id: layoutChoice
    objectName: "trustedKeyboardLayout"
    width: parent.width
    height: 44
    focusPolicy: Qt.NoFocus
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.body
    palette.window: Commons.Color.lock.background
    palette.base: Commons.Color.lock.background
    palette.button: Commons.Color.lock.background
    palette.text: Commons.Color.lock.text
    palette.buttonText: Commons.Color.lock.text
    model: VirtualKeyboardSettings.availableLocales
    currentIndex: model.indexOf(VirtualKeyboardSettings.locale)
    displayText: Commons.I18n.t("lock.keyboardLayout").arg(VirtualKeyboardSettings.locale)
    onActivated: {
      VirtualKeyboardSettings.locale = model[currentIndex]
      root.focusRequested()
      Qt.inputMethod.show()
    }
  }
  InputPanel {
    id: panel
    width: parent.width
    y: layoutChoice.height
    visible: Qt.inputMethod.visible
  }
}
