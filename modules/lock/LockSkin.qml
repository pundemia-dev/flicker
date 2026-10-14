import QtQuick
import Quickshell
import "../../components"
import "../../config"

// Lock skin: LockBackdrop (grab → regions dissolve into the wallpaper) +
// avatar / clock / date / state feedback (placeholder column, shown once the
// dissolve ran) + LockField: the island's copy flying down into the password
// field over the column's `fieldSlot`. Receives lock/pam/scope/screen as
// initial properties (see LockSurface).
Item {
    id: root

    required property var lock
    required property var pam
    required property var scope
    required property ShellScreen screen

    focus: true

    Keys.onPressed: event => {
        pam.handleKey(event);
        event.accepted = true;
        // A layout switch (Caps with grp:caps_toggle, …) types nothing, and on
        // the static lock driftwm reports it only after the next frame: ask.
        if (event.text === "")
            layoutPoll.restart();
    }
    Timer {
        id: layoutPoll
        interval: 20
        onTriggered: root.scope?.keyboard?.keyboardLayout?.poll()
    }

    LockBackdrop {
        id: backdrop
        anchors.fill: parent
        scope: root.scope
        screen: root.screen
        hole: field.homeRect
        onUnlockDone: {
            root.backDone = true;
            root.tryFinish();
        }
        onDissolvedChanged: if (backdrop.dissolved) {
            const p = fieldSlot.mapToItem(root, 0, 0);
            field.slot = Qt.rect(p.x, p.y, fieldSlot.width, fieldSlot.height);
            field.out = true;
            const c = clockSlot.mapToItem(root, 0, 0);
            clock.slot = Qt.rect(c.x, c.y, clockSlot.width, clockSlot.height);
            clock.out = true;
        }
    }

    // Unlock finishes once the regions are back AND the field is home.
    property bool backDone: false
    property bool fieldHome: false
    property bool clockHome: false
    function tryFinish(): void {
        if (root.backDone && root.fieldHome && root.clockHome)
            root.lock.finishUnlock();
    }

    FadeBlur {
        anchors.fill: parent
        shown: backdrop.dissolved && !backdrop.unlocking

        // Fail/error flash + shake feedback
        Rectangle {
            id: flash
            anchors.fill: parent
            color: "#B33"
            opacity: 0
            SequentialAnimation {
                id: flashAnim
                NumberAnimation { target: flash; property: "opacity"; to: 0.22; duration: 90 }
                NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 260 }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 14

            // Own blur-fade: waits for the media (GIF / video decode late),
            // so it blurs in once instead of popping in after the column.
            FadeBlur {
                anchors.horizontalCenter: parent.horizontalCenter
                width: avatar.implicitWidth
                height: avatar.implicitHeight
                blurMax: root.scope?.cfg?.avatarBlurMax ?? 48
                shown: backdrop.dissolved && !backdrop.unlocking && avatar.settled

                LockAvatar {
                    id: avatar
                    anchors.fill: parent
                    cfg: root.scope?.cfg ?? ({})
                }
            }

            // Where the clock lands (LockClock flies in from the bar clock);
            // invisible, same text/font so the slot has the clock's size.
            Text {
                id: clockSlot
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: 0
                text: clock.text
                font.pixelSize: clock.finalPx
                font.family: clock.family
                font.weight: Font.Light
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.capitalize(new Date().toLocaleDateString(I18n.locale, I18n.tr("dddd, MMMM d")))
                color: "#8B93A3"
                font.pixelSize: 15
            }

            // Where the password field lands (LockField flies in from the
            // island and sits over this slot).
            Item {
                id: fieldSlot
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.scope?.cfg?.fieldWidth ?? 360
                height: root.scope?.cfg?.fieldHeight ?? 52
            }

            // Room for the keyboard pill (LockKeyboardPill) under the field,
            // so the status line below never sits under it.
            Item {
                width: 1
                height: Math.max(0, (root.scope?.keyboard?.cfg?.pillHeight ?? 26) + (root.scope?.keyboard?.cfg?.lockGap ?? 14) - parent.spacing)
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: text.length > 0
                text: {
                    if (root.pam.state === "fail")
                        return I18n.tr("Incorrect password");
                    if (root.pam.state === "error")
                        return I18n.tr("Authentication error");
                    if (root.pam.state === "max")
                        return I18n.tr("Too many attempts");
                    return root.pam.lockMessage;
                }
                color: "#D98080"
                font.pixelSize: 12
            }
        }
    }

    // The island's copy, over everything: flies down into the password field.
    LockField {
        id: field
        cfg: root.scope?.cfg ?? ({})
        pam: root.pam
        grabItem: backdrop.grabItem
        home: root.scope?.islandRect(root.screen?.name ?? "") ?? null
        onArrivedHome: {
            root.fieldHome = true;
            root.tryFinish();
        }
    }

    // Caps Lock / layout pill under the password field (the lock hides the
    // desktop KeyboardOverlay).
    LockKeyboardPill {
        anchors.fill: parent
        keyboard: root.scope?.keyboard ?? null
        theme: root.scope?.theme ?? null
        field: field
        active: field.out && field.atField
    }

    // The bar clock flying out to the big clock (over the field: both start
    // on the island).
    LockClock {
        id: clock
        cfg: root.scope?.cfg ?? ({})
        home: root.scope?.islandRect(root.screen?.name ?? "")?.clock ?? null
        onArrivedHome: {
            root.clockHome = true;
            root.tryFinish();
        }
    }

    Connections {
        target: root.pam
        function onFlashMsg(): void {
            flashAnim.restart();
            field.kick();
        }
    }

    Connections {
        target: root.lock
        function onUnlock(): void {
            // Never left (unlocked before the dissolve started): already home.
            if (!field.out)
                root.fieldHome = true;
            if (!clock.out)
                root.clockHome = true;
            field.out = false;
            clock.out = false;
            backdrop.playUnlock();
        }
    }
}
