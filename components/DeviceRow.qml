import QtQuick
import qs.Common
import qs.Widgets

Rectangle {
    id: root

    property var device: null
    property bool compact: false
    property bool showDetails: false

    signal activated

    readonly property bool isOnline: device?.online ?? false
    readonly property bool isExitActive: device?.exitNode ?? false

    height: compact ? 44 : 56
    radius: Theme.cornerRadius
    color: hoverArea.containsMouse ? Theme.surfaceHover : "transparent"

    Rectangle {
        id: statusDot
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        width: 8
        height: 8
        radius: 4
        color: root.isOnline ? Theme.success : Theme.outlineButton
    }

    DankIcon {
        id: osIcon
        anchors.left: statusDot.right
        anchors.leftMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        name: TailscaleService.osIcon(root.device?.os ?? "")
        size: Theme.iconSize - 4
        color: Theme.surfaceVariantText
    }

    Column {
        anchors.left: osIcon.right
        anchors.leftMargin: Theme.spacingM
        anchors.right: badges.left
        anchors.rightMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        StyledText {
            width: parent.width
            elide: Text.ElideRight
            text: (root.device?.name ?? "") + ((root.device?.isSelf ?? false) ? "  (this device)" : "")
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
        }

        StyledText {
            width: parent.width
            elide: Text.ElideRight
            visible: text.length > 0
            text: {
                const d = root.device;
                if (!d)
                    return "";
                let s = d.ip;
                if (!root.compact && d.owner && !d.isSelf)
                    s += " • " + d.owner;
                if (!d.online) {
                    const seen = TailscaleService.relTime(d.lastSeen);
                    s += seen ? " • last seen " + seen : " • offline";
                }
                return s;
            }
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }

    Row {
        id: badges
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS

        Rectangle {
            visible: root.showDetails && (root.device?.routes?.length ?? 0) > 0
            anchors.verticalCenter: parent.verticalCenter
            height: 20
            width: routesText.width + Theme.spacingM
            radius: 10
            color: Theme.surfaceVariantAlpha

            StyledText {
                id: routesText
                anchors.centerIn: parent
                text: "subnet " + (root.device?.routes ?? []).join(", ")
                font.pixelSize: Theme.fontSizeSmall - 1
                color: Theme.surfaceVariantText
            }
        }

        Rectangle {
            visible: (root.device?.exitNodeOption ?? false) || root.isExitActive
            anchors.verticalCenter: parent.verticalCenter
            height: 20
            width: exitText.width + Theme.spacingM
            radius: 10
            color: root.isExitActive ? Theme.primary : Theme.surfaceVariantAlpha

            StyledText {
                id: exitText
                anchors.centerIn: parent
                text: root.isExitActive ? "exit • active" : "exit node"
                font.pixelSize: Theme.fontSizeSmall - 1
                color: root.isExitActive ? Theme.primaryText : Theme.surfaceVariantText
            }
        }

        DankIcon {
            visible: hoverArea.containsMouse
            anchors.verticalCenter: parent.verticalCenter
            name: "content_copy"
            size: Theme.iconSizeSmall
            color: Theme.primary
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
