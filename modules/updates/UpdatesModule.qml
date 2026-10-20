import QtQuick
import "../../components"
import "../../config"
import "../polkit"

// System updates (services/Updates). Two faces, by the run's phase:
//   list  pending packages (repo / AUR sections, old → new) + Репозитории
//         (pacman -Syu) / Всё (yay -Syu: repos, then AUR)
//   run   the live log of the run (tmux, see scripts/updates/update.sh),
//         its question when the tty waits (Yes / No, Enter = the default),
//         Терминал (attach) / Скрыть; when it is over, a result line
//         (reboot needed, .pacnew files) and Готово (back to the list).
// A transaction started elsewhere (pacman in a terminal: PacmanWatch busy,
// no own run) shows /var/log/pacman.log instead.
// Layout follows the polkit prompt; height is content-fitted
// (preferredHeight → ModuleHost → Island.moduleSize).
Item {
    id: root
    required property var updates
    required property var theme
    required property var cfg
    signal closeRequested

    readonly property string phase: root.updates.phase
    readonly property bool external: root.phase === "idle" && (root.updates.pacman?.busy ?? false)
    readonly property bool listView: root.phase === "idle" && !root.external
    readonly property var logLines: root.external ? root.updates.externalLines : root.updates.lines
    readonly property int total: root.updates.repoCount + root.updates.aurCount

    readonly property real preferredWidth: root.cfg.width
    readonly property real preferredHeight: body.implicitHeight + root.cfg.padding * 2

    Component.onCompleted: {
        root.updates.viewers++;
        root.updates.refreshIfStale();
    }
    Component.onDestruction: root.updates.viewers--

    readonly property string title: {
        if (root.external)
            return I18n.tr("Updating packages");
        if (root.phase === "running")
            return root.updates.prompt !== "" ? I18n.tr("Waiting for answer") : I18n.tr("Updating");
        if (root.phase === "done")
            return I18n.tr("Updated");
        if (root.phase === "failed")
            return root.updates.exitCode === -1 ? I18n.tr("Update interrupted") : I18n.tr("Update failed");
        return I18n.tr("Updates");
    }
    readonly property string subtitle: {
        if (root.external)
            return I18n.tr("Started in a terminal");
        if (root.phase !== "idle")
            return root.updates.mode === "all" ? I18n.tr("Repositories + AUR") : I18n.tr("Repositories");
        if (root.updates.checking && root.updates.checkedAt === 0)
            return I18n.tr("Checking…");
        if (root.updates.listError && root.updates.repoCount === 0)
            return I18n.tr("Couldn't check for updates");
        if (root.total === 0)
            return I18n.tr("Up to date");
        return I18n.trN(root.total, "%1 package", "%1 packages");
    }

    Column {
        id: body
        x: root.cfg.padding
        y: root.cfg.padding
        width: root.width - root.cfg.padding * 2
        spacing: root.cfg.gap
        move: Transition { Spring { properties: "y" } }

        // ── Header ──
        Item {
            width: parent.width
            height: Math.max(disc.height, headCol.implicitHeight)

            Rectangle {
                id: disc
                width: root.cfg.discSize
                height: width
                radius: width / 2
                color: root.theme.cardBg

                Text {
                    anchors.centerIn: parent
                    readonly property bool ok: root.phase === "done"
                    readonly property bool bad: root.phase === "failed"
                    // tabler circle-check-filled / alert-circle, else md-pac_man
                    text: ok ? "" : bad ? "" : String.fromCodePoint(0xf0baf)
                    font.family: ok || bad ? root.theme.iconFamily : root.theme.nerdIconFamily
                    font.pixelSize: root.cfg.iconSize
                    color: ok ? root.theme.accentGreen : bad ? root.theme.accentRed : root.theme.accentYellow
                }
            }

            Column {
                id: headCol
                anchors.left: disc.right
                anchors.leftMargin: root.cfg.gap
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: root.title
                    color: root.theme.islandFg
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.cfg.titleSize
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.subtitle
                    color: root.theme.subtleFg
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.cfg.fontSize
                    elide: Text.ElideRight
                }
            }
        }

        // ── Pending packages ──
        Rectangle {
            visible: root.listView && root.total > 0
            width: parent.width
            height: Math.min(root.cfg.listHeight, pkgList.contentHeight + root.cfg.cardPadding * 2)
            radius: root.cfg.buttonHeight / 2
            color: root.theme.cardBg

            ListView {
                id: pkgList
                anchors.fill: parent
                anchors.margins: root.cfg.cardPadding
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.updates.packages
                section.property: "source"
                section.delegate: Text {
                    required property string section
                    width: ListView.view.width
                    height: root.cfg.rowHeight
                    verticalAlignment: Text.AlignVCenter
                    text: section === "aur" ? I18n.tr("AUR") : I18n.tr("Repositories")
                    color: root.theme.cardDim
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.cfg.detailSize
                    font.weight: Font.DemiBold
                }
                delegate: Item {
                    required property var modelData
                    width: ListView.view.width
                    height: root.cfg.rowHeight

                    Text {
                        id: pkgName
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width * 0.55)
                        text: modelData.name
                        color: root.theme.islandFg
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.cfg.fontSize
                        elide: Text.ElideRight
                    }
                    Text {
                        anchors.left: pkgName.right
                        anchors.leftMargin: root.cfg.gap
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: modelData.from + "  →  " + modelData.to
                        color: root.theme.subtleFg
                        font.family: root.theme.monoFamily
                        font.pixelSize: root.cfg.logSize
                        elide: Text.ElideLeft
                    }
                }
            }
        }

        // ── Log ──
        Rectangle {
            visible: !root.listView
            width: parent.width
            height: root.cfg.logHeight
            radius: root.cfg.buttonHeight / 2
            color: root.theme.cardBg

            // One styled Text in a Flickable, not a ListView: a new lines
            // array rebuilt every delegate and threw the scroll position
            // away. Follows the end unless scrolled up.
            Flickable {
                id: logView
                anchors.fill: parent
                anchors.margins: root.cfg.cardPadding
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: logText.implicitHeight
                property bool follow: true
                property bool auto: false
                function toEnd(): void {
                    logView.auto = true;
                    logView.contentY = Math.max(0, logView.contentHeight - logView.height);
                    logView.auto = false;
                }
                onContentHeightChanged: if (logView.follow) logView.toEnd()
                onHeightChanged: if (logView.follow) logView.toEnd()
                onContentYChanged: if (!logView.auto)
                    logView.follow = logView.contentY >= logView.contentHeight - logView.height - 4

                Text {
                    id: logText
                    width: logView.width
                    function esc(s: string): string {
                        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/ /g, "&nbsp;");
                    }
                    function tone(l: string): color {
                        return /^(error|ошибка)/i.test(l) ? root.theme.accentRed
                            : /^(warning|предупреждение)/i.test(l) ? root.theme.accentYellow
                            : /^(::|==>)/.test(l) ? root.theme.islandFg : root.theme.subtleFg;
                    }
                    text: root.logLines.map(l => `<font color="${tone(l)}">${esc(l)}</font>`).join("<br>")
                    textFormat: Text.StyledText
                    font.family: root.theme.monoFamily
                    font.pixelSize: root.cfg.logSize
                    wrapMode: Text.WrapAnywhere
                }
            }
        }

        // ── Result notices ──
        Text {
            visible: root.phase === "done" && (root.updates.reboot || root.updates.pacnew > 0)
            width: parent.width
            text: [root.updates.reboot ? I18n.tr("The kernel was updated: restart to use it") : "",
                root.updates.pacnew > 0 ? I18n.trN(root.updates.pacnew, "%1 new config file (.pacnew)", "%1 new config files (.pacnew)") : ""]
                .filter(s => s !== "").join("\n")
            color: root.theme.accentYellow
            font.family: root.theme.fontFamily
            font.pixelSize: root.cfg.fontSize
            wrapMode: Text.Wrap
        }

        // ── The tty's question ──
        Text {
            visible: root.phase === "running" && root.updates.prompt !== "" && root.updates.promptText !== ""
            width: parent.width
            text: root.updates.promptText
            color: root.theme.islandFg
            font.family: root.theme.fontFamily
            font.pixelSize: root.cfg.fontSize
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }

        // ── Actions ──
        Item {
            width: parent.width
            height: root.cfg.buttonHeight

            // Left: re-check (list) / the run's terminal.
            PolkitButton {
                anchors.left: parent.left
                visible: root.listView || root.phase === "running"
                theme: root.theme
                cfg: root.cfg
                label: root.listView ? (root.updates.checking ? I18n.tr("Checking…") : I18n.tr("Check")) : I18n.tr("Terminal")
                enabled: !root.listView || !root.updates.checking
                onClicked: root.listView ? root.updates.refresh() : root.updates.openTerminal()
            }

            Row {
                anchors.right: parent.right
                spacing: root.cfg.gap

                // List: Репозитории + Всё (only one button when one side is empty).
                PolkitButton {
                    visible: root.listView && root.updates.repoCount > 0 && root.updates.aurCount > 0
                    theme: root.theme
                    cfg: root.cfg
                    label: I18n.tr("Repositories")
                    onClicked: root.updates.start("repo")
                }
                PolkitButton {
                    visible: root.listView && root.total > 0
                    theme: root.theme
                    cfg: root.cfg
                    base: root.theme.qsBlue
                    label: root.updates.aurCount === 0 ? I18n.tr("Update") : I18n.tr("Everything")
                    onClicked: root.updates.start(root.updates.aurCount === 0 ? "repo" : "all")
                }

                // Run waiting on a question.
                PolkitButton {
                    visible: root.phase === "running" && root.updates.prompt === "yesno"
                    theme: root.theme
                    cfg: root.cfg
                    base: root.updates.promptDefaultYes ? root.theme.cardBg : root.theme.qsBlue
                    label: I18n.tr("No")
                    onClicked: root.updates.send("n")
                }
                PolkitButton {
                    visible: root.phase === "running" && root.updates.prompt === "yesno"
                    theme: root.theme
                    cfg: root.cfg
                    base: root.updates.promptDefaultYes ? root.theme.qsBlue : root.theme.cardBg
                    label: I18n.tr("Yes")
                    onClicked: root.updates.send("y")
                }
                PolkitButton {
                    visible: root.phase === "running" && root.updates.prompt === "input"
                    theme: root.theme
                    cfg: root.cfg
                    base: root.theme.qsBlue
                    label: I18n.tr("Default")
                    onClicked: root.updates.send("")
                }

                PolkitButton {
                    visible: (root.phase === "running" && root.updates.prompt === "") || root.external
                    theme: root.theme
                    cfg: root.cfg
                    label: I18n.tr("Hide")
                    onClicked: root.closeRequested()
                }
                PolkitButton {
                    visible: root.phase === "done" || root.phase === "failed"
                    theme: root.theme
                    cfg: root.cfg
                    base: root.theme.qsBlue
                    label: I18n.tr("Done")
                    onClicked: root.updates.clear()
                }
            }
        }
    }
}
