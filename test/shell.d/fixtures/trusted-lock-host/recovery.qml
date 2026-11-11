import QtQuick
import Quickshell

// Real Service retry/control wiring; the isolated probe returns a test status.
// No password is entered and this offscreen screen cannot acquire a lock.
ShellRoot {
  id: root
  property var service: null
  property var retry: null
  property var probe: null
  property int phase: 0
  function check(value, message) { if (!value) throw new Error(message) }
  Timer {
    interval: 10; running: true; repeat: true
    onTriggered: {
      try {
        if (phase === 0) {
          var component = Qt.createComponent("file://" + Quickshell.env("OMARCHY_AUTH_SOURCE_ROOT") + "/shell/plugins/lock/Service.qml")
          check(component.status === Component.Ready, component.errorString())
          root.service = component.createObject(null, {trustedHost: true})
          check(service !== null, component.errorString())
          service.passwordPamConfigured = true
          var objects = service.data || []
          for (var i = 0; i < objects.length; i++) {
            if (objects[i].budget === 20 && typeof objects[i].rearm === "function") root.retry = objects[i]
            if (objects[i].command && String(objects[i].command).indexOf("omarchy-lock-host stranded") !== -1) root.probe = objects[i]
          }
          check(retry !== null && probe !== null, "production bounded retry and probe found")
          check(service.snapshot().realScreens === 0, "fixture has no lock-capable output")
          retry.interval = 10 // Accelerate the actual 20-tick budget only here.
          root.phase = 1
        } else if (phase === 1 || phase === 3) {
          if (retry.remaining > 0 || probe.running) return
          check(!service.ownerReady && !service.currentlyLocked() && !service.snapshot().secure, "unknown/competitor remains conservative after budget")
          console.log(phase === 1 ? "RECOVERY_EXHAUSTED" : "RECOVERY_SECOND_EXHAUSTED")
          root.phase++
        } else if (phase === 2) {
          if (retry.remaining <= 0) return
          check(!service.ownerReady && !service.currentlyLocked(), "fresh unknown probe cannot start lock")
          console.log("RECOVERY_REARMED")
          root.phase = 3
        } else if (phase === 4 && service.lockRequested) {
          check(service.ownerReady && !service.snapshot().secure && !service.snapshot().sessionLocked, "resolved proof permits request, never offscreen secure")
          console.log("EXPLICIT_LOCK_RECOVERY_PASS")
          Qt.quit()
        }
      } catch (error) { console.error("EXPLICIT_LOCK_RECOVERY_FAIL " + error); Qt.quit() }
    }
  }
}
