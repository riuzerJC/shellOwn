pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.appcatalog.services

Item {
    id: root

    required property ScreenState screenState


    readonly property int padding: Tokens.padding.large
    readonly property int cardWidth: 620
    readonly property var statusLabels: ({
            installed: Tr.tr("Installed"),
            missing: Tr.tr("Missing"),
            unknown: Catalog.resolvingInstalled ? Tr.tr("Checking") : Tr.tr("Unknown")
        })
    readonly property var typeFilters: ["all", "gui", "tui", "cli"]
    readonly property var statusFilters: ["all", "installed", "missing"]

    function setTypeFilter(type: string): void {
        Catalog.setFilters(search.text, type, Catalog.statusFilter, []);
    }

    function setStatusFilter(status: string): void {
        Catalog.setFilters(search.text, Catalog.typeFilter, status, []);
    }

    function closeCatalog(): void {
        root.screenState.appCatalog = false;
    }

    implicitWidth: cardWidth + padding * 2
    implicitHeight: Math.min(panel.implicitHeight + padding * 2, 640)

    Keys.onEscapePressed: closeCatalog()

    StyledRect {
        id: panel

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.padding

        implicitHeight: content.implicitHeight + root.padding * 2

        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainer

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.padding
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                StyledRect {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 48
                    implicitHeight: 48
                    radius: Tokens.rounding.large
                    color: Colours.palette.m3primaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "apps"
                        color: Colours.palette.m3onPrimaryContainer
                        fontStyle: Tokens.font.icon.large
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Apps & TUIs")
                        font: Tokens.font.title.large
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Curated applications and terminal tools")
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurfaceVariant
                        wrapMode: Text.WordWrap
                    }
                }

                IconButton {
                    icon: "close"
                    isToggle: false
                    type: IconButton.Text
                    inactiveOnColour: Colours.palette.m3onSurfaceVariant
                    onClicked: root.closeCatalog()
                }
            }

            StyledTextField {
                id: search

                Layout.fillWidth: true
                placeholderText: Tr.tr("Search apps, tools, tags, or packages")
                leadingIcon: "search"
                type: StyledTextField.Filled

                onTextChanged: Catalog.setFilters(text, Catalog.typeFilter, Catalog.statusFilter, [])
                Keys.onEscapePressed: root.closeCatalog()
                Component.onCompleted: forceActiveFocus()

                Connections {
                    function onAppCatalogChanged(): void {
                        if (!root.screenState.appCatalog) {
                            search.text = "";
                            Catalog.setFilters("", "all", "all", []);
                        } else {
                            search.forceActiveFocus();
                        }
                    }

                    target: root.screenState
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Repeater {
                    model: root.typeFilters
                    delegate: TextButton {
                        required property string modelData
                        text: modelData === "all" ? Tr.tr("All") : modelData.toUpperCase()
                        isToggle: true
                        checked: Catalog.typeFilter === modelData
                        type: TextButton.Tonal
                        onClicked: root.setTypeFilter(modelData)
                    }
                }

                Repeater {
                    model: root.statusFilters
                    delegate: TextButton {
                        required property string modelData
                        text: modelData === "all" ? Tr.tr("Any status") : root.statusLabels[modelData]
                        isToggle: true
                        checked: Catalog.statusFilter === modelData
                        type: TextButton.Tonal
                        onClicked: root.setStatusFilter(modelData)
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: Math.min(catalogList.contentHeight + Tokens.spacing.small * 2, 360)
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainerLow
                clip: true

                ListView {
                    id: catalogList

                    anchors.fill: parent
                    anchors.margins: Tokens.spacing.small
                    model: Catalog.filteredEntries
                    spacing: Tokens.spacing.small
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 200

                    delegate: CatalogEntryCard {
                        required property var modelData
                        width: catalogList.width
                        entry: modelData
                    }

                    footer: StyledText {
                        width: catalogList.width
                        padding: root.padding
                        visible: Catalog.loaded && Catalog.filteredEntries.length === 0
                        text: Catalog.entries.length === 0 ? Tr.tr("No catalog entries are available.") : Tr.tr("No entries match the current search or filters.")
                        color: Colours.palette.m3onSurfaceVariant
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: Catalog.warningText || Catalog.errorText || Catalog.invalidCount > 0
                text: Catalog.errorText || Catalog.warningText || Tr.tr("%1 invalid catalog entries were skipped.").arg(Catalog.invalidCount)
                color: Catalog.errorText ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                wrapMode: Text.WordWrap
            }
        }
    }

    component CatalogEntryCard: StyledRect {
        required property var entry

        readonly property string etype: entry?.type ?? ""
        readonly property string ename: entry?.name ?? ""
        readonly property string edesc: entry?.description ?? ""
        readonly property var etags: entry?.tags ?? []
        readonly property string eicon: entry?.icon ?? "apps"

        readonly property string status: Catalog.statusFor(entry)


        implicitHeight: row.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainerHigh

        StateLayer {}

        RowLayout {
            id: row

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            Item {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 36
                implicitHeight: 36

                Loader {
                    anchors.fill: parent
                    asynchronous: true
                    sourceComponent: etype === "tui" ? tuiIcon : guiIcon
                }

                Component {
                    id: tuiIcon
                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "terminal"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.medium
                    }
                }

                Component {
                    id: guiIcon
                    IconImage {
                        asynchronous: true
                        source: Quickshell.iconPath(eicon, "image-missing")
                        implicitSize: 36
                        anchors.centerIn: parent
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: ename
                        font: Tokens.font.title.small
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        text: etype.toUpperCase()
                        font: Tokens.font.label.small
                        color: Colours.palette.m3primary
                    }

                    StyledText {
                        text: root.statusLabels[status] ?? Tr.tr("Unknown")
                        font: Tokens.font.label.small
                        color: status === "missing" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: edesc
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: etags.length > 0
                    text: etags.map(tag => `#${tag}`).join("  ")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                }
            }
        }
    }
}
