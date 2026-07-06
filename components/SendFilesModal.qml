import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Modals.FileBrowser
import qs.Widgets

DankModal {
    id: modal

    // The device files are sent to. Set by the caller before open().
    property var targetDevice: null

    // Staged file paths (plain array so appends/removes are simple). Cleared
    // whenever the dialog opens or closes.
    property var stagedFiles: []

    readonly property string targetName: targetDevice ? (targetDevice.name || targetDevice.dnsName || targetDevice.ip) : ""

    function addFile(path) {
        const clean = (path || "").replace(/^file:\/\//, "");
        if (!clean || stagedFiles.indexOf(clean) !== -1)
            return;
        stagedFiles = stagedFiles.concat([clean]);
    }

    function removeFile(path) {
        stagedFiles = stagedFiles.filter(p => p !== path);
    }

    function baseName(path) {
        const p = (path || "").replace(/\/+$/, "");
        return p.substring(p.lastIndexOf("/") + 1);
    }

    layerNamespace: "dms:tailscale-send"
    modalWidth: 460
    modalHeight: 520
    enableShadow: true
    // No dimming scrim behind the modal — click-outside-to-close still works
    // (it's a separate click catcher, not the background).
    showBackground: false
    closeOnEscapeKey: true
    closeOnBackgroundClick: true
    // Keep the content (and the staged list) alive while we hide the modal to
    // show the file picker (see below), so it comes back intact.
    keepContentLoaded: true
    onBackgroundClicked: close()

    // The staged list is reset by openSend() in the widget when a fresh send is
    // started — deliberately NOT on open/close here, since we close-and-reopen
    // this modal around the file picker and must not wipe the list mid-flow.

    // The picker is a FloatingWindow (xdg-toplevel); this modal is a layer-shell
    // surface that renders above it, so the picker would otherwise open behind
    // the modal. Hide this modal while the picker is up, and bring it back when
    // the picker closes (whether a file was chosen or cancelled).
    FileBrowserModal {
        id: filePicker
        parentModal: modal
        browserTitle: "Select file to send"
        browserIcon: "upload_file"
        filterExtensions: ["*.*"]
        onFileSelected: path => modal.addFile(path)
        onDialogClosed: modal.open()
    }

    content: Component {
        Item {
            anchors.fill: parent

            // Header
            Item {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: Theme.spacingL
                anchors.leftMargin: Theme.spacingL
                anchors.rightMargin: Theme.spacingL
                height: 40

                DankIcon {
                    id: headerIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    name: "send"
                    size: Theme.iconSize
                    color: Theme.primary
                }

                Column {
                    anchors.left: headerIcon.right
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: headerClose.left
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    StyledText {
                        text: "Send files"
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                    }

                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: modal.targetName ? "to " + modal.targetName : ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }

                DankActionButton {
                    id: headerClose
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "close"
                    iconColor: Theme.surfaceVariantText
                    onClicked: modal.close()
                }
            }

            DankButton {
                id: addButton
                anchors.top: header.bottom
                anchors.topMargin: Theme.spacingM
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Theme.spacingL
                anchors.rightMargin: Theme.spacingL
                text: "Add files"
                iconName: "add"
                onClicked: {
                    modal.instantClose();
                    filePicker.open();
                }
            }

            // Staged file list
            StyledRect {
                id: listCard
                anchors.top: addButton.bottom
                anchors.topMargin: Theme.spacingM
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: footer.top
                anchors.leftMargin: Theme.spacingL
                anchors.rightMargin: Theme.spacingL
                anchors.bottomMargin: Theme.spacingM
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                DankFlickable {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingXS
                    clip: true
                    contentHeight: fileCol.height

                    Column {
                        id: fileCol
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: modal.stagedFiles

                            Rectangle {
                                required property var modelData
                                width: parent.width
                                height: 40
                                radius: Theme.cornerRadius
                                color: rowHover.containsMouse ? Theme.surfaceHover : "transparent"

                                DankIcon {
                                    id: fileIcon
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "draft"
                                    size: Theme.iconSize - 6
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    anchors.left: fileIcon.right
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.right: removeBtn.left
                                    anchors.rightMargin: Theme.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideMiddle
                                    text: modal.baseName(modelData)
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                MouseArea {
                                    id: rowHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                }

                                DankActionButton {
                                    id: removeBtn
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.spacingXS
                                    anchors.verticalCenter: parent.verticalCenter
                                    buttonSize: 28
                                    iconName: "close"
                                    iconColor: Theme.surfaceVariantText
                                    tooltipText: "Remove"
                                    onClicked: modal.removeFile(modelData)
                                }
                            }
                        }

                        StyledText {
                            visible: modal.stagedFiles.length === 0
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            topPadding: Theme.spacingM
                            text: "No files added yet"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }

            // Footer actions
            Row {
                id: footer
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.bottomMargin: Theme.spacingL
                anchors.rightMargin: Theme.spacingL
                spacing: Theme.spacingM

                DankButton {
                    text: "Cancel"
                    backgroundColor: Theme.surfaceContainerHigh
                    textColor: Theme.surfaceText
                    onClicked: modal.close()
                }

                DankButton {
                    text: modal.stagedFiles.length > 0 ? "Send " + modal.stagedFiles.length : "Send"
                    iconName: "send"
                    enabled: modal.stagedFiles.length > 0 && !TailscaleService.sending
                    onClicked: {
                        TailscaleService.sendToDevice(modal.targetDevice, modal.stagedFiles);
                        modal.close();
                    }
                }
            }
        }
    }
}
