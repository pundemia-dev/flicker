import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../config"

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

    // Art as the player reports it (YouTube: thumbnail from the video id).
    readonly property string remoteArt: {
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

    // What the UI shows: local art as is, http(s) art as a cached local
    // copy fetched with `curl -4` (Qt's network loader stalls on the broken
    // IPv6 here — Spotify's i.scdn.co covers never appeared). The previous
    // art stays until the new file lands, so a track change crossfades
    // old -> new without a fallback flash.
    property string artUrl: ""
    readonly property string artDir: Quickshell.cachePath("art")

    function isRemote(url: string): bool {
        return url.startsWith("http://") || url.startsWith("https://");
    }
    function artFile(url: string): string {
        return `${artDir}/${Qt.md5(url)}`;
    }
    function resolveArt(): void {
        const url = remoteArt;
        if (!isRemote(url)) {
            artUrl = url;
            return;
        }
        if (artFetch.running) {
            artFetch.queued = true;
            return;
        }
        artFetch.url = url;
        artFetch.running = true;
    }
    onRemoteArtChanged: resolveArt()
    Component.onCompleted: resolveArt()

    // Process gotcha: a live Process cannot be restarted in the same tick,
    // so a change mid-fetch is picked up in onExited.
    property Process artFetch: Process {
        property string url: ""
        property bool queued: false
        command: ["sh", "-c", `f="$1"; [ -s "$f" ] && exit 0
mkdir -p "$(dirname "$f")"
curl -4 -fsSL --max-time "$3" -o "$f.part" "$2" && mv "$f.part" "$f" || { rm -f "$f.part"; exit 1; }
ls -t "$(dirname "$f")" | tail -n +$(($4 + 1)) | sed "s|^|$(dirname "$f")/|" | xargs -r -d '\\n' rm -f`,
            "sh", root.artFile(url), url,
            String(Config.data.mediaArt?.fetchTimeoutSec ?? 10),
            String(Config.data.mediaArt?.cacheMax ?? 200)]
        onExited: code => {
            if (code !== 0)
                console.warn("[Players] art fetch failed", code, url);
            if (url === root.remoteArt)
                root.artUrl = code === 0 ? `file://${root.artFile(url)}` : "";
            if (queued) {
                queued = false;
                Qt.callLater(root.resolveArt);
            }
        }
    }

    // Lyrics of the active track (player module's lyrics panel).
    property Lyrics lyrics: Lyrics {
        players: root
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
