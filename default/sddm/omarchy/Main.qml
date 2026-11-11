import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.VirtualKeyboard

Controls.Pane {
  id: root
  width: 640
  height: 480
  padding: 0
  palette.window: "#1a1b26"
  palette.base: "#1a1b26"
  palette.button: "#1a1b26"
  palette.text: "#ffffff"
  palette.placeholderText: "#b8b8b8"
  font.family: "JetBrainsMono Nerd Font"
  font.pixelSize: 18
  palette.buttonText: "#ffffff"
  palette.highlight: "#ffffff"
  palette.highlightedText: "#1a1b26"
  background: Rectangle { color: "#1a1b26" }

  readonly property string currentUser: userName.editText.trim()
  property bool loginFailed: false
  property bool authenticating: false
  property bool keyboardRequested: false
  readonly property int sessionIndex: session.currentIndex
  readonly property real keyboardHeight: keyboardLoader.item && Qt.inputMethod.visible ? keyboardLoader.item.implicitHeight : 0

  function initialSessionIndex() {
    var count = sessionModel.rowCount()
    if (sessionModel.lastIndex >= 0 && sessionModel.lastIndex < count) return sessionModel.lastIndex
    for (var i = 0; i < count; i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1) return i
    }
    return count > 0 ? 0 : -1
  }

  function showKeyboard() {
    if (authenticating) return
    keyboardRequested = true
    password.forceActiveFocus()
    Qt.inputMethod.show()
  }

  function cancelEntry() {
    if (authenticating) return
    Qt.inputMethod.reset()
    password.clear()
    loginFailed = false
    keyboardRequested = false
    Qt.inputMethod.hide()
    password.forceActiveFocus()
  }

  function submit() {
    if (authenticating || !currentUser || sessionIndex < 0) return
    // Commit any composed character before copying the masked field to SDDM.
    Qt.inputMethod.commit()
    authenticating = true
    sddm.login(currentUser, password.text, sessionIndex)
    password.clear()
    Qt.inputMethod.hide()
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.authenticating = false
      root.loginFailed = true
      password.clear()
      password.forceActiveFocus()
      if (root.keyboardRequested) Qt.inputMethod.show()
    }
    function onLoginSucceeded() {
      password.clear()
      root.keyboardRequested = false
      Qt.inputMethod.hide()
    }
  }

  Item {
    anchors { top: parent.top; left: parent.left; right: parent.right; bottom: keyboardLoader.top }

    Column {
      id: form
      width: Math.min(580, parent.width - 32)
      anchors.centerIn: parent
      spacing: 12

      Image {
        source: "logo.png"
        width: Math.min(sourceSize.width, form.width * 0.8)
        height: visible ? Math.min(90, width * sourceSize.height / Math.max(1, sourceSize.width)) : 0
        visible: root.keyboardHeight === 0
        fillMode: Image.PreserveAspectFit
        anchors.horizontalCenter: parent.horizontalCenter
      }

      Controls.ComboBox {
        id: userName
        objectName: "loginUser"
        width: parent.width
        height: 44
        model: userModel
        textRole: "name"
        currentIndex: userModel.lastIndex
        editable: true
        enabled: !root.authenticating
        Accessible.name: qsTr("User")
        onEditTextChanged: { password.clear(); root.loginFailed = false }
        onActivated: password.forceActiveFocus()
      }

      Controls.ComboBox {
        id: session
        objectName: "loginSession"
        width: parent.width
        height: 44
        model: sessionModel
        textRole: "name"
        currentIndex: root.initialSessionIndex()
        enabled: !root.authenticating
        Accessible.name: qsTr("Session")
        onActivated: password.forceActiveFocus()
      }

      Controls.TextField {
        id: password
        objectName: "loginPassword"
        width: parent.width
        height: 52
        placeholderText: qsTr("Password")
        echoMode: TextInput.Password
        passwordMaskDelay: 0
        inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
        enabled: !root.authenticating
        selectByMouse: false
        focus: true
        onTextEdited: root.loginFailed = false
        onAccepted: root.submit()
        Keys.onEscapePressed: root.cancelEntry()
        TapHandler { onTapped: root.showKeyboard() }
      }

      Row {
        spacing: 12
        Controls.Button {
          objectName: "loginKeyboard"
          text: qsTr("Keyboard")
          width: (form.width - 24) / 3
          height: 48
          focusPolicy: Qt.NoFocus
          enabled: !root.authenticating
          onClicked: {
            if (root.keyboardHeight > 0) {
              root.keyboardRequested = false
              Qt.inputMethod.hide()
            } else root.showKeyboard()
          }
        }
        Controls.Button {
          objectName: "loginCancel"
          text: qsTr("Cancel")
          width: (form.width - 24) / 3
          height: 48
          focusPolicy: Qt.NoFocus
          enabled: !root.authenticating
          onClicked: root.cancelEntry()
        }
        Controls.Button {
          objectName: "loginSubmit"
          text: qsTr("Sign in")
          width: (form.width - 24) / 3
          height: 48
          enabled: !root.authenticating && root.currentUser.length > 0 && root.sessionIndex >= 0
          onClicked: root.submit()
        }
      }

      Text {
        objectName: "loginStatus"
        width: parent.width
        height: 24
        text: root.authenticating ? qsTr("Signing in…") : (root.loginFailed ? qsTr("Sign-in failed. Try again.") : "")
        textFormat: Text.PlainText
        color: root.loginFailed ? "#f7768e" : "#ffffff"
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: 16
        elide: Text.ElideRight
      }
    }
  }

  // Only the active screen creates a panel: Qt supports one InputPanel per
  // process. It lives inside the greeter window, never in a desktop OSK window.
  Loader {
    id: keyboardLoader
    objectName: "loginKeyboardLoader"
    active: root.keyboardRequested && root.Window.active
    width: Math.min(root.width - 16, root.height * 1.3, 1000)
    height: root.keyboardHeight
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    sourceComponent: InputPanel {
      width: keyboardLoader.width
      visible: Qt.inputMethod.visible
    }
    onLoaded: { password.forceActiveFocus(); Qt.inputMethod.show() }
  }

  Component.onCompleted: password.forceActiveFocus()
}
