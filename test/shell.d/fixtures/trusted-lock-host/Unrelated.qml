import QtQuick
import QtQuick.VirtualKeyboard.Core as Core
Item {
  function focusedText() {
    var item = Core.InputContext.inputItem
    if (!item && Core.InputContext.priv) item = Core.InputContext.priv.inputItem
    return item && item.text !== undefined ? item.text : null
  }
  function contains(node, value) {
    if (!node) return false
    if (node.passwordText === value || node.pendingPassword === value || node.enteredPassword === value || node.text === value) return true
    var children = node.children || []
    for (var i = 0; i < children.length; i++) if (contains(children[i], value)) return true
    return false
  }
  function fromParents(value) {
    for (var node = this; node; node = node.parent) if (contains(node, value)) return true
    return false
  }
}
