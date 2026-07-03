import QtQuick
import qs.Common
import qs.Widgets

// Flyout for the popout's account card: switch accounts, jump to the
// Accounts tab of the manager, and see/renew the session key expiry.
StyledRect {
    id: menu

    signal dismissed
    signal openSettings

    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHighest
    border.width: 1
    border.color: Theme.outlineMedium
    height: menuCol.height + Theme.spacingS * 2

    readonly property string expiryIso: TailscaleService.selfDevice?.keyExpiry ?? ""
    readonly property string expiryIn: TailscaleService.untilTime(expiryIso)
    readonly property string expiryText: {
        if (!expiryIn)
            return "No expiry information";
        const date = Qt.formatDate(new Date(expiryIso), "MMMM d, yyyy");
        return expiryIn === "expired" ? date + " (expired)" : date + " (in " + expiryIn + ")";
    }

    component MenuRow: Rectangle {
        id: row

        property string iconName: ""
        property color iconColor: Theme.surfaceVariantText
        property bool iconFilled: false
        property string title: ""
        property string subtitle: ""
        property color titleColor: Theme.surfaceText

        signal activated

        width: parent.width
        height: 40
        radius: Theme.cornerRadius
        color: rowArea.containsMouse ? Theme.surfaceHover : "transparent"

        DankIcon {
            id: rowIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            name: row.iconName
            filled: row.iconFilled
            size: Theme.iconSize - 6
            color: row.iconColor
        }

        StyledText {
            anchors.left: rowIcon.right
            anchors.leftMargin: Theme.spacingS
            anchors.right: subtitleText.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: row.title
            color: row.titleColor
        }

        StyledText {
            id: subtitleText
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: row.subtitle
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.activated()
        }
    }

    Column {
        id: menuCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacingS
        spacing: 2

        Repeater {
            model: TailscaleService.accounts

            MenuRow {
                required property var modelData
                iconName: modelData.active ? "radio_button_checked" : "radio_button_unchecked"
                iconColor: modelData.active ? Theme.primary : Theme.surfaceVariantText
                title: modelData.account
                subtitle: modelData.active ? "active" : ""
                onActivated: {
                    if (!modelData.active) {
                        TailscaleService.switchAccount(modelData.account);
                        menu.dismissed();
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.outlineMedium
        }

        MenuRow {
            iconName: "manage_accounts"
            title: "Account settings…"
            onActivated: menu.openSettings()
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.outlineMedium
        }

        StyledRect {
            width: parent.width
            height: expiryCol.height + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceVariantAlpha

            Column {
                id: expiryCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                StyledText {
                    text: "Session expires"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: menu.expiryText
                    color: menu.expiryIn === "expired" ? Theme.error : Theme.surfaceText
                }
            }
        }

        MenuRow {
            iconName: "autorenew"
            iconColor: Theme.primary
            title: "Renew session…"
            titleColor: Theme.primary
            subtitle: "admin console"
            onActivated: {
                TailscaleService.renewSession();
                menu.dismissed();
            }
        }
    }
}
