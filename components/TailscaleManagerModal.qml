import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Widgets

DankModal {
    id: modal

    property int currentTab: 0

    // Bubbled up so the root widget can open the send-files dialog for a device
    // picked from the Devices tab.
    signal sendRequested(var device)

    readonly property string statusLine: {
        if (TailscaleService.operatorMissing)
            return "Operator access required";
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
    // No dimming scrim behind the modal — click-outside-to-close still works
    // (it's a separate click catcher, not the background).
    showBackground: false
    closeOnEscapeKey: true
    closeOnBackgroundClick: true
    onBackgroundClicked: close()

    // Starting a login raises a polkit password prompt, which would otherwise
    // appear behind this modal (and the modal can't be dragged aside). Close
    // on login start so the prompt — and then the browser — are reachable.
    Connections {
        target: TailscaleService
        function onLoginInProgressChanged() {
            if (TailscaleService.loginInProgress)
                modal.close();
        }
    }

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
                        text: "Dankscale"
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
                        visible: !TailscaleService.operatorMissing
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
                visible: !TailscaleService.operatorMissing
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
                    { text: "DNS", icon: "dns" },
                    { text: "Accounts", icon: "switch_account" }
                ]
            }

            // Everything below the header is replaced by the operator warning
            // while the user can't control the daemon — the tabs would only
            // show details and actions that are guaranteed to fail.
            Item {
                visible: TailscaleService.operatorMissing
                anchors.top: header.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                OperatorWarning {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Theme.spacingL * 2, 440)
                }
            }

            Loader {
                active: !TailscaleService.operatorMissing
                visible: active
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
                        return dnsTabComp;
                    case 4:
                        return accountsTabComp;
                    default:
                        return devicesTabComp;
                    }
                }
            }

            Component {
                id: devicesTabComp
                DevicesTab {
                    onSendRequested: device => modal.sendRequested(device)
                }
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
                id: dnsTabComp
                DnsTab {}
            }

            Component {
                id: accountsTabComp
                AccountsTab {}
            }
        }
    }
}
