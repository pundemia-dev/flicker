import QtQuick
import "../../../components"
import "../../../config"

// Mini-games of the empty Notification Center. One game is live at a time
// (Loader — idle games cost nothing); a horizontal swipe switches to the
// next/previous one in notifications.games, which slides in from that side.
//
// Input: this deck owns all presses over the game (it must — taps jump),
// so it also forwards the module's swipe-up close (AGENTS: module content
// must stay closable). A press on a running game acts immediately (jump);
// on an idle/over game the tap starts it on release, so swipes never start
// a round by accident. Keyboard (Space/↑/↓, Esc) works once the island got
// keyboard focus (OnDemand while the center is open: click the game).
//
// Game contract: `title`, `running`, press(button)/release(button), and it
// reads/writes its best score through `best` + `bestChanged`.
Item {
    id: root

    property var service
    property var cfg
    property var theme
    signal closeRequested

    readonly property var games: (root.cfg?.games ?? ["dino"]).filter(g => root.registry[g] !== undefined)
    readonly property var registry: ({ dino: dinoComp, flappy: flappyComp })
    readonly property real swipeDistance: root.cfg?.centerSwipeDistance ?? 80
    property int index: 0
    readonly property string current: root.games[root.index] ?? "dino"
    readonly property var game: loader.item

    Component.onCompleted: root.index = Math.max(0, root.games.indexOf(root.service?.lastGame ?? ""))

    function go(step: int): void {
        const n = root.games.length;
        if (n < 2) {
            stage.offset = 0;
            return;
        }
        root.index = (root.index + step + n) % n;
        if (root.service)
            root.service.lastGame = root.current;
        // New game enters from the side the swipe came from.
        stage.instant = true;
        stage.offset = step * root.width;
        stage.instant = false;
        stage.offset = 0;
    }

    function saveBest(name: string, value: int): void {
        if (!root.service || value <= (root.service.gameBest[name] ?? 0))
            return;
        const next = Object.assign({}, root.service.gameBest);
        next[name] = value;
        root.service.gameBest = next;
    }

    Keys.onEscapePressed: root.closeRequested()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_BracketRight || event.key === Qt.Key_Tab) {
            root.go(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_BracketLeft || event.key === Qt.Key_Backtab) {
            root.go(-1);
            event.accepted = true;
        }
    }

    Item {
        id: stage
        width: root.width
        height: root.height
        x: stage.offset
        clip: true

        property real offset: 0
        property bool instant: false
        Behavior on offset {
            enabled: !stage.instant && !ma.pressed
            Spring { stiffness: 4.5; damp: 0.45 }
        }

        Loader {
            id: loader
            anchors.fill: parent
            focus: true
            sourceComponent: root.registry[root.current] ?? null
        }
    }

    // Caption: empty-state hint + game name (top-left).
    Text {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 16
        anchors.topMargin: 12
        text: I18n.tr("No notifications · %1").arg(root.game?.title ?? "")
        font.pixelSize: 12
        color: "#8E95A1"
    }

    // Page dots.
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        spacing: 6
        visible: root.games.length > 1

        Repeater {
            model: root.games.length
            Rectangle {
                required property int index
                width: 6
                height: 6
                radius: 3
                color: "#E9ECF1"
                opacity: index === root.index ? 0.85 : 0.25
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        property real pressX: 0
        property real pressY: 0
        property string axis: ""
        property bool fired: false
        property bool wasRunning: false

        onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
            axis = "";
            fired = false;
            loader.forceActiveFocus();
            wasRunning = root.game?.running ?? false;
            if (wasRunning)
                root.game.press(mouse.button);
        }
        onPositionChanged: mouse => {
            const dx = mouse.x - pressX;
            const dy = mouse.y - pressY;
            if (axis === "") {
                if (Math.abs(dx) > 10 && Math.abs(dx) > Math.abs(dy))
                    axis = "x";
                else if (Math.abs(dy) > 10)
                    axis = "y";
            }
            if (axis === "x")
                stage.offset = root.games.length > 1 ? dx : dx * 0.2;
            else if (axis === "y" && !fired && dy < -30) {
                fired = true;
                root.closeRequested();
            }
        }
        onReleased: mouse => {
            if (axis === "x") {
                const dx = mouse.x - pressX;
                if (Math.abs(dx) > root.swipeDistance)
                    root.go(dx < 0 ? 1 : -1);
                else
                    stage.offset = 0;
            } else if (axis === "" && !wasRunning) {
                root.game?.press(mouse.button);
            }
            root.game?.release(mouse.button);
        }
        onCanceled: stage.offset = 0
    }

    Component {
        id: dinoComp
        DinoGame {
            best: root.service?.gameBest?.dino ?? 0
            onNewBest: v => root.saveBest("dino", v)
        }
    }
    Component {
        id: flappyComp
        FlappyGame {
            best: root.service?.gameBest?.flappy ?? 0
            onNewBest: v => root.saveBest("flappy", v)
        }
    }
}
