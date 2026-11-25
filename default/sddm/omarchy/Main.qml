import QtQuick

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#1a1b26"

  property string currentUser: userModel.lastUser
  property bool loginFailed: false
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loginFailed = true
      password.text = ""
      password.focus = true
    }
    function onLoginSucceeded() {
      root.loginFailed = false
      if (keyboard.visible)
        Qt.inputMethod.hide()
    }
  }

  Column {
    id: form
    anchors.centerIn: parent
    anchors.verticalCenterOffset: keyboard.visible ? -keyboard.height / 2 : 0
    spacing: keyboard.visible ? 16 : 40

    Image {
      id: logo
      source: "logo.png"
      width: Math.min(sourceSize.width, root.width * 0.8)
      readonly property real scaledHeight: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
      height: keyboard.visible
        ? Math.max(0, Math.min(scaledHeight, root.height - keyboard.height - entryRow.height - form.spacing))
        : scaledHeight
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

          onTextChanged: root.loginFailed = false

          onAccepted: sddm.login(root.currentUser, text, root.sessionIndex)

          TapHandler {
            acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Stylus
            enabled: !keyboard.unavailable
            onTapped: {
              password.forceActiveFocus()
              if (keyboard.item)
                Qt.inputMethod.show()
              else
                keyboard.requested = true
            }
          }
        }
      }
    }
  }

  // SDDM creates a window per screen. Only the active window owns the panel.
  Loader {
    id: keyboard
    objectName: "greeterKeyboard"
    property bool requested: false
    property bool unavailable: false

    active: requested && root.Window.active
    source: "Keyboard.qml"
    visible: item?.active ?? false
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    width: Math.min(root.width, root.height * 1.4, 1000)

    onLoaded: Qt.inputMethod.show()
    onStatusChanged: {
      if (status === Loader.Error)
        unavailable = true
    }
  }

  Window.onActiveChanged: {
    if (!Window.active)
      keyboard.requested = false
  }

  Component.onCompleted: password.forceActiveFocus()
}
