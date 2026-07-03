import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: tab

    DankFlickable {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: bottomCol.top
        anchors.bottomMargin: Theme.spacingM
        clip: true
        contentHeight: accountsCol.height

        Column {
            id: accountsCol
            width: parent.width
            spacing: Theme.spacingXS

            Repeater {
                model: TailscaleService.accounts

                Rectangle {
                    id: acctRow

                    required property var modelData

                    width: parent.width
                    height: 56
                    radius: Theme.cornerRadius
                    color: acctArea.containsMouse && !modelData.active ? Theme.surfaceHover : (modelData.active ? Theme.primaryPressed : "transparent")

                    DankIcon {
                        id: acctIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        name: acctRow.modelData.active ? "check_circle" : "account_circle"
                        filled: acctRow.modelData.active
                        color: acctRow.modelData.active ? Theme.primary : Theme.surfaceVariantText
                    }

                    Column {
                        anchors.left: acctIcon.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: switchLabel.left
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: acctRow.modelData.account
                            font.weight: Font.Medium
                        }

                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: "Tailnet: " + acctRow.modelData.tailnet
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    StyledText {
                        id: switchLabel
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        text: acctRow.modelData.active ? "Active" : (acctArea.containsMouse ? "Switch" : "")
                        color: acctRow.modelData.active ? Theme.primary : Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    MouseArea {
                        id: acctArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: acctRow.modelData.active ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: {
                            if (!acctRow.modelData.active)
                                TailscaleService.switchAccount(acctRow.modelData.account);
                        }
                    }
                }
            }

            StyledText {
                visible: TailscaleService.accounts.length === 0
                text: "No Tailscale accounts on this device yet"
                color: Theme.surfaceVariantText
            }
        }
    }

    Column {
        id: bottomCol
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.spacingM

        StyledRect {
            visible: TailscaleService.loginInProgress
            width: parent.width
            height: loginCol.height + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: loginCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                StyledText {
                    text: "Waiting for browser sign-in…"
                    font.weight: Font.Medium
                }

                StyledText {
                    visible: TailscaleService.authUrl.length > 0
                    width: parent.width
                    elide: Text.ElideRight
                    text: TailscaleService.authUrl
                    color: Theme.primary
                    font.pixelSize: Theme.fontSizeSmall

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: TailscaleService.copyText(TailscaleService.authUrl)
                    }
                }

                DankButton {
                    text: "Cancel"
                    backgroundColor: Theme.surfaceVariantAlpha
                    textColor: Theme.surfaceText
                    buttonHeight: 32
                    onClicked: TailscaleService.cancelLogin()
                }
            }
        }

        DankButton {
            text: TailscaleService.accounts.length > 0 ? "Add another account" : "Log in to Tailscale"
            iconName: "person_add"
            visible: !TailscaleService.loginInProgress
            onClicked: TailscaleService.startLogin()
        }
    }
}
