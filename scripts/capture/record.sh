#!/usr/bin/env bash
# record.sh <audio-mode> <out-file> [wf-recorder extra args…]
# Port of pShell scripts/capture_record.sh.
#
# audio-mode: none | system | mic | both
#   system — the default sink's monitor (what the speakers play)
#   mic    — the default input source
#   both   — the sink monitor and the mic recorded by two parecords, mixed
#            by ffmpeg (amix) per segment. The old null sink + 2 loopbacks
#            mix recorded DIGITAL SILENCE in ~1 of 4 runs whenever another
#            stream started meanwhile (graph linked fine, zeros came out —
#            reproduced on the old script too, Oct 2026).
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
#
# Speed: "<out-file>.speedctl" holds the playback speed for the NEXT
# segment (the shell writes it + SIGUSR2, like the audio switch), so a
# speed applies from the moment it was picked. A segment with speed ≠ 1 is
# re-timed after its mux (setpts + atempo, pitch kept; libx264 re-encode,
# frame rate capped at --max-fps via a 1/fps encoder time base: ffmpeg 9
# rejects -r / -fpsmax together with -fps_mode vfr) in the BACKGROUND (niced)
# while the next segment records. With any speed used the final concat
# re-encodes through the concat filter (copy otherwise).
# "<out-file>.discard" present at stop = skip the assembly.
set -u

mode="$1"
out="$2"
shift 2

