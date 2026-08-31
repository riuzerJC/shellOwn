pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

Variants {
    model: Quickshell.screens

    delegate: PolkitDialog {
        required property ShellScreen modelData

        screen: modelData
    }
}
