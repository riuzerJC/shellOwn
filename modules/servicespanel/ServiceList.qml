pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.servicespanel.items
import qs.modules.servicespanel.core

GridView {
    id: root

    required property StyledTextField search

    // Frozen in T1: five 179 px cards on a 1920x1080 display at scale 1, with
    // four 8 px gaps between them. Panel width = 5*card + 4*spacing + 2*padding.
    readonly property int columns: 5
    readonly property int cardSize: 179
    readonly property int cellSpacing: Tokens.spacing.small
    // A GridView cell is `cardSize + cellSpacing` wide, so the viewport needs one
    // extra `cellSpacing` beyond the drawn cards for the fifth column to fit.
    readonly property int cardsWidth: columns * cardSize + (columns - 1) * cellSpacing
    readonly property int rows: Math.ceil(count / columns)
    readonly property int maxVisibleRows: 4
    readonly property int visibleRows: Math.min(rows, maxVisibleRows)

    model: ServiceOrchestrator.query(root.search.text)
    cellWidth: cardSize + cellSpacing
    cellHeight: cardSize + cellSpacing
    implicitWidth: cardsWidth + cellSpacing
    implicitHeight: visibleRows <= 0 ? 0 : visibleRows * cardSize + (visibleRows - 1) * cellSpacing
    clip: true

    preferredHighlightBegin: 0
    preferredHighlightEnd: height
    highlightRangeMode: GridView.ApplyRange
    highlightFollowsCurrentItem: false

    highlight: StyledRect {
        radius: Tokens.rounding.medium
        color: Colours.tPalette.m3primary
        opacity: 0.12

        x: root.currentItem?.x ?? 0
        y: root.currentItem?.y ?? 0
        implicitWidth: root.currentItem ? root.cardSize : 0
        implicitHeight: root.currentItem ? root.cardSize : 0

        Behavior on x {
            Anim {
                type: Anim.DefaultSpatial
            }
        }

        Behavior on y {
            Anim {
                type: Anim.DefaultSpatial
            }
        }
    }

    delegate: Item {
        id: cell

        required property var modelData

        function triggerPrimaryAction(): void {
            card.triggerPrimaryAction();
        }

        width: root.cardSize
        height: root.cardSize

        ServiceItem {
            id: card

            list: root
            modelData: cell.modelData
            height: cell.height
        }
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

    move: Transition {
        Anim {
            properties: "x,y"
        }
        Anim {
            properties: "opacity,scale"
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

    displaced: Transition {
        Anim {
            properties: "x,y"
        }
        Anim {
            properties: "opacity,scale"
            to: 1
        }
    }
}
