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
  property bool sawCrash: false
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
          probe.exited.connect(function(code, status) {
            if (code === 1) console.log("ORPHAN_PROBE_EXIT code=" + code + " status=" + status)
            if (status === 1) { // Installed QProcess::CrashExit; actual signal, not a mock callback.
              check(code === 1, "SIGHUP is reported as code 1")
              root.sawCrash = true
            }
          })
          check(service.snapshot().realScreens === 0, "fixture has no lock-capable output")
          retry.interval = 10 // Accelerate the actual 20-tick budget only here.
          root.phase = 1
        } else if (phase === 1 || phase === 3 || phase === 5) {
          if (root.sawCrash) check(!service.ownerReady && !service.currentlyLocked(), "crashed probe must not resolve readiness or dispatch intent")
          if (retry.remaining > 0 || probe.running) return
          check(!service.ownerReady && !service.currentlyLocked() && !service.snapshot().secure, "unknown/competitor remains conservative after budget")
          if (phase === 5) check(root.sawCrash, "actual process crash was observed")
          console.log(phase === 1 ? "RECOVERY_EXHAUSTED" : (phase === 3 ? "RECOVERY_SECOND_EXHAUSTED" : "RECOVERY_CRASH_EXHAUSTED"))
          root.phase++
        } else if (phase === 2 || phase === 4) {
          if (root.sawCrash) check(!service.ownerReady && !service.currentlyLocked(), "crashed probe cannot start lock")
          if (retry.remaining <= 0) return
          check(!service.ownerReady && !service.currentlyLocked(), "fresh unknown probe cannot start lock")
          console.log(phase === 2 ? "RECOVERY_REARMED" : "RECOVERY_CRASH_REARMED")
          root.phase++
        } else if (phase === 6 && service.lockRequested) {
          check(service.ownerReady && !service.snapshot().secure && !service.snapshot().sessionLocked, "resolved proof permits request, never offscreen secure")
          console.log("EXPLICIT_LOCK_RECOVERY_PASS")
          Qt.quit()
        }
      } catch (error) { console.error("EXPLICIT_LOCK_RECOVERY_FAIL " + error); Qt.quit() }
    }
  }
}
