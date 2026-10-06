import QtQuick
import Quickshell
import "../../../components"
import "../../../config"

// Flappy-style mini-game: the Dino pterodactyl flaps through gaps between
// pillars. Flap: LMB / Space / ↑. Same deck contract as DinoGame.
Item {
    id: root

    readonly property string title: "Flappy Ptero"
    property int best: 0
    signal newBest(int value)

    focus: true

    property bool running: false
    property bool over: false
    property int score: 0

    readonly property real gravity: 1300
    readonly property real flapForce: -330
    readonly property real speed: 150
    readonly property real gap: 74
    readonly property real pillarW: 34
    readonly property real pillarSpacing: 170
    readonly property real birdX: 70
    readonly property real birdW: 34
    readonly property real birdH: 22
    readonly property real ceilY: 34
    readonly property real floorY: root.height - 22

    property real birdY: (root.ceilY + root.floorY) / 2
    property real vy: 0
    property real hover: 0
    // Pillars {x, gapY (gap centre), scored}; mutated in place + `tick`.
    property var pillars: []
    property int tick: 0

    readonly property string spriteDir: `file://${Quickshell.shellDir}/assets/dino/`

    function reset(): void {
        root.running = false;
        root.over = false;
        root.score = 0;
        root.vy = 0;
        root.birdY = (root.ceilY + root.floorY) / 2;
        root.pillars = [];
        root.tick++;
    }

    function start(): void {
        root.reset();
        root.running = true;
        root.flap();
    }

    function flap(): void {
        if (!root.running) {
            root.start();
            return;
        }
        root.vy = root.flapForce;
    }

    function press(button: int): void {
        if (button === Qt.LeftButton)
            root.flap();
    }

    function release(button: int): void {
    }

    function addPillar(x: real): void {
        const margin = root.gap / 2 + 12;
        const gapY = root.ceilY + margin + Math.random() * Math.max(0, root.floorY - root.ceilY - 2 * margin);
        root.pillars.push({ x: x, gapY: gapY, scored: false });
    }

    function gameOver(): void {
        root.running = false;
        root.over = true;
        if (root.score > root.best)
            root.newBest(root.score);
    }

    function step(dt: real): void {
        root.vy += root.gravity * dt;
        root.birdY += root.vy * dt;

        const dx = root.speed * dt;
        for (const p of root.pillars)
            p.x -= dx;
        while (root.pillars.length > 0 && root.pillars[0].x + root.pillarW < 0)
            root.pillars.shift();
        const last = root.pillars[root.pillars.length - 1];
        if (!last || last.x < root.width - root.pillarSpacing)
            root.addPillar(last ? last.x + root.pillarSpacing : root.width + 20);

        // Hitbox inset a little: the sprite has transparent wing tips.
        const l = root.birdX + 5, r = root.birdX + root.birdW - 5;
        const t = root.birdY + 4, b = root.birdY + root.birdH - 4;
        if (t < 0 || b > root.floorY) {
            root.gameOver();
        } else {
            for (const p of root.pillars) {
                if (!p.scored && p.x + root.pillarW < l) {
                    p.scored = true;
                    root.score++;
                }
                const inX = r > p.x && l < p.x + root.pillarW;
                const inGap = t > p.gapY - root.gap / 2 && b < p.gapY + root.gap / 2;
                if (inX && !inGap) {
                    root.gameOver();
                    break;
                }
            }
        }
        root.tick++;
    }

    FrameAnimation {
        running: root.running
        onTriggered: root.step(Math.min(0.05, frameTime))
    }
    // Idle bob before the first flap.
    FrameAnimation {
        running: !root.running && !root.over
        onTriggered: root.hover += frameTime
    }

    Keys.onPressed: event => {
        if (event.isAutoRepeat)
            return;
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Up || event.key === Qt.Key_W) {
            root.flap();
            event.accepted = true;
        }
    }

    // ── Scene ──
    Repeater {
        model: 4
        Item {
            id: pillar
            required property int index
            function f(key: string): var {
                return root.tick >= 0 ? (root.pillars[index]?.[key] ?? 0) : 0;
            }
            visible: root.tick >= 0 && index < root.pillars.length
            x: f("x")
            width: root.pillarW
            height: root.floorY

            Rectangle {
                width: parent.width
                y: -radius
                height: pillar.f("gapY") - root.gap / 2 + radius
                radius: 8
                color: "#2C2C2E"
                border.width: 1
                border.color: "#48484C"
            }
            Rectangle {
                width: parent.width
                y: pillar.f("gapY") + root.gap / 2
                height: root.floorY - y + radius
                radius: 8
                color: "#2C2C2E"
                border.width: 1
                border.color: "#48484C"
            }
        }
    }

    Rectangle {
        y: root.floorY
        width: parent.width
        height: 2
        color: "#E9ECF1"
        opacity: 0.45
    }

    Image {
        x: root.birdX
        y: root.running || root.over ? root.birdY : root.birdY + Math.sin(root.hover * 4) * 4
        width: root.birdW
        height: root.birdH
        source: root.spriteDir + "Chrome_Pterodactyl.png"
        // The sprite faces left; the bird flies right.
        mirror: true
        smooth: false
        fillMode: Image.PreserveAspectFit
        rotation: root.running || root.over ? Math.max(-25, Math.min(60, root.vy / 8)) : 0
    }

    Row {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 16
        anchors.topMargin: 12
        spacing: 10

        Text {
            text: "HI " + Math.max(root.best, root.over ? root.score : 0)
            font.family: "monospace"
            font.pixelSize: 12
            color: "#8E95A1"
            visible: root.best > 0
        }
        Text {
            text: String(root.score)
            font.family: "monospace"
            font.pixelSize: 12
            font.weight: Font.Bold
            color: "#E9ECF1"
        }
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -10
        spacing: 4
        visible: !root.running

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.over ? "G A M E   O V E R" : "Flappy Ptero"
            font.pixelSize: 16
            font.weight: Font.Bold
            color: root.over ? "#E4483E" : "#E9ECF1"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.over ? I18n.tr("Click or Space — play again") : I18n.tr("Click / Space — flap")
            font.pixelSize: 11
            color: "#8E95A1"
        }
    }
}
