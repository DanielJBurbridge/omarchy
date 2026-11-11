import QtQuick
import QtQuick.VirtualKeyboard.Core as KeyboardCore

// No reference to the lock service, view or host: this is the unrelated
// importer's public process-global route to the focused input QObject.
QtObject {
  function focusedText() {
    var item = KeyboardCore.InputContext.inputItem
    if (!item && KeyboardCore.InputContext.priv) item = KeyboardCore.InputContext.priv.inputItem
    return item && item.text !== undefined ? item.text : null
  }
}
