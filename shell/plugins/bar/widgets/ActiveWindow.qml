import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.active-window"

  readonly property var toplevel: ToplevelManager.activeToplevel
  readonly property string title: toplevel ? (toplevel.title || toplevel.appId || "") : ""
  readonly property int maxLabelWidth: Number(setting("maxWidth", 280))

  readonly property var screen: root.QsWindow.window?.screen
  readonly property bool handheldScreen: root.bar?.shell?.isHandheldScreen?.(screen) === true
  readonly property bool showsWindowName: title !== "" && !vertical && !(handheldScreen && setting("closeOnly", false))
  readonly property var closeTarget: {
    if (!handheldScreen || !toplevel) return null
    const monitor = Hyprland.monitorFor(screen)
    const workspace = monitor?.activeWorkspace
    if (!monitor?.focused || !workspace) return null
    return workspace.toplevels.values.some(client => client.wayland === toplevel) ? toplevel : null
  }

  visible: showsWindowName || closeTarget !== null
  implicitWidth: (showsWindowName ? Math.min(maxLabelWidth, labelText.implicitWidth) + Style.spacing.controlPaddingX * 2 : 0)
    + (closeTarget ? barSize : 0)
  implicitHeight: barSize

  function closeWindow(target) {
    if (target && target === root.closeTarget) target.close()
  }

  Behavior on implicitWidth {
    NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
  }

  Item {
    anchors.left: parent.left
    anchors.right: closeControl.visible ? closeControl.left : parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    visible: root.showsWindowName

    Item {
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      clip: true

      Text {
        id: labelText
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        width: parent.width
        text: root.title
        color: root.bar ? root.bar.barForeground : Commons.Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        opacity: 0.85
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor

      onClicked: function(mouse) {
        if (!root.toplevel) return
        if (mouse.button === Qt.MiddleButton) {
          root.toplevel.close()
        } else if (mouse.button === Qt.RightButton) {
          root.toplevel.close()
        } else {
          root.toplevel.activate()
        }
      }
      onEntered: if (root.bar) root.bar.showTooltip(root, root.title)
      onExited: if (root.bar) root.bar.hideTooltip(root)
    }
  }

  WidgetButton {
    id: closeControl
    anchors.right: parent.right
    bar: root.bar
    fixedWidth: root.barSize
    fixedHeight: root.barSize
    fontSize: Style.font.body * 1.4
    text: "×"
    tooltipText: I18n.t("bar.closeWindow")
    visible: root.closeTarget !== null
    pressFeedbackButtons: Qt.LeftButton

    Accessible.role: Accessible.Button
    Accessible.name: tooltipText
    Accessible.onPressAction: root.closeWindow(root.closeTarget)

    property var pressedWindow: null
    // The bar gives its registered targets the pointer-down state separately
    // from the click that follows release.
    onHeldButtonsChanged: if (heldButtons & Qt.LeftButton) pressedWindow = root.closeTarget
    onPressed: function(button) {
      if (button !== Qt.LeftButton) return
      const target = pressedWindow
      pressedWindow = null
      root.closeWindow(target)
    }
  }
}
