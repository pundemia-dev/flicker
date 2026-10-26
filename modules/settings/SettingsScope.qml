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
    required property var vpn
    required property var audio
    required property var audioDevices
    required property var audioPolicy
    required property var displays
    required property var notifications
    property var idle: null
    property var nightLight: null

    property bool shown: false
    // Section the window (re)opens on: the last one shown or requested.
    property string lastSection: "general"

    function open(section: string): void {
        if (section !== "")
            root.lastSection = section;
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
            vpn: root.vpn
            audio: root.audio
            audioDevices: root.audioDevices
            audioPolicy: root.audioPolicy
            displays: root.displays
            notifications: root.notifications
            idle: root.idle
            nightLight: root.nightLight
            initialSection: root.lastSection
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
