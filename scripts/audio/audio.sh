#!/bin/sh
# Audio helpers for services/AudioPolicy.qml (QS audio panel, settings →
# Sound).
#
#   voice <source> <agc 0|1>   voice processing: a standalone PipeWire
#                              client running the WebRTC echo canceller
#                              (noise suppression + echo cancellation,
#                              optional gain control) on <source>; its
#                              cleaned source is node "flicker_voice". The
#                              echo reference is the default sink's monitor
#                              (monitor.mode: apps need not play into it).
#                              Streams are passive: the mic only runs while
#                              something records from flicker_voice.
#   test <sink> <left|right>   voice "Front left / right" on that channel
#                              only (the freedesktop sound is mono: a
#                              stereo copy with the other side silent is
#                              cached in $XDG_RUNTIME_DIR/flicker).
set -eu

dir="${XDG_RUNTIME_DIR:-/tmp}/flicker"
mkdir -p "$dir"

case "${1:-}" in
voice)
    src="$2"
    agc=false
    [ "${3:-0}" = 1 ] && agc=true
    conf="$dir/voice.conf"
    cat > "$conf" <<CONF
context.properties = { log.level = 0 }
context.spa-libs = {
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}
context.modules = [
    { name = libpipewire-module-rt args = { } flags = [ ifexists nofail ] }
    { name = libpipewire-module-protocol-native }
    { name = libpipewire-module-client-node }
    { name = libpipewire-module-adapter }
    { name = libpipewire-module-echo-cancel
        args = {
            library.name = aec/libspa-aec-webrtc
            monitor.mode = true
            audio.channels = 1
            aec.args = {
                webrtc.noise_suppression = true
                webrtc.extended_filter = true
                webrtc.high_pass_filter = true
                webrtc.gain_control = $agc
            }
            capture.props = {
                node.name = "flicker_voice.capture"
                target.object = "$src"
                node.passive = true
                node.dont-reconnect = true
            }
            sink.props = { node.name = "flicker_voice.reference" node.passive = true }
            source.props = {
                node.name = "flicker_voice"
                node.description = "Voice processing"
            }
        }
    }
]
CONF
    exec pipewire -c "$conf"
    ;;
test)
    sink="$2"
    side="$3"
    out="$dir/test-$side.wav"
    if [ ! -s "$out" ]; then
        in="/usr/share/sounds/freedesktop/stereo/audio-channel-front-$side.oga"
        if [ "$side" = left ]; then pan="stereo|c0=c0|c1=0*c0"; else pan="stereo|c0=0*c0|c1=c0"; fi
        ffmpeg -loglevel error -y -i "$in" -af "pan=$pan" "$out"
    fi
    exec pw-play --target "$sink" -P '{ node.name = "flicker_test" media.role = "Test" }' "$out"
    ;;
*)
    echo "usage: audio.sh voice <source> <agc> | test <sink> <left|right>" >&2
    exit 2
    ;;
esac
