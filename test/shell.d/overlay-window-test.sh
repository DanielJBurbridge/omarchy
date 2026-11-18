#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8')
const overlay = read('shell/Ui/OverlayWindow.qml')

const readyExpression = /readonly property bool contentReady: ([^\n]*(?:\n    &&[^\n]*)*)/.exec(overlay)[1]
const ready = new Function('shown', 'backingWindowVisible', 'width', 'height', 'targetScreen', 'targetMonitor', 'devicePixelRatio', `return ${readyExpression}`)
const screen = { name: 'eDP-1', width: 1200, height: 750 }
const monitor = { name: 'eDP-1', scale: 1.6 }
for (const scale of [2, 1, 1.6]) {
  assertEqual(ready(true, true, 1200, 750, screen, monitor, scale), scale === 1.6,
    `opening frames at ${scale}x wait for the monitor's 1.6x scale`)
}
for (const scale of [1, 1.25, 1.5, 2]) {
  assert(ready(true, true, 1200, 750, screen, { scale }, scale),
    `overlay reveals at the correct ${scale}x scale`)
}
assert(ready(true, true, 1200, 750, screen, { scale: 1.333333 }, 160 / 120),
  'scale comparison tolerates compositor floating point rounding')
assert(!ready(true, true, 500, 500, screen, monitor, 1.6),
  'initial window geometry never stretches content across the screen')
assert(!ready(true, false, 1200, 750, screen, monitor, 1.6),
  'content waits for a mapped backing window')
assert(!ready(false, true, 1200, 750, screen, monitor, 1.6),
  'closed content stays transparent even at the correct scale')
assert(!ready(true, true, 1200, 750, null, monitor, 1.6) &&
  !ready(true, true, 1200, 750, screen, null, 1.6),
  'content waits for a connected screen and its monitor information')

const revealBody = /onContentReadyChanged: \{([\s\S]*?)\n  \}/.exec(overlay)[1]
const reveal = new Function('window', 'Qt', `with (window) { ${revealBody} }`)
const reveals = []
const revealQt = { callLater(callback) { reveals.push(callback) } }
const content = { contentReady: true, contentRevealed: false }
reveal(content, revealQt)
assert(!content.contentRevealed, 'scale and resize notifications finish before content reveals')
reveals.shift()()
assert(content.contentRevealed, 'settled content reveals on the next event-loop turn')
content.contentReady = false
reveal(content, revealQt)
assert(!content.contentRevealed, 'losing readiness immediately hides content')
content.contentReady = true
reveal(content, revealQt)
content.contentReady = false
reveal(content, revealQt)
reveals.shift()()
assert(!content.contentRevealed, 'a close or screen loss cancels a pending reveal')

const shownHandler = /onShownChanged: \{([\s\S]*?)\n  \}/.exec(overlay)[1]
let refreshed = 0
const Hyprland = { refreshMonitors() { refreshed++ } }
const changeShown = new Function('window', 'Hyprland', `with (window) { ${shownHandler} }`)
const window = { shown: false, resourcesAvailable: true, remapping: false }
changeShown(window, Hyprland)
assertEqual(refreshed, 0, 'closing does not refresh monitor data')
window.shown = true
changeShown(window, Hyprland)
assertEqual(refreshed, 1, 'opening refreshes monitor scales after a live change while closed')
const scaleHandler = /onDevicePixelRatioChanged: ([^\n]+)/.exec(overlay)[1]
const changeScale = new Function('shown', 'Hyprland', scaleHandler)
changeScale(false, Hyprland)
assertEqual(refreshed, 1, 'scale changes on hidden windows do not refresh monitor data')
const changedScreen = { name: 'eDP-1', width: 960, height: 600 }
assert(!ready(true, true, 960, 600, changedScreen, monitor, 2),
  'a stale monitor scale keeps content transparent after a live scale change')
Hyprland.refreshMonitors = () => { refreshed++; monitor.scale = 2 }
changeScale(true, Hyprland)
assertEqual(refreshed, 2, 'a showing window refreshes monitor scales when Qt receives a live change')
assert(ready(true, true, 960, 600, changedScreen, monitor, 2),
  'fresh monitor data lets content reveal at the new scale')

const closedBody = /onClosed: \{([\s\S]*?)\n  \}/.exec(overlay)[1]
const compositorClosed = new Function('window', 'Qt', `with (window) { ${closedBody} }`)
const visibleExpression = /  visible: ([^\n]+)/.exec(overlay)[1]
const visible = new Function('window', 'Quickshell', `with (window) { return ${visibleExpression} }`)
const pending = []
const Qt = { callLater(callback) { pending.push(callback) } }
const Quickshell = { screens: [screen] }
assert(visible(window, Quickshell), 'an open overlay maps while the display server configures its output')
compositorClosed(window, Qt)
assert(!visible(window, Quickshell), 'an output disconnect waits for Qt to finish destroying the old window')
pending.shift()()
assert(visible(window, Quickshell), 'an open overlay remaps after the disconnected window is gone')
Quickshell.screens = []
assert(!visible(window, Quickshell), 'no outputs leave the overlay unmapped')
Quickshell.screens = [screen]
compositorClosed(window, Qt)
window.shown = false
pending.shift()()
assert(!visible(window, Quickshell), 'closing before a deferred remap prevents a stale reopen')
window.shown = true
const lostBody = /onResourcesLost: ([^\n]+)/.exec(overlay)[1]
const loseResources = new Function('window', `with (window) { ${lostBody} }`)
loseResources(window)
compositorClosed(window, Qt)
assert(!visible(window, Quickshell) && pending.length === 0,
  'losing graphics resources does not automatically retry window creation')
changeShown(window, Hyprland)
assert(visible(window, Quickshell), 'a new open retries after graphics resources were lost')

// Moving an open menu to another output drops the old output's layout.
const menuQml = read('shell/plugins/menu/Menu.qml')
const screenHandler = /onTargetScreenChanged: \{([^\n]*)\}/.exec(menuQml)[1]
const changeScreen = new Function('panel', `with (panel) { ${screenHandler} }`)
const menuPanel = { shown: true, cardTop: 945, maxRowsHeight: 510 }
changeScreen(menuPanel)
assertEqual(menuPanel.cardTop, -1, 'moving an open menu off a disconnected output unfreezes its old top edge')
assertEqual(menuPanel.maxRowsHeight, -1, 'moving an open menu drops the old output row-height limit')
assert(menuPanel.shown, 'resetting the layout keeps the menu open')

// Fullscreen overlays open without an additional compositor animation.
const shellRules = read('default/hypr/apps/omarchy-shell.lua')
const noAnim = /namespace = "\^\(([^)]*)\)\$" \}, no_anim = true/.exec(shellRules)
assert(noAnim, 'the shell overlays share one no-animation layer rule')
const unanimated = noAnim ? noAnim[1].split('|') : []
const overlayFiles = fs.readdirSync(path.join(root, 'shell/plugins'), { recursive: true })
  .filter(file => file.endsWith('.qml'))
  .map(file => 'shell/plugins/' + file)
  .filter(file => read(file).includes('OverlayWindow {'))
assert(overlayFiles.length > 0, 'shell plugins use the shared overlay window')
for (const file of overlayFiles) {
  const namespace = /WlrLayershell\.namespace: "([^"]+)"/.exec(read(file))
  assert(namespace && unanimated.includes(namespace[1]), `${file} is exempt from Hyprland's layer animation`)
}
JS
