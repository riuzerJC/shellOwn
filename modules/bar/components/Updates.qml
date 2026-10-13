import QtQuick
import Caelestia.Config
import qs.components
import qs.services as Services

Item {
    id: root

    required property var bar

    implicitWidth: content.implicitWidth + Tokens.padding.small
    implicitHeight: content.implicitHeight
    visible: Services.Updates.hasUpdates

    Row {
        id: content

        anchors.centerIn: parent
        spacing: Tokens.spacing.extraSmall

        MaterialIcon {
            id: icon

            anchors.verticalCenter: parent.verticalCenter
            animate: true
            text: "system_update_alt"
            color: Services.Colours.palette.m3primary
            fontStyle: Tokens.font.icon.builders.small.weight(Font.Bold).build()
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Services.Updates.actionableCount
            color: Services.Colours.palette.m3primary
            font: Tokens.font.body.builders.small.build()
        }
    }

    StateLayer {
        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: implicitHeight
        implicitHeight: content.implicitHeight + Tokens.padding.small
        radius: Tokens.rounding.full
        onClicked: {
            const popouts = root.bar.popouts;
            popouts.currentName = "updates";
            popouts.currentCenter = root.mapToItem(root.bar, 0, root.implicitHeight / 2).y;
            popouts.hasCurrent = true;
        }
    }
}
