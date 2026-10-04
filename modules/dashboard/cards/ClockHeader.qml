import QtQuick
import "../../../components"

// Thin header strip above the card grid: time pinned left, date pinned
// right, sharing one baseline (no empty half-row next to a stacked block).
// Dates are Russian regardless of locale. The time label is also the
// shared-element slot "time": the bar clock flies in, grows to this
// label's colour/size/weight and docks; the own label hides meanwhile but
// keeps its box (the date's baseline anchor).
Item {
    id: root
    required property var clock
    required property var theme
    required property var dash

    readonly property date now: (clock?.date) ?? new Date()
    readonly property var _days: ["Воскресенье", "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота"]
    readonly property var _months: ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    readonly property string dateStr: `${root._days[root.now.getDay()]}, ${root.now.getDate()} ${root._months[root.now.getMonth()]}`
    readonly property Item timeSlot: time
    readonly property string timeStr: `${String(root.now.getHours()).padStart(2, "0")}:${String(root.now.getMinutes()).padStart(2, "0")}`

    // Slot wrapper: the docked element becomes its child, so only the own
    // label inside hides (hiding the slot would hide the guest too).
    Item {
        id: time
        property Item docked: null
        readonly property color color: timeText.color
        readonly property font font: timeText.font
        anchors.left: parent.left
        anchors.leftMargin: root.dash?.cardPadding ?? 10
        anchors.verticalCenter: parent.verticalCenter
        width: timeText.implicitWidth
        height: timeText.implicitHeight

        Text {
            id: timeText
            anchors.fill: parent
            visible: time.docked === null
            text: root.timeStr
            color: "white"
            font.pixelSize: root.dash?.headerTimeSize ?? 30
            font.weight: Font.DemiBold
        }
    }
    Text {
        id: dateText
        anchors.right: parent.right
        anchors.rightMargin: root.dash?.cardPadding ?? 10
        // Shared baseline with the time (inside the slot, not a sibling).
        anchors.top: time.top
        anchors.topMargin: timeText.baselineOffset - dateText.baselineOffset
        text: root.dateStr
        color: root.theme?.cardDim ?? "#99EBEBF5"
        font.pixelSize: root.dash?.headerDateSize ?? 15
    }
}
