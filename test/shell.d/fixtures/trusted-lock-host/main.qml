import QtQuick
import Quickshell
import qs.Commons as Commons

// Deliberately plugin-bearing/caller-controlled process. The authentication
// view and PAM contexts live only in the other process.
ShellRoot {
  id: root
  Window {
    id: publicWindow
    width: 320; height: 200; visible: true
    TextInput { id: publicInput; text: "public-main-field"; focus: true }
    Unrelated { id: unrelated }
  }
  property var broker: null
  property int step: 0
  Timer {
    interval: 200; running: true; repeat: true
    onTriggered: {
      try {
        if (root.step === 0) {
          var c = Qt.createComponent("file://" + Quickshell.env("OMARCHY_AUTH_SOURCE_ROOT") + "/shell/plugins/lock/Broker.qml")
          if (c.status !== Component.Ready) throw new Error(c.errorString())
          root.broker = c.createObject(publicWindow.contentItem)
          if (!root.broker) throw new Error(c.errorString())
          publicWindow.requestActivate()
          publicInput.forceActiveFocus()
        } else {
          if (unrelated.focusedText() !== "public-main-field") throw new Error("caller-selected main input context was not active")
          if (unrelated.focusedText() === "ä@É9!") throw new Error("main InputContext observed trusted-host password")
          if (unrelated.fromParents("ä@É9!")) throw new Error("main parent traversal reached trusted-host password")
          if (root.broker.state.password !== undefined || root.broker.state.enteredPassword !== undefined) throw new Error("credential crossed broker")
          if (root.broker.state.secure || root.broker.state.ready || !root.broker.state.locked) throw new Error("missing real unit identity must keep broker failclosed")
          // Call the real Broker's registered ShellIpc handler. A valid
          // unready snapshot can have all actual compositor flags false.
          root.broker.state = {protocol: 1, owner: "trusted-host", ready: false, locked: false, requested: false, secure: false}
          var answer = Commons.IpcRegistry.call("lock", "isLocked", [])
          if (!answer.ran || answer.output !== "true") throw new Error("unready broker reported unlocked")
          root.broker.state = {protocol: 1, owner: "trusted-host", ready: true, locked: false, requested: false, secure: false}
          answer = Commons.IpcRegistry.call("lock", "isLocked", [])
          if (!answer.ran || answer.output !== "false") throw new Error("ready unlocked broker did not recover")
          root.broker.state = {ready: "true", locked: false}
          if (Commons.IpcRegistry.call("lock", "isLocked", []).output !== "true") throw new Error("non-boolean readiness authorised broker")
          root.broker.unknown()
          if (Commons.IpcRegistry.call("lock", "isLocked", []).output !== "true") throw new Error("unknown broker reported unlocked")
          console.log("BROKER_READINESS_PASS")
          console.log("MAIN_LOCK_ISOLATION_PASS")
          Qt.quit()
        }
        root.step++
      } catch (error) { console.error("MAIN_LOCK_ISOLATION_FAIL " + error); Qt.quit() }
    }
  }
}
