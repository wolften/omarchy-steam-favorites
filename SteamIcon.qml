import QtQuick
import qs.Commons
import qs.Ui

// Steam mark from the shared nerd-font glyph set, so it sits on the same
// optical canvas and weight as the rest of the Omarchy bar.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property string fontFamily: Style.font.family

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  OpticalGlyph {
    anchors.fill: parent
    text: "󰓓"
    fontFamily: root.fontFamily
    fontSize: root.iconSize
    color: root.color
  }
}
