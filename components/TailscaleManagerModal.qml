import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Widgets

DankModal {
    id: modal

    property int currentTab: 0

    readonly property string statusLine: {
        if (TailscaleService.health.length > 0)
            return TailscaleService.health[0];
        if (!TailscaleService.isRunning) {
            const acct = TailscaleService.currentAccount;
            return TailscaleService.stateLabel + (acct ? " • " + acct : "");
        }
        let s = TailscaleService.currentAccount || TailscaleService.currentTailnet;
        s += " • " + TailscaleService.onlineCount + " of " + TailscaleService.deviceCount + " devices online";
        if (TailscaleService.activeExitNode)
            s += " • exit node: " + TailscaleService.activeExitNode.name;
        return s;
    }

    layerNamespace: "dms:tailscale-manager"
    modalWidth: 760
    modalHeight: 620
    enableShadow: true
    closeOnEscapeKey: true
    closeOnBackgroundClick: true
    onBackgroundClicked: close()

    content: Component {
        Item {
            anchors.fill: parent

            Item {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: Theme.spacingL
                anchors.leftMargin: Theme.spacingL
                anchors.rightMargin: Theme.spacingL
                height: 48

                TailscaleLogo {
                    id: headerIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    size: Theme.iconSizeLarge
                    connected: TailscaleService.isRunning
                    dotColor: TailscaleService.isRunning ? Theme.primary : Theme.surfaceVariantText
                }

                Column {
                    anchors.left: headerIcon.right
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: headerControls.left
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    StyledText {
                        text: "Tailscale"
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                    }

                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: modal.statusLine
                        font.pixelSize: Theme.fontSizeSmall
                        color: TailscaleService.health.length > 0 ? Theme.warning : Theme.surfaceVariantText
                    }
                }

                Row {
                    id: headerControls
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingM

                    DankToggle {
                        anchors.verticalCenter: parent.verticalCenter
                        hideText: true
                        checked: TailscaleService.isRunning
                        toggling: TailscaleService.busy
                        enabled: !TailscaleService.daemonDown
                        onToggled: TailscaleService.toggleConnection()
                    }

                    DankActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "close"
                        iconColor: Theme.surfaceVariantText
                        onClicked: modal.close()
                    }
                }
            }

            DankTabBar {
                id: tabBar
                anchors.top: header.bottom
                anchors.topMargin: Theme.spacingM
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Theme.spacingL
                anchors.rightMargin: Theme.spacingL
                currentIndex: modal.currentTab
                onTabClicked: index => modal.currentTab = index
                model: [
                    { text: "Devices", icon: "devices" },
                    { text: "Exit Nodes", icon: "vpn_lock" },
                    { text: "Routes", icon: "alt_route" },
                    { text: "Accounts", icon: "switch_account" }
                ]
            }

            Loader {
                anchors.top: tabBar.bottom
                anchors.topMargin: Theme.spacingM
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: Theme.spacingL
                anchors.rightMargin: Theme.spacingL
                anchors.bottomMargin: Theme.spacingL
                sourceComponent: {
                    switch (modal.currentTab) {
                    case 1:
                        return exitTabComp;
                    case 2:
                        return routesTabComp;
                    case 3:
                        return accountsTabComp;
                    default:
                        return devicesTabComp;
                    }
                }
            }

            Component {
                id: devicesTabComp
                DevicesTab {}
            }

            Component {
                id: exitTabComp
                ExitNodesTab {}
            }

            Component {
                id: routesTabComp
                RoutesTab {}
            }

            Component {
                id: accountsTabComp
                AccountsTab {}
            }
        }
    }
}
