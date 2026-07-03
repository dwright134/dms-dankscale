import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: settingsRoot

    pluginId: "tailscale"

    StyledText {
        width: parent.width
        text: "Tailscale"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Bar widget and manager for your Tailscale network. Uses the tailscale CLI — make sure your user is the Tailscale operator (sudo tailscale set --operator=$USER) so no root prompts are needed."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

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
