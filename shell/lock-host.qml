// SECURITY BOUNDARY: no desktop plugin imports, registry or user QML loader.
import QtQuick
import Quickshell
import Quickshell.Wayland
import "plugins/lock" as TrustedLock

ShellRoot {
  TrustedLock.Service {
    trustedHost: true
    omarchyPath: Quickshell.env("OMARCHY_PATH")
  }
}
