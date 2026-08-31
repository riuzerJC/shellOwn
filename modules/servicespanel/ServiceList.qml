pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.servicespanel.items
import qs.modules.servicespanel.core

StyledListView {
    id: root

    required property StyledTextField search

    model: ServiceOrchestrator.query(root.search.text)
    spacing: Tokens.spacing.small
    orientation: Qt.Vertical
    implicitWidth: 460
    implicitHeight: Math.min(Math.max((64 + spacing) * Math.min(6, count) - spacing, 180), 480)

    preferredHighlightBegin: 0
    preferredHighlightEnd: height
    highlightRangeMode: ListView.ApplyRange
    highlightFollowsCurrentItem: false

    highlight: StyledRect {
        radius: Tokens.rounding.medium
        color: Colours.tPalette.m3primary
        opacity: 0.12

        y: root.currentItem?.y ?? 0
        implicitWidth: root.width
        implicitHeight: root.currentItem?.implicitHeight ?? 0

        Behavior on y {
            Anim {
                type: Anim.DefaultSpatial
            }
        }
    }

    delegate: ServiceItem {
        list: root
    }

    StyledScrollBar.vertical: StyledScrollBar {
        flickable: root
    }

    add: Transition {
        enabled: true

        Anim {
            properties: "opacity,scale"
            from: 0
            to: 1
        }
    }

    remove: Transition {
        enabled: true

        Anim {
            properties: "opacity,scale"
            from: 1
            to: 0
        }
    }

    move: Transition {
        Anim {
            property: "y"
        }
        Anim {
            properties: "opacity,scale"
            to: 1
        }
    }
}
