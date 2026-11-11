import QtQuick
import qs.Ui
import qs.Commons

// Optional, placed by the Ally keyboard setup. The bar's layer never takes
// keyboard focus, so tapping this leaves the app's text field as the target.
BarWidget {
  id: root
  moduleName: "omarchy.desktop-keyboard"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: I18n.t("bar.desktopKeyboard")
    textRotation: root.vertical ? 90 : 0
    fixedWidth: root.vertical ? root.barSize : Math.max(88, labelWidth + 24)
    fixedHeight: root.vertical ? Math.max(88, labelWidth + 24) : root.barSize
    tooltipText: I18n.t("bar.desktopKeyboardToggle")
    onPressed: function(button) {
      if (button === Qt.LeftButton) root.bar.run("omarchy-toggle-desktop-keyboard")
      else if (button === Qt.RightButton) root.bar.run("omarchy-toggle-desktop-keyboard hide")
    }
  }
}
