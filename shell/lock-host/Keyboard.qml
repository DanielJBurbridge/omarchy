import QtQuick
import QtQuick.VirtualKeyboard.Styles.Omarchy as Auth
import qs.Commons as Commons

Auth.Keyboard {
  backgroundColor: Commons.Color.background
  foregroundColor: Commons.Color.lock.text
  accentColor: Commons.Color.accent
  fontFamily: Commons.Style.font.family
  fontSize: Math.max(16, Commons.Style.font.heading)
  cornerRadius: Commons.Style.cornerRadius
  layoutText: Commons.I18n.t("lock.keyboardLayout")
}
