import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: tab

    Column {
        id: topCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.spacingM

        StyledRect {
            width: parent.width
            height: acceptToggle.height + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            DankToggle {
                id: acceptToggle
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Theme.spacingS
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: "Accept subnet routes"
                description: "Use routes advertised by other devices on the tailnet"
                checked: TailscaleService.acceptRoutes
                onToggled: checked => TailscaleService.setAcceptRoutes(checked)
            }
        }

        StyledRect {
            width: parent.width
            height: advertiseCol.height + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: advertiseCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                StyledText {
                    text: "Advertise routes from this device"
                    font.weight: Font.Medium
                }

                StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Comma-separated CIDR ranges this device can reach, e.g. 192.168.1.0/24. Routes must be approved in the Tailscale admin console before other devices can use them."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    DankTextField {
                        id: routesField
                        width: parent.width - applyButton.width - Theme.spacingS
                        placeholderText: "192.168.1.0/24, 10.0.0.0/8"

                        Component.onCompleted: text = TailscaleService.advertisedRoutes.join(", ")

                        Connections {
                            target: TailscaleService
                            function onAdvertisedRoutesChanged() {
                                if (!routesField.activeFocus)
                                    routesField.text = TailscaleService.advertisedRoutes.join(", ");
                            }
                        }
                    }

                    DankButton {
                        id: applyButton
                        anchors.verticalCenter: routesField.verticalCenter
                        text: "Apply"
                        onClicked: TailscaleService.setAdvertisedRoutes(routesField.text)
                    }
                }
            }
        }

        StyledText {
            text: "Subnet routers on this tailnet"
            font.weight: Font.Medium
        }
    }

    StyledRect {
        anchors.top: topCol.bottom
        anchors.topMargin: Theme.spacingS
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        DankFlickable {
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            clip: true
            contentHeight: routerCol.height

            Column {
                id: routerCol
                width: parent.width
                spacing: Theme.spacingXS

                Repeater {
                    model: TailscaleService.subnetRouters

                    DeviceRow {
                        required property var modelData
                        width: parent.width
                        device: modelData
                        showDetails: true
                        onActivated: TailscaleService.copyDevice(modelData)
                    }
                }

                StyledText {
                    visible: TailscaleService.subnetRouters.length === 0
                    text: "No devices are advertising subnet routes"
                    color: Theme.surfaceVariantText
                }
            }
        }
    }
}
