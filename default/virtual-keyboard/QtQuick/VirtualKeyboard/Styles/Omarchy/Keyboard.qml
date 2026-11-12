import QtQuick
import QtQuick.VirtualKeyboard
import QtQuick.VirtualKeyboard.Settings

Item {
  id: root
  property color backgroundColor: Theme.background
  property color foregroundColor: Theme.foreground
  property color accentColor: foregroundColor
  property string fontFamily: "monospace"
  property real fontSize: 18
  property real cornerRadius: 0
  property string layoutText: "Layout: %1"
  signal focusRequested()
  implicitHeight: layoutChoice.height + panel.implicitHeight + 8
  LayoutMirroring.enabled: false
  LayoutMirroring.childrenInherit: true

  Binding { target: Theme; property: "background"; value: root.backgroundColor }
  Binding { target: Theme; property: "foreground"; value: root.foregroundColor }
  Binding { target: Theme; property: "accent"; value: root.accentColor }
  Binding { target: Theme; property: "fontFamily"; value: root.fontFamily }
  Binding { target: Theme; property: "fontSize"; value: root.fontSize }
  Binding { target: Theme; property: "radius"; value: root.cornerRadius }
  Binding { target: Theme; property: "keyboardWidth"; value: root.width }
  Component.onCompleted: {
    VirtualKeyboardSettings.styleName = "Omarchy"
    VirtualKeyboardSettings.fullScreenMode = false
  }

  Rectangle { anchors.fill: parent; color: root.backgroundColor }
  AuthChoice {
    id: layoutChoice
    objectName: "trustedKeyboardLayout"
    width: Math.min(parent.width, Math.max(220, implicitContentWidth + 48))
    height: 44
    anchors.right: parent.right
    anchors.rightMargin: 3
    model: VirtualKeyboardSettings.availableLocales
    currentIndex: model.indexOf(InputContext.locale)
    displayText: root.layoutText.arg(InputContext.locale)
    onActivated: {
      VirtualKeyboardSettings.locale = model[currentIndex]
      root.focusRequested()
      Qt.inputMethod.show()
    }
  }
  InputPanel {
    id: panel
    width: parent.width
    y: layoutChoice.height + 8
    visible: Qt.inputMethod.visible
    externalLanguageSwitchEnabled: true
    onExternalLanguageSwitch: layoutChoice.popup.open()
  }
}
