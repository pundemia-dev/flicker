import QtQuick
import Quickshell.Services.Mpris

QtObject {
    id: root

    readonly property var players: Mpris.players.values
    property MprisPlayer manualActive: null

    // Active-player selection (dms _resolveActivePlayer pattern): prefer a
    // playing player; when everything pauses/stops keep the LAST playing one;
    // at cold start a paused player beats a registered-idle one (Telegram
    // registers Stopped with stale voice-message metadata and can be
    // players[0] — the plain players[0] pick showed it instead of the
    // actually playing app).
    property MprisPlayer remembered: null

    // Filters harvest per-player playbackState reads as dependencies, so
    // they re-evaluate when any player's state changes.
    readonly property var _playing: players.filter(p => p.playbackState === MprisPlaybackState.Playing)
    readonly property MprisPlayer _paused: players.find(p => p.playbackState === MprisPlaybackState.Paused) ?? null

    on_PlayingChanged: {
        if (_playing.length > 0)
            remembered = _playing[0];
    }
    onPlayersChanged: {
        if (remembered && !players.includes(remembered))
            remembered = null;
    }

    readonly property MprisPlayer active: manualActive ?? _playing[0] ?? remembered ?? _paused ?? players[0] ?? null

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
