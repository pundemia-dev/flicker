import QtQuick

// Drum-roll text (Apple numericText-style): on a text change only the
// characters that differ roll — the old glyph slides out and fades, the new
// one slides in from the opposite side — the rest stays put.
// Slots are matched from the RIGHT (Row RightToLeft, delegate index 0 =
// last char), so units/suffixes keep their place when the length changes
// ("9%" -> "10%": "%" still, "9"->"0" rolls, "1" rolls in on the left).
// Direction (direction: 0 = auto): numeric value increased (or
// non-numeric) -> roll UP (new glyph rises from below), decreased -> roll
// DOWN (user-confirmed mapping; the first guess was inverted). Motion is a Spring per slot
// (movement = springs, spec); slot width springs with it, so the total
// width morphs instead of jumping. Slots never shrink in count: a vanished
// leading char rolls out to an empty, zero-width slot.
Item {
    id: root

    property string text: ""
    property color color: "#E9ECF1"
    property real pixelSize: 12
    property int weight: Font.Normal
    property string family: "SF Pro Display"
    // Tabular digits: every digit has the same advance, so a rolling digit
    // never changes the slot width (no horizontal jitter).
    property bool tabular: true
    // 0 = auto (numeric compare); 1 = roll down; -1 = roll up.
    property int direction: 0
    // Roll distance as a fraction of the line height.
    property real travel: 0.6
    property real stiffness: 5
    property real damp: 0.5

    property string _shown: ""
    property int _dir: 1
    property int _count: 0

    implicitWidth: row.implicitWidth
    implicitHeight: fm.height

    function _num(s: string): real {
        const m = String(s).replace(/[^\d.,-]/g, "").replace(",", ".");
        return m === "" ? NaN : Number(m);
    }
    // Direction first, then the slot count, then the text (delegates react
    // to _shown and read _dir at that moment). On creation the text is set
    // before the count, so the initial value appears without a roll.
    function _apply(initial: bool): void {
        const a = root._num(root._shown), b = root._num(root.text);
        root._dir = root.direction !== 0 ? root.direction : (isFinite(a) && isFinite(b) && b < a ? 1 : -1);
        if (initial)
            root._shown = root.text;
        root._count = Math.max(root._count, root.text.length);
        root._shown = root.text;
    }
    onTextChanged: root._apply(false)
    Component.onCompleted: root._apply(true)

    FontMetrics {
        id: fm
        font.family: root.family
        font.pixelSize: root.pixelSize
        font.weight: root.weight
    }

    Row {
        id: row
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        layoutDirection: Qt.RightToLeft

        Repeater {
            model: root._count
            delegate: Item {
                id: slot
                required property int index
                readonly property string ch: {
                    const i = root._shown.length - 1 - slot.index;
                    return i >= 0 ? root._shown.charAt(i) : "";
                }
                property string cur: ""
                property string prev: ""
                property int dir: 1
                property real p: 1
                readonly property real q: Math.max(0, Math.min(1, slot.p))
                readonly property real dist: fm.height * root.travel

                Component.onCompleted: slot.cur = slot.ch
                onChChanged: {
                    if (slot.ch === slot.cur)
                        return;
                    slot.prev = slot.cur;
                    slot.cur = slot.ch;
                    slot.dir = root._dir;
                    slot.p = 0;
                    roll.restart();
                }

                width: prevText.implicitWidth + (curText.implicitWidth - prevText.implicitWidth) * slot.q
                height: fm.height

                Spring {
                    id: roll
                    target: slot
                    property: "p"
                    from: 0
                    to: 1
                    stiffness: root.stiffness
                    damp: root.damp
                    eps: 0.005
                }

                // Outgoing glyph: slides away along dir, fades out early.
                Text {
                    id: prevText
                    x: (slot.width - implicitWidth) / 2
                    y: slot.dir * slot.dist * slot.p
                    visible: slot.p < 1 && slot.prev !== ""
                    opacity: Math.max(0, 1 - slot.q * 1.6)
                    scale: 1 - 0.25 * slot.q
                    text: slot.prev
                    color: root.color
                    font.family: root.family
                    font.pixelSize: root.pixelSize
                    font.weight: root.weight
                    font.features: root.tabular ? { "tnum": 1 } : {}
                }
                // Incoming glyph: arrives from the opposite side.
                Text {
                    id: curText
                    x: (slot.width - implicitWidth) / 2
                    y: -slot.dir * slot.dist * (1 - slot.p)
                    opacity: Math.min(1, slot.q * 1.4)
                    scale: 0.75 + 0.25 * slot.q
                    text: slot.cur
                    color: root.color
                    font.family: root.family
                    font.pixelSize: root.pixelSize
                    font.weight: root.weight
                    font.features: root.tabular ? { "tnum": 1 } : {}
                }
            }
        }
    }
}
