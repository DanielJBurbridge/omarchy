import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.VirtualKeyboard.Styles.Omarchy as Auth

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#1a1b26"
  readonly property color foreground: "#ffffff"
  readonly property color errorColor: "#f7768e"
  readonly property string fontFamily: "JetBrainsMono Nerd Font"

  Binding { target: Auth.Theme; property: "background"; value: root.color }
  Binding { target: Auth.Theme; property: "foreground"; value: root.foreground }
  Binding { target: Auth.Theme; property: "fontFamily"; value: root.fontFamily }

  readonly property string currentUser: userName.editText.trim()
  property bool loginFailed: false
  property bool authenticating: false
  property bool keyboardRequested: false
  property var keyboardFocusTarget: password
  Window.onActiveFocusItemChanged: {
    var field = root.Window.activeFocusItem
    if (field === password || field === userName.contentItem) root.keyboardFocusTarget = field
  }
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

  function showKeyboard(target) {
    if (authenticating) return
    keyboardRequested = true
    keyboardFocusTarget = target || password
    keyboardFocusTarget.forceActiveFocus()
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
      objectName: "loginForm"
      width: Math.min(440, parent.width - 40)
      anchors.centerIn: parent
      spacing: root.keyboardHeight > 0 ? 6 : 16

      Image {
        source: "logo.png"
        width: Math.min(sourceSize.width, form.width * 0.8)
        height: root.keyboardHeight > 0 ? 30 : Math.min(100, width * sourceSize.height / Math.max(1, sourceSize.width))
        fillMode: Image.PreserveAspectFit
        anchors.horizontalCenter: parent.horizontalCenter
      }

      Row {
        width: parent.width
        spacing: 8
        Auth.AuthChoice {
          id: userName
          objectName: "loginUser"
          width: (parent.width - 8) * 0.4
          model: userModel
          textRole: "name"
          currentIndex: userModel.lastIndex
          editable: true
          enabled: !root.authenticating
          Accessible.name: qsTr("User")
          onEditTextChanged: { password.clear(); root.loginFailed = false }
          onActivated: password.forceActiveFocus()
          onInputRequested: root.showKeyboard(contentItem)
        }
        Auth.AuthChoice {
          id: session
          objectName: "loginSession"
          width: (parent.width - 8) * 0.6
          model: sessionModel
          textRole: "name"
          currentIndex: root.initialSessionIndex()
          enabled: !root.authenticating
          Accessible.name: qsTr("Session")
          onActivated: password.forceActiveFocus()
        }
      }

      Row {
        width: parent.width
        spacing: 14
        Image {
          source: root.loginFailed ? "lock-failed.png" : "lock.png"
          width: 30
          height: 34
          fillMode: Image.PreserveAspectFit
          anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
          width: parent.width - 44
          height: 56
          color: root.color
          border.width: 3
          border.color: root.loginFailed ? root.errorColor : root.foreground
          Controls.TextField {
            id: password
            objectName: "loginPassword"
            anchors.fill: parent
            anchors.margins: 3
            leftPadding: 16
            rightPadding: 16
            background: Item {}
            Accessible.name: qsTr("Password")
            cursorVisible: activeFocus && text.length > 0
            color: root.foreground
            selectionColor: Auth.Theme.alpha(root.foreground, 0.35)
            selectedTextColor: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 20
            font.letterSpacing: text.length > 0 ? 4 : 0
            horizontalAlignment: TextInput.AlignHCenter
            echoMode: TextInput.Password
            passwordCharacter: "\u25CF"
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
          Text {
            anchors.fill: password
            visible: password.text.length === 0 && !root.authenticating
            text: qsTr("Password")
            textFormat: Text.PlainText
            color: Auth.Theme.alpha(root.foreground, 0.66)
            font.family: root.fontFamily
            font.pixelSize: 20
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
        }
      }

      Row {
        spacing: 8
        Auth.AuthButton {
          objectName: "loginKeyboard"
          text: qsTr("Keyboard")
          selected: root.keyboardHeight > 0
          width: (form.width - 16) / 3
          height: 48
          enabled: !root.authenticating
          onClicked: {
            if (root.keyboardHeight > 0) {
              root.keyboardRequested = false
              Qt.inputMethod.hide()
            } else root.showKeyboard()
          }
        }
        Auth.AuthButton {
          objectName: "loginCancel"
          text: qsTr("Cancel")
          width: (form.width - 16) / 3
          height: 48
          enabled: !root.authenticating
          onClicked: root.cancelEntry()
        }
        Auth.AuthButton {
          objectName: "loginSubmit"
          text: qsTr("Sign in")
          width: (form.width - 16) / 3
          height: 48
          enabled: !root.authenticating && root.currentUser.length > 0 && root.sessionIndex >= 0
          onClicked: root.submit()
        }
      }

      Text {
        objectName: "loginStatus"
        width: parent.width
        height: 20
        text: root.authenticating ? qsTr("Signing in…") : (root.loginFailed ? qsTr("Sign-in failed. Try again.") : "")
        textFormat: Text.PlainText
        color: root.loginFailed ? root.errorColor : root.foreground
        horizontalAlignment: Text.AlignHCenter
        font.family: root.fontFamily
        font.pixelSize: 14
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
    width: Math.min(root.width - 32, root.height * 1.65, 880)
    height: root.keyboardHeight
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: root.keyboardHeight > 0 ? 8 : 0
    sourceComponent: Auth.Keyboard {
      width: keyboardLoader.width
      backgroundColor: root.color
      foregroundColor: root.foreground
      fontFamily: root.fontFamily
      layoutText: qsTr("Layout: %1")
      onFocusRequested: root.keyboardFocusTarget.forceActiveFocus()
    }
    onLoaded: { root.keyboardFocusTarget.forceActiveFocus(); Qt.inputMethod.show() }
  }

  Component.onCompleted: password.forceActiveFocus()
}
