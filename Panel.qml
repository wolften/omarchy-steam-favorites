import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.wolften.steam-favorites"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var games: []
  property string statusText: "Carregando…"
  property string noteText: ""

  function open() {
    refreshGames()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function pluginDir() {
    return Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  }

  function refreshGames() {
    statusText = "Carregando…"
    noteText = ""
    games = []
    discover.running = false
    discover.command = ["python3", pluginDir() + "/scripts/discover-favorites.py"]
    discover.running = true
  }

  function launchGame(appid) {
    Qt.openUrlExternally("steam://rungameid/" + appid)
  }

  Process {
    id: discover
    stdout: StdioCollector {
      id: outCollector
    }
    stderr: StdioCollector {
      id: errCollector
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0 && (!outCollector.text || outCollector.text.length === 0)) {
        root.games = []
        root.statusText = "Falha ao descobrir jogos"
        root.noteText = (errCollector.text || "python3 / script indisponível").trim()
        return
      }
      try {
        var data = JSON.parse(outCollector.text)
        if (data.games && data.games.length) {
          root.games = data.games
          root.statusText = data.games.length + " jogo(s)"
          root.noteText = data.note || ""
        } else {
          root.games = []
          root.statusText = data.error || "Nenhum jogo instalado"
          root.noteText = data.note || "Só lista jogos com appmanifest (instalados)."
        }
      } catch (e) {
        root.games = []
        root.statusText = "Falha ao ler lista da Steam"
        root.noteText = String(e)
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(Math.min(Style.space(420), content.implicitHeight + Style.space(16)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: "Steam Favorites"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Item { width: Style.space(8); height: 1 }

          WidgetButton {
            bar: root.bar
            text: "↻"
            tooltipText: "Atualizar lista"
            onPressed: function(buttonCode) {
              if (buttonCode === Qt.LeftButton) root.refreshGames()
            }
          }
        }

        Text {
          width: parent.width
          text: root.statusText
          color: root.barForeground
          opacity: 0.7
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.noteText.length > 0
          text: root.noteText
          color: root.barForeground
          opacity: 0.55
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Repeater {
          model: root.games

          delegate: WidgetButton {
            required property var modelData
            width: content.width
            bar: root.bar
            text: modelData.name || ("App " + modelData.appid)
            tooltipText: "Abrir steam://rungameid/" + modelData.appid
            onPressed: function(buttonCode) {
              if (buttonCode === Qt.LeftButton)
                root.launchGame(modelData.appid)
            }
          }
        }
      }
    }
  }
}
