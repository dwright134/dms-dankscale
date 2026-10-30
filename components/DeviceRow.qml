import QtQuick
import qs.Common
import qs.Widgets

Rectangle {
    id: root

    property var device: null
    property bool compact: false
    property bool showDetails: false

    // The send button and exit badge sit above hoverArea. The action
    // icons are always visible (not hover-gated) so this no longer causes a
    // layout shift, but we still OR this in for the row highlight so it stays
    // lit while the cursor is over the button.
    property bool sendHovered: false

    signal activated
    signal send

    readonly property bool canSend: TailscaleService.fileSharingEnabled && !(device?.isSelf ?? false) && (device?.online ?? false)

    readonly property bool isOnline: device?.online ?? false
    readonly property bool isExitActive: device != null && !(device?.isSelf ?? false) && TailscaleService.isExitNodeSelected(device)
    readonly property bool canSelectExitNode: !(device?.isSelf ?? false) && (device?.exitNodeOption ?? false) && (device?.ip ?? "") !== ""

    height: compact ? 44 : 56
    radius: Theme.cornerRadius
    color: (hoverArea.containsMouse || root.sendHovered || exitState.containsMouse) ? Theme.surfaceHover : "transparent"

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

    // Status markers (subnet / exit node) — placed before the action icons so
    // the icons keep a stable position regardless of which markers are present.
    Row {
        id: badges
        // Keep badge actions above the row's copy handler.
        z: 1
        anchors.right: copyIcon.left
        anchors.rightMargin: Theme.spacingS
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
            id: exitBadge
            objectName: "exitNodeBadge"
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

            StateLayer {
                id: exitState
                enabled: root.canSelectExitNode
                disabled: TailscaleService.busy
                stateColor: root.isExitActive ? Theme.primaryText : Theme.primary
                tooltipText: root.isExitActive ? "Currently selected exit node" : "Use as exit node"
                onClicked: {
                    if (!disabled && !root.isExitActive)
                        TailscaleService.setExitNode(root.device.ip, root.device.name);
                }
            }
        }
    }

    // Copy hint — always visible now (a stable layout avoids the hover flicker),
    // brightening when the row is hovered. Non-interactive: the row's MouseArea
    // beneath handles the actual copy click.
    DankIcon {
        id: copyIcon
        anchors.right: root.canSend ? sendButton.left : parent.right
        anchors.rightMargin: root.canSend ? Theme.spacingXS : Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        name: "content_copy"
        size: Theme.iconSizeSmall
        color: hoverArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    // Send-files action. Declared after hoverArea so it sits on top and its own
    // click is consumed here (the row's copy action does not also fire). Always
    // visible (not hover-gated) for online, non-self devices while Taildrop is
    // enabled, so its position never shifts.
    DankActionButton {
        id: sendButton
        visible: root.canSend
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        buttonSize: root.compact ? 28 : 32
        iconName: "upload_file"
        iconColor: Theme.primary
        tooltipText: "Send files"
        onEntered: root.sendHovered = true
        onExited: root.sendHovered = false
        onClicked: root.send()
    }
}
