import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: tab

    property string filterText: ""

    readonly property var visibleDevices: TailscaleService.allDevices.filter(d => {
        if (!tab.filterText)
            return true;
        const f = tab.filterText.toLowerCase();
        return d.name.toLowerCase().includes(f) || d.hostName.toLowerCase().includes(f) || d.ip.includes(f) || d.os.toLowerCase().includes(f);
    })

    DankTextField {
        id: searchField
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        leftIconName: "search"
        showClearButton: true
        placeholderText: "Filter devices…"
        onTextChanged: tab.filterText = text
    }

    StyledRect {
        id: listCard
        anchors.top: searchField.bottom
        anchors.topMargin: Theme.spacingM
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: hintText.top
        anchors.bottomMargin: Theme.spacingM
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        DankFlickable {
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            clip: true
            contentHeight: deviceCol.height

            Column {
                id: deviceCol
                width: parent.width
                spacing: Theme.spacingXS

                Repeater {
                    model: tab.visibleDevices

                    DeviceRow {
                        required property var modelData
                        width: parent.width
                        device: modelData
                        showDetails: true
                        onActivated: TailscaleService.copyDevice(modelData)
                    }
                }

                StyledText {
                    visible: tab.visibleDevices.length === 0
                    text: TailscaleService.statusReady ? "No devices found" : "Loading…"
                    color: Theme.surfaceVariantText
                }
            }
        }
    }

    StyledText {
        id: hintText
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Click a device to copy its " + (TailscaleService.copyField === "dns" ? "MagicDNS name" : "Tailscale IP")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }
}
