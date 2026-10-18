import QtQuick
import Quickshell
import Quickshell.Io

// The settings window — the one shell surface that is an ordinary app
// window (xdg-toplevel): the compositor places, tiles, focuses and closes
// it like any other. Created on open, destroyed on close (nothing idles).
// IPC target `settings`: open / section <id> / close / toggle.
Scope {
    id: root
    required property var theme
    required property var wallpaper

    property bool shown: false
    // Section to show when the window (re)opens; "" = keep the last one.
    property string requested: ""
    property string lastSection: "general"

    function open(section: string): void {
        if (section !== "")
            root.requested = section;
        root.shown = true;
        if (section !== "" && loader.item)
            loader.item.showSection(section);
    }

    LazyLoader {
        id: loader
        active: root.shown

        SettingsWindow {
            theme: root.theme
            wallpaper: root.wallpaper
            initialSection: root.requested !== "" ? root.requested : root.lastSection
            onSectionChanged: root.lastSection = section
            onClosed: root.shown = false
        }
    }

    IpcHandler {
        target: "settings"

        function open(): void {
            root.open("");
        }
        function section(id: string): void {
            root.open(id);
        }
        function close(): void {
            root.shown = false;
        }
        function toggle(): void {
            root.shown = !root.shown;
        }
    }
}
