import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "./components"

PluginComponent {
    id: root

    readonly property int pollSeconds: parseInt(pluginData.pollSeconds) || 5
    readonly property string copyPreference: pluginData.copyField || "ip"
    readonly property bool showOffline: pluginData.showOffline === undefined ? true : pluginData.showOffline === true

    readonly property string statusText: {
        if (TailscaleService.tailscaleMissing)
            return "Tailscale is not installed";
        if (TailscaleService.operatorMissing)
            return "Operator access required";
        if (TailscaleService.needsLogin)
            return "Login required";
        if (TailscaleService.daemonDown)
            return "tailscaled is not running";
        if (!TailscaleService.isRunning)
            return TailscaleService.stateLabel;
        let s = TailscaleService.onlineCount + " of " + TailscaleService.deviceCount + " online";
        if (TailscaleService.activeExitNode)
            s += " • exit: " + TailscaleService.activeExitNode.name;
        return s;
    }

    readonly property var popoutDevices: TailscaleService.allDevices.filter(d => root.showOffline || d.online)

    Binding {
        target: TailscaleService
        property: "pollIntervalMs"
        value: root.pollSeconds * 1000
    }

    Binding {
        target: TailscaleService
        property: "copyField"
        value: root.copyPreference
    }

    // Persist which account was last active so the popout can still show it as
    // selected after a restart while logged out (Tailscale stops marking any
    // profile active once it needs login). Seed the service's fallback from
    // settings before any account goes active this session.
    onPluginDataChanged: {
        if (pluginData && pluginData.lastAccount && !TailscaleService.lastActiveAccount)
            TailscaleService.lastActiveAccount = pluginData.lastAccount;
    }

    Connections {
        target: TailscaleService
        function onCurrentAccountChanged() {
            const acct = TailscaleService.currentAccount;
            if (acct && root.pluginService && root.pluginData.lastAccount !== acct)
                root.pluginService.savePluginData(root.pluginId, "lastAccount", acct);
        }
    }

    // Control center tile
    ccWidgetIcon: "apps"
    ccWidgetPrimaryText: "Dankscale"
    ccWidgetSecondaryText: statusText
    ccWidgetIsActive: TailscaleService.isRunning
    ccWidgetIsToggle: true
    onCcWidgetToggled: TailscaleService.toggleConnection()

    popoutWidth: 420

    function openManager(tab) {
        if (tab !== undefined)
            managerModal.currentTab = tab;
        closePopout();
        managerModal.open();
    }

    TailscaleManagerModal {
        id: managerModal
    }

    IpcHandler {
        target: "tailscale"

        function toggle(): string {
            TailscaleService.toggleConnection();
            return TailscaleService.backendState;
        }

        function manager(): string {
            root.openManager();
            return "opened";
        }

        function managertab(tab: string): string {
            root.openManager(parseInt(tab) || 0);
            return "opened";
        }

        function managerclose(): string {
            managerModal.close();
            return "closed";
        }

        function popout(): string {
            root.triggerPopout();
            return "toggled";
        }

        function status(): string {
            return TailscaleService.stateLabel + " • " + TailscaleService.onlineCount + "/" + TailscaleService.deviceCount + " online";
        }

        function operator(): string {
            return JSON.stringify({
                operatorMissing: TailscaleService.operatorMissing,
                detectedUser: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""
            });
        }
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: barIcon.width
            implicitHeight: barIcon.height
            anchors.verticalCenter: parent.verticalCenter

            TailscaleLogo {
                id: barIcon
                anchors.centerIn: parent
                size: root.iconSizeLarge - 4
                connected: TailscaleService.isRunning && !TailscaleService.operatorMissing
                dotColor: Theme.widgetIconColor
            }

            DankIcon {
                visible: TailscaleService.activeExitNode !== null
                name: "shield"
                filled: true
                size: barIcon.size * 0.5
                color: Theme.primary
                anchors.right: barIcon.right
                anchors.bottom: barIcon.bottom
                anchors.rightMargin: -2
                anchors.bottomMargin: -2
            }

            DankIcon {
                visible: TailscaleService.needsLogin || TailscaleService.daemonDown || TailscaleService.operatorMissing || TailscaleService.tailscaleMissing
                name: "priority_high"
                filled: true
                size: barIcon.size * 0.55
                color: Theme.error
                anchors.right: barIcon.right
                anchors.top: barIcon.top
                anchors.rightMargin: -3
                anchors.topMargin: -2
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: barIconV.width
            implicitHeight: barIconV.height
            anchors.horizontalCenter: parent.horizontalCenter

            TailscaleLogo {
                id: barIconV
                anchors.centerIn: parent
                size: root.iconSizeLarge
                connected: TailscaleService.isRunning && !TailscaleService.operatorMissing
                dotColor: Theme.widgetIconColor
            }

            DankIcon {
                visible: TailscaleService.activeExitNode !== null
                name: "shield"
                filled: true
                size: barIconV.size * 0.5
                color: Theme.primary
                anchors.right: barIconV.right
                anchors.bottom: barIconV.bottom
                anchors.rightMargin: -2
                anchors.bottomMargin: -2
            }

            DankIcon {
                visible: TailscaleService.needsLogin || TailscaleService.daemonDown || TailscaleService.operatorMissing || TailscaleService.tailscaleMissing
                name: "priority_high"
                filled: true
                size: barIconV.size * 0.55
                color: Theme.error
                anchors.right: barIconV.right
                anchors.top: barIconV.top
                anchors.rightMargin: -3
                anchors.topMargin: -2
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout

            // Without operator rights every control here would fail, so the
            // popout shows only the OperatorWarning until access is granted.
            readonly property bool locked: TailscaleService.operatorMissing

            headerText: "Dankscale"
            detailsText: root.statusText
            showCloseButton: true

            headerActions: Component {
                Row {
                    spacing: Theme.spacingXS

                    DankActionButton {
                        iconName: "refresh"
                        iconColor: Theme.surfaceVariantText
                        buttonSize: 28
                        tooltipText: "Refresh"
                        tooltipSide: "bottom"
                        onClicked: TailscaleService.refresh()
                    }

                    DankActionButton {
                        iconName: "open_in_new"
                        iconColor: Theme.surfaceVariantText
                        buttonSize: 28
                        tooltipText: "Open Manager"
                        tooltipSide: "bottom"
                        onClicked: root.openManager()
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                OperatorWarning {
                    visible: popout.locked
                    width: parent.width
                }

                // Connection card
                StyledRect {
                    visible: !popout.locked
                    width: parent.width
                    height: 64
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: connControls.left
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        StyledText {
                            text: TailscaleService.stateLabel
                            font.weight: Font.Medium
                        }

                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: TailscaleService.currentTailnet || "Tailscale VPN"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    Item {
                        id: connControls
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        width: TailscaleService.needsLogin ? loginBtn.width : connToggle.width
                        height: parent.height

                        DankToggle {
                            id: connToggle
                            visible: !TailscaleService.needsLogin
                            anchors.centerIn: parent
                            hideText: true
                            checked: TailscaleService.isRunning
                            toggling: TailscaleService.busy
                            enabled: !TailscaleService.daemonDown && !TailscaleService.operatorMissing && !TailscaleService.tailscaleMissing
                            onToggled: TailscaleService.toggleConnection()
                        }

                        DankButton {
                            id: loginBtn
                            visible: TailscaleService.needsLogin
                            anchors.centerIn: parent
                            text: "Log in"
                            buttonHeight: 32
                            onClicked: TailscaleService.startLogin()
                        }
                    }
                }

                // Account card — click to reveal the account menu
                StyledRect {
                    id: acctCard

                    property bool menuOpen: false

                    visible: !popout.locked && TailscaleService.accounts.length > 0
                    width: parent.width
                    height: 52
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    z: menuOpen ? 100 : 0

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: acctCard.menuOpen = !acctCard.menuOpen
                    }

                    DankIcon {
                        id: acctIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        name: "account_circle"
                        size: Theme.iconSize - 2
                        color: Theme.surfaceVariantText
                    }

                    Column {
                        anchors.left: acctIcon.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: acctChevron.left
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: TailscaleService.effectiveAccount || "No account"
                        }

                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: TailscaleService.accounts.length > 1 ? TailscaleService.accounts.length + " accounts" : "Account"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    DankIcon {
                        id: acctChevron
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        name: "expand_more"
                        size: Theme.iconSize - 4
                        color: Theme.surfaceVariantText
                        rotation: acctCard.menuOpen ? 180 : 0

                        Behavior on rotation {
                            NumberAnimation {
                                duration: Theme.shortDuration
                            }
                        }
                    }

                    AccountMenu {
                        visible: acctCard.menuOpen
                        y: acctCard.height + Theme.spacingXS
                        width: acctCard.width
                        onDismissed: acctCard.menuOpen = false
                        onOpenSettings: {
                            acctCard.menuOpen = false;
                            root.openManager(3);
                        }
                    }
                }

                // Exit node card — click to reveal the exit node menu
                StyledRect {
                    id: exitCard

                    property bool menuOpen: false

                    visible: !popout.locked && TailscaleService.isRunning
                    width: parent.width
                    height: 52
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    z: menuOpen ? 100 : 0

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: exitCard.menuOpen = !exitCard.menuOpen
                    }

                    DankIcon {
                        id: exitIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        name: "vpn_lock"
                        size: Theme.iconSize - 2
                        color: TailscaleService.activeExitNode ? Theme.primary : Theme.surfaceVariantText
                    }

                    Column {
                        anchors.left: exitIcon.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: clearExitButton.visible ? clearExitButton.left : exitChevron.left
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: TailscaleService.activeExitNode ? TailscaleService.activeExitNode.name : "No exit node"
                        }

                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: "Exit node"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    DankIcon {
                        id: exitChevron
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        name: "expand_more"
                        size: Theme.iconSize - 4
                        color: Theme.surfaceVariantText
                        rotation: exitCard.menuOpen ? 180 : 0

                        Behavior on rotation {
                            NumberAnimation {
                                duration: Theme.shortDuration
                            }
                        }
                    }

                    DankActionButton {
                        id: clearExitButton
                        visible: TailscaleService.activeExitNode !== null
                        anchors.right: exitChevron.left
                        anchors.rightMargin: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "close"
                        iconColor: Theme.surfaceVariantText
                        tooltipText: "Disable exit node"
                        onClicked: TailscaleService.setExitNode("", "")
                    }

                    ExitNodeMenu {
                        visible: exitCard.menuOpen
                        y: exitCard.height + Theme.spacingXS
                        width: exitCard.width
                        onDismissed: exitCard.menuOpen = false
                    }
                }

                StyledText {
                    visible: !popout.locked
                    text: "Devices (" + root.popoutDevices.length + ")"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceVariantText
                }

                DankFlickable {
                    visible: !popout.locked
                    width: parent.width
                    height: 260
                    clip: true
                    contentHeight: popoutDeviceCol.height

                    Column {
                        id: popoutDeviceCol
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: root.popoutDevices

                            DeviceRow {
                                required property var modelData
                                width: parent.width
                                device: modelData
                                compact: true
                                onActivated: TailscaleService.copyDevice(modelData)
                            }
                        }

                        StyledText {
                            visible: root.popoutDevices.length === 0
                            text: TailscaleService.statusReady ? "No devices" : "Loading…"
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                DankButton {
                    visible: !popout.locked
                    width: parent.width
                    text: "Open Manager"
                    iconName: "tune"
                    onClicked: root.openManager()
                }
            }
        }
    }
}
