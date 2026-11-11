import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// No password fields, PAM contexts, session-lock surfaces or auth objects.
// The canonical CLI takes the independently peer-checked control path directly.
Item {
  id: root
  property var shell: null
  property string omarchyPath: ""
  property var state: ({ready: false, locked: true, requested: false, secure: false, owner: "trusted-host"})
  property bool refreshPending: false
  readonly property string endpoint: Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-lock-control-" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + ".sock"

  function unknown() { state = {ready: false, locked: true, requested: false, secure: false, owner: "trusted-host"} }
  function refresh() {
    unknown()
    if (statusProcess.running) { refreshPending = true; return }
    statusProcess.running = true
  }

  // Incoming data only triggers a separately peer/unit/PID/start-time checked
  // status query. Never trust JSON or QObject references from this raw socket.
  Socket {
    id: events
    path: root.endpoint
    onConnectionStateChanged: { root.unknown(); if (connected) root.refresh() }
    onError: root.unknown()
    parser: SplitParser { onRead: root.refresh() }
  }
  FileView {
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-lock-ready-" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + ".json"
    watchChanges: true
    printErrors: false
    function reconnect() {
      events.connected = false
      Qt.callLater(function() { events.connected = true })
    }
    onLoaded: reconnect()
    onFileChanged: reload()
    onLoadFailed: root.unknown()
  }
  Process {
    id: statusProcess
    command: [Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-lock-host", "status"]
    stdout: StdioCollector { id: response; waitForEnd: true }
    onExited: function(code) {
      if (code === 0 && events.connected) {
        try {
          var value = JSON.parse(response.text)
          if (typeof value.ready === "boolean" && typeof value.locked === "boolean" && typeof value.secure === "boolean") root.state = value
        } catch (error) { root.unknown() }
      } else root.unknown()
      if (root.refreshPending) { root.refreshPending = false; root.refresh() }
    }
  }
  Process {
    id: requestProcess
    command: [Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-lock-host", "lock"]
    onExited: root.refresh()
  }
  ShellIpc {
    target: "lock"
    function lock(): string { if (!requestProcess.running) requestProcess.running = true; return "pending" }
    function isLocked(): string { return root.state.ready === true && root.state.locked === false ? "false" : "true" }
    function status(): string { return JSON.stringify(root.state) }
  }
}
