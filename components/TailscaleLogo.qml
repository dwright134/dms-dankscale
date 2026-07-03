import QtQuick
import qs.Common

// Tailscale-style 3x3 dot grid. Disconnected: all dots muted.
// Connected: middle row + bottom-middle dot lit (a "T"), rest muted.
Item {
    id: logo

    property real size: 24
    property bool connected: false
    property color dotColor: Theme.surfaceText
    property real mutedOpacity: 0.35

    readonly property real dotSize: size * 0.26
    readonly property real gap: (size - dotSize * 3) / 2

    width: size
    height: size

    Grid {
        anchors.fill: parent
        columns: 3
        columnSpacing: logo.gap
        rowSpacing: logo.gap

        Repeater {
            model: 9

            Rectangle {
                required property int index
                width: logo.dotSize
                height: logo.dotSize
                radius: width / 2
                color: logo.dotColor
                opacity: logo.connected && (index === 3 || index === 4 || index === 5 || index === 7) ? 1 : logo.mutedOpacity

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.shortDuration
                    }
                }
            }
        }
    }
}
