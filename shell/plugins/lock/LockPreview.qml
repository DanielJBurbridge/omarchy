import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons as Commons

PanelWindow {
  id: previewWindow
  property string backgroundPath: ""
  property string videoPosterPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool fingerprintUnavailable: false
  signal dismissed()
  // Right-to-left languages read this window mirrored.
  Binding { target: previewWindow.contentItem; property: "LayoutMirroring.enabled"; value: Commons.I18n.rightToLeft }
  Binding { target: previewWindow.contentItem; property: "LayoutMirroring.childrenInherit"; value: true }

  visible: true
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "omarchy-lock-preview"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore

  LockView {
    anchors.fill: parent
    backgroundPath: previewWindow.backgroundPath
    videoPosterPath: previewWindow.videoPosterPath
    backgroundVersion: previewWindow.backgroundVersion
    fingerprintConfigured: previewWindow.fingerprintConfigured
    fingerprintUnavailable: previewWindow.fingerprintUnavailable
    authenticatingPassword: false
    failureMessage: ""
    failedAttempts: 0
    inputEnabled: false
    loadBackground: true
    passwordText: ""
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: previewWindow.dismissed()
  }
}
