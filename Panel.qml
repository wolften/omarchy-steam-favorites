pragma ComponentBehavior: Bound

import QtQuick
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
  property string statusText: "Loading…"
  property string noteText: ""
  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color iconColor: bar ? bar.barForeground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int columns: 2
  readonly property int panelWidth: Style.space(200)
  readonly property int gridGap: Style.spacing.sm
  readonly property int nameHeight: Style.space(16)
  readonly property int maxGridHeight: Style.space(360)
  // contentWidth is the card outer size; covers must fit inside padding+border.
  readonly property int innerWidth: Math.max(
    1,
    panel.contentWidth - panel.padding * 2 - Math.max(2, Style.space(2)) * 2 - 2
  )

  function open() {
    refreshGames()
    root.controller.show()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    cursorActive = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function pluginDir() {
    var url = Qt.resolvedUrl(".").toString()
    if (url.indexOf("file://") === 0) url = url.substring(7)
    return url.replace(/\/$/, "")
  }

  function refreshGames() {
    if (games.length === 0) statusText = "Loading…"
    noteText = ""
    discover.running = false
    discover.command = ["python3", pluginDir() + "/scripts/discover-favorites.py"]
    discover.running = true
  }

  function launchGame(appid) {
    if (!appid) return
    Qt.openUrlExternally("steam://rungameid/" + appid)
  }

  function displayName(game) {
    if (game && game.name) return String(game.name)
    if (game && game.appid) return "App " + game.appid
    return "Game"
  }

  function libraryCoverUrl(appid) {
    return "https://cdn.cloudflare.steamstatic.com/steam/apps/" + appid + "/library_600x900.jpg"
  }

  function capsuleCoverUrl(appid) {
    return "https://cdn.cloudflare.steamstatic.com/steam/apps/" + appid + "/library_capsule.jpg"
  }

  function headerCoverUrl(appid) {
    return "https://cdn.cloudflare.steamstatic.com/steam/apps/" + appid + "/header.jpg"
  }

  function moveCursor(dx, dy) {
    if (games.length === 0) return
    if (!cursorActive) {
      cursorActive = true
      cursorIndex = 0
      return
    }
    var next = cursorIndex
    if (dx !== 0) next += dx
    if (dy !== 0) next += dy * columns
    cursorIndex = Math.max(0, Math.min(games.length - 1, next))
  }

  function activateCursor() {
    if (!cursorActive || games.length === 0) return
    var game = games[Math.max(0, Math.min(cursorIndex, games.length - 1))]
    if (game) launchGame(game.appid)
  }

  Process {
    id: discover
    stdout: StdioCollector { id: outCollector }
    stderr: StdioCollector { id: errCollector }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0 && (!outCollector.text || outCollector.text.length === 0)) {
        root.games = []
        root.statusText = "Could not find games"
        root.noteText = (errCollector.text || "python3 / script unavailable").trim()
        return
      }
      try {
        var data = JSON.parse(outCollector.text)
        if (data.games && data.games.length) {
          root.games = data.games
          root.statusText = data.games.length === 1 ? "1 game" : data.games.length + " games"
          root.noteText = ""
          root.cursorIndex = Math.min(root.cursorIndex, data.games.length - 1)
        } else {
          root.games = []
          root.statusText = data.error || "No games found"
          root.noteText = ""
        }
      } catch (e) {
        root.games = []
        root.statusText = "Could not read Steam library"
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
    contentHeight: panel.fittedContentHeight(bodyCol.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshGames()
      }

      Column {
        id: bodyCol
        width: root.innerWidth
        spacing: Style.spacing.panelGap

        PanelHero {
          id: hero
          width: parent.width
          title: "Steam"
          meta: root.statusText
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          iconComponent: Component {
            SteamIcon {
              iconSize: Style.font.display
              color: root.iconColor
              fontFamily: root.contentFontFamily
            }
          }
          trailingControl: Component {
            PanelActionButton {
              iconText: "󰑓"
              tooltipText: "Refresh"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.refreshGames()
            }
          }
        }

        Text {
          width: parent.width
          visible: root.noteText.length > 0
          text: root.noteText
          textFormat: Text.PlainText
          color: root.contentForeground
          opacity: 0.55
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        Flickable {
          id: gameFlick
          width: parent.width
          visible: root.games.length > 0
          height: Math.min(root.maxGridHeight, gridBox.height)
          implicitHeight: height
          contentWidth: width
          contentHeight: gridBox.height
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height

          Item {
            id: gridBox
            width: gameFlick.width
            height: {
              var n = root.games.length
              if (n <= 0) return 0
              var rows = Math.ceil(n / root.columns)
              return rows * cellH + (rows - 1) * gap
            }

            readonly property int gap: root.gridGap
            readonly property int cellW: Math.max(1, Math.floor((width - gap) / root.columns))
            readonly property int coverH: Math.round(cellW * 1.5)
            readonly property int cellH: coverH + root.nameHeight

            Repeater {
              model: root.games

              delegate: Item {
                id: cell
                required property var modelData
                required property int index

                width: gridBox.cellW
                height: gridBox.cellH
                x: (index % root.columns) * (gridBox.cellW + gridBox.gap)
                y: Math.floor(index / root.columns) * (gridBox.cellH + gridBox.gap)
                clip: true

                readonly property int appid: modelData && modelData.appid ? modelData.appid : 0
                readonly property string gameName: root.displayName(modelData)
                readonly property string localCover: modelData && modelData.cover ? String(modelData.cover) : ""
                readonly property bool selected: root.cursorActive && root.cursorIndex === index
                property int coverStage: localCover !== "" ? 0 : 1

                function coverSource() {
                  if (coverStage === 0 && localCover !== "") return localCover
                  if (coverStage <= 1) return root.libraryCoverUrl(appid)
                  if (coverStage === 2) return root.capsuleCoverUrl(appid)
                  return root.headerCoverUrl(appid)
                }

                Rectangle {
                  id: coverFrame
                  width: parent.width
                  height: gridBox.coverH
                  radius: Style.cornerRadius
                  color: Style.normalFillFor(root.contentForeground, Color.accent)
                  clip: true
                  border.width: (cellHover.containsMouse || cell.selected) ? Math.max(1, Style.space(2)) : 1
                  border.color: (cellHover.containsMouse || cell.selected)
                    ? Style.hoverBorderFor(root.contentForeground, Color.accent)
                    : Style.normalBorderFor(root.contentForeground, Color.accent)

                  Image {
                    id: cover
                    anchors.fill: parent
                    anchors.margins: 1
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    source: cell.coverSource()
                    onStatusChanged: {
                      if (status === Image.Error && cell.coverStage < 4) {
                        cell.coverStage += 1
                        if (cell.coverStage <= 3)
                          source = cell.coverSource()
                      }
                    }
                  }

                  Rectangle {
                    anchors.fill: parent
                    visible: cover.status !== Image.Ready
                    color: Qt.rgba(0, 0, 0, 0.18)

                    SteamIcon {
                      anchors.centerIn: parent
                      iconSize: Style.font.display
                      color: root.contentForeground
                      fontFamily: root.contentFontFamily
                      opacity: 0.35
                    }
                  }
                }

                Text {
                  id: nameLabel
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: coverFrame.bottom
                  anchors.topMargin: Style.space(2)
                  text: cell.gameName
                  textFormat: Text.PlainText
                  color: root.contentForeground
                  opacity: (cellHover.containsMouse || cell.selected) ? 1 : 0.75
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  maximumLineCount: 1
                  horizontalAlignment: Text.AlignHCenter
                }

                MouseArea {
                  id: cellHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.launchGame(cell.appid)
                  onEntered: {
                    root.cursorActive = true
                    root.cursorIndex = cell.index
                    if (root.bar) root.bar.showTooltip(root, cell.gameName)
                  }
                  onExited: if (root.bar) root.bar.hideTooltip(root)
                }
              }
            }
          }
        }

        Column {
          width: parent.width
          visible: root.games.length === 0 && root.statusText !== "Loading…"
          spacing: Style.space(6)
          topPadding: Style.space(12)
          bottomPadding: Style.space(12)

          SteamIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            iconSize: Style.font.display
            color: root.contentForeground
            fontFamily: root.contentFontFamily
            opacity: 0.35
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.statusText
            textFormat: Text.PlainText
            color: root.contentForeground
            opacity: 0.7
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
