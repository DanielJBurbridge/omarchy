import QtQuick
import QtQuick.VirtualKeyboard as VirtualKeyboard
import QtQuick.VirtualKeyboard.Settings
import Quickshell

// Real Qt input context, real LockView and greeter; no PAM or compositor lock.
ShellRoot {
  id: root
  property var view: null
  property int step: 0
  property var submitted: []
  readonly property string sourceRoot: Quickshell.env("OMARCHY_PATH")

  ListModel {
    id: userModel
    property int lastIndex: 0
    ListElement { name: "fixture-user" }
  }
  ListModel {
    id: sessionModel
    property int lastIndex: 1
    function rowCount() { return count }
    ListElement { name: "Hyprland (uwsm)" }
    ListElement { name: "Omarchy Gaming" }
  }
  QtObject {
    id: sddm
    signal loginFailed()
    signal loginSucceeded()
    function login(user, password, session) { root.submitted.push([user, password, session]) }
  }

  Window { id: host; width: 1280; height: 720; visible: true }

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }
  function find(item, name) {
    if (item.objectName === name) return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) {
      var found = find(children[i], name)
      if (found) return found
    }
    return null
  }
  function load(path) {
    var component = Qt.createComponent("file://" + sourceRoot + path, Component.PreferSynchronous)
    check(component.status === Component.Ready, component.errorString())
    view = component.createObject(host.contentItem, {width: host.width, height: host.height})
    check(view !== null, component.errorString())
  }
  function typeText(text) {
    VirtualKeyboard.InputContext.inputEngine.virtualKeyClick(Qt.Key_unknown, text, Qt.NoModifier)
  }
  function key(code) {
    VirtualKeyboard.InputContext.inputEngine.virtualKeyClick(code, "", Qt.NoModifier)
  }

  Timer {
    interval: 500
    running: true
    repeat: true
    onTriggered: {
      try {
        if (root.step === 0) {
          root.load("/default/sddm/omarchy/Main.qml")
          view.showKeyboard()
        } else if (root.step === 1) {
          check(find(view, "loginKeyboardLoader").item !== null, "greeter keyboard loads inside window")
          if (!VirtualKeyboard.InputContext.inputEngine.inputMethod || view.keyboardHeight <= 0) return
          if (VirtualKeyboardSettings.locale !== "de_DE") {
            VirtualKeyboardSettings.locale = "de_DE"
            return
          }
          check(view.sessionIndex === 1, "remembered gaming session honoured")
          find(view, "loginSession").currentIndex = 0
          var field = find(view, "loginPassword")
          check(field.activeFocus, "greeter keyboard keeps password focus")
          root.typeText("é@Z9!x")
          root.key(Qt.Key_Backspace)
          check(field.text === "é@Z9!", "greeter receives non-US input")
          find(view, "loginSubmit").clicked()
          check(root.submitted.length === 1 && root.submitted[0][0] === "fixture-user" && root.submitted[0][1] === "é@Z9!" && root.submitted[0][2] === 0, "touch sign-in passes exact user/password/session to SDDM")
          check(field.text === "" && view.authenticating, "credential cleared while checking")
          view.submit()
          check(root.submitted.length === 1, "no duplicate SDDM login")
          sddm.loginFailed()
          check(!view.authenticating && view.loginFailed && field.text === "", "failure restores empty field")
          check(view.sessionIndex === 0, "failed sign-in preserves chosen session")
        } else if (root.step === 2) {
          root.typeText("retry")
          root.key(Qt.Key_Return)
          check(root.submitted.length === 2 && root.submitted[1][1] === "retry", "greeter virtual Return submits")
          sddm.loginFailed()
          root.typeText("clear")
          find(view, "loginCancel").clicked()
          check(find(view, "loginPassword").text === "" && !view.keyboardRequested, "greeter cancel clears without authenticating")
          check(root.submitted.length === 2, "greeter cancel never logs in")
          console.log("TRUSTED_AUTH_TEST_PASS")
          Qt.quit()
        }
        root.step++
      } catch (error) {
        console.error("TRUSTED_AUTH_TEST_FAIL step " + root.step + ": " + error)
        Qt.quit()
      }
    }
  }
}
