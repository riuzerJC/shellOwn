pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.modules.servicespanel.core

Item {
    id: root

    required property ScreenState screenState

    readonly property bool shouldBeActive: screenState.services

    property real offsetScale: shouldBeActive ? 0 : 1

    // Frozen in T1: 5 columns of 179 px cards, four 8 px gaps, two 16 px panel paddings.
    readonly property real panelWidth: 5 * 179 + 4 * Tokens.spacing.small + Tokens.padding.large * 2

    onShouldBeActiveChanged: {
        ServiceOrchestrator.setPanelVisible(shouldBeActive);

        if (shouldBeActive)
            implicitHeight = Qt.binding(() => content.implicitHeight);
        else
            implicitHeight = implicitHeight;
    }

    visible: offsetScale < 1
    anchors.bottomMargin: (-implicitHeight - 5) * offsetScale
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || panelWidth
    opacity: 1 - offsetScale

    Component.onCompleted: ServiceOrchestrator.setPanelVisible(shouldBeActive)

    Behavior on offsetScale {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    Loader {
        id: content

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        active: root.shouldBeActive || root.visible

        sourceComponent: Content {
            screenState: root.screenState
        }
    }
}
