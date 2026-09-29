import QtQuick
import "../../../components"

// Small dim section header shared by all cards ("Погода", "Батарея", ...).
// Bare Text resolves to the themed components/Text (SF Pro Display).
Text {
    property var theme: null
    property var dash: null
    property string label: ""

    text: label
    color: theme?.cardDim ?? "#99EBEBF5"
    font.pixelSize: dash?.titleSize ?? 13
    font.weight: Font.DemiBold
}
