import QtQuick
// Namespaced so Controls' Button doesn't shadow the qs.Ui one.
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Zephyrus Duo keyboard: bar icon plus a touch-sized card. The card shows whether
// the magnetic keyboard is seated or lifted, shows the on-screen keyboard, and
// turns the plugin off. Everything goes through bin/zephyrus-duo-keyboard; live
// state comes from the daemon's state file.
Panel {
  id: root
  moduleName: "brogers.zephyrus-duo-keyboard"
  ipcTarget: "brogers.zephyrus-duo-keyboard"
  // Own the IPC target so it can also carry refresh().
  manageIpc: false

  // From `zephyrus-duo-keyboard status --json`.
  property var info: ({})
  property string busy: ""
  property string actionError: ""

  readonly property string cli: decodeURIComponent(Qt.resolvedUrl("bin/zephyrus-duo-keyboard").toString().replace("file://", ""))
  // The daemon's folder. Without XDG_RUNTIME_DIR nothing is watched (the timer still refreshes):
  // a guessed shared path like /tmp could be someone else's file.
  readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") + "/zephyrus-duo-keyboard" : ""
  readonly property string setup: info.setup || "unknown"
  readonly property bool ready: setup === "ready"
  readonly property bool daemonUp: !!info.running
  readonly property bool lifted: info.dock === "lifted"
  readonly property bool seated: info.dock === "seated"

  // The bar makes one widget per monitor. The floating button follows the panel
  // the keyboard is pinned to once a second screen is connected.
  readonly property var barScreen: button.QsWindow.window ? button.QsWindow.window.screen : null
  readonly property bool onEdp: barScreen !== null && /^eDP/.test(String(barScreen.name || ""))
  readonly property bool onKeyboardScreen: {
    if (!onEdp) return false
    var screens = Quickshell.screens
    var count = screens ? screens.length : 0
    if (count <= 1) return true
    var name = String(barScreen.name || "")
    var target = String(info.osk_output || "")
    if (target !== "") return name === target
    // Status has not named a panel yet. The lower internal screen is the bottom one.
    var lowest = name
    var lowestY = barScreen.y
    for (var i = 0; i < count; i++) {
      var screen = screens[i]
      if (!screen || !/^eDP/.test(String(screen.name || ""))) continue
      if (screen.y > lowestY) {
        lowestY = screen.y
        lowest = String(screen.name || "")
      }
    }
    return name === lowest
  }
  readonly property string keyboardGlyph: "\udb80\udf0c"
  readonly property string keyboardCloseGlyph: "\udb80\udf0f"

  readonly property string liftedGlyph: "󰓶"
  readonly property string seatedGlyph: "󰌢"

  // The bar API handed to third-party plugins has run() but not shellQuote(),
  // so quote locally.
  function quote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function refresh() {
    if (!infoProc.running) infoProc.running = true
  }

  // Refresh every copy of the widget (one per monitor), as BarWidget.broadcast does.
  function refreshAll() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) {
      if (items[i] && typeof items[i].refresh === "function") items[i].refresh()
    }
  }

  function runAction(kind, args) {
    if (busy !== "") return
    busy = kind
    actionError = ""
    actionProc.command = [cli].concat(args)
    actionProc.running = true
  }

  // Install asks for a password, and doctor talks to you, so they get a terminal.
  function openTerminal(command) {
    if (!bar) return
    close()
    // The helper runs its arguments through `bash -c` again, so the path is quoted twice.
    bar.run("omarchy-launch-floating-terminal-with-presentation " + quote(quote(cli)) + " " + command)
  }

  function statusCaption() {
    if (busy === "disable") return "TURNING OFF..."
    if (busy === "enable") return "STARTING..."
    if (setup === "disabled") return "OFF"
    if (setup === "install") return "NOT SET UP"
    if (setup === "enable") return "ONE STEP LEFT"
    if (setup === "stopped") return "STOPPED"
    if (setup !== "ready") return ""
    if (seated) return "SEATED"
    if (lifted) return "LIFTED"
    return ""
  }

  function setupText() {
    if (setup === "disabled") return "Turned off. The service is stopped and the on-screen keyboard is hidden."
    if (setup === "install") return "Needs wvkbd-deskus, the on-screen keyboard. Setup installs it and asks for your password."
    if (setup === "enable") return "Installed. Last step: start the service and add the menu entries."
    if (setup === "stopped") return "The keyboard service isn't running."
    return ""
  }

  function dockText() {
    if (seated) return "Seated on the bottom panel"
    if (lifted) return "Lifted"
    return "Unknown"
  }

  function oskSubtitle() {
    if (info.osk && info.osk_output) return "Shown on " + info.osk_output
    return info.osk ? "Shown" : "Hidden"
  }

  IpcHandler {
    target: "brogers.zephyrus-duo-keyboard"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refreshAll() }
  }

  onOpenedChanged: {
    if (opened) {
      actionError = ""
      refresh()
    }
  }

  Component.onCompleted: refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: infoProc
    command: [root.cli, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.info = JSON.parse(String(text || "{}")) } catch (e) { }
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      id: actionErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var lines = String(actionErr.text || "").trim().split("\n")
        root.actionError = lines[lines.length - 1].replace(/^.*Error:\s*/, "") || "That didn't work"
      }
      root.busy = ""
      root.refreshAll()
    }
  }

  // The daemon rewrites this on every change, so the icon follows the keyboard live.
  FileView {
    path: root.runDir !== "" ? root.runDir + "/state.json" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
    onLoadFailed: root.refresh()
  }

  Timer {
    interval: root.opened ? 3000 : 20000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // Floating keyboard button on the bottom panel while the daemon is running and
  // the keyboard is lifted. A single screen keeps the button. One tap shows the
  // on-screen keyboard, another hides it.
  // It keeps out of other surfaces' exclusive zones, so while the keyboard is up
  // it sits just above it, within thumb reach either way.
  PanelWindow {
    id: oskButton
    screen: root.barScreen
    visible: root.daemonUp && root.lifted && root.onKeyboardScreen
    anchors { bottom: true; right: true }
    margins { bottom: Style.space(18); right: Style.space(18) }
    implicitWidth: Style.space(64)
    implicitHeight: Style.space(64)
    color: "transparent"
    WlrLayershell.namespace: "zephyrus-duo-keyboard-button"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Normal

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: Commons.Color.background
      border.width: Math.max(1, Style.normalBorderWidth)
      border.color: Commons.Color.accent
      opacity: oskTap.pressed ? 0.75 : 0.95

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.info.osk ? root.keyboardCloseGlyph : root.keyboardGlyph
        color: Commons.Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.display
      }

      MouseArea {
        id: oskTap
        anchors.fill: parent
        onClicked: root.runAction("osk", ["osk", "toggle"])
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.lifted ? root.liftedGlyph : root.seatedGlyph
    dimmed: !root.ready
    tooltipText: root.opened ? "" : (root.ready
      ? (root.seated ? "Keyboard seated" : (root.lifted ? "Keyboard lifted" : "Zephyrus Duo keyboard"))
      : (root.setup === "disabled" ? "Zephyrus Duo keyboard: off" : "Zephyrus Duo keyboard: not set up"))
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // The card is capped at the screen's height, so on a short screen the content
      // scrolls instead of losing its bottom row.
      Controls.ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
        Controls.ScrollBar.vertical.policy: column.implicitHeight > height ? Controls.ScrollBar.AsNeeded : Controls.ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: column.implicitHeight > scrollArea.height
        }

        Column {
          id: column
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero: icon, title/status, dock ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroValue.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: root.lifted ? root.liftedGlyph : root.seatedGlyph
              color: root.bar.foreground
              opacity: root.ready ? 1 : 0.45
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: heroValue.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Keyboard"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: root.statusCaption()
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }

            Column {
              id: heroValue
              visible: root.seated || root.lifted
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter

              Text {
                anchors.right: parent.right
                textFormat: Text.PlainText
                text: root.seated ? "Seated" : "Lifted"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                anchors.right: parent.right
                text: "DOCK"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1.2
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Setup, stopped or disabled ----------
          Column {
            visible: !root.ready
            width: parent.width
            spacing: Style.space(10)

            Text {
              textFormat: Text.PlainText
              text: root.actionError !== "" ? root.actionError : root.setupText()
              color: root.actionError !== "" ? Commons.Color.urgent : root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              width: parent.width
            }

            Row {
              id: setupRow
              width: parent.width
              spacing: Style.space(6)
              readonly property real cellWidth: (width - spacing) / 2

              Button {
                width: setupRow.cellWidth
                iconText: root.setup === "install" ? "" : "󰐥"
                text: root.setup === "install" ? "Set up" : (root.setup === "enable" ? "Finish setup" : (root.setup === "stopped" ? "Start" : "Turn on"))
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                onClicked: root.setup === "install" ? root.openTerminal("install") : root.runAction("enable", ["enable"])
              }

              Button {
                width: setupRow.cellWidth
                iconText: ""
                text: "Check"
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                onClicked: root.openTerminal("doctor")
              }
            }
          }

          // ---------- Dock status and the on-screen keyboard ----------
          Column {
            visible: root.ready
            width: parent.width
            spacing: Style.space(12)

            Item {
              width: parent.width
              implicitHeight: dockLabels.implicitHeight

              Column {
                id: dockLabels
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Style.space(2)

                Text {
                  text: "Dock"
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  width: parent.width
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.dockText()
                  color: root.bar.foreground
                  opacity: 0.6
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  width: parent.width
                  wrapMode: Text.WordWrap
                }
              }
            }

            SwitchRow {
              title: "On-screen keyboard"
              subtitle: root.actionError !== "" ? root.actionError : root.oskSubtitle()
              warn: root.actionError !== ""
              checked: !!root.info.osk
              onToggled: root.runAction("osk", ["osk", "toggle"])
            }
          }

          PanelSeparator { visible: root.ready; foreground: root.bar.foreground }

          Row {
            id: toolsRow
            visible: root.ready
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing) / 2

            Button {
              width: toolsRow.cellWidth
              iconText: ""
              text: "Check"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              onClicked: root.openTerminal("doctor")
            }

            Button {
              width: toolsRow.cellWidth
              iconText: "󰐥"
              text: "Turn off"
              tooltipText: "Stop the service and hide the on-screen keyboard"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              onClicked: root.runAction("disable", ["disable"])
            }
          }
        }
      }
    }
  }

  component SwitchRow: Item {
    id: row
    property string title: ""
    property string subtitle: ""
    property bool checked: false
    property bool warn: false
    signal toggled()

    width: parent ? parent.width : 0
    implicitHeight: Math.max(labels.implicitHeight, toggle.implicitHeight)

    Column {
      id: labels
      anchors.left: parent.left
      anchors.right: toggle.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        text: row.title
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        width: parent.width
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        text: row.subtitle
        color: row.warn ? Commons.Color.urgent : root.bar.foreground
        opacity: row.warn ? 1 : 0.6
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        width: parent.width
        wrapMode: Text.WordWrap
      }
    }

    ToggleSwitch {
      id: toggle
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: row.checked
      busy: root.busy !== ""
      foreground: root.bar.foreground
      onToggled: row.toggled()
    }
  }
}
