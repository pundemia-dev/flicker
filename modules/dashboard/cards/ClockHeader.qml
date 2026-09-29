import QtQuick
import QtQuick.Layouts
import "../../../components"

// Fixed-height header block (1 unit tall) above the card grid.
// Content is vertically centered; dates are Russian regardless of locale.
Item {
    id: root
    required property var clock
    required property var theme
    required property var dash

    readonly property date now: (clock?.date) ?? new Date()
    readonly property var _days: ["Воскресенье", "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота"]
    readonly property var _months: ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    readonly property string dateStr: `${root._days[root.now.getDay()]}, ${root.now.getDate()} ${root._months[root.now.getMonth()]}`
    readonly property string timeStr: `${String(root.now.getHours()).padStart(2, "0")}:${String(root.now.getMinutes()).padStart(2, "0")}`

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            text: root.dateStr
            color: root.theme?.cardDim ?? "#99EBEBF5"
            font.pixelSize: root.dash?.headerDateSize ?? 15
        }
        Text {
            text: root.timeStr
            color: "white"
            font.pixelSize: root.dash?.headerTimeSize ?? 44
            font.weight: Font.DemiBold
        }
    }
}
