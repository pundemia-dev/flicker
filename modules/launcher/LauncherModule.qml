import QtQuick
import Quickshell
import "../../components"

Item {
    id: root
    signal closeRequested

    readonly property var allApps: DesktopEntries.applications.values.filter(a => !a.noDisplay)
    property string query: ""

    readonly property var results: {
        const q = query.toLowerCase().trim();
        if (q.length === 0)
            return allApps.slice().sort((a, b) => a.name.localeCompare(b.name)).slice(0, 6);
        return allApps.filter(a => a.name.toLowerCase().includes(q)).sort((a, b) => {
            const an = a.name.toLowerCase(), bn = b.name.toLowerCase();
            const ap = an.startsWith(q) ? 0 : 1, bp = bn.startsWith(q) ? 0 : 1;
            return ap - bp || an.localeCompare(bn);
        }).slice(0, 6);
    }

    function launch(entry: var): void {
        if (!entry)
            return;
        const props = { command: entry.command };
        if (entry.workingDirectory)
            props.workingDirectory = entry.workingDirectory;
        Quickshell.execDetached(props);
        root.closeRequested();
    }

    function launchFirst(): void {
        if (results.length > 0)
            launch(results[0]);
    }

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        Rectangle {
            width: parent.width
            height: 30
            radius: 10
            color: "#222731"

            TextInput {
                id: searchField
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                color: "#F0F4FB"
                selectionColor: "#4C6EF5"
                selectedTextColor: "white"
                font.pixelSize: 13
                // Matches Theme.fontFamily (this module is theme-less).
                font.family: "SF Pro Display"
                focus: true
                clip: true
                onTextChanged: root.query = text
                onAccepted: {
                    // Enter launches the keyboard-selected result, falling
                    // back to the first one when nothing is highlighted.
                    const idx = resultsList.currentIndex;
                    if (idx >= 0 && idx < root.results.length)
                        root.launch(root.results[idx]);
                    else
                        root.launchFirst();
                }

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: "Search applications..."
                    color: "#6E7A8C"
                    font.pixelSize: 13
                    visible: searchField.text.length === 0 && !searchField.activeFocus
                }
            }
        }

        ListView {
            id: resultsList
            width: parent.width
            height: parent.height - 36
            clip: true
            model: root.results
            spacing: 2
            keyNavigationWraps: true
            highlightMoveDuration: 90

            delegate: Rectangle {
                id: itemRect
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 30
                radius: 8
                color: ListView.view.currentIndex === itemRect.index ? "#2A3140" : "transparent"

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: Text.AlignVCenter
                    text: itemRect.modelData.name
                    color: "#E6EBF5"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: resultsList.currentIndex = itemRect.index
                    onClicked: root.launch(itemRect.modelData)
                }
            }
        }
    }

    Keys.onEscapePressed: root.closeRequested()
    Keys.onUpPressed: resultsList.decrementCurrentIndex()
    Keys.onDownPressed: resultsList.incrementCurrentIndex()
}
