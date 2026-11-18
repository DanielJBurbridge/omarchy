import QtQuick
import QtCore
import QtQuick.Controls.Basic as Controls

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#1a1b26"

  property string currentUser: userModel.lastUser
  property bool loginFailed: false
  property bool authenticating: false
  property bool keyboardRequested: false
  property bool keyboardUnavailable: false
  readonly property bool handheldPanel: /^eDP-[0-9]+$/.test(root.Screen.name)
    && StandardPaths.locate(StandardPaths.RuntimeLocation, "omarchy-greeter-rc71l").toString() !== ""
  readonly property bool showTouchActions: handheldPanel || config.boolValue("ShowKeyboard")
  readonly property color foreground: "#ffffff"
  property int sessionIndex: {
    // SDDM exposes the desktop filename through FileRole, not DisplayRole.
    const fileRole = Qt.UserRole + 2
    let desktopIndex = -1
    for (let i = 0; i < sessionModel.rowCount(); i++) {
      const file = sessionModel.data(sessionModel.index(i, 0), fileRole) || ""
      const session = file.split("/").pop()
      if (session === "omarchy-managed-desktop.desktop")
        return i
      if (session === "omarchy.desktop" && desktopIndex < 0)
        desktopIndex = i
    }
    return desktopIndex >= 0 ? desktopIndex : sessionModel.lastIndex
  }

  function showKeyboard() {
    if (authenticating || keyboardUnavailable) return
    keyboardRequested = true
    password.forceActiveFocus()
    Qt.inputMethod.show()
  }

  function hideKeyboard() {
    keyboardRequested = false
    Qt.inputMethod.hide()
  }

  function submit() {
    if (authenticating || !currentUser || sessionIndex < 0) return
    Qt.inputMethod.commit()
    const secret = password.text
    authenticating = true
    password.clear()
    Qt.inputMethod.hide()
    sddm.login(currentUser, secret, sessionIndex)
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.authenticating = false
      root.loginFailed = true
      password.forceActiveFocus()
      if (root.keyboardRequested) root.showKeyboard()
    }
    function onLoginSucceeded() {
      root.hideKeyboard()
    }
  }

  Column {
    id: form
    readonly property real availableHeight: root.height - (keyboard.visible ? keyboard.height : 0)
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.max(0, (availableHeight - height) / 2)
    spacing: keyboard.visible ? 12 : actions.visible ? 24 : 40

    Image {
      id: logo
      source: "logo.png"
      width: Math.min(sourceSize.width, root.width * 0.8)
      readonly property real scaledHeight: sourceSize.width > 0 ? width * sourceSize.height / sourceSize.width : 0
      height: actions.visible
        ? Math.max(0, Math.min(scaledHeight, form.availableHeight - entryRow.height - actions.height - 2 * form.spacing - 16))
        : Math.round(scaledHeight)
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Row {
      id: entryRow
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15

      Image {
        source: root.loginFailed ? "lock-failed.png" : "lock.png"
        width: 34
        height: 38
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        width: entry.width
        height: entry.height

        Image {
          id: entry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5

          Repeater {
            model: Math.min(password.text.length, 21)

            Image {
              source: "bullet.png"
              width: 7
              height: 7
            }
          }
        }

        TextInput {
          id: password
          objectName: "greeterPassword"
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          verticalAlignment: TextInput.AlignVCenter
          echoMode: TextInput.Password
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 24
          font.letterSpacing: 5
          passwordCharacter: "\u2022"
          color: "transparent"
          selectionColor: "transparent"
          selectedTextColor: "transparent"
          cursorDelegate: Item {}
          focus: true
          enabled: !root.authenticating
          Accessible.name: qsTr("Password")
          passwordMaskDelay: 0
          inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase

          onTextEdited: root.loginFailed = false
          onAccepted: root.submit()
          Keys.onEscapePressed: root.hideKeyboard()
          TapHandler {
            acceptedDevices: root.showTouchActions ? PointerDevice.AllDevices : PointerDevice.TouchScreen | PointerDevice.Stylus
            onTapped: root.showKeyboard()
          }
        }
      }
    }

    Row {
      id: actions
      visible: root.showTouchActions || keyboard.visible
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 12

      GreeterButton {
        objectName: "greeterKeyboardToggle"
        text: qsTr("Keyboard")
        visible: !root.keyboardUnavailable
        enabled: !root.authenticating
        onClicked: {
          if (keyboard.visible) root.hideKeyboard()
          else root.showKeyboard()
        }
      }

      GreeterButton {
        objectName: "greeterSubmit"
        text: qsTr("Sign in")
        enabled: !root.authenticating && root.currentUser.length > 0 && root.sessionIndex >= 0
        onClicked: root.submit()
      }
    }
  }

  // Only the active SDDM window can own Qt's process-wide input panel. Load
  // its optional import separately so physical input still works without it.
  Loader {
    id: keyboard
    objectName: "greeterKeyboard"
    active: root.keyboardRequested && !root.keyboardUnavailable && root.Window.active
    visible: !!item && item.active
    source: "Keyboard.qml"
    width: Math.min(root.width - 16, root.height * 1.4, 1000)
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    onLoaded: root.showKeyboard()
    onStatusChanged: {
      if (status === Loader.Error) {
        Qt.callLater(function() {
          root.keyboardUnavailable = true
          root.hideKeyboard()
        })
      }
    }
  }

  component GreeterButton: Controls.Button {
    height: 44
    width: Math.max(104, implicitWidth)
    focusPolicy: Qt.NoFocus
    palette.buttonText: root.foreground
    palette.highlightedText: root.foreground
    background: Rectangle {
      color: parent.down ? Qt.alpha(root.foreground, 0.2) : root.color
      border.color: root.foreground
      opacity: parent.enabled ? 1 : 0.5
    }
  }

  Component.onCompleted: password.forceActiveFocus()
}
