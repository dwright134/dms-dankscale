import QtQuick
import qs.Common
import qs.Widgets

// Extra settings for the popout's exit node settings card.
StyledRect {
    id: menu

    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHighest
    border.width: 1
    border.color: Theme.outlineMedium
    height: menuCol.height + Theme.spacingS * 2

    Column {
        id: menuCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacingS
        spacing: 2

        DankToggle {
            width: parent.width
            text: "Allow local network access"
            checked: TailscaleService.exitNodeAllowLan
            onToggled: checked => TailscaleService.setExitNodeAllowLan(checked)
        }

        DankToggle {
            width: parent.width
            text: "Run this device as an exit node"
            checked: TailscaleService.advertisesExitNode
            onToggled: checked => TailscaleService.setAdvertiseExitNode(checked)
        }
    }
}
