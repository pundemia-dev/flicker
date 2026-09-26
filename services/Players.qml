import QtQuick
import Quickshell.Services.Mpris

QtObject {
    id: root

    readonly property var players: Mpris.players.values
    property MprisPlayer manualActive: null
    readonly property MprisPlayer active: manualActive ?? players[0] ?? null

    readonly property bool musicActive: active !== null && active.playbackState === MprisPlaybackState.Playing
    readonly property string trackTitle: active?.trackTitle ?? ""
    readonly property string trackArtist: active?.trackArtist ?? ""
    readonly property real position: active?.position ?? 0
    readonly property bool canTogglePlaying: active?.canTogglePlaying ?? false
    readonly property bool canGoNext: active?.canGoNext ?? false
    readonly property bool canGoPrevious: active?.canGoPrevious ?? false

    readonly property string artUrl: {
        const player = active;
        if (!player)
            return "";
        if (player.trackArtUrl)
            return player.trackArtUrl;
        const url = player.metadata["xesam:url"] ?? "";
        if (url.startsWith("https://www.youtube.com/watch")) {
            const id = url.match(/[?&]v=([\w-]{11})/)?.[1];
            return id ? `https://img.youtube.com/vi/${id}/hqdefault.jpg` : "";
        }
        return "";
    }

    function playPause(): void {
        if (active?.canTogglePlaying)
            active.togglePlaying();
    }
    function next(): void {
        if (active?.canGoNext)
            active.next();
    }
    function previous(): void {
        if (active?.canGoPrevious)
            active.previous();
    }
}
