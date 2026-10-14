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
            font: Tokens.font.body.builders.small.scale(0.9).build()
        }
    }

    StateLayer {
        // The hover has to span the whole entry. The icon-only pattern from Power — a centred square
        // with a full radius — drew a circle that did not even cover the count sitting next to the icon.
        radius: Tokens.rounding.small
        onClicked: {
            const popouts = root.bar.popouts;
            popouts.currentName = "updates";
            popouts.currentCenter = root.mapToItem(root.bar, 0, root.implicitHeight / 2).y;
            popouts.hasCurrent = true;
        }
    }
}
