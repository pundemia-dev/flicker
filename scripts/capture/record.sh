#!/usr/bin/env bash
# record.sh <audio-mode> <out-file> [wf-recorder extra args…]
# Port of pShell scripts/capture_record.sh.
#
# audio-mode: none | system | mic | both
#   system — the default sink's monitor (what the speakers play)
#   mic    — the default input source
#   both   — mic + system mixed into a temporary null sink (module-null-sink
#            + 2× loopback); its monitor is recorded.
#
# Video and audio are captured SEPARATELY and muxed per segment:
# wf-recorder 0.6 here drops the video stream whenever --audio is used
# (pulse backend) or the audio (pipewire backend), verified Oct 2026. So
# wf-recorder records video only and parecord records the audio source;
# each segment is muxed with ffmpeg (video copied, audio → AAC). Every
# segment gets an audio track (silence for "none") so the final concat
# stays stream-compatible across live audio switches.
#
# Signals:
#   SIGUSR1 — toggle pause: each pause boundary finalizes the current
#             segment, resume starts the next; stop concatenates them
#             losslessly (ffmpeg -c copy).
#   SIGUSR2 — re-read "<out-file>.audioctl" and restart the segment with the
#             new audio source (live audio switching, same segment trick).
#   SIGINT/SIGTERM — stop: finalize, concat, clean up.
set -u

mode="$1"
out="$2"
shift 2

# Optional "--hw <render-node>": VAAPI encode when a libva driver exists
# (silent CPU fallback otherwise). Cross-GPU encode is broken in
# wf-recorder, so only pass the compositor's node here.
hwdev=""
extra=()
while [ $# -gt 0 ]; do
    if [ "$1" = "--hw" ] && [ $# -ge 2 ]; then
        hwdev="$2"
        shift 2
    else
        extra+=("$1")
        shift
    fi
done

ctl="$out.audioctl"
outdir="$(dirname "$out")"
mkdir -p "$outdir"
segdir="$outdir/.pillshell_rec_$$"
mkdir -p "$segdir"

enc_args=(--pixel-format yuv420p)
if [ -n "$hwdev" ] && [ -e "$hwdev" ] && { [ -e /usr/lib/dri/iHD_drv_video.so ] || [ -e /usr/lib/dri/i965_drv_video.so ]; }; then
    enc_args=(-c h264_vaapi -d "$hwdev")
fi
base_args=("${enc_args[@]}" "${extra[@]}")

seg_modules=()
audio_dev=""

# Unload pillshell_rec leftovers from a crashed session.
pactl list short modules 2>/dev/null | grep pillshell_rec | cut -f1 | while read -r m; do
    pactl unload-module "$m" 2>/dev/null
done

# WirePlumber may promote a freshly created null sink to the DEFAULT sink,
# silently stealing every new audio stream. Snapshot the default and
# re-assert it over the ~1s promotion window.
load_mix_sink() {
    local prev sink_id
    prev="$(pactl get-default-sink 2>/dev/null)"
    sink_id="$(pactl load-module module-null-sink sink_name=pillshell_rec sink_properties='device.description=pillShell-recording priority.session=0 priority.driver=0')"
    seg_modules+=("$sink_id")
    if [ -n "$prev" ] && [ "$prev" != pillshell_rec ]; then
        pactl set-default-sink "$prev" 2>/dev/null
        (
            for _ in 1 2 3 4 5 6; do
                sleep 0.15
                [ "$(pactl get-default-sink 2>/dev/null)" = pillshell_rec ] &&
                    pactl set-default-sink "$prev" 2>/dev/null
            done
        ) &
    fi
}

setup_audio() {
    local m="$1" sink src lp
    audio_dev=""
    case "$m" in
    system)
        sink="$(pactl get-default-sink 2>/dev/null)"
        [ -n "$sink" ] && audio_dev="$sink.monitor"
        ;;
    mic)
        audio_dev="$(pactl get-default-source 2>/dev/null)"
        ;;
    both)
        load_mix_sink
        lp="$(pactl load-module module-loopback source=@DEFAULT_SOURCE@ sink=pillshell_rec latency_msec=20 source_output_properties=node.name=pillshell_rec_mic)"
        seg_modules+=("$lp")
        sink="$(pactl get-default-sink 2>/dev/null)"
        if [ -n "$sink" ]; then
            lp="$(pactl load-module module-loopback source="$sink.monitor" sink=pillshell_rec latency_msec=20 source_output_properties=node.name=pillshell_rec_sys)"
            seg_modules+=("$lp")
        fi
        audio_dev="pillshell_rec.monitor"
        ;;
    esac
}

