import QtQuick
import "../../../components"
import "../../../config"

// Month calendar (2x2, iOS month widget): red month name, Monday-first
// weekday initials, the month's dates (5 or 6 rows, row height shares the
// leftover space), today on a red disc, weekends dimmed. No backend.
DashboardCard {
    id: root
    required property var clock

    readonly property real _pad: (dash?.cardPadding) ?? 10
    readonly property real _fs: Math.max(11, Math.round((root.width - 2 * _pad) / 7 * 0.5))

    readonly property date now: (clock?.date) ?? new Date()
    readonly property int year: root.now.getFullYear()
    readonly property int month: root.now.getMonth()
    readonly property int today: root.now.getDate()
    // Monday-first one-letter weekday names in the UI language.
    readonly property var _wd: [1, 2, 3, 4, 5, 6, 0].map(d => I18n.locale.standaloneDayName(d, Locale.NarrowFormat).toUpperCase())

    // Monday-first offset of the 1st and the month length.
    readonly property int lead: (new Date(root.year, root.month, 1).getDay() + 6) % 7
    readonly property int days: new Date(root.year, root.month + 1, 0).getDate()
    readonly property int rows: Math.ceil((root.lead + root.days) / 7)

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: root._pad

        readonly property real colW: body.width / 7

        Text {
            id: title
            text: I18n.locale.standaloneMonthName(root.month, Locale.LongFormat).toUpperCase()
            color: root.theme?.accentRed ?? "#E4483E"
            font.pixelSize: (root.dash?.titleSize ?? 13) - 2
            font.weight: Font.Bold
            font.letterSpacing: 0.5
            x: 4
        }

        Row {
            id: weekdays
            anchors.top: title.bottom
            anchors.topMargin: 5
            Repeater {
                model: root._wd
                delegate: Text {
                    required property string modelData
                    required property int index
                    width: body.colW
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: root.theme?.cardDim ?? "#99EBEBF5"
                    font.pixelSize: root._fs - 1
                    font.weight: Font.DemiBold
                    opacity: index >= 5 ? 0.6 : 1
                }
            }
        }

        Grid {
            id: dates
            anchors.top: weekdays.bottom
            anchors.topMargin: 2.5
            columns: 7
            readonly property real cellH: (body.height - title.height - weekdays.height - 8) / root.rows

            Repeater {
                model: root.rows * 7
                delegate: Item {
                    id: cell
                    required property int index
                    readonly property int day: cell.index - root.lead + 1
                    readonly property bool inMonth: cell.day >= 1 && cell.day <= root.days
                    readonly property bool isToday: cell.day === root.today
                    width: body.colW
                    height: dates.cellH

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(cell.width, cell.height) - 1
                        height: width
                        radius: width / 2
                        color: root.theme?.accentRed ?? "#E4483E"
                        visible: cell.inMonth && cell.isToday
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: cell.inMonth
                        text: cell.day
                        color: "white"
                        opacity: cell.isToday ? 1 : (cell.index % 7 >= 5 ? 0.5 : 0.9)
                        font.pixelSize: root._fs
                        font.weight: cell.isToday ? Font.Bold : Font.Medium
                    }
                }
            }
        }
    }
}
