pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.servicespanel.core

Item {
    id: root

    required property ScreenState screenState

    readonly property int padding: Tokens.padding.large

    implicitWidth: listWrapper.width + padding * 2
    implicitHeight: searchWrapper.height + listWrapper.height + padding * 2

    Item {
        id: listWrapper

        implicitWidth: list.width
        implicitHeight: list.height + root.padding

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: searchWrapper.top
        anchors.bottomMargin: root.padding

        ServiceList {
            id: list

            anchors.top: parent.top
            anchors.topMargin: root.padding / 2
            anchors.horizontalCenter: parent.horizontalCenter

            search: search
        }
    }

    StyledRect {
        id: searchWrapper

        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)
        radius: Tokens.rounding.full
        border.width: 1
        border.color: Colours.tPalette.m3outlineVariant

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.padding

        implicitHeight: Math.max(searchIcon.implicitHeight, search.implicitHeight, reloadIcon.implicitHeight)

        MaterialIcon {
            id: searchIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: root.padding

            text: "deployed_code"
            fontStyle: Tokens.font.icon.medium
            color: Colours.tPalette.m3onSurfaceVariant
        }

        StyledTextField {
            id: search

            anchors.left: searchIcon.right
            anchors.right: reloadIcon.left
            anchors.leftMargin: Tokens.spacing.small
            anchors.rightMargin: Tokens.spacing.small

            topPadding: Tokens.padding.medium
            bottomPadding: Tokens.padding.medium

            placeholderText: Tr.tr("Search services…")

            onAccepted: list.currentItem?.triggerPrimaryAction()

            Keys.onUpPressed: list.decrementCurrentIndex()
            Keys.onDownPressed: list.incrementCurrentIndex()
            Keys.onEscapePressed: root.screenState.services = false

            Component.onCompleted: forceActiveFocus()

            Connections {
                function onServicesChanged(): void {
                    if (!root.screenState.services)
                        search.text = "";
                    else
                        search.forceActiveFocus();
                }

                target: root.screenState
            }
        }

        MaterialIcon {
            id: reloadIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: root.padding

            text: "refresh"
            fontStyle: Tokens.font.icon.medium
            color: reloadMouse.pressed ? Qt.alpha(Colours.tPalette.m3onSurfaceVariant, 0.7) : Colours.tPalette.m3onSurfaceVariant

            MouseArea {
                id: reloadMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onClicked: ServiceOrchestrator.refreshVisible()
            }
        }
    }
}
