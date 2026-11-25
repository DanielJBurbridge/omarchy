import QtQuick
import QtTest
import "theme" as Greeter

Greeter.Main {
  id: greeter

  QtObject {
    id: userModel
    readonly property string lastUser: "fixture"
  }

  QtObject {
    id: sessionModel
    readonly property int lastIndex: 0
    function rowCount() { return 0 }
  }

  QtObject {
    id: sddm
    property var attempts: []
    signal loginFailed()
    signal loginSucceeded()

    function login(user, password, session) {
      attempts = attempts.concat([[user, password, session]])
    }
  }

  TestCase {
    name: "SddmTouchKeyboard"
    when: windowShown

    function tap(item) {
      touchEvent(item).press(0, item).commit().release(0, item).commit()
    }

    function findKey(item, matches) {
      if (item.visible && matches(item))
        return item
      for (const child of item.children) {
        const match = findKey(child, matches)
        if (match)
          return match
      }
      return null
    }

    function tapKey(panel, matches) {
      const key = findKey(panel, matches)
      verify(key !== null, "native key is present")
      tap(key)
    }

    function test_withoutKeyboard() {
      const password = findChild(greeter, "greeterPassword")
      const panel = findChild(greeter, "greeterKeyboard")
      const position = password.mapToItem(greeter, 0, 0)
      compare(panel.status, Loader.Null)
      tap(password)
      tryCompare(panel, "status", Loader.Error)
      verify(!panel.visible)
      compare(password.mapToItem(greeter, 0, 0), position)
      keyClick("a")
      keyClick(Qt.Key_Return)
      compare(sddm.attempts, [["fixture", "a", 0]])
    }

    function test_withKeyboard() {
      const password = findChild(greeter, "greeterPassword")
      const panel = findChild(greeter, "greeterKeyboard")
      mouseClick(password)
      compare(panel.status, Loader.Null)
      keyClick("a")
      keyClick(Qt.Key_Enter)
      compare(sddm.attempts, [["fixture", "a", 0]])
      sddm.loginFailed()

      tap(password)
      tryCompare(panel, "visible", true)
      verify(password.mapToItem(greeter, 0, password.height).y <= panel.y)
      tapKey(panel.item, key => String(key).startsWith("HideKeyboardKey"))
      tryCompare(panel, "visible", false)
      tap(password)
      tryCompare(panel, "visible", true)
      tapKey(panel.item, key => key.key === Qt.Key_Shift)
      tapKey(panel.item, key => key.key === Qt.Key_A)
      tapKey(panel.item, key => key.key === Qt.Key_Context1)
      tapKey(panel.item, key => key.key === Qt.Key_1)
      tapKey(panel.item, key => key.key === Qt.Key_Backspace)
      tapKey(panel.item, key => key.key === Qt.Key_Exclam)
      tapKey(panel.item, key => key.key === Qt.Key_Return)
      compare(sddm.attempts, [["fixture", "a", 0], ["fixture", "A!", 0]])

      sddm.loginFailed()
      tap(password)
      tryCompare(panel, "visible", true)
      keyClick("z")
      keyClick(Qt.Key_Return)
      compare(sddm.attempts[2], ["fixture", "z", 0])
    }
  }
}
