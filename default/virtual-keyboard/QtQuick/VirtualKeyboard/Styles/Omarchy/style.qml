import QtQuick
import QtQuick.VirtualKeyboard
import QtQuick.VirtualKeyboard.Styles
import QtQuick.VirtualKeyboard.Styles.Omarchy

// Only presentation is supplied here. Qt's packaged layouts, modifiers,
// alternatives and input engine remain responsible for all key behaviour.
KeyboardStyle {
  id: keyboardStyle
  keyboardDesignWidth: 960
  keyboardDesignHeight: 960 * Math.max(0.27, 224 / Math.max(1, Theme.keyboardWidth))
  keyboardRelativeLeftMargin: 0
  keyboardRelativeRightMargin: 0
  keyboardRelativeTopMargin: 0
  keyboardRelativeBottomMargin: 0
  keyboardBackground: Rectangle { color: Theme.background }
  keyPanel: AuthKey {}
  backspaceKeyPanel: AuthKey { label: "⌫" }
  shiftKeyPanel: AuthKey { label: InputContext.capsLockActive ? "⇪" : "⇧"; selected: InputContext.shiftActive || InputContext.capsLockActive }
  enterKeyPanel: AuthKey { label: "↵"; selected: true }
  spaceKeyPanel: AuthKey { label: "␣" }
  symbolKeyPanel: AuthKey { label: control.displayText }
  languageKeyPanel: AuthKey { label: "◎" }
  hideKeyPanel: AuthKey { label: "⌄" }
  modeKeyPanel: AuthKey { selected: control.mode }
  handwritingKeyPanel: AuthKey { label: "✎" }
  navigationHighlight: Rectangle { color: "transparent"; border.color: Theme.accent; border.width: 2 }
  alternateKeysListItemWidth: 48
  alternateKeysListItemHeight: 56
  alternateKeysListDelegate: Text {
    width: keyboardStyle.alternateKeysListItemWidth
    height: keyboardStyle.alternateKeysListItemHeight
    text: model.text
    textFormat: Text.PlainText
    color: Theme.foreground
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }
  alternateKeysListHighlight: Rectangle { color: Theme.alpha(Theme.foreground, 0.18) }
  alternateKeysListBackground: Rectangle { color: Theme.background; border.color: Theme.accent }
  selectionListHeight: 44
  selectionListDelegate: SelectionListItem {
    width: candidate.implicitWidth + 24
    Text { id: candidate; anchors.centerIn: parent; text: display; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
  }
  selectionListBackground: Rectangle { color: Theme.background }
  selectionListHighlight: Rectangle { color: Theme.alpha(Theme.foreground, 0.18) }
}
