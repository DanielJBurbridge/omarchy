import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root
  property var producer: null
  property bool locked: true
  property int step: -1
  property var first: []
  property var second: []
  property bool firstLost: false
  property bool secondLost: false
  readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-lock-fixture.sock"

  Socket {
    id: firstClient
    path: root.socketPath
    onConnectionStateChanged: if (!connected) root.firstLost = true
    parser: SplitParser {
      onRead: function(line) { root.first.push(JSON.parse(line)) }
    }
  }
  Socket {
    id: secondClient
    path: root.socketPath
    onConnectionStateChanged: if (!connected) root.secondLost = true
    parser: SplitParser {
      onRead: function(line) { root.second.push(JSON.parse(line)) }
    }
  }

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      try {
        if (root.step === -1) {
          var component = Qt.createComponent("file://" + Quickshell.env("OMARCHY_PATH") + "/shell/plugins/lock/LockStateSocket.qml")
          check(component.status === Component.Ready, component.errorString())
          root.producer = component.createObject(null, {readLocked: function() { return root.locked }})
          check(root.producer !== null, component.errorString())
          check(root.producer.path === root.socketPath, "instance-scoped runtime socket")
          root.producer.active = true
        } else if (root.step === 0) {
          // Dynamic Reloadables activate on the next event-loop turn.
          check(root.producer.active, "server activated after component creation")
          firstClient.connected = true
        } else if (root.step === 1) {
          check(root.first.length === 1 && root.first[0].locked === true, "new subscriber immediately sees current lock")
          check(Object.keys(root.first[0]).join() === "locked", "payload contains no auth details")
          root.locked = false
          root.producer.stateChanged()
        } else if (root.step === 2) {
          check(root.first.length === 2 && root.first[1].locked === false, "unlock pushes false")
          secondClient.connected = true
        } else if (root.step === 3) {
          check(root.second.length === 1 && root.second[0].locked === false, "late subscriber reads fresh state")
          root.locked = true
          root.producer.stateChanged()
        } else if (root.step === 4) {
          check(root.first.length === 3 && root.first[2].locked === true, "lock request pushes true to first subscriber")
          check(root.second.length === 2 && root.second[1].locked === true, "broadcast reaches second subscriber")
          root.producer.stateChanged()
          // No inbound command is permitted, even one that looks like state.
          firstClient.write('{"locked":false}\n')
          firstClient.flush()
        } else if (root.step === 5) {
          check(root.locked && root.first.length === 3 && root.second.length === 2, "duplicate transition and inbound bytes cannot alter state")
          check(root.firstLost, "writer is disconnected")
          root.producer.destroy()
          root.producer = null
        } else {
          check(root.secondLost, "producer destruction closes subscribers (fail closed on EOF)")
          console.log("LOCK_STATE_SOCKET_TEST_PASS")
          Qt.quit()
        }
        root.step++
      } catch (error) {
        console.error("LOCK_STATE_SOCKET_TEST_FAIL step " + root.step + ": " + error)
        Qt.quit()
      }
    }
  }
}
