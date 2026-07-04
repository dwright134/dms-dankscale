import QtQuick
import qs.Common
import qs.Widgets

// Full-view notice shown instead of any Tailscale details while the user is
// logged in but lacks operator rights on the daemon — every mutating command
// would be rejected, so nothing is shown until access is granted. (When logged
// out, operator isn't treated as missing; the normal card offers Log in, which
// re-establishes operator itself.) The command box copies the grant command.
Column {
    id: root

    spacing: Theme.spacingM

    TailscaleLogo {
        anchors.horizontalCenter: parent.horizontalCenter
        size: Theme.iconSizeLarge + 8
        connected: false
        dotColor: Theme.error
    }

    StyledText {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: "Tailscale needs operator access"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
    }

    StyledText {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: "Your user isn't allowed to control the Tailscale daemon. Grant access below (you'll be prompted for your password) and this view unlocks automatically."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    DankButton {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Grant access"
        iconName: "admin_panel_settings"
        onClicked: TailscaleService.grantOperator()
    }

    StyledText {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: "Or run this once in a terminal:"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    StyledRect {
        width: parent.width
        height: 44
        radius: Theme.cornerRadius
        color: cmdArea.containsMouse ? Theme.surfaceHover : Theme.surfaceContainerHigh

        MouseArea {
            id: cmdArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: TailscaleService.copyText(TailscaleService.operatorFixCommand)
        }

        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.right: copyIcon.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            font.family: "monospace"
            font.pixelSize: Theme.fontSizeSmall
            text: TailscaleService.operatorFixCommand
        }

        DankIcon {
            id: copyIcon
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            name: "content_copy"
            size: Theme.iconSize - 6
            color: Theme.surfaceVariantText
        }
    }
}
