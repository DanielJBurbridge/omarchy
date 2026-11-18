import QtQuick
import "../../../../default/sddm/omarchy" as Greeter

Item {
  property QtObject config: QtObject { function boolValue(key) { return false } }
  property QtObject userModel: QtObject { property string lastUser: "fixture" }
  property QtObject sddm: QtObject { signal loginFailed(); signal loginSucceeded() }
  property QtObject sessionModel: QtObject {
    property var files: ["omarchy-managed-desktop.desktop", "omarchy.desktop", "last.desktop"]
    property int lastIndex: files.length - 1
    property bool hasDisplayRole: false
    function rowCount() { return files.length }
    function index(row, column) { return row }
    function data(row, role) {
      if (role === Qt.UserRole + 2) return files[row]
      if (role === Qt.DisplayRole && hasDisplayRole && files[row] === "omarchy.desktop") return "Hyprland (uwsm)"
      return ""
    }
  }

  Greeter.Main { id: greeter }

  Component.onCompleted: Qt.callLater(function() {
    const ally = Qt.application.arguments.includes("ally")
    const choices = [greeter.sessionIndex]
    sessionModel.hasDisplayRole = true
    choices.push(greeter.sessionIndex)
    sessionModel.files = ["omarchy.desktop", "last.desktop"]
    choices.push(greeter.sessionIndex)
    sessionModel.files = ["other.desktop", "last.desktop"]
    choices.push(greeter.sessionIndex)
    const expected = ally ? [0, 0, 0, 1] : [2, 1, 0, 1]
    if (choices.join() !== expected.join()) {
      console.error("session choices", choices.join(), "expected", expected.join())
      Qt.exit(1)
    } else {
      Qt.quit()
    }
  })
}
