.pragma library

// Transcript result (scripts/stash/transcribe.py JSON) → what the stash
// transcript view shows / copies / saves. No timecodes anywhere except .srt.

// Segments → paragraphs [{speaker, text}]: consecutive segments join while
// the pause between them is under gapSec, the speaker stays the same and
// the paragraph is under maxChars.
function paragraphs(doc, gapSec, maxChars) {
    const out = [];
    let cur = null;
    let lastEnd = 0;
    for (const s of doc?.segments ?? []) {
        const spk = s.speaker ?? "";
        if (cur && spk === cur.speaker && s.start - lastEnd < gapSec && cur.text.length + s.text.length < maxChars)
            cur.text += " " + s.text;
        else {
            cur = { speaker: spk, text: s.text };
            out.push(cur);
        }
        lastEnd = s.end;
    }
    return out;
}

// SPEAKER_00 → "Speaker 1" (label = the translated "Speaker %1").
function speakerName(id, label) {
    const m = /(\d+)$/.exec(id ?? "");
    return m ? label.arg(parseInt(m[1]) + 1) : (id ?? "");
}

// Plain text: paragraphs split by a blank line; with speakers, a name line
// whenever the speaker changes.
function plain(paras, label) {
    const parts = [];
    let last = null;
    for (const p of paras) {
        if (p.speaker !== "" && p.speaker !== last)
            parts.push(speakerName(p.speaker, label) + ":\n" + p.text);
        else
            parts.push(p.text);
        last = p.speaker;
    }
    return parts.join("\n\n") + "\n";
}

function stamp(t) {
    const ms = Math.max(0, Math.round(t * 1000));
    const pad = (n, w) => String(n).padStart(w, "0");
    return `${pad(Math.floor(ms / 3600000), 2)}:${pad(Math.floor(ms / 60000) % 60, 2)}:${pad(Math.floor(ms / 1000) % 60, 2)},${pad(ms % 1000, 3)}`;
}

function srt(doc, label) {
    return (doc?.segments ?? []).map((s, i) => {
        const who = s.speaker ? `[${speakerName(s.speaker, label)}] ` : "";
        return `${i + 1}\n${stamp(s.start)} --> ${stamp(s.end)}\n${who}${s.text}\n`;
    }).join("\n");
}
