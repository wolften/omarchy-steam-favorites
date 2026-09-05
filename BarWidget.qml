import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "io.github.wolften.steam-favorites"

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Glyph-style Steam mark (monochrome asset tinted to bar foreground).
  Item {
    id: button
    implicitWidth: Style.space(26)
    implicitHeight: root.barSize || Style.space(26)

    Image {
      id: steamGlyph
      anchors.centerIn: parent
      width: Style.font.icon
      height: Style.font.icon
      source: Qt.resolvedUrl("assets/steam-glyph.png")
      sourceSize.width: Math.round(width * Screen.devicePixelRatio)
      sourceSize.height: Math.round(height * Screen.devicePixelRatio)
      fillMode: Image.PreserveAspectFit
      smooth: true
      asynchronous: true
      visible: false
    }

    ColorOverlay {
      anchors.centerIn: parent
      width: steamGlyph.width
      height: steamGlyph.height
      source: steamGlyph
      color: root.bar ? root.bar.barForeground : (root.barForeground || "#ffffff")
      visible: steamGlyph.status === Image.Ready
    }

    // Fallback if the PNG fails to load (Nerd Font / FA steam).
    Text {
      anchors.centerIn: parent
      visible: steamGlyph.status !== Image.Ready
      text: "󰓓"
      color: root.bar ? root.bar.barForeground : (root.barForeground || "#ffffff")
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.icon
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton
      onClicked: root.toggle()
      onEntered: if (root.bar) root.bar.showTooltip(root, "Steam Favorites")
      onExited: if (root.bar) root.bar.hideTooltip(root)
    }
  }
}
