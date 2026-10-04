.pragma library

// Colour helpers for the capture pipette (port of pShell services/Capture
// colour formatting + ColorPanel text parsing).

function clamp255(v) {
    return Math.max(0, Math.min(255, Math.round(v)));
}

function toHex(r, g, b) {
    const h = n => clamp255(n).toString(16).padStart(2, "0");
    return `#${h(r)}${h(g)}${h(b)}`;
}

function rgbToHsl(r, g, b) {
    r /= 255;
    g /= 255;
    b /= 255;
    const max = Math.max(r, g, b), min = Math.min(r, g, b);
    let h = 0, s = 0;
    const l = (max + min) / 2;
    const d = max - min;
    if (d !== 0) {
        s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
        if (max === r)
            h = (g - b) / d + (g < b ? 6 : 0);
        else if (max === g)
            h = (b - r) / d + 2;
        else
            h = (r - g) / d + 4;
        h /= 6;
    }
    return { h: Math.round(h * 360), s: Math.round(s * 100), l: Math.round(l * 100) };
}

function format(r, g, b, fmt) {
    switch (fmt) {
    case "rgb":
        return `rgb(${clamp255(r)}, ${clamp255(g)}, ${clamp255(b)})`;
    case "rgba":
        return `rgba(${clamp255(r)}, ${clamp255(g)}, ${clamp255(b)}, 1)`;
    case "hsl": {
        const c = rgbToHsl(r, g, b);
        return `hsl(${c.h}, ${c.s}%, ${c.l}%)`;
    }
    default:
        return toHex(r, g, b);
    }
}

// Typed colour → {r, g, b} or {h, s, l} (0..1), null when invalid:
// hex (#abc / #aabbcc), rgb()/rgba(), hsl()/hsla().
function parse(t) {
    const s = String(t).trim().toLowerCase();
    let m = s.match(/^#?([0-9a-f]{6})$/);
    if (m)
        return { r: parseInt(m[1].slice(0, 2), 16), g: parseInt(m[1].slice(2, 4), 16), b: parseInt(m[1].slice(4, 6), 16) };
    m = s.match(/^#?([0-9a-f]{3})$/);
    if (m)
        return { r: parseInt(m[1][0] + m[1][0], 16), g: parseInt(m[1][1] + m[1][1], 16), b: parseInt(m[1][2] + m[1][2], 16) };
    m = s.match(/^rgba?\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)/);
    if (m)
        return { r: clamp255(parseInt(m[1])), g: clamp255(parseInt(m[2])), b: clamp255(parseInt(m[3])) };
    m = s.match(/^hsla?\(\s*(\d+)[,\s]+(\d+)%?[,\s]+(\d+)%?/);
    if (m)
        return {
            h: Math.max(0, Math.min(360, parseInt(m[1]))) / 360,
            s: Math.max(0, Math.min(100, parseInt(m[2]))) / 100,
            l: Math.max(0, Math.min(100, parseInt(m[3]))) / 100
        };
    return null;
}
