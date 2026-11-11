import QtQuick
import Quickshell
import Quickshell.Io

// A one-way state feed, retained inside the detached authentication service.
// Consumers must fail closed on EOF/error and check for a stranded compositor
// lock at connect/action boundaries. This socket never accepts auth requests.
SocketServer {
  id: root

  required property var readLocked
  readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR")
  readonly property string instance: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
  path: runtime.startsWith("/") && /^[A-Za-z0-9_.-]+$/.test(instance)
    ? runtime + "/omarchy-lock-" + instance + ".sock" : ""
  active: false

  signal stateChanged()

  handler: Socket {
    id: connection
    property var lastSent: undefined

    function publish() {
      if (!connected) return
      var locked = !!root.readLocked()
      if (lastSent === locked) return
      write(JSON.stringify({ locked: locked }) + "\n")
      flush()
      lastSent = locked
    }

    onConnectionStateChanged: publish()
    Component.onCompleted: publish()

    property Connections stateSubscription: Connections {
      target: root
      function onStateChanged() { connection.publish() }
    }

    // Subscribers only read. Unsolicited bytes close the connection; they
    // never form a request protocol beside the existing authentication IPC.
    parser: SplitParser {
      splitMarker: ""
      onRead: connection.connected = false
    }
  }
}
