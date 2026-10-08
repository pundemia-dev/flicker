import QtQuick
import "../../config"

// Common base of the drawn event glyphs. EventIcon sets `size`, `color`
// (the event tint), `args` (event glyphArgs), `theme`, and binds `ready`
// once the icon has faded in; `begin()` fires exactly once after that —
// glyphs start their reveal there (starting at creation ran it under the
// icon's blur-fade-in, invisible). Tunables: Config.data.glyphs.<glyphName>,
// falling back to glyphs.common (`p(key, default)`).
Item {
    id: base
    property real size: 18
    property color color: "#5AA9FF"
    property var args: ({})
    property var theme: null
    property string glyphName: ""
    property bool ready: false
    property bool begun: false
    signal begin

    readonly property var cfg: Config.data.glyphs?.[base.glyphName] ?? ({})
    readonly property var common: Config.data.glyphs?.common ?? ({})
    function p(key: string, def: var): var {
        const v = base.cfg?.[key];
        if (v !== undefined)
            return v;
        const c = base.common?.[key];
        return c !== undefined ? c : def;
    }
    function u(x: real): real {
        return x * base.size;
    }

    // Palette: the event tint as the family's vertical gradient; Apple-ish
    // device bodies in a light neutral gradient; dark ink for details.
    readonly property color fillTop: Qt.lighter(base.color, base.p("lighter", 1.18))
    readonly property color fillBottom: Qt.darker(base.color, base.p("darker", 1.45))
    readonly property color deviceTop: base.theme?.glyphDeviceTop ?? "#F5F6F8"
    readonly property color deviceBottom: base.theme?.glyphDeviceBottom ?? "#A9AFB9"
    readonly property color ink: base.theme?.glyphInk ?? "#16171B"
    readonly property real handoff: base.p("handoff", 0.08)
    readonly property real sheen: base.p("sheen", 0.32)

    width: base.size
    height: base.size

    onReadyChanged: base.tryBegin()
    Component.onCompleted: base.tryBegin()
    function tryBegin(): void {
        if (!base.ready || base.begun)
            return;
        base.begun = true;
        base.begin();
    }
}
