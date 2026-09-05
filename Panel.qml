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

  readonly property int panelWidth: Style.space(360)
  readonly property int gridGap: Style.space(8)
  readonly property int cellWidth: Math.floor((panelWidth - gridGap) / 2)
  readonly property int coverHeight: Style.space(96)
  readonly property int cellHeight: coverHeight + Style.space(36)

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

  function libraryCoverUrl(appid) {
    return "https://cdn.cloudflare.steamstatic.com/steam/apps/" + appid + "/library_600x900.jpg"
  }

  function capsuleCoverUrl(appid) {
    return "https://cdn.cloudflare.steamstatic.com/steam/apps/" + appid + "/capsule_231x87.jpg"
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
    contentWidth: panel.fittedContentWidth(root.panelWidth)
    contentHeight: panel.fittedContentHeight(
      Math.min(Style.space(460), headerCol.implicitHeight + gameFlick.implicitHeight + Style.space(16))
    )

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: headerCol
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
            elide: Text.ElideRight
            width: parent.width - Style.space(40)
          }

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
          elide: Text.ElideRight
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
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        Flickable {
          id: gameFlick
          width: parent.width
          // Grow with content up to a cap so the popup stays on-screen.
          height: Math.min(Style.space(360), grid.implicitHeight)
          implicitHeight: height
          contentWidth: width
          contentHeight: grid.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          visible: root.games.length > 0

          Grid {
            id: grid
            width: gameFlick.width
            columns: 2
            columnSpacing: root.gridGap
            rowSpacing: root.gridGap

            Repeater {
              model: root.games

              delegate: Item {
                id: cell
                required property var modelData
                width: root.cellWidth
                height: root.cellHeight

                readonly property int appid: modelData.appid
                readonly property string gameName: modelData.name || ("App " + modelData.appid)
                property bool useCapsule: false

                Rectangle {
                  id: card
                  anchors.fill: parent
                  radius: Style.spacing.labelGap
                  color: Style.normalFillFor(root.barForeground, Color.accent)
                  clip: true

                  Column {
                    anchors.fill: parent
                    anchors.margins: Style.space(4)
                    spacing: Style.space(4)

                    Item {
                      width: parent.width
                      height: root.coverHeight

                      Image {
                        id: cover
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        source: cell.useCapsule
                          ? root.capsuleCoverUrl(cell.appid)
                          : root.libraryCoverUrl(cell.appid)
                        onStatusChanged: {
                          if (status === Image.Error && !cell.useCapsule) {
                            cell.useCapsule = true
                          }
                        }
                      }

                      // Fallback glyph when CDN art is missing.
                      Rectangle {
                        anchors.fill: parent
                        visible: cover.status !== Image.Ready
                        color: Qt.rgba(0, 0, 0, 0.12)

                        Text {
                          anchors.centerIn: parent
                          text: "󰖹"
                          color: root.barForeground
                          opacity: 0.55
                          font.family: root.bar ? root.bar.fontFamily : Style.font.family
                          font.pixelSize: Style.font.display
                        }
                      }
                    }

                    Text {
                      width: parent.width
                      text: cell.gameName
                      color: root.barForeground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      elide: Text.ElideRight
                      maximumLineCount: 2
                      wrapMode: Text.WordWrap
                      horizontalAlignment: Text.AlignHCenter
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.launchGame(cell.appid)
                    onEntered: if (root.bar) root.bar.showTooltip(root, cell.gameName)
                    onExited: if (root.bar) root.bar.hideTooltip(root)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
