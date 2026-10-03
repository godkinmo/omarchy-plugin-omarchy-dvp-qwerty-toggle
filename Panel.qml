import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Kanata service toggle. The bar glyph opens a small popup with one on/off
// switch that starts or stops both systemd user units behind the Programmer
// Dvorak (DVP) + QWERTY setup:
//   - kanata.service            — the kanata keyboard remapper
//   - kanata-layer-watcher.service — the fcitx5-driven DVP/QWERTY layer switcher
//
// The switch is the whole point: one throw starts both units, throw it back and
// both stop. Live status drives the switch and the bar icon.
Panel {
  id: root
  moduleName: "godkin.omarchy-dvp-qwerty-toggle"
  ipcTarget: "kanata-service"
  manageIpc: false

  readonly property string kanataUnit: setting("kanataUnit", "kanata.service")
  readonly property string watcherUnit: setting("watcherUnit", "kanata-layer-watcher.service")
  readonly property int refreshIntervalSec: setting("refreshIntervalSec", 5)

  property bool kanataActive: false
  property bool watcherActive: false
  property bool busy: false

  readonly property bool bothActive: kanataActive && watcherActive
  readonly property string stateText: busy
    ? "Kanata: switching…"
    : (bothActive ? "Kanata on" : (kanataActive || watcherActive ? "Kanata partial" : "Kanata off"))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggleServices() {
    if (busy) return
    busy = true
    controlProc.command = bothActive
      ? ["systemctl", "--user", "stop", kanataUnit, watcherUnit]
      : ["systemctl", "--user", "start", kanataUnit, watcherUnit]
    controlProc.running = true
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function togglePanel(): void { root.toggle() }
    function toggle(): void { root.toggleServices() }
    function refresh(): void { root.broadcast("refresh") }
  }

  Process {
    id: statusProc
    command: ["systemctl", "--user", "is-active", root.kanataUnit, root.watcherUnit]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text).trim().split("\n")
        root.kanataActive = (lines[0] || "").trim() === "active"
        root.watcherActive = (lines[1] || "").trim() === "active"
      }
    }
  }

  Process {
    id: controlProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.trim() !== "") console.warn("kanata-service: " + text.trim())
      }
    }
    onExited: function(exitCode) {
      root.busy = false
      root.refresh()
    }
  }

  Timer {
    interval: Math.max(2, root.refreshIntervalSec) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌌"
    active: root.bothActive
    opacity: root.bothActive ? 1 : 0.5
    tooltipText: root.stateText
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) return
      root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(
      Math.max(Style.space(250),
        titleLabel.implicitWidth + Style.spacing.xl + showSwitch.implicitWidth
          + panel.padding * 2 + Border.left(panel.borderSpec) + Border.right(panel.borderSpec)))
    contentHeight: menuColumn.implicitHeight + panel.padding * 2

    Column {
      id: menuColumn
      width: parent.width
      spacing: Style.spacing.lg

      Item {
        id: switchRow
        width: parent.width
        height: Math.max(labelText.implicitHeight, showSwitch.implicitHeight)

        Column {
          id: labelText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xxs
          width: parent.width - showSwitch.implicitWidth - Style.spacing.xl

          Text {
            id: titleLabel
            text: "Kanata services"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: Color.popups.text
          }

          Text {
            text: root.stateText
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Qt.darker(Color.popups.text, 1.4)
          }
        }

        ToggleSwitch {
          id: showSwitch
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: root.bothActive
          busy: root.busy
          foreground: Color.popups.text
          accent: Color.accent
          onToggled: root.toggleServices()
        }
      }
    }
  }

  onOpenedChanged: if (opened) refresh()
}
