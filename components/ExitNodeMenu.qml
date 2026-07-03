import QtQuick
import qs.Common
import qs.Widgets

// Flyout for the popout's exit node card: pick an exit node,
// allow LAN access, or advertise this device as an exit node.
StyledRect {
    id: menu

    signal dismissed

    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHighest
    border.width: 1
    border.color: Theme.outlineMedium
    height: menuCol.height + Theme.spacingS * 2

    component MenuOption: Rectangle {
        id: opt

        property string title: ""
        property string subtitle: ""
        property bool selected: false
        property bool dimmed: false

        signal activated

        width: parent.width
        height: 40
        radius: Theme.cornerRadius
        color: optArea.containsMouse ? Theme.surfaceHover : "transparent"

        DankIcon {
            id: radioIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            name: opt.selected ? "radio_button_checked" : "radio_button_unchecked"
            size: Theme.iconSize - 6
            color: opt.selected ? Theme.primary : Theme.surfaceVariantText
        }

        StyledText {
            id: titleText
            anchors.left: radioIcon.right
            anchors.leftMargin: Theme.spacingS
            anchors.right: subtitleText.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: opt.title
            opacity: opt.dimmed ? 0.5 : 1
        }

        StyledText {
            id: subtitleText
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: opt.subtitle
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            opacity: opt.dimmed ? 0.5 : 1
        }

        MouseArea {
            id: optArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: opt.activated()
        }
    }

    Column {
        id: menuCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacingS
        spacing: 2

        MenuOption {
            title: "None"
            subtitle: "direct"
            selected: !TailscaleService.activeExitNode && TailscaleService.prefExitNodeId === "" && TailscaleService.prefExitNodeIp === ""
            onActivated: {
                TailscaleService.setExitNode("", "");
                menu.dismissed();
            }
        }

        Repeater {
            model: TailscaleService.exitNodeCandidates

            MenuOption {
                required property var modelData
                title: modelData.name
                subtitle: modelData.online ? modelData.ip : "offline"
                dimmed: !modelData.online
                selected: modelData.exitNode || TailscaleService.prefExitNodeId === modelData.id || (TailscaleService.prefExitNodeIp !== "" && TailscaleService.prefExitNodeIp === modelData.ip)
                onActivated: {
                    TailscaleService.setExitNode(modelData.ip, modelData.name);
                    menu.dismissed();
                }
            }
        }

        StyledText {
            visible: TailscaleService.exitNodeCandidates.length === 0
            text: "No exit nodes advertised on this tailnet"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.outlineMedium
        }

        DankToggle {
            width: parent.width
            text: "Allow local network access"
            checked: TailscaleService.exitNodeAllowLan
            onToggled: checked => TailscaleService.setExitNodeAllowLan(checked)
        }

        DankToggle {
            width: parent.width
            text: "Run this device as an exit node"
            checked: TailscaleService.advertisesExitNode
            onToggled: checked => TailscaleService.setAdvertiseExitNode(checked)
        }
    }
}