# Optional "--hw <render-node>": VAAPI encode when a libva driver exists
# (silent CPU fallback otherwise). Cross-GPU encode is broken in
# wf-recorder, so only pass the compositor's node here.
hwdev=""
maxfps=60
extra=()
while [ $# -gt 0 ]; do
    if [ "$1" = "--hw" ] && [ $# -ge 2 ]; then
        hwdev="$2"
        shift 2
    elif [ "$1" = "--max-fps" ] && [ $# -ge 2 ]; then
        maxfps="$2"
        shift 2
    else
        extra+=("$1")
        shift
    fi
done

ctl="$out.audioctl"
speedctl="$out.speedctl"
discardflag="$out.discard"
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
mic_dev=""

# Unload pillshell_rec leftovers from a crashed session.
pactl list short modules 2>/dev/null | grep pillshell_rec | cut -f1 | while read -r m; do
    pactl unload-module "$m" 2>/dev/null
done

setup_audio() {
    local m="$1" sink
    audio_dev=""
    mic_dev=""
    case "$m" in
    system)
        sink="$(pactl get-default-sink 2>/dev/null)"
        [ -n "$sink" ] && audio_dev="$sink.monitor"
        ;;
    mic)
        audio_dev="$(pactl get-default-source 2>/dev/null)"
        ;;
    both)
        sink="$(pactl get-default-sink 2>/dev/null)"
        [ -n "$sink" ] && audio_dev="$sink.monitor"
        mic_dev="$(pactl get-default-source 2>/dev/null)"
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

# atempo takes 0.5..2 per stage (older ffmpeg): chain stages for the rest.
atempo_chain() {
    awk -v s="$1" 'BEGIN { c = ""; while (s > 2) { c = c "atempo=2,"; s /= 2 } while (s < 0.5) { c = c "atempo=0.5,"; s *= 2 } printf "%satempo=%.6f", c, s }'
}

# Re-time "$1" by speed "$2" into "$3".
retime() {
    ffmpeg -y -i "$1" -filter:v "setpts=PTS/$2" -af "$(atempo_chain "$2")" \
        -fps_mode vfr -enc_time_base "1/$maxfps" -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p \
        -c:a aac -b:a 160k -ar 48000 -ac 2 "$3" < /dev/null > /dev/null 2>&1
}

segs=()
finishers=()
audio_mode_cur=""
sped=0
seg_speed=1
seg_i=0
pid=""
apid=""
mpid=""
cur=""

start_seg() {
    local m
    m="$(cat "$ctl" 2>/dev/null || true)"
    [ -n "$m" ] || m="$mode"
    seg_speed="$(cat "$speedctl" 2>/dev/null || true)"
    [ -n "$seg_speed" ] || seg_speed=1
    # Same source as the running segment: keep the modules (the previous
    # parecord may still be flushing from them).
    if [ "$m" != "$audio_mode_cur" ]; then
        teardown_audio
        setup_audio "$m"
        audio_mode_cur="$m"
    fi
    seg_i=$((seg_i + 1))
    cur="$segdir/seg_$seg_i"
    wf-recorder "${base_args[@]}" -f "$cur.video.mp4" &
    pid=$!
    if [ -n "$audio_dev" ]; then
        # client-name lets the shell's mic indicator ignore this stream;
        # low latency: on SIGINT parecord drops its unflushed buffer (the
        # default ~2s buffer lost most of a short segment).
        parecord --device="$audio_dev" --client-name=pillshell_rec_audio --latency-msec=50 --rate=48000 --file-format=wav "$cur.wav" &
        apid=$!
    fi
    if [ -n "$mic_dev" ]; then
        parecord --device="$mic_dev" --client-name=pillshell_rec_mic --latency-msec=50 --rate=48000 --file-format=wav "$cur.mic.wav" &
        mpid=$!
    fi
}

# Mux (+ re-time) one finished segment into "$1.final.mp4". Runs in the
# background: done inline it left a capture gap as long as the re-encode
# (measured 1.4 s for a 3.5 s segment) before the next segment started.
finalize_seg() {
    local c="$1" sp="$2"
    [ -s "$c.video.mp4" ] || return
    local ain=(-f lavfi -i anullsrc=r=48000:cl=stereo) af="[1:a]apad[a]"
    if [ -s "$c.wav" ] && [ -s "$c.mic.wav" ]; then
        ain=(-i "$c.wav" -i "$c.mic.wav")
        af="[1:a][2:a]amix=inputs=2:duration=longest:normalize=0,apad[a]"
    elif [ -s "$c.wav" ]; then
        ain=(-i "$c.wav")
    elif [ -s "$c.mic.wav" ]; then
        ain=(-i "$c.mic.wav")
    fi
    ffmpeg -y -i "$c.video.mp4" "${ain[@]}" -filter_complex "$af" -map 0:v:0 -map "[a]" -c:v copy -c:a aac -b:a 160k -ar 48000 -ac 2 -shortest \
        "$c.mp4" < /dev/null > /dev/null 2>&1 || return
    if [ "$sp" != 1 ] && [ ! -e "$discardflag" ] && retime "$c.mp4" "$sp" "$c.r.mp4"; then
        mv "$c.r.mp4" "$c.final.mp4"
    else
        mv "$c.mp4" "$c.final.mp4"
    fi
}

# Signal the segment's recorders and hand them to a background finisher
# that waits for them to exit, then muxes / re-times. NOT waited here: a
# wf-recorder took ~2.4 s to exit (VAAPI) — the next segment (speed / audio
# switch, resume) must start at once instead of leaving a capture gap.
# (bash reaps its exited children itself, so `kill -0` turns false.)
end_seg() {
    [ -n "$pid" ] || return
    kill -INT "$pid" 2>/dev/null
    [ -n "$apid" ] && kill -INT "$apid" 2>/dev/null
    [ -n "$mpid" ] && kill -INT "$mpid" 2>/dev/null
    segs+=("$cur.final.mp4")
    [ "$seg_speed" != 1 ] && sped=1
    nice -n 10 bash -c "$(declare -f finalize_seg retime atempo_chain)
        for p in $pid $apid $mpid; do while kill -0 \$p 2>/dev/null; do sleep 0.05; done; done
        discardflag=$(printf %q "$discardflag") maxfps=$maxfps finalize_seg $(printf %q "$cur") $seg_speed" &
    finishers+=($!)
    pid=""
    apid=""
    mpid=""
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

# Saving progress for the shell (Recorder.saveProgress → status drop):
# "progress <0..1>" lines on stdout. Finishers count up to `fw`, the
# assembly fills the rest (a re-encoding concat reports ffmpeg's time).
progress() { printf 'progress %s\n' "$1"; }
fw=0.9
[ "$sped" = 1 ] && [ "${#segs[@]}" -gt 1 ] && fw=0.5
[ -e "$discardflag" ] && fw=1
progress 0

# Wait for the background finishers, keep the segments that made it.
fi_n=${#finishers[@]}
fi_i=0
for f in "${finishers[@]}"; do
    while kill -0 "$f" 2>/dev/null; do wait "$f" 2>/dev/null; done
    fi_i=$((fi_i + 1))
    progress "$(awk -v i=$fi_i -v n=$fi_n -v w=$fw 'BEGIN { printf "%.3f", w * i / n }')"
done
done_segs=()
for f in "${segs[@]}"; do
    [ -s "$f" ] && done_segs+=("$f")
done
segs=("${done_segs[@]}")

# Assemble the final file.
if [ -e "$discardflag" ]; then
    :
elif [ "${#segs[@]}" -eq 1 ]; then
    mv "${segs[0]}" "$out"
elif [ "${#segs[@]}" -gt 1 ]; then
    list="$segdir/list.txt"
    : > "$list"
    for s in "${segs[@]}"; do
        printf "file '%s'\n" "$s" >> "$list"
    done
    if [ "$sped" = 1 ]; then
        # Any speed used: the concat DEMUXER mis-times segments of different
        # time bases (measured: video 2.7 s vs audio 5.8 s) — the concat
        # FILTER re-times every input.
        ins=()
        pads=""
        for i in "${!segs[@]}"; do
            ins+=(-i "${segs[i]}")
            pads="$pads[$i:v:0][$i:a:0]"
        done
        total=0
        for s in "${segs[@]}"; do
            d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$s" 2>/dev/null)
            total=$(awk -v a="$total" -v b="${d:-0}" 'BEGIN { printf "%.3f", a + b }')
        done
        ffmpeg -y "${ins[@]}" -filter_complex "${pads}concat=n=${#segs[@]}:v=1:a=1[v][a]" -map "[v]" -map "[a]" \
            -fps_mode vfr -enc_time_base "1/$maxfps" -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p \
            -c:a aac -b:a 160k -ar 48000 -ac 2 -nostats -progress pipe:1 "$out" < /dev/null 2>/dev/null \
            | awk -F= -v t="$total" -v w="$fw" '$1 == "out_time_us" && t > 0 { p = w + (1 - w) * ($2 / 1e6) / t; if (p > 1) p = 1; if (p >= 0) { printf "progress %.3f\n", p; fflush() } }'
    else
        ffmpeg -y -f concat -safe 0 -i "$list" -c copy "$out" < /dev/null > /dev/null 2>&1
    fi
fi
progress 1
rm -rf "$segdir"
rm -f "$ctl" "$speedctl" "$discardflag"

teardown_audio

[ -s "$out" ]
