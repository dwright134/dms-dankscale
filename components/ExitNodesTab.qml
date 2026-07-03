import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: tab

    component ExitOption: Rectangle {
        id: opt

        property string title: ""
        property string subtitle: ""
        property bool selected: false
        property bool dimmed: false

        signal activated

        width: parent.width
        height: 52
        radius: Theme.cornerRadius
        color: optArea.containsMouse ? Theme.surfaceHover : (selected ? Theme.primaryPressed : "transparent")

        DankIcon {
            id: radioIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            name: opt.selected ? "radio_button_checked" : "radio_button_unchecked"
            size: Theme.iconSize - 2
            color: opt.selected ? Theme.primary : Theme.surfaceVariantText
        }

        Column {
            anchors.left: radioIcon.right
            anchors.leftMargin: Theme.spacingM
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            opacity: opt.dimmed ? 0.5 : 1

            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: opt.title
                font.weight: Font.Medium
            }

            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: opt.subtitle
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        MouseArea {
            id: optArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: opt.activated()
        }
    }

    StyledText {
        id: introText
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        text: "Route all internet traffic through a device on your tailnet."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledRect {
        id: optionsCard
        anchors.top: introText.bottom
        anchors.topMargin: Theme.spacingM
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: togglesCard.top
        anchors.bottomMargin: Theme.spacingM
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        DankFlickable {
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            clip: true
            contentHeight: optCol.height

            Column {
                id: optCol
                width: parent.width
                spacing: Theme.spacingXS

                ExitOption {
                    title: "None"
                    subtitle: "Route traffic directly (no exit node)"
                    selected: !TailscaleService.activeExitNode && TailscaleService.prefExitNodeId === "" && TailscaleService.prefExitNodeIp === ""
                    onActivated: TailscaleService.setExitNode("", "")
                }

                Repeater {
                    model: TailscaleService.exitNodeCandidates

                    ExitOption {
                        required property var modelData
                        title: modelData.name
                        subtitle: modelData.ip + (modelData.online ? "" : " • offline")
                        dimmed: !modelData.online
                        selected: modelData.exitNode || TailscaleService.prefExitNodeId === modelData.id || (TailscaleService.prefExitNodeIp !== "" && TailscaleService.prefExitNodeIp === modelData.ip)
                        onActivated: TailscaleService.setExitNode(modelData.ip, modelData.name)
                    }
                }

                StyledText {
                    visible: TailscaleService.exitNodeCandidates.length === 0
                    text: "No devices on your tailnet offer an exit node"
                    color: Theme.surfaceVariantText
                }
            }
        }
    }

    StyledRect {
        id: togglesCard
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: togglesCol.height + Theme.spacingS * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: togglesCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Theme.spacingS
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS

            DankToggle {
                width: parent.width
                text: "Allow local network access"
                description: "Keep direct access to your LAN while using an exit node"
                checked: TailscaleService.exitNodeAllowLan
                onToggled: checked => TailscaleService.setExitNodeAllowLan(checked)
            }

            DankToggle {
                width: parent.width
                text: "Run this device as an exit node"
                description: "Let other tailnet devices route their internet traffic through this machine"
                checked: TailscaleService.advertisesExitNode
                onToggled: checked => TailscaleService.setAdvertiseExitNode(checked)
            }
        }
    }
}
