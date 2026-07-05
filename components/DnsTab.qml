import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: tab

    // A label/value line inside the status card.
    component InfoRow: Row {
        property string label: ""
        property string value: ""
        property color valueColor: Theme.surfaceText

        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            width: 120
            text: parent.label
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        StyledText {
            width: parent.width - 120 - Theme.spacingS
            text: parent.value
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: parent.valueColor
        }
    }

    DankFlickable {
        anchors.fill: parent
        clip: true
        contentHeight: col.height

        Column {
            id: col
            width: parent.width
            spacing: Theme.spacingM

            // "Use Tailscale DNS" (--accept-dns) — the one writable DNS pref.
            StyledRect {
                width: parent.width
                height: acceptCol.height + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                Column {
                    id: acceptCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Theme.spacingS
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS

                    DankToggle {
                        width: parent.width
                        text: "Use Tailscale DNS"
                        description: "Apply the DNS configuration from your tailnet (MagicDNS, split DNS, search domains). Off reverts to the system default resolver."
                        checked: TailscaleService.acceptDns
                        onToggled: checked => TailscaleService.setAcceptDns(checked)
                    }
                }
            }

            // Current DNS configuration pushed by the coordination server.
            StyledText {
                text: "DNS configuration"
                font.weight: Font.Medium
            }

            StyledRect {
                width: parent.width
                height: statusCol.height + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                Column {
                    id: statusCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    InfoRow {
                        label: "MagicDNS"
                        value: TailscaleService.magicDnsEnabled ? "Enabled tailnet-wide" : "Disabled tailnet-wide"
                        valueColor: TailscaleService.magicDnsEnabled ? Theme.primary : Theme.surfaceVariantText
                    }

                    InfoRow {
                        visible: TailscaleService.magicDnsSuffix !== ""
                        label: "MagicDNS suffix"
                        value: TailscaleService.magicDnsSuffix
                    }

                    InfoRow {
                        visible: TailscaleService.dnsSelfName !== ""
                        label: "This device"
                        value: TailscaleService.dnsSelfName
                    }

                    InfoRow {
                        label: "Search domains"
                        value: TailscaleService.dnsSearchDomains.length > 0 ? TailscaleService.dnsSearchDomains.join(", ") : "None"
                    }

                    InfoRow {
                        label: "Split DNS"
                        value: TailscaleService.dnsSplitRoutes.length > 0 ? "" : "None"
                        visible: TailscaleService.dnsSplitRoutes.length === 0
                    }

                    // Split-DNS routes get their own rows so each domain and its
                    // resolvers are readable.
                    Repeater {
                        model: TailscaleService.dnsSplitRoutes

                        InfoRow {
                            required property var modelData
                            label: modelData.domain
                            value: modelData.resolvers
                        }
                    }

                    StyledText {
                        visible: !TailscaleService.dnsStatusReady
                        text: "Loading…"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }

            // DNS lookup tool (tailscale dns query).
            StyledText {
                text: "DNS lookup"
                font.weight: Font.Medium
            }

            StyledRect {
                width: parent.width
                height: lookupCol.height + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                Column {
                    id: lookupCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    StyledText {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Resolve a name through the tailnet resolver (100.100.100.100). Optionally set a record type (A, AAAA, CNAME, MX, TXT…)."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingS

                        DankTextField {
                            id: nameField
                            width: parent.width - typeField.width - lookupButton.width - Theme.spacingS * 2
                            placeholderText: "host name or FQDN"
                            onAccepted: TailscaleService.runDnsQuery(nameField.text, typeField.text)
                        }

                        DankTextField {
                            id: typeField
                            width: 72
                            placeholderText: "A"
                            onAccepted: TailscaleService.runDnsQuery(nameField.text, typeField.text)
                        }

                        DankButton {
                            id: lookupButton
                            anchors.verticalCenter: nameField.verticalCenter
                            text: "Look up"
                            enabled: !TailscaleService.dnsQuerying && nameField.text.trim().length > 0
                            onClicked: TailscaleService.runDnsQuery(nameField.text, typeField.text)
                        }
                    }

                    StyledRect {
                        visible: TailscaleService.dnsQuerying || TailscaleService.dnsQueryResult !== ""
                        width: parent.width
                        height: resultCol.height + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainer

                        Column {
                            id: resultCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingXS

                            // Header with a clear button — only once a result is in.
                            Item {
                                width: parent.width
                                height: 24
                                visible: !TailscaleService.dnsQuerying && TailscaleService.dnsQueryResult !== ""

                                StyledText {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Result"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: Theme.surfaceVariantText
                                }

                                DankActionButton {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    buttonSize: 24
                                    iconName: "close"
                                    iconColor: Theme.surfaceVariantText
                                    tooltipText: "Clear result"
                                    onClicked: TailscaleService.clearDnsQuery()
                                }
                            }

                            StyledText {
                                id: resultText
                                width: parent.width
                                wrapMode: Text.Wrap
                                font.family: "monospace"
                                font.pixelSize: Theme.fontSizeSmall
                                text: TailscaleService.dnsQuerying ? "Querying…" : TailscaleService.dnsQueryResult
                                color: Theme.surfaceText
                            }
                        }
                    }
                }
            }
        }
    }
}