teardown_audio() {
    local i
    for ((i = ${#seg_modules[@]} - 1; i >= 0; i--)); do
        pactl unload-module "${seg_modules[i]}" 2>/dev/null
    done
    seg_modules=()
}

segs=()
seg_i=0
pid=""
apid=""
cur=""

start_seg() {
    local m
    m="$(cat "$ctl" 2>/dev/null || true)"
    [ -n "$m" ] || m="$mode"
    teardown_audio
    setup_audio "$m"
    seg_i=$((seg_i + 1))
    cur="$segdir/seg_$seg_i"
    wf-recorder "${base_args[@]}" -f "$cur.video.mp4" &
    pid=$!
    if [ -n "$audio_dev" ]; then
        # client-name lets the shell's mic indicator ignore this stream;
        # low latency: on SIGINT parecord drops its unflushed buffer (the
        # default ~2s buffer lost most of a short segment).
        parecord --device="$audio_dev" --client-name=pillshell_rec_audio --latency-msec=50 --file-format=wav "$cur.wav" &
        apid=$!
    fi
}

end_seg() {
    [ -n "$pid" ] || return
    kill -INT "$pid" 2>/dev/null
    [ -n "$apid" ] && kill -INT "$apid" 2>/dev/null
    wait "$pid" 2>/dev/null
    [ -n "$apid" ] && wait "$apid" 2>/dev/null
    pid=""
    apid=""
    if [ -s "$cur.video.mp4" ]; then
        local ain=(-f lavfi -i anullsrc=r=48000:cl=stereo)
        [ -s "$cur.wav" ] && ain=(-i "$cur.wav")
        if ffmpeg -y -i "$cur.video.mp4" "${ain[@]}" -map 0:v:0 -map 1:a:0 -c:v copy -af apad -c:a aac -b:a 160k -ar 48000 -ac 2 -shortest \
            "$cur.mp4" < /dev/null > /dev/null 2>&1; then
            segs+=("$cur.mp4")
        fi
    fi
}

want=run
restart=0
stop=0
trap 'if [ "$want" = run ]; then want=pause; else want=run; fi' USR1
trap 'restart=1' USR2
trap 'stop=1' INT TERM

start_seg

while :; do
    if [ "$stop" = 1 ]; then
        end_seg
        break
    fi
    if [ "$restart" = 1 ]; then
        restart=0
        # paused: the new mode is picked up by the next resume's start_seg
        if [ "$want" = run ]; then
            end_seg
            start_seg
        fi
    fi
    if [ "$want" = pause ] && [ -n "$pid" ]; then
        end_seg
    elif [ "$want" = run ] && [ -z "$pid" ]; then
        start_seg
    fi
    sleep 0.2 &
    wait $! 2>/dev/null
done

# Assemble the final file.
if [ "${#segs[@]}" -eq 1 ]; then
    mv "${segs[0]}" "$out"
elif [ "${#segs[@]}" -gt 1 ]; then
    list="$segdir/list.txt"
    : > "$list"
    for s in "${segs[@]}"; do
        printf "file '%s'\n" "$s" >> "$list"
    done
    ffmpeg -y -f concat -safe 0 -i "$list" -c copy "$out" < /dev/null > /dev/null 2>&1
fi
rm -rf "$segdir"
rm -f "$ctl"

teardown_audio

[ -s "$out" ]
