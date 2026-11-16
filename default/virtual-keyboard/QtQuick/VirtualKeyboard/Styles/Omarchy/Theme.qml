pragma Singleton
import QtQuick

// Visual data only. Each authentication process supplies its own palette;
// this module has no authentication object, service or caller-selected source.
QtObject {
  property color background: "#1a1b26"
  property color foreground: "#ffffff"
  property color accent: foreground
  property string fontFamily: "monospace"
  property real fontSize: 18
  property real radius: 0
  property real keyboardWidth: 880
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
}
