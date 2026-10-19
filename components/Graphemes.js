.pragma library

// A string as user-perceived characters (RollingText slots, per-character
// widths). QML's JS has no Intl.Segmenter and charAt() splits surrogate
// pairs, so emoji came out as two broken halves. Enough of UAX #29 for
// what the shell shows: surrogate pairs, flags (regional indicator pairs),
// ZWJ sequences, variation selectors, skin tones, keycaps, emoji tag
// sequences and combining marks stay one cluster.

function isRegional(c) {
    return c >= 0x1F1E6 && c <= 0x1F1FF;
}

// Attaches to the cluster before it.
function isExtend(c) {
    return c >= 0x0300 && c <= 0x036F      // combining diacritics
        || c >= 0x1AB0 && c <= 0x1AFF
        || c >= 0x1DC0 && c <= 0x1DFF
        || c >= 0x20D0 && c <= 0x20FF      // combining marks for symbols, keycap 20E3
        || c >= 0xFE00 && c <= 0xFE0F      // variation selectors
        || c >= 0xFE20 && c <= 0xFE2F
        || c >= 0x1F3FB && c <= 0x1F3FF    // skin tones
        || c >= 0xE0020 && c <= 0xE007F    // emoji tag sequences
        || c === 0x200D;                   // ZWJ (the next one joins too)
}

function split(s) {
    const out = [];
    let joinNext = false;
    let regionalOpen = false;
    for (const ch of String(s)) {
        const c = ch.codePointAt(0);
        const last = out.length - 1;
        if (last >= 0 && (joinNext || isExtend(c) || isRegional(c) && regionalOpen)) {
            out[last] += ch;
            regionalOpen = false;
        } else {
            out.push(ch);
            regionalOpen = isRegional(c);
        }
        joinNext = c === 0x200D;
    }
    return out;
}
