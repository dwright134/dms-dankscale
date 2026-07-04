import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: tab

    // Which account's details fill the right-hand pane. Empty means "follow
    // the active account" — the detail resolver falls back to the active (or
    // first) account, so the pane is populated as soon as accounts load and
    // stays on the active one until the user explicitly picks another row.
    property string selectedId: ""

    readonly property var selectedAccount: {
        const accts = TailscaleService.accounts;
        if (accts.length === 0)
            return null;
        return accts.find(a => a.id === tab.selectedId) || accts.find(a => a.active) || accts[0];
    }

    Row {
        anchors.fill: parent
        spacing: Theme.spacingM

        // --- master: account list + add-account controls ---
        StyledRect {
            width: 260
            height: parent.height
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingS
                spacing: Theme.spacingS

                DankFlickable {
                    width: parent.width
                    height: parent.height - bottomCol.height - parent.spacing
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
                                readonly property bool selected: acctRow.modelData.id === tab.selectedAccount?.id

                                width: parent.width
                                height: 56
                                radius: Theme.cornerRadius
                                color: acctRow.selected ? Theme.primaryPressed : (acctArea.containsMouse ? Theme.surfaceHover : "transparent")

                                DankIcon {
                                    id: acctIcon
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "account_circle"
                                    color: acctRow.modelData.active ? Theme.primary : Theme.surfaceVariantText
                                }

                                // Presence dot on the avatar for the active account.
                                Rectangle {
                                    visible: acctRow.modelData.active
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: "#4CAF50"
                                    border.width: 2
                                    border.color: acctRow.selected ? Theme.primaryPressed : Theme.surfaceContainerHigh
                                    anchors.right: acctIcon.right
                                    anchors.bottom: acctIcon.bottom
                                }

                                Column {
                                    anchors.left: acctIcon.right
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.right: parent.right
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
                                        text: acctRow.modelData.tailnet
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }
                                }

                                MouseArea {
                                    id: acctArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: tab.selectedId = acctRow.modelData.id
                                }
                            }
                        }

                        StyledText {
                            visible: TailscaleService.accounts.length === 0
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "No Tailscale accounts on this device yet"
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                Column {
                    id: bottomCol
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledRect {
                        visible: TailscaleService.loginInProgress
                        width: parent.width
                        height: loginCol.height + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceVariant

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
                                buttonHeight: 30
                                onClicked: TailscaleService.cancelLogin()
                            }
                        }
                    }

                    DankButton {
                        width: parent.width
                        text: TailscaleService.accounts.length > 0 ? "Add Account…" : "Log in to Tailscale"
                        iconName: "person_add"
                        visible: !TailscaleService.loginInProgress
                        onClicked: TailscaleService.startLogin()
                    }
                }
            }
        }

        // --- detail: selected account ---
        StyledRect {
            width: parent.width - 260 - Theme.spacingM
            height: parent.height
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            // Empty state — no account selected because none exist.
            Column {
                visible: !tab.selectedAccount
                anchors.centerIn: parent
                spacing: Theme.spacingM
                width: parent.width - Theme.spacingXL * 2

                DankIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "account_circle"
                    size: 64
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "No account signed in.\nAdd an account to get started."
                    color: Theme.surfaceVariantText
                }
            }

            DankFlickable {
                visible: !!tab.selectedAccount
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                clip: true
                contentHeight: detailCol.height

                Column {
                    id: detailCol
                    width: parent.width
                    spacing: Theme.spacingL

                    readonly property var account: tab.selectedAccount
                    readonly property bool isActive: account?.active ?? false
                    // The profile the daemon is currently on — active while
                    // logged in, and still "current" when logged out (Tailscale
                    // drops the * marker then). Matches the popout's selection.
                    readonly property bool isCurrent: !!account && account.account === TailscaleService.effectiveAccount
                    // Full status/expiry data only exists for the active
                    // account (it's the one `tailscale status` describes).
                    readonly property bool loggedIn: isActive && !TailscaleService.needsLogin
                    readonly property string expiryIn: isActive ? TailscaleService.untilTime(TailscaleService.selfDevice?.keyExpiry ?? "") : ""

                    // Profile header.
                    Column {
                        width: parent.width
                        spacing: Theme.spacingS

                        DankIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "account_circle"
                            size: 72
                            color: Theme.primary
                        }

                        StyledText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: detailCol.account?.account ?? ""
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                        }
                    }

                    // Field grid: label column + value column.
                    Grid {
                        width: parent.width
                        columns: 2
                        rowSpacing: Theme.spacingM
                        columnSpacing: Theme.spacingL

                        readonly property real labelWidth: 88

                        // Tailnet
                        StyledText {
                            width: parent.labelWidth
                            horizontalAlignment: Text.AlignRight
                            text: "Tailnet"
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                        }
                        StyledText {
                            width: parent.width - parent.labelWidth - parent.columnSpacing
                            elide: Text.ElideRight
                            text: detailCol.account?.tailnet ?? ""
                        }

                        // Email
                        StyledText {
                            width: parent.labelWidth
                            horizontalAlignment: Text.AlignRight
                            text: "Email"
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                        }
                        StyledText {
                            width: parent.width - parent.labelWidth - parent.columnSpacing
                            elide: Text.ElideRight
                            text: detailCol.account?.account ?? ""
                        }

                        // Status
                        StyledText {
                            width: parent.labelWidth
                            horizontalAlignment: Text.AlignRight
                            text: "Status"
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                        }
                        Column {
                            width: parent.width - parent.labelWidth - parent.columnSpacing
                            spacing: Theme.spacingS

                            Row {
                                spacing: Theme.spacingS

                                Rectangle {
                                    width: 12
                                    height: 12
                                    radius: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: detailCol.loggedIn ? "#4CAF50" : Theme.surfaceVariantText
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: detailCol.loggedIn ? "Logged In" : (detailCol.isCurrent ? "Login required" : "Inactive account")
                                }
                            }

                            // Active account: log out / admin console.
                            Row {
                                visible: detailCol.isActive
                                spacing: Theme.spacingS

                                DankButton {
                                    text: "Log Out"
                                    iconName: "logout"
                                    backgroundColor: Theme.surfaceVariantAlpha
                                    textColor: Theme.surfaceText
                                    buttonHeight: 30
                                    enabled: !TailscaleService.busy
                                    onClicked: TailscaleService.logout()
                                }

                                DankButton {
                                    text: "Admin Console…"
                                    backgroundColor: Theme.surfaceVariantAlpha
                                    textColor: Theme.surfaceText
                                    buttonHeight: 30
                                    onClicked: TailscaleService.openAdminConsole()
                                }
                            }

                            // Current profile but logged out: sign back in.
                            DankButton {
                                visible: detailCol.isCurrent && !detailCol.isActive
                                text: TailscaleService.loginInProgress ? "Signing in…" : "Log In"
                                iconName: "login"
                                backgroundColor: Theme.surfaceVariantAlpha
                                textColor: Theme.surfaceText
                                buttonHeight: 30
                                enabled: !TailscaleService.loginInProgress
                                onClicked: TailscaleService.startLogin()
                            }

                            // A different, inactive profile: switch to it.
                            DankButton {
                                visible: !detailCol.isCurrent
                                text: "Switch to This Account"
                                iconName: "switch_account"
                                backgroundColor: Theme.surfaceVariantAlpha
                                textColor: Theme.surfaceText
                                buttonHeight: 30
                                enabled: !TailscaleService.busy
                                onClicked: TailscaleService.switchAccount(detailCol.account.account)
                            }
                        }

                        // Expiry (active account only).
                        StyledText {
                            visible: detailCol.isActive
                            width: parent.labelWidth
                            horizontalAlignment: Text.AlignRight
                            text: "Expiry"
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                        }
                        Column {
                            visible: detailCol.isActive
                            width: parent.width - parent.labelWidth - parent.columnSpacing
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                elide: Text.ElideRight
                                text: {
                                    if (!detailCol.expiryIn)
                                        return "No expiry information";
                                    return detailCol.expiryIn === "expired" ? "Session expired" : "Expires in " + detailCol.expiryIn;
                                }
                                color: detailCol.expiryIn === "expired" ? Theme.error : Theme.surfaceText
                            }

                            DankButton {
                                text: "Renew…"
                                backgroundColor: Theme.surfaceVariantAlpha
                                textColor: Theme.surfaceText
                                buttonHeight: 30
                                onClicked: TailscaleService.renewSession()
                            }
                        }
                    }
                }
            }
        }
    }
}
