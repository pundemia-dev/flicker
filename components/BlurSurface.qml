import QtQuick

Rectangle {
    property bool blurEnabled: true
    property real blurStrength: 0
    color: blurEnabled ? Qt.rgba(1, 1, 1, 0.08 * blurStrength) : "transparent"
}
