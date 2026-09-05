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

  readonly property int panelWidth: Style.space(380)
  readonly property int gridGap: Style.space(10)
  readonly property int cellWidth: Math.floor((panelWidth - gridGap) / 2)
  readonly property int coverHeight: Style.space(110)
  readonly property int cardRadius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(10)
  readonly property int gameIconSize: Style.space(22)

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

  function headerCoverUrl(appid) {
    return "https://cdn.cloudflare.steamstatic.com/steam/apps/" + appid + "/header.jpg"
  }

  // Clean display name only — never prefix with source/installed labels.
  function displayName(game) {
    if (game && game.name) return String(game.name)
    if (game && game.appid) return "App " + game.appid
    return "Jogo"
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
          root.statusText = data.games.length === 1 ? "1 jogo" : data.games.length + " jogos"
          root.noteText = ""
        } else {
          root.games = []
          root.statusText = data.error || "Nenhum jogo encontrado"
          root.noteText = ""
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
      Math.min(Style.space(480), bodyCol.implicitHeight + Style.space(4))
    )

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: bodyCol
        width: parent.width
        spacing: Style.space(10)

        // ---- Header (padrão Omarchy: título + ação à direita) ----
        Row {
          width: parent.width
          height: Math.max(titleCol.implicitHeight, refreshBtn.height)
          spacing: Style.space(8)

          Column {
            id: titleCol
            width: parent.width - refreshBtn.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: "Steam Favorites"
              textFormat: Text.PlainText
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: root.statusText
              textFormat: Text.PlainText
              color: root.barForeground
              opacity: 0.6
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          PanelActionButton {
            id: refreshBtn
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰑓"
            tooltipText: "Atualizar"
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.refreshGames()
          }
        }

        Text {
          width: parent.width
          visible: root.noteText.length > 0
          text: root.noteText
          textFormat: Text.PlainText
          color: root.barForeground
          opacity: 0.55
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        PanelSectionHeader {
          width: parent.width
          visible: root.games.length > 0
          text: "BIBLIOTECA"
          foreground: root.barForeground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }

        // ---- Grid 2 colunas ----
        Flickable {
          id: gameFlick
          width: parent.width
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
                required property int index
                width: root.cellWidth
                height: coverBox.height + infoRow.height + Style.space(12)

                readonly property int appid: modelData.appid
                readonly property string gameName: root.displayName(modelData)
                readonly property string localCover: modelData.cover || ""
                readonly property string localLogo: modelData.logo || ""
                readonly property string localIcon: modelData.icon || ""
                property int coverStage: (modelData.cover || "") !== "" ? 0 : 1 // 0 local, 1 library CDN, 2 capsule, 3 header, 4 done

                function coverSource() {
                  if (cell.coverStage === 0 && cell.localCover !== "") return cell.localCover
                  if (cell.coverStage <= 1) return root.libraryCoverUrl(cell.appid)
                  if (cell.coverStage === 2) return root.capsuleCoverUrl(cell.appid)
                  return root.headerCoverUrl(cell.appid)
                }

                Rectangle {
                  id: card
                  anchors.fill: parent
                  radius: root.cardRadius
                  color: cellHover.containsMouse
                    ? Style.hoverFillFor(root.barForeground, Color.accent)
                    : Style.normalFillFor(root.barForeground, Color.accent)
                  border.width: 1
                  border.color: cellHover.containsMouse
                    ? Style.hoverBorderFor(root.barForeground, Color.accent)
                    : Style.normalBorderFor(root.barForeground, Color.accent)
                  clip: true

                  Behavior on color { ColorAnimation { duration: 90 } }

                  Column {
                    anchors.fill: parent
                    spacing: 0

                    // Capa do jogo (local primeiro, CDN como fallback).
                    Item {
                      id: coverBox
                      width: parent.width
                      height: root.coverHeight
                      clip: true

                      Image {
                        id: cover
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        source: cell.coverSource()
                        onStatusChanged: {
                          if (status === Image.Error && cell.coverStage < 4) {
                            cell.coverStage += 1
                            if (cell.coverStage <= 3)
                              cover.source = cell.coverSource()
                          }
                        }
                      }

                      // Glyph de fallback quando não há arte.
                      Rectangle {
                        anchors.fill: parent
                        visible: cover.status !== Image.Ready
                        color: Qt.rgba(0, 0, 0, 0.14)

                        Text {
                          anchors.centerIn: parent
                          text: "󰖹"
                          color: root.barForeground
                          opacity: 0.5
                          font.family: root.bar ? root.bar.fontFamily : Style.font.family
                          font.pixelSize: Style.font.display
                        }
                      }

                      // Logo do jogo sobre a capa (quando disponível).
                      Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Style.space(6)
                        width: Math.min(parent.width - Style.space(16), Style.space(120))
                        height: Style.space(26)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        visible: status === Image.Ready
                        source: cell.localLogo
                      }
                    }

                    // Linha info: ícone + nome (sem prefixos).
                    Item {
                      id: infoRow
                      width: parent.width
                      height: Math.max(root.gameIconSize, nameText.implicitHeight) + Style.space(8)

                      Row {
                        anchors.fill: parent
                        anchors.leftMargin: Style.space(8)
                        anchors.rightMargin: Style.space(8)
                        anchors.topMargin: Style.space(4)
                        anchors.bottomMargin: Style.space(4)
                        spacing: Style.space(8)

                        // Ícone do jogo (cache local 32px) com fallback.
                        Item {
                          width: root.gameIconSize
                          height: root.gameIconSize
                          anchors.verticalCenter: parent.verticalCenter

                          Image {
                            id: gameIcon
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true
                            smooth: true
                            visible: status === Image.Ready
                            source: cell.localIcon
                          }

                          Text {
                            anchors.centerIn: parent
                            visible: cell.localIcon === "" || gameIcon.status !== Image.Ready
                            text: "󰓓"
                            color: root.barForeground
                            opacity: 0.6
                            font.family: root.bar ? root.bar.fontFamily : Style.font.family
                            font.pixelSize: Style.font.body
                          }
                        }

                        Text {
                          id: nameText
                          width: parent.width - root.gameIconSize - parent.spacing
                          anchors.verticalCenter: parent.verticalCenter
                          text: cell.gameName
                          textFormat: Text.PlainText
                          color: root.barForeground
                          font.family: root.bar ? root.bar.fontFamily : Style.font.family
                          font.pixelSize: Style.font.body
                          font.weight: cellHover.containsMouse ? Font.DemiBold : Font.Normal
                          elide: Text.ElideRight
                          maximumLineCount: 2
                          wrapMode: Text.WordWrap
                          lineHeight: 1.1
                        }
                      }
                    }
                  }

                  MouseArea {
                    id: cellHover
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

        // ---- Estado vazio ----
        Column {
          width: parent.width
          visible: root.games.length === 0 && root.statusText !== "Carregando…"
          spacing: Style.space(6)
          topPadding: Style.space(12)
          bottomPadding: Style.space(12)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "󰖹"
            color: root.barForeground
            opacity: 0.4
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.display
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.statusText
            textFormat: Text.PlainText
            color: root.barForeground
            opacity: 0.7
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
