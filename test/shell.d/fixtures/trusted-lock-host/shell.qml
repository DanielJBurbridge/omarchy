import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.Commons

// This config is the trusted test process. It never loads an unrelated QML
// importer; the regression's separate main process owns that importer.
ShellRoot {
  id: root
  property var service: null
  property var view: null
  property var pam: null
  property int step: 0
  property bool released: false
  property bool startRequested: false
  property bool pamFinished: false
  property int submitted: 0
  property string pamFailure: ""
  readonly property string sourceRoot: Quickshell.env("OMARCHY_AUTH_SOURCE_ROOT")
  readonly property string dummy: "ä@É9!"
  Window { id: host; width: 1280; height: 720; visible: true }

  function check(value, message) { if (!value) throw new Error(message) }
  function find(item, name) {
    if (item.objectName === name) return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) { var v = find(children[i], name); if (v) return v }
    return null
  }
  function findKey(item, code) {
    if (item.key === code && typeof item.clicked === "function") return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) { var value = findKey(children[i], code); if (value) return value }
    return null
  }
  function typeText(text) {
    var panel = find(view, "lockKeyboardLoader").item
    // The real Qt keyboard owns the input engine; no direct password setter.
    var component = Qt.createQmlObject('import QtQuick; import QtQuick.VirtualKeyboard; QtObject { function type(text) { InputContext.inputEngine.virtualKeyClick(text === null ? Qt.Key_Return : Qt.Key_unknown, text || "", Qt.NoModifier) } }', host)
    component.type(text)
    component.destroy()
  }
  FileView {
    path: Quickshell.env("OMARCHY_AUTH_START_FILE")
    watchChanges: true
    printErrors: false
    onLoaded: root.startRequested = true
    onFileChanged: reload()
  }
  FileView {
    path: Quickshell.env("OMARCHY_AUTH_RELEASE_FILE")
    watchChanges: true
    printErrors: false
    onLoaded: root.released = true
    onFileChanged: reload()
  }
  Timer {
    interval: 200; running: true; repeat: true
    onTriggered: {
      try {
        if (step === 0) {
          if (root.service === null) {
            var c = Qt.createComponent("file://" + sourceRoot + "/shell/plugins/lock/Service.qml")
            check(c.status === Component.Ready, c.errorString())
            root.service = c.createObject(null, {trustedHost: true, omarchyPath: sourceRoot})
            check(service !== null, c.errorString())
            service.passwordPamConfigured = false
            service.strandedLockResolved = false
            console.log("TRUSTED_LOCK_HOST_UNREADY")
          }
          if (!root.startRequested) return
          // Keep offscreen fixtures away from compositor acquisition and real
          // system credentials. Production has no fixture configuration API.
          service.passwordPamConfigured = true
          service.strandedLockResolved = true
          var children = service.data || []
          for (var i = 0; i < children.length; i++) {
            if (children[i].config === "omarchy-lock-password") root.pam = children[i]
          }
          check(pam !== null, "real password PAM context found")
          pam.configDirectory = Quickshell.env("OMARCHY_AUTH_PAM_DIR")
          pam.config = "deny"
          service.lockRequested = true
          pam.completed.connect(function(result) {
            root.pamFinished = true
            if ((root.step === 3 && result === PamResult.Success) || (root.step === 5 && result !== PamResult.Success)) root.pamFailure = "unexpected real PAM result"
          })
          var v = Qt.createComponent("file://" + sourceRoot + "/shell/plugins/lock/LockView.qml")
          check(v.status === Component.Ready, v.errorString())
          root.view = v.createObject(host.contentItem, {width: 1280, height: 720, loadBackground: false, keyboardAvailable: true,
            passwordText: Qt.binding(function() { return root.service.enteredPassword }),
            inputEnabled: Qt.binding(function() { return root.service.lockRequested }),
            authenticatingPassword: Qt.binding(function() { return root.service.authenticatingPassword }),
            failureMessage: Qt.binding(function() { return root.service.failureMessage })})
          view.passwordTextEdited.connect(function(text) { root.service.enteredPassword = text })
          view.clearFailureRequested.connect(function() { root.service.failureMessage = "" })
          view.submitPassword.connect(function(text) {
            check(text === root.dummy, "exact non-US keyboard text reaches private submit")
            root.submitted++
            root.service.submitPassword(text)
          })
          view.showKeyboard()
        } else if (step === 1) {
          var keyboard = find(view, "lockKeyboardLoader").item
          check(keyboard !== null && view.keyboardHeight > 0, "trusted keyboard is visible")
          var choice = find(keyboard, "trustedKeyboardLayout")
          check(choice !== null, "visible layout chooser")
          if (choice.count < 2) return
          if (choice.displayText.indexOf("de_DE") === -1) {
            choice.currentIndex = choice.model.indexOf("de_DE")
            check(choice.currentIndex >= 0, "German is a supported Qt layout")
            choice.activated(choice.currentIndex)
            return
          }
          // Exercise the real upstream Shift key and its resulting label.
          var shift = findKey(keyboard, Qt.Key_Shift)
          var q = findKey(keyboard, Qt.Key_Q)
          check(shift !== null && q !== null, "native Shift and character keys")
          shift.clicked()
          check(q.uppercased === true, "Shift activates native key label capitalisation")
          typeText(q.uppercased ? q.text.toUpperCase() : q.text)
          check(view.passwordText === "Q", "shifted label reaches private field")
          view.clearPassword()
          typeText(root.dummy)
          check(view.passwordText === root.dummy, "real Qt non-US input")
          check(find(view, "lockPassword").displayText.indexOf(root.dummy) === -1, "immediate masking")
          // Keep a dummy focused field in this process while unrelated main
          // importer runs in a separate process; no test reads a user secret.
          if (Quickshell.env("OMARCHY_AUTH_CAPTURE")) view.grabToImage(function(result) { result.saveToFile(Quickshell.env("OMARCHY_AUTH_CAPTURE")) })
          console.log("TRUSTED_LOCK_HOST_DUMMY_READY")
        } else if (step === 2) {
          if (!root.released) return
          root.pamFinished = false
          find(view, "lockSubmit").clicked()
          check(submitted === 1 && view.passwordText === "", "private submit clears")
          view.submitEntry()
          check(submitted === 1, "PAM-in-flight duplicate submit guard")
        } else if (step === 3) {
          if (!pamFinished) return
          check(root.pamFailure === "", root.pamFailure)
          check(service.failedAttempts > 0 && service.failureMessage.length > 0 && service.currentlyLocked(), "PAM failure keeps lock and reports retry")
          typeText("discard")
          find(view, "lockCancel").clicked()
          check(view.passwordText === "" && service.currentlyLocked(), "cancel clears entry but never unlocks")
          pam.config = "permit"
          root.pamFinished = false
          view.showKeyboard()
        } else if (step === 4) {
          if (!find(view, "lockKeyboardLoader").item || view.keyboardHeight <= 44) return
          typeText(root.dummy)
          typeText(null)
          check(root.submitted === 2, "retry reaches same private submit route")
        } else if (step === 5) {
          if (!pamFinished) return
          check(root.pamFailure === "", root.pamFailure)
          check(!service.currentlyLocked() && service.pendingPassword === "", "successful PAM retry clears private password and unlocks model")
          console.log("TRUSTED_LOCK_HOST_TEST_PASS")
          Qt.quit()
        }
        root.step++
      } catch (error) { console.error("TRUSTED_LOCK_HOST_TEST_FAIL: " + error); Qt.quit() }
    }
  }
}
