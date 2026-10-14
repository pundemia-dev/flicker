import QtQuick
import "../../components"
import "../../config"

// Password field born from the island (user, Oct 2026). Starts as an exact
// copy of the island at its lock-time rect (LockScope.islandRects) showing
// the grab's crop of the bar, so the first frame has no seam; on `out` the bar
// content blur-fades, then (`fieldDelayMs`) the black body flies down over
// everything on springs into `slot` (a placeholder in the skin's column) and
// the dots / placeholder blur in. `out = false` (unlock) = the way back: the
// content leaves, the body flies home, the bar crop returns, `arrivedHome`.
// x/width (and y/height) share one spring, so the centre stays exact.
Item {
    id: root

    required property var cfg
    required property var pam
    // LockBackdrop.grabItem (the base grab); null = locked without a grab.
    property Item grabItem: null
    // Island rect at lock time (screen-local) or null (no island there).
    property var home: null
    property rect slot: Qt.rect(0, 0, 0, 0)
    property bool out: false

    signal arrivedHome

    // Text caret, field-local x: just past the last dot (the dot row is
    // centred and its width springs), the centre while empty. The keyboard
    // pill sits under it (LockKeyboardPill), like under a desktop caret.
    readonly property real caretX: root.width / 2 + (dots.width > 0 ? dots.width / 2 + (root.cfg.caretGap ?? 4) : 0)

    readonly property var homeRect: root.home ?? root.fallbackHome()
    function fallbackHome(): var {
        const w = root.cfg.fieldFallbackWidth ?? 78, h = Config.data.island?.height ?? 36;
        return { x: ((root.parent?.width ?? 0) - w) / 2, y: Config.data.island?.topMargin ?? 10, width: w, height: h, radius: h / 2 };
    }

    // Body geometry: plain targets set imperatively (springs never read an
    // animated value).
    property bool animate: false
    property real radius

    function place(r: var, animated: bool): void {
        root.animate = animated;
        root.x = r.x;
        root.y = r.y;
        root.width = r.width;
        root.height = r.height;
        root.radius = r.radius;
    }

    function fieldRect(): var {
        return { x: root.slot.x, y: root.slot.y, width: root.slot.width, height: root.slot.height, radius: root.slot.height / 2 };
    }

    readonly property bool atField: Math.abs(root.y - root.slot.y) < 2 && Math.abs(root.height - root.slot.height) < 2
    readonly property bool atHome: Math.abs(root.y - root.homeRect.y) < 1 && Math.abs(root.width - root.homeRect.width) < 1
        && Math.abs(root.height - root.homeRect.height) < 1

    // Initial bindings (broken by place()): the very first frame already sits
    // on the island, and Behaviors never run during creation.
    x: root.homeRect.x
    y: root.homeRect.y
    width: root.homeRect.width
    height: root.homeRect.height
    radius: root.homeRect.radius

    onOutChanged: {
        if (root.out) {
            flyTimer.restart();
        } else {
            flyTimer.stop();
            root.place(root.homeRect, true);
            homeCheck.restart();
        }
    }

    Timer {
        id: flyTimer
        interval: root.cfg.fieldDelayMs ?? 300
        onTriggered: root.place(root.fieldRect(), true)
    }

    // Home = the body back on the island rect and the bar crop faded in.
    Timer {
        id: homeCheck
        interval: 50
        repeat: true
        onTriggered: if (root.atHome && crop.p > 0.99) {
            homeCheck.stop();
            root.arrivedHome();
        }
    }

    Behavior on x { enabled: root.animate; Spring { stiffness: root.cfg.fieldStiffness ?? 3.5; damp: root.cfg.fieldDamping ?? 0.4 } }
    Behavior on y { enabled: root.animate; Spring { stiffness: root.cfg.fieldStiffness ?? 3.5; damp: root.cfg.fieldDamping ?? 0.4 } }
    Behavior on width { enabled: root.animate; Spring { stiffness: root.cfg.fieldStiffness ?? 3.5; damp: root.cfg.fieldDamping ?? 0.4 } }
    Behavior on height { enabled: root.animate; Spring { stiffness: root.cfg.fieldStiffness ?? 3.5; damp: root.cfg.fieldDamping ?? 0.4 } }
    Behavior on radius { enabled: root.animate; Spring { stiffness: root.cfg.fieldStiffness ?? 3.5; damp: root.cfg.fieldDamping ?? 0.4 } }

    // Wrong password: an under-damped kick sideways.
    property real shake: 0
    Behavior on shake { id: shakeSpring; Spring { stiffness: root.cfg.shakeStiffness ?? 6; damp: root.cfg.shakeDamping ?? 0.12; eps: 0.1 } }
    function kick(): void {
        shakeSpring.enabled = false;
        root.shake = root.cfg.shakePx ?? 14;
        shakeSpring.enabled = true;
        root.shake = 0;
    }
    transform: Translate { x: root.shake }

    Rectangle {
        anchors.fill: parent
        radius: Math.min(root.radius, width / 2, height / 2)
        color: root.cfg.fieldColor ?? "#000000"
        border.width: 1
        border.color: root.cfg.fieldRim ?? "#26FFFFFF"
    }

    // The bar as it was (raw grab crop of the island rect + holeMarginPx, so
    // the side arcs come along; the base grab has it all painted out): leaves
    // first on the way out, returns once the body is (nearly) home.
    FadeBlur {
        id: crop
        readonly property real m: root.cfg.holeMarginPx ?? 14
        readonly property real topY: Math.max(0, root.homeRect.y - crop.m)
        x: -crop.m
        y: crop.topY - root.homeRect.y
        width: root.homeRect.width + crop.m * 2
        height: root.homeRect.y + root.homeRect.height + crop.m - crop.topY
        visible: root.grabItem !== null
        shown: !root.out && (root.atHome || Math.abs(root.height - root.homeRect.height) < 3)

        ShaderEffectSource {
            anchors.fill: parent
            sourceItem: root.grabItem
            sourceRect: Qt.rect(root.homeRect.x - crop.m, crop.topY, crop.width, crop.height)
        }
    }

    FadeBlur {
        anchors.fill: parent
        shown: root.out && root.atField

        FadeBlur {
            anchors.fill: parent
            shown: root.pam.buffer.length === 0

            Text {
                anchors.centerIn: parent
                text: I18n.tr("Enter Password")
                color: root.cfg.fieldPlaceholderColor ?? "#8B93A3"
                font.pixelSize: root.cfg.fieldFontSize ?? 17
            }
        }

        LockDots {
            id: dots
            anchors.centerIn: parent
            cfg: root.cfg
            count: root.pam.buffer.length
            color: root.cfg.fieldDotColor ?? "#EDF1F8"
        }
    }
}
