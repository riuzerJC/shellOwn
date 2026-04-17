pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components

Item {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities

    readonly property bool configEnabled: Config.workspaceOverlay?.enabled !== false
    readonly property bool shouldBeActive: visibilities.workspaceOverlay && configEnabled

    property real offsetScale: shouldBeActive ? 0 : 1

    visible: shouldBeActive || offsetScale < 0.999
    anchors.topMargin: (-implicitHeight - 5) * offsetScale
    implicitWidth: content.active ? (content.implicitWidth || 960) : 0
    implicitHeight: content.active ? (content.implicitHeight || 620) : 0
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    Loader {
        id: content

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top

        active: root.shouldBeActive || root.offsetScale < 0.999
        asynchronous: true

        sourceComponent: Content {
            screen: root.screen
            visibilities: root.visibilities
        }
    }
}
