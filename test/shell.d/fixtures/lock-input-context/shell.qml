import QtQuick
import Quickshell

ShellRoot {
  id: root
  property var view: null
  property int step: 0
  readonly property string dummyPassword: "Auth-regression-only-9!"

  Window { id: host; width: 800; height: 600; visible: true }
  Unrelated { id: unrelated }

  function find(item, name) {
    if (item.objectName === name) return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) {
      var found = find(children[i], name)
      if (found) return found
    }
    return null
  }

  Timer {
    interval: 150
    repeat: true
    running: true
    onTriggered: {
      try {
        if (root.step === 0) {
          var component = Qt.createComponent("file://" + Quickshell.env("OMARCHY_AUTH_SOURCE_ROOT") + "/shell/plugins/lock/LockView.qml")
          if (component.status !== Component.Ready) throw new Error(component.errorString())
          root.view = component.createObject(host.contentItem, {width: 800, height: 600, loadBackground: false, passwordText: root.dummyPassword})
          if (!root.view) throw new Error(component.errorString())
          root.view.forcePasswordFocus()
        } else {
          var password = find(root.view, "lockPassword")
          if (!password || !password.activeFocus || password.text !== root.dummyPassword) throw new Error("real lock password field must be focused and populated")
          var leaked = unrelated.focusedText() === root.dummyPassword
          if (leaked !== (Quickshell.env("OMARCHY_AUTH_EXPECT_EXPOSED") === "1")) throw new Error("unrelated importer read the focused password through InputContext")
          // Exercise Quickshell's real INITIAL_ENVIRONMENT child boundary.
          Quickshell.execDetached(["python3", "-c", "import json,os,sys; json.dump({k:os.environ.get(k) for k in ['QT_IM_MODULE','QT_IM_MODULES','QT_VIRTUALKEYBOARD_DESKTOP_DISABLE']},open(sys.argv[1],'w'))", Quickshell.env("OMARCHY_AUTH_CHILD_RESULT")])
          console.log("LOCK_INPUT_CONTEXT_TEST_PASS")
          Qt.quit()
        }
        root.step++
      } catch (error) {
        console.error("LOCK_INPUT_CONTEXT_TEST_FAIL: " + error)
        Qt.quit()
      }
    }
  }
}
