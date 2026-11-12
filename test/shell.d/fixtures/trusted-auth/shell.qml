import QtQuick
import QtTest
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

  TestCase { id: touch; name: "trusted-auth"; when: false }

  Window { id: host; width: 960; height: 540; visible: true }

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
    view = component.createObject(host.contentItem, {width: Qt.binding(function() { return host.width }), height: Qt.binding(function() { return host.height })})
    check(view !== null, component.errorString())
  }
  function typeText(text) {
    VirtualKeyboard.InputContext.inputEngine.virtualKeyClick(Qt.Key_unknown, text, Qt.NoModifier)
  }
  function key(code) {
    VirtualKeyboard.InputContext.inputEngine.virtualKeyClick(code, "", Qt.NoModifier)
  }

  function geometry(prefix) {
    var loader = find(view, prefix + "KeyboardLoader")
    var panel = loader.item
    var field = find(view, prefix + "Password")
    check(panel !== null && view.keyboardHeight > 0, "embedded keyboard remains visible")
    var keyboardTop = loader.mapToItem(view, 0, 0).y
    for (var name of [prefix + "Password", prefix + "Keyboard", prefix + "Cancel", prefix + "Submit"]) {
      var item = find(view, name)
      var point = item.mapToItem(view, 0, 0)
      check(point.x >= 0 && point.y >= 0 && point.x + item.width <= view.width + 1, name + " stays on screen")
      check(point.y + item.height <= keyboardTop, name + " is above keyboard")
      check(item.height >= 44, name + " retains a touch target")
    }
    check(loader.y + loader.height <= view.height, "keyboard stays on screen")
    check(field.activeFocus, "layout and resize preserve password focus")
  }
  function findKey(item, code) {
    if (item.key === code && typeof item.clicked === "function") return item
    for (var child of (item.children || [])) { var found = findKey(child, code); if (found) return found }
    return null
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
          geometry("login")
          check(view.sessionIndex === 1, "remembered gaming session honoured")
          find(view, "loginSession").currentIndex = 0
          var field = find(view, "loginPassword")
          check(field.activeFocus, "greeter keyboard keeps password focus")
          touch.keyClick(Qt.Key_Tab)
          check(find(view, "loginKeyboard").activeFocus, "physical Tab can reach greeter actions")
          var userField = find(view, "loginUser").contentItem
          view.showKeyboard(userField)
          for (var hop = 0; hop < 8 && !field.activeFocus; hop++) touch.keyClick(Qt.Key_Tab)
          check(field.activeFocus, "physical navigation reaches password after editing user")
          var mixedChooser = find(find(view, "loginKeyboardLoader").item, "trustedKeyboardLayout")
          touch.mouseClick(mixedChooser, mixedChooser.width - 12, mixedChooser.height / 2)
          touch.wait(50)
          touch.mouseClick(mixedChooser.popup.contentItem.currentItem)
          touch.wait(50)
          check(!mixedChooser.popup.visible, "touch selection closes the layout chooser")
          check(field.activeFocus, "touch layout selection restores the physically selected password field")
          root.typeText("focus-probe")
          check(field.text === "focus-probe" && find(view, "loginUser").editText === "fixture-user", "mixed input stays in the masked field")
          field.clear()
          root.typeText("é@Z9!x")
          root.key(Qt.Key_Backspace)
          check(field.text === "é@Z9!", "greeter receives non-US input")
          touch.mouseClick(find(view, "loginSubmit"))
          check(root.submitted.length === 1 && root.submitted[0][0] === "fixture-user" && root.submitted[0][1] === "é@Z9!" && root.submitted[0][2] === 0, "touch sign-in passes exact user/password/session to SDDM")
          check(field.text === "" && view.authenticating, "credential cleared while checking")
          view.submit()
          check(root.submitted.length === 1, "no duplicate SDDM login")
          sddm.loginFailed()
          check(!view.authenticating && view.loginFailed && field.text === "", "failure restores empty field")
          check(view.sessionIndex === 0, "failed sign-in preserves chosen session")
          var chooser = find(find(view, "loginKeyboardLoader").item, "trustedKeyboardLayout")
          touch.mouseClick(chooser, chooser.width - 12, chooser.height / 2)
          check(chooser.popup.visible, "touch layout chooser opens")
        } else if (root.step === 2) {
          var chooser = find(find(view, "loginKeyboardLoader").item, "trustedKeyboardLayout")
          check(chooser.popup.contentItem.currentItem.contentItem.text.length > 0, "layout popup renders actual locale labels")
          chooser.popup.close()
          root.typeText("retry")
          touch.keyClick(Qt.Key_Return)
          check(root.submitted.length === 2 && root.submitted[1][1] === "retry", "greeter physical Return submits")
          sddm.loginFailed()
          root.typeText("clear")
          find(view, "loginCancel").clicked()
          check(find(view, "loginPassword").text === "" && !view.keyboardRequested, "greeter cancel clears without authenticating")
          check(root.submitted.length === 2, "greeter cancel never logs in")
          host.width = 540; host.height = 960
          view.showKeyboard()
        } else if (root.step === 3) {
          geometry("login")
          view.cancelEntry()
          view.destroy()
          root.load("/shell/plugins/lock/LockView.qml")
          view.loadBackground = false
          view.keyboardAvailable = true
          view.passwordTextEdited.connect(function(text) { root.view.passwordText = text })
          view.showKeyboard()
        } else if (root.step === 4) {
          geometry("lock")
          var keyboard = find(view, "lockKeyboardLoader").item
          var shift = findKey(keyboard, Qt.Key_Shift)
          var q = findKey(keyboard, Qt.Key_Q)
          check(shift !== null && q !== null, "packaged layout supplies real keys")
          touch.mouseClick(shift)
          check(q.uppercased, "Shift changes the native key label")
          touch.mouseClick(q)
          check(view.passwordText === "Q", "shifted key reaches masked entry")
          key(Qt.Key_Backspace)
          check(view.passwordText === "", "Backspace edits real entry")
          // Styling may not disconnect the Qt symbol-mode key or alternatives.
          var symbol = findKey(keyboard, Qt.Key_Context1)
          check(symbol !== null, "packaged symbol-mode key remains present")
          touch.mouseClick(symbol)
          host.width = 960; host.height = 540
        } else if (root.step === 5) {
          geometry("lock")
          check(findKey(find(view, "lockKeyboardLoader").item, Qt.Key_At) !== null, "symbol mode loads actual symbol keys")
          typeText("@é!")
          check(find(view, "lockPassword").displayText.indexOf("é") === -1, "native entry masks immediately")
          touch.mouseClick(findKey(find(view, "lockKeyboardLoader").item, Qt.Key_Context1))
          VirtualKeyboardSettings.locale = "en_GB"
        } else if (root.step === 6) {
          var keyboard = find(view, "lockKeyboardLoader").item
          var popup = find(keyboard, "alternativeKeys")
          check(popup.open(findKey(keyboard, Qt.Key_A), 120, 40), "native alternative keys open")
        } else if (root.step === 7) {
          var popup = find(find(view, "lockKeyboardLoader").item, "alternativeKeys")
          check(popup.listView.currentItem.width >= 44 && popup.listView.currentItem.height >= 44, "alternative characters have separate readable touch targets")
          popup.close()
          view.cancelEntry()
          check(view.passwordText === "" && !view.keyboardRequested, "lock cancel clears and hides")
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
