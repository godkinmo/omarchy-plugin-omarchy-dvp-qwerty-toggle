import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "godkin.omarchy-dvp-qwerty-toggle"

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

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggle() {
    if (busy) return
    busy = true
    controlProc.command = bothActive
      ? ["systemctl", "--user", "stop", kanataUnit, watcherUnit]
      : ["systemctl", "--user", "start", kanataUnit, watcherUnit]
    controlProc.running = true
  }

  IpcHandler {
    target: "kanata-service"

    function toggle(): void {
      root.toggle()
    }

    function refresh(): void {
      root.broadcast("refresh")
    }
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
    onPressed: root.toggle()
  }
}
