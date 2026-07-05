import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Modules.Settings.Widgets

PluginSettings {
    id: settingsRoot

    pluginId: "tailscaleControl"

    SettingsCard {
        title: "Widget"
        iconName: "tune"

        SelectionSetting {
            settingKey: "pollSeconds"
            label: "Refresh interval"
            description: "How often the widget polls tailscale status"
            options: [
                { label: "2 seconds", value: "2" },
                { label: "5 seconds", value: "5" },
                { label: "10 seconds", value: "10" },
                { label: "30 seconds", value: "30" }
            ]
            defaultValue: "5"
        }

        SelectionSetting {
            settingKey: "copyField"
            label: "Click copies"
            description: "What gets copied to the clipboard when you click a device"
            options: [
                { label: "Tailscale IPv4", value: "ip" },
                { label: "MagicDNS name", value: "dns" }
            ]
            defaultValue: "ip"
        }

        ToggleSetting {
            settingKey: "showOffline"
            label: "Show offline devices"
            description: "Include offline devices in the bar drop-down list"
            defaultValue: true
        }
    }

    SettingsCard {
        title: "Requirements"
        iconName: "info"

        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Everything is driven by the tailscale CLI — make sure your user is the Tailscale operator so no root prompts are needed:"
            color: Theme.surfaceVariantText
        }

        StyledRect {
            width: parent.width
            height: operatorCmd.height + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceVariant

            StyledText {
                id: operatorCmd
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                text: "sudo tailscale set --operator=$USER"
                isMonospace: true
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
