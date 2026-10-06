import QtQuick
import Quickshell
import "../../../components"
import "../../../config"

// Chrome T-Rex runner (port of components/DinoGame.qml from the caelestia
// fork dim-ghub/caelestia-shell, GPL-3.0; sprites in assets/dino/, recoloured
// white for the black island). Jump: LMB / Space / ↑; duck: RMB / ↓ / S.
// Frame-driven (FrameAnimation, dt-scaled), so speed is refresh-rate proof.
Item {
    id: root

    readonly property string title: "Dino"
    property int best: 0
    signal newBest(int value)

    focus: true

    property bool running: false
    property bool over: false
    property int score: 0
    property bool ducking: false
    property int frame: 0
    property real animAcc: 0
    property real scoreAcc: 0

    readonly property real gravity: 2000
    readonly property real jumpForce: -600
    readonly property real initialSpeed: 300
    readonly property real maxSpeed: 800
    readonly property real groundY: root.height - 34
    readonly property real dinoX: 34
    readonly property real dinoH: root.ducking ? 27 : 42
    readonly property real dinoW: root.ducking ? 59 : 44

    property real dinoY: root.groundY - 42
    property real vy: 0
    property real speed: root.initialSpeed
    property real spawnAcc: 0
    property real nextSpawn: 1.2
    property real distance: 0
    // Obstacles {x, y, w, h, type: 0 cactus / 1 big cactus / 2 bird};
    // mutated in place, `tick` re-evaluates the fixed render slots.
    property var obstacles: []
    property int tick: 0

    readonly property string spriteDir: `file://${Quickshell.shellDir}/assets/dino/`
    readonly property bool airborne: root.dinoY < root.groundY - root.dinoH - 1

    onGroundYChanged: if (!root.airborne) root.dinoY = root.groundY - root.dinoH

    onDuckingChanged: {
        if (root.over)
            return;
        if (root.vy >= 0 && root.dinoY >= root.groundY - 45)
            root.dinoY = root.groundY - root.dinoH;
        // Fast drop when ducking mid-air.
        if (root.ducking && root.airborne)
            root.vy += 800;
    }

    function reset(): void {
        root.running = false;
        root.over = false;
        root.score = 0;
        root.speed = root.initialSpeed;
        root.obstacles = [];
        root.spawnAcc = 0;
        root.nextSpawn = 1.2;
        root.scoreAcc = 0;
        root.ducking = false;
        root.vy = 0;
        root.dinoY = root.groundY - 42;
        root.tick++;
    }

    function start(): void {
        root.reset();
        root.running = true;
    }

    function jump(): void {
        if (!root.running) {
            root.start();
            return;
        }
        if (!root.airborne) {
            root.vy = root.jumpForce;
            root.dinoY = root.groundY - root.dinoH - 1;
            root.ducking = false;
        }
    }

    function press(button: int): void {
        if (button === Qt.RightButton) {
            if (root.running)
                root.ducking = true;
        } else {
            root.jump();
        }
    }

    function release(button: int): void {
        if (button === Qt.RightButton)
            root.ducking = false;
    }

    function spawn(): void {
        const r = Math.floor(Math.random() * 5);
        let o;
        if (r <= 1) {
            o = { w: 25, h: 52, type: 0 };
        } else if (r <= 3) {
            o = { w: 52, h: 52, type: 1 };
        } else {
            // Bird heights: high (run under), head (duck), feet (jump).
            const lift = [85, 62, 32][Math.floor(Math.random() * 3)];
            o = { w: 46, h: 30, type: 2, lift: lift };
        }
        o.x = root.width + 10;
        o.y = root.groundY - (o.type === 2 ? o.lift : o.h);
        root.obstacles.push(o);
    }

    // Forgiving hitboxes (insets on both rects).
    function hits(o): bool {
        const l1 = root.dinoX + 8, r1 = root.dinoX + root.dinoW - 8;
        const t1 = root.dinoY + 8, b1 = root.dinoY + root.dinoH - 4;
        const l2 = o.x + 6, r2 = o.x + o.w - 6, t2 = o.y + 6, b2 = o.y + o.h - 4;
        return !(r1 < l2 || l1 > r2 || b1 < t2 || t1 > b2);
    }

    function gameOver(): void {
        root.running = false;
        root.over = true;
        if (root.score > root.best)
            root.newBest(root.score);
    }

    function step(dt: real): void {
        root.animAcc += dt;
        if (root.animAcc >= 0.1) {
            root.frame = 1 - root.frame;
            root.animAcc = 0;
        }

        const ground = root.groundY - root.dinoH;
        if (root.dinoY < ground || root.vy < 0) {
            root.vy += root.gravity * dt;
            root.dinoY = Math.min(ground, root.dinoY + root.vy * dt);
            if (root.dinoY >= ground)
                root.vy = 0;
        } else {
            root.dinoY = ground;
            root.vy = 0;
        }

        const dx = root.speed * dt;
        root.distance += dx;
        for (const o of root.obstacles)
            o.x -= dx;
        while (root.obstacles.length > 0 && root.obstacles[0].x + root.obstacles[0].w < 0)
            root.obstacles.shift();

        root.spawnAcc += dt;
        if (root.spawnAcc >= root.nextSpawn) {
            root.spawn();
            root.spawnAcc = 0;
            // Minimum gap ≈ one jump at the current speed.
            root.nextSpawn = Math.max(0.7, (0.9 + Math.random() * 1.5) * root.initialSpeed / root.speed);
        }
        root.speed = Math.min(root.maxSpeed, root.speed + 5 * dt);

        root.scoreAcc += dt;
        if (root.scoreAcc >= 0.1) {
            root.score++;
            root.scoreAcc = 0;
        }

        for (const o of root.obstacles) {
            if (root.hits(o)) {
                root.gameOver();
                break;
            }
        }
        root.tick++;
    }

    FrameAnimation {
        running: root.running
        onTriggered: root.step(Math.min(0.05, frameTime))
    }

    Keys.onPressed: event => {
        if (event.isAutoRepeat)
            return;
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Up || event.key === Qt.Key_W) {
            root.jump();
            event.accepted = true;
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) {
            if (root.running)
                root.ducking = true;
            event.accepted = true;
        }
    }
    Keys.onReleased: event => {
        if (!event.isAutoRepeat && (event.key === Qt.Key_Down || event.key === Qt.Key_S)) {
            root.ducking = false;
            event.accepted = true;
        }
    }

    // ── Scene ──
    Rectangle {
        y: root.groundY - 1
        width: parent.width
        height: 2
        color: "#E9ECF1"
        opacity: 0.45
    }
    // Ground specks scrolling with the world (motion cue).
    Repeater {
        model: 9
        Rectangle {
            required property int index
            readonly property real span: root.width + 40
            x: ((index * 67 + (index % 3) * 23 - root.distance) % span + span) % span - 20
            y: root.groundY + 5 + (index % 3) * 4
            width: 3 + (index % 4) * 2
            height: 2
            color: "#E9ECF1"
            opacity: 0.3
        }
    }

    Image {
        x: root.dinoX
        y: root.dinoY
        width: root.dinoW
        height: root.dinoH
        fillMode: Image.PreserveAspectFit
        smooth: false
        source: {
            if (root.over)
                return root.spriteDir + "Dead_Chrome_T-Rex.png";
            if (root.airborne || !root.running)
                return root.spriteDir + "Chrome_T-Rex_Left_Run.png";
            if (root.ducking)
                return root.spriteDir + (root.frame === 0 ? "Chrome_T-Rex_Left_Duck.png" : "Chrome_T-Rex_Right_Duck.png");
            return root.spriteDir + (root.frame === 0 ? "Chrome_T-Rex_Left_Run.png" : "Chrome_T-Rex_Right_Run.png");
        }
    }

    Repeater {
        model: 5
        Image {
            required property int index
            // Read through `tick`: the obstacle objects mutate in place,
            // so a cached object reference would never notify.
            function f(key: string): var {
                return root.tick >= 0 ? (root.obstacles[index]?.[key] ?? 0) : 0;
            }
            visible: root.tick >= 0 && index < root.obstacles.length
            x: f("x")
            y: f("y")
            width: f("w")
            height: f("h")
            opacity: 0.75
            smooth: false
            fillMode: Image.PreserveAspectFit
            source: root.spriteDir + (["1_Cactus_Chrome_Dino.png", "3_Cactus_Chrome_Dino.png", "Chrome_Pterodactyl.png"][f("type")])
        }
    }

    // Score (top-right).
    Row {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 16
        anchors.topMargin: 12
        spacing: 10

        Text {
            text: "HI " + String(Math.max(root.best, root.over ? root.score : 0)).padStart(5, "0")
            font.family: "monospace"
            font.pixelSize: 12
            color: "#8E95A1"
            visible: root.best > 0
        }
        Text {
            text: String(root.score).padStart(5, "0")
            font.family: "monospace"
            font.pixelSize: 12
            font.weight: Font.Bold
            color: "#E9ECF1"
        }
    }

    // Idle / game-over overlay.
    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -22
        spacing: 4
        visible: !root.running

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.over ? "G A M E   O V E R" : "Dino Runner"
            font.pixelSize: 16
            font.weight: Font.Bold
            color: root.over ? "#E4483E" : "#E9ECF1"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.over ? I18n.tr("Click or Space — play again") : I18n.tr("Click / Space — jump, RMB / ↓ — duck")
            font.pixelSize: 11
            color: "#8E95A1"
        }
    }
}
