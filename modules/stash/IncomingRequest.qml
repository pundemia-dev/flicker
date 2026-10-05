import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../components"
import "../notifications/center"

// Incoming LocalSend transfer (pShell IncomingRequest port): sender + files
// (or the text of a clipboard send), destination (cfg.downloadDir, one-off
// override via the system folder dialog) and Reject / Accept; switches to
// a progress bar while the transfer runs.
Item {
    id: root
    required property var localSend
    required property var stash
    required property var cfg
    required property var theme

    readonly property var req: root.localSend.request
    readonly property bool isText: root.req?.isText ?? false
    readonly property string defaultDir: root.stash.expand(root.cfg.downloadDir)
    property string chosenDir: ""
    readonly property string targetDir: root.chosenDir !== "" ? root.chosenDir : root.defaultDir

    Connections {
        target: root.localSend
        function onRequestArrived(): void { root.chosenDir = ""; }
    }

    function fmtSize(bytes: real): string {
        if (bytes < 1024)
            return bytes + " B";
        const u = ["KB", "MB", "GB", "TB"];
        let v = bytes / 1024, i = 0;
        while (v >= 1024 && i < u.length - 1) {
            v /= 1024;
            i++;
        }
        return v.toFixed(v < 10 ? 1 : 0) + " " + u[i];
    }

    function themeIcon(name: string): string {
        const ext = name.includes(".") ? name.split(".").pop().toLowerCase() : "";
        if (["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg"].includes(ext))
            return "image-x-generic";
        if (ext === "pdf")
            return "application-pdf";
        if (["mp4", "mkv", "avi", "mov", "webm"].includes(ext))
            return "video-x-generic";
        if (["mp3", "wav", "flac", "ogg", "aac", "m4a"].includes(ext))
            return "audio-x-generic";
        if (["zip", "tar", "gz", "bz2", "xz", "rar", "7z"].includes(ext))
            return "application-x-archive";
        return "application-x-generic";
    }

    Column {
        anchors.fill: parent
        spacing: root.cfg.gap

        // ── Header ──
        Item {
            width: parent.width
            height: root.cfg.pickerHeaderHeight

            Text {
                id: glyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: root.theme.cardBlue
                font.family: root.theme.iconFamily
                font.pixelSize: 20
            }
            Column {
                anchors.left: glyph.right
                anchors.leftMargin: 10
                anchors.right: size.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: root.isText ? "Входящее сообщение" : "Входящие файлы"
                    color: root.theme.islandFg
                    font.pixelSize: root.theme.fontSizeClock
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: "от " + (root.req?.alias ?? "")
                    color: root.theme.subtleFg
                    font.pixelSize: root.theme.fontSizeBody
                    elide: Text.ElideRight
                }
            }
            Text {
                id: size
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.req ? root.fmtSize(root.req.totalSize ?? 0) : ""
                color: root.theme.subtleFg
                font.pixelSize: root.theme.fontSizeBody
            }
        }

        // ── Body: text message ──
        Text {
            visible: root.isText
            width: parent.width
            height: root.cfg.incomingTextHeight
            text: root.req?.text ?? ""
            color: root.theme.islandFg
            font.pixelSize: root.theme.fontSizeBody
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            textFormat: Text.PlainText
            verticalAlignment: Text.AlignTop
        }

        // ── Body: files ──
        Item {
            visible: !root.isText
            width: parent.width
            height: Math.max(1, Math.min(root.cfg.visibleDevicesMax, root.req?.files?.length ?? 1)) * root.cfg.incomingFileRowHeight
            clip: true

            Column {
                width: parent.width
                Repeater {
                    model: root.req?.files ?? []
                    Item {
                        required property var modelData
                        width: parent.width
                        height: root.cfg.incomingFileRowHeight

                        IconImage {
                            id: fileIcon
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 20
                            source: Quickshell.iconPath(root.themeIcon(modelData.name), "application-x-generic")
                            asynchronous: true
                        }
                        Text {
                            anchors.left: fileIcon.right
                            anchors.leftMargin: 8
                            anchors.right: fileSize.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name
                            color: root.theme.islandFg
                            font.pixelSize: root.theme.fontSizeBody
                            elide: Text.ElideMiddle
                        }
                        Text {
                            id: fileSize
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.fmtSize(modelData.size ?? 0)
                            color: root.theme.subtleFg
                            font.pixelSize: root.theme.fontSizeBody
                        }
                    }
                }
            }
        }

        // ── Progress (receiving) | destination ──
        Item {
            width: parent.width
            height: root.cfg.actionsHeight

            Item {
                anchors.fill: parent
                visible: root.localSend.transferring

                Rectangle {
                    id: track
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 6
                    height: 4
                    radius: 2
                    color: Qt.alpha(root.theme.cardBlue, 0.22)
                    Rectangle {
                        height: parent.height
                        radius: 2
                        color: root.theme.cardBlue
                        width: parent.width * root.localSend.progress
                        Behavior on width { Spring {} }
                    }
                }
                Text {
                    anchors.top: track.bottom
                    anchors.topMargin: 6
                    text: "Получение… " + Math.round(root.localSend.progress * 100) + "%"
                    color: root.theme.subtleFg
                    font.pixelSize: root.theme.fontSizeBody
                }
            }

            Item {
                anchors.fill: parent
                visible: !root.localSend.transferring && !root.isText

                Text {
                    anchors.left: parent.left
                    anchors.right: pick.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.targetDir
                    color: root.theme.subtleFg
                    font.pixelSize: root.theme.fontSizeBody
                    elide: Text.ElideMiddle
                }
                IconButton {
                    id: pick
                    anchors.right: parent.right
                    theme: root.theme
                    width: root.cfg.actionsHeight
                    height: root.cfg.actionsHeight
                    glyph: ""
                    onClicked: pickProc.running = true
                }
            }
        }

        // ── Reject / Accept ──
        Row {
            visible: !root.localSend.transferring
            anchors.right: parent.right
            height: root.cfg.actionsHeight
            spacing: root.cfg.gap

            Pill {
                anchors.verticalCenter: parent.verticalCenter
                label: root.isText ? "Закрыть" : "Отклонить"
                onClicked: root.localSend.reject()
            }
            Pill {
                anchors.verticalCenter: parent.verticalCenter
                label: root.isText ? "Скопировать" : "Принять"
                color: root.theme.cardBlue
                onClicked: root.localSend.accept(root.targetDir)
            }
        }
    }

    Process {
        id: pickProc
        command: ["bash", `${root.localSend.scriptsDir}/pickdir.sh`, root.targetDir]
        stdout: StdioCollector {
            id: pickOut
            onStreamFinished: {
                const dir = pickOut.text.trim();
                if (dir.length > 0)
                    root.chosenDir = dir;
            }
        }
    }
}
