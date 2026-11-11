import QtQuick
import Quickshell
import Quickshell.Io

// Safe scalar control/status only. No password, unlock, object or eval API.
SocketServer {
  id: root
  required property var readStatus
  signal lockRequested()
  signal stateChanged()
  signal listening()
  path: Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-lock-control-" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + ".sock"
  onActiveStatusChanged: if (active) listening()
  handler: Socket {
    id: connection
    property string pending: ""
    function sendStatus() {
      if (connected) { write(JSON.stringify(root.readStatus()) + "\n"); flush() }
    }
    onConnectionStateChanged: sendStatus()
    property Connections subscription: Connections {
      target: root
      function onStateChanged() { connection.sendStatus() }
    }
    parser: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        // Bound incomplete requests too. Never accumulate an unbounded
        // newline-free client buffer or dispatch arbitrary names/data.
        connection.pending += chunk
        if (connection.pending.length > 64) { connection.connected = false; return }
        var end
        while ((end = connection.pending.indexOf("\n")) !== -1) {
          var line = connection.pending.slice(0, end)
          connection.pending = connection.pending.slice(end + 1)
          if (line === '{"method":"lock"}') { root.lockRequested(); connection.sendStatus() }
          else if (line === '{"method":"status"}') connection.sendStatus()
          else { connection.connected = false; return }
        }
      }
    }
  }
}
