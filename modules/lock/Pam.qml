import QtQuick
import Quickshell
import Quickshell.Services.Pam

// PAM auth logic for the lock screen (simplified port of pShell Pam.qml):
// the password context here, the fingerprint one in PamFingerprint (runs
// alongside; a miss = state "fingerprint" + the same flash as a wrong
// password). Skins read state/buffer and call handleKey(); lock is
// duck-typed: needs secure, unlock signal, beginUnlock().
Scope {
    id: root

    required property var lock

    readonly property alias passwd: passwd
    property string state
    property string buffer
    property string lockMessage

    signal flashMsg

    function handleKey(event: var): void {
        if (passwd.active || state === "max")
            return;

        if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
            passwd.start();
        } else if (event.key === Qt.Key_Backspace) {
            if (event.modifiers & Qt.ControlModifier)
                buffer = "";
            else
                buffer = buffer.slice(0, -1);
        } else if (/^[^\x00-\x1F\x7F-\x9F]+$/.test(event.text)) {
            buffer += event.text;
        }
    }

    PamContext {
        id: passwd

        config: "flicker"
        configDirectory: Quickshell.shellDir + "/assets/pam.d"

        onMessageChanged: {
            if (message.startsWith("The account is locked"))
                root.lockMessage = message;
            else if (root.lockMessage && message.endsWith(" left to unlock)"))
                root.lockMessage += "\n" + message;
        }

        onResponseRequiredChanged: {
            if (!responseRequired)
                return;
            respond(root.buffer);
            root.buffer = "";
        }

        onCompleted: res => {
            if (res === PamResult.Success) {
                fingerprint.stop();
                return root.lock.beginUnlock();
            }

            if (res === PamResult.Error)
                root.state = "error";
            else if (res === PamResult.MaxTries)
                root.state = "max";
            else if (res === PamResult.Failed)
                root.state = "fail";

            root.flashMsg();
            stateReset.restart();
        }
    }

    PamFingerprint {
        id: fingerprint
        lock: root.lock

        onMatched: {
            fingerprint.stop();
            if (passwd.active)
                passwd.abort();
            root.buffer = "";
            root.lock.beginUnlock();
        }
        onFailed: {
            if (root.state === "max")
                return;
            root.state = "fingerprint";
            root.flashMsg();
            stateReset.restart();
        }
    }

    Timer {
        id: stateReset
        interval: 4000
        onTriggered: if (root.state !== "max")
            root.state = ""
    }

    Connections {
        target: root.lock
        function onSecureChanged(): void {
            if (root.lock.secure) {
                root.buffer = "";
                root.state = "";
                root.lockMessage = "";
                fingerprint.begin();
            } else {
                fingerprint.stop();
            }
        }
        function onUnlock(): void {
            fingerprint.stop();
        }
    }
}
