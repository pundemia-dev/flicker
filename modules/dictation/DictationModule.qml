import QtQuick
import "../../components"
import "../../config"

Item {
    id: root
    required property var dictation
    signal closeRequested

    readonly property string phaseText: {
        if (!root.dictation.active)
            return root.dictation.lastError.length > 0 ? root.dictation.lastError : I18n.tr("Dictation ready");
        const lang = (root.dictation.sessionLang ?? "").length > 0 ? ` · ${root.dictation.sessionLang.toUpperCase()}` : "";
        const p = root.dictation.phase ?? "streaming";
        if (p === "switching")
            return I18n.tr("Switching…") + lang;
        if (p === "refining")
            return I18n.tr("Refining…") + lang;
        if (p === "finalizing")
            return I18n.tr("Finalizing…") + lang;
        return I18n.tr("Listening…") + lang;
    }
    readonly property string live: root.dictation.liveText ?? ""

    Row {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        Rectangle {
            width: 34
            height: 34
            radius: 17
            anchors.verticalCenter: parent.verticalCenter
            color: root.dictation.active ? "#C74E5A" : "#39414E"
            Text {
                anchors.centerIn: parent
                text: root.dictation.active ? "⏹" : "🎙"
                font.pixelSize: 13
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.dictation.toggle()
            }
        }

        Column {
            width: parent.width - 98
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text {
                text: root.phaseText
                color: "#E5EAF3"
                font.pixelSize: 12
            }
            Text {
                width: parent.width
                text: root.live
                color: "#98A4B6"
                font.pixelSize: 11
                elide: Text.ElideLeft
                visible: root.live.length > 0
            }
        }

        // Cancel (✕): kill the stream without committing; typed partial is
        // erased via BackSpace. Toggle (⏹) commits instead.
        Rectangle {
            width: 34
            height: 34
            radius: 17
            anchors.verticalCenter: parent.verticalCenter
            color: "#39414E"
            visible: root.dictation.active
            Text {
                anchors.centerIn: parent
                text: "✕"
                font.pixelSize: 13
                color: "#E5EAF3"
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.dictation.cancel()
            }
        }
    }
}
