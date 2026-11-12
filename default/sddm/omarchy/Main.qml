import QtQuick
import QtQuick.Controls.Basic as Controls

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#1a1b26"
  readonly property color foreground: "#ffffff"
  readonly property color errorColor: "#f7768e"
  readonly property string fontFamily: "JetBrainsMono Nerd Font"

  // LoginForm imports the Omarchy virtual-keyboard style. That import fails
  // closed when qt6-virtualkeyboard or the style module is absent, and a
  // failed greeter import used to take the whole sign-in screen with it.
  // The fallback below is ordinary Qt Quick and still accepts a password.
  readonly property Item activeForm: styledLogin.item || fallbackLogin.item
  readonly property int sessionIndex: activeForm ? activeForm.sessionIndex : -1
  readonly property real keyboardHeight: activeForm ? activeForm.keyboardHeight : 0
  readonly property bool keyboardRequested: activeForm ? activeForm.keyboardRequested : false
  readonly property bool authenticating: activeForm ? activeForm.authenticating : false
  readonly property bool loginFailed: activeForm ? activeForm.loginFailed : false

  function showKeyboard(target) {
    if (activeForm) activeForm.showKeyboard(target)
  }

  function cancelEntry() {
    if (activeForm) activeForm.cancelEntry()
  }

  function submit() {
    if (activeForm) activeForm.submit()
  }

  function bindForm(item) {
    item.width = Qt.binding(function() { return root.width })
    item.height = Qt.binding(function() { return root.height })
    item.screenColor = Qt.binding(function() { return root.color })
    item.foreground = Qt.binding(function() { return root.foreground })
    item.fontFamily = Qt.binding(function() { return root.fontFamily })
    item.errorColor = root.errorColor
  }

  // "1" or "0" in handheld-variant beside this file forces the branch under
  // test. Otherwise the RC71L DMI name plus the handheld session desktop is
  // the variant. Laptops, including a laptop that only has the session
  // package, keep the form that does not import Qt Virtual Keyboard.
  function readText(url) {
    try {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", url, false)
      xhr.send()
      if (xhr.status === 200 || xhr.status === 0) return String(xhr.responseText || "")
    } catch (e) {}
    return ""
  }

  function detectHandheld() {
    var forced = readText(Qt.resolvedUrl("handheld-variant")).trim()
    if (forced === "1") return true
    if (forced === "0") return false
    var vendor = readText("file:///sys/class/dmi/id/sys_vendor").trim()
    var product = readText("file:///sys/class/dmi/id/product_name").trim()
    var board = readText("file:///sys/class/dmi/id/board_name").trim()
    var ally = vendor === "ASUSTeK COMPUTER INC." && (product.indexOf("ROG Ally RC71L") === 0 || board === "RC71L")
    if (!ally) return false
    var session = readText("file:///usr/share/wayland-sessions/omarchy-handheld.desktop")
    return session.indexOf("[Desktop Entry]") !== -1
  }

  Loader {
    id: styledLogin
    objectName: "loginStyledLoader"
    anchors.fill: parent
    active: false
    onLoaded: root.bindForm(item)
  }

  Loader {
    id: fallbackLogin
    objectName: "loginFallbackLoader"
    anchors.fill: parent
    active: false
    sourceComponent: fallbackForm
    onLoaded: root.bindForm(item)
  }

  Component.onCompleted: {
    // The handheld sign-in screen keeps Qt Virtual Keyboard. A missing
    // module must not swap in the laptop form, which has no touch keyboard.
    if (root.detectHandheld()) {
      // active stays false until set. Assigning source alone stores the
      // form and never loads it.
      styledLogin.source = "LoginForm.qml"
      styledLogin.active = true
    } else {
      fallbackLogin.active = true
    }
  }

  Component {
    id: fallbackForm
    Item {
      id: fallback
      property color screenColor: root.color
      property color foreground: root.foreground
      property color errorColor: root.errorColor
      property string fontFamily: root.fontFamily
      property bool loginFailed: false
      property bool authenticating: false
      property bool keyboardRequested: false
      readonly property int sessionIndex: sessionBox.currentIndex
      readonly property real keyboardHeight: 0
      readonly property string currentUser: userBox.editText.trim()

      function initialSessionIndex() {
        var count = sessionModel.rowCount()
        if (sessionModel.lastIndex >= 0 && sessionModel.lastIndex < count) return sessionModel.lastIndex
        for (var i = 0; i < count; i++) {
          var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
          if (name.indexOf("uwsm") !== -1) return i
        }
        return count > 0 ? 0 : -1
      }

      function showKeyboard(target) {
        var field = target || passwordBox
        field.forceActiveFocus()
      }

      function cancelEntry() {
        if (authenticating) return
        passwordBox.clear()
        loginFailed = false
        passwordBox.forceActiveFocus()
      }

      function submit() {
        if (authenticating || !currentUser || sessionIndex < 0) return
        authenticating = true
        sddm.login(currentUser, passwordBox.text, sessionIndex)
        passwordBox.clear()
      }

      Connections {
        target: sddm
        function onLoginFailed() {
          fallback.authenticating = false
          fallback.loginFailed = true
          passwordBox.clear()
          passwordBox.forceActiveFocus()
        }
        function onLoginSucceeded() {
          passwordBox.clear()
        }
      }

      Column {
        width: Math.min(440, parent.width - 40)
        anchors.centerIn: parent
        spacing: 16

        Controls.ComboBox {
          id: userBox
          objectName: "loginUser"
          width: parent.width
          model: userModel
          textRole: "name"
          currentIndex: userModel.lastIndex
          editable: true
          enabled: !fallback.authenticating
          Accessible.name: qsTr("User")
        }

        Controls.ComboBox {
          id: sessionBox
          objectName: "loginSession"
          width: parent.width
          model: sessionModel
          textRole: "name"
          currentIndex: fallback.initialSessionIndex()
          enabled: !fallback.authenticating
          Accessible.name: qsTr("Session")
        }

        Controls.TextField {
          id: passwordBox
          objectName: "loginPassword"
          width: parent.width
          height: 56
          Accessible.name: qsTr("Password")
          color: fallback.foreground
          font.family: fallback.fontFamily
          font.pixelSize: 20
          echoMode: TextInput.Password
          passwordCharacter: "\u25CF"
          inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
          enabled: !fallback.authenticating
          focus: true
          placeholderText: qsTr("Password")
          onTextEdited: fallback.loginFailed = false
          onAccepted: fallback.submit()
          Keys.onEscapePressed: fallback.cancelEntry()
        }

        Controls.Button {
          objectName: "loginSubmit"
          text: qsTr("Sign in")
          width: parent.width
          height: 48
          enabled: !fallback.authenticating && fallback.currentUser.length > 0 && fallback.sessionIndex >= 0
          onClicked: fallback.submit()
        }

        Text {
          objectName: "loginStatus"
          width: parent.width
          height: 20
          text: fallback.authenticating ? qsTr("Signing in…") : (fallback.loginFailed ? qsTr("Sign-in failed. Try again.") : "")
          color: fallback.loginFailed ? fallback.errorColor : fallback.foreground
          horizontalAlignment: Text.AlignHCenter
          font.family: fallback.fontFamily
          font.pixelSize: 14
        }
      }

      Component.onCompleted: passwordBox.forceActiveFocus()
    }
  }
}
