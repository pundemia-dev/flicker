.pragma library

// Teleprompter markdown → blocks of styled pieces + a flat word list.
// A pragmatic subset: # headings, paragraphs, - / 1. lists, > quotes,
// ``` code, ---, **bold**, *italic*, `code`, [link](url) as text, Obsidian
// ==highlight== (==🔴…== 🟠 🟡 🟢 🔵 🟣 = colour; the circle is markup, not
// shown; unclosed == runs to the end of the paragraph, \= escapes; not
// parsed inside `code` / [notes]); %%comments%% are hidden (Obsidian).
// Images: a paragraph of nothing but ![alt](path) = an "img" block (no
// words, not drawn in the text: the module shows it in a side panel from
// its place up to `until` = the %%/img%% after it, else the next images /
// heading / ---); an image inside text, or one that cannot be loaded
// (http(s): Qt's network loader stalls here; a relative path with no base,
// e.g. a clipboard script) = its alt (or file name) as a note. Stage
// directions are NOT spoken:
// [in square brackets], <!-- html comments -->, > quotes and code — drawn
// as notes and skipped by the speech alignment (PrompterAlign), otherwise
// the tracker stalls on them.
//
// Block: { kind: "h"|"p"|"li"|"note"|"code"|"hr"|"img", level, pieces,
//          first, count } (+ images: [{ src, alt }], until for "img":
//          shown while first <= cursor < until; src = URL)
// Piece: { t, b, i, c, n, h, w } — raw text, bold/italic/code/note,
// highlight key ("" | "default" | "red" | "orange" | "yellow" | "green" |
// "blue" | "purple"), word index (-1 = separator). Offsets in a block's
// TextEdit = running sum of raw piece lengths (one space between words,
// "\n" = one line separator; markup such as == and the colour circle adds
// nothing), so htmlFor() and charOffset() must stay in lockstep.
// Word: { text, norm, spoken, block }.

function normalize(s) {
    return String(s).toLowerCase().replace(/ё/g, "е").replace(/[^a-z0-9а-яà-öø-ÿ]+/g, "");
}

const HIGHLIGHTS = { "🔴": "red", "🟠": "orange", "🟡": "yellow", "🟢": "green", "🔵": "blue", "🟣": "purple" };
const IMAGE = /!\[([^\]]*)\]\(\s*(<[^>]*>|[^)\s]*)(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)/y;
const IMAGES_ONLY = /^(?:\s*!\[[^\]]*\]\(\s*(?:<[^>]*>|[^)\s]*)(?:\s+(?:"[^"]*"|'[^']*'))?\s*\))+\s*$/;

// Image path → URL for Image.source, "" = not loadable. opts: { base: dir
// of the script ("" = none), home }. Absolute / ~/ / file:// as is,
// relative against base; any other scheme (http…) is not loaded.
function resolveSrc(url, opts) {
    let s = String(url ?? "").trim().replace(/^<|>$/g, "");
    if (/^file:\/\//i.test(s))
        return s;
    if (s.length === 0 || /^[a-z][a-z0-9+.-]*:/i.test(s))
        return "";
    try {
        s = decodeURIComponent(s);
    } catch (e) {}
    const base = opts?.base ?? "";
    if (s.startsWith("~/") && (opts?.home ?? "").length > 0)
        s = `${opts.home}/${s.slice(2)}`;
    else if (!s.startsWith("/"))
        s = base.length > 0 ? `${base.replace(/\/+$/, "")}/${s}` : "";
    return s.length > 0 ? "file://" + s.split("/").map(encodeURIComponent).join("/") : "";
}

// Name shown for an image: its alt, else the file name.
function imageLabel(alt, url) {
    const a = String(alt ?? "").trim();
    if (a.length > 0)
        return a;
    const name = String(url ?? "").replace(/^<|>$/g, "").split(/[\/?#]/).filter(x => x.length > 0);
    let n = name.length > 0 ? name[name.length - 1] : "image";
    try {
        n = decodeURIComponent(n);
    } catch (e) {}
    return n;
}

function parse(src, opts) {
    const lines = String(src ?? "").replace(/\r\n?/g, "\n").split("\n");
    const out = { blocks: [], words: [], opts: opts ?? {}, imgEnds: [] };
    let para = [];
    let paraKind = "p";

    function flushPara() {
        if (para.length > 0) {
            const text = para.join(" ");
            if (paraKind === "p" && IMAGES_ONLY.test(text))
                addImages(out, text);
            else
                addBlock(out, paraKind, 0, text, "");
        }
        para = [];
        paraKind = "p";
    }

    for (let k = 0; k < lines.length; k++) {
        const line = lines[k];
        const trimmed = line.trim();
        if (/^(```|~~~)/.test(trimmed)) {
            flushPara();
            const fence = trimmed.slice(0, 3);
            const body = [];
            k++;
            while (k < lines.length && !lines[k].trim().startsWith(fence))
                body.push(lines[k++]);
            addCode(out, body);
            continue;
        }
        if (trimmed.startsWith("%%") && (trimmed.match(/%%/g) ?? []).length % 2 === 1) {
            // Multi-line %% comment: hidden; may be the /img end mark.
            flushPara();
            let text = trimmed.slice(2);
            while (!text.includes("%%") && k + 1 < lines.length)
                text += " " + lines[++k].trim();
            if (text.replace(/%%[\s\S]*$/, "").trim() === "/img")
                out.imgEnds.push(out.words.length);
            continue;
        }
        if (trimmed.startsWith("<!--")) {
            flushPara();
            let text = trimmed;
            while (!text.includes("-->") && k + 1 < lines.length)
                text += " " + lines[++k].trim();
            addBlock(out, "note", 0, text.replace(/<!--|-->/g, "").trim(), "", true);
            continue;
        }
        if (trimmed.length === 0) {
            flushPara();
            continue;
        }
        if (/^([-*_])(\s*\1){2,}$/.test(trimmed)) {
            flushPara();
            out.blocks.push({ kind: "hr", level: 0, pieces: [], first: out.words.length, count: 0 });
            continue;
        }
        let m = /^(#{1,6})\s+(.*?)\s*#*$/.exec(trimmed);
        if (m) {
            flushPara();
            addBlock(out, "h", m[1].length, m[2], "");
            continue;
        }
        m = /^>\s?(.*)$/.exec(trimmed);
        if (m) {
            if (paraKind !== "note")
                flushPara();
            paraKind = "note";
            para.push(m[1]);
            continue;
        }
        m = /^([-*+]|\d+[.)])\s+(.*)$/.exec(trimmed);
        if (m) {
            flushPara();
            addBlock(out, "li", 0, m[2], /\d/.test(m[1]) ? m[1].replace(")", ".") + " " : "• ");
            continue;
        }
        if (paraKind === "note")
            flushPara();
        para.push(trimmed);
    }
    flushPara();
    imageSpans(out);
    delete out.opts;
    delete out.imgEnds;
    return out;
}

// `until` of each "img" block: its %%/img%% (the first one after it and
// before the next images), else the next images / heading / ---.
function imageSpans(out) {
    const blocks = out.blocks;
    for (let i = 0; i < blocks.length; i++) {
        const b = blocks[i];
        if (b.kind !== "img")
            continue;
        let next = out.words.length, stop = out.words.length;
        for (let j = i + 1; j < blocks.length; j++) {
            if (blocks[j].kind === "img") {
                next = blocks[j].first;
                break;
            }
            if ((blocks[j].kind === "h" || blocks[j].kind === "hr") && stop === out.words.length)
                stop = blocks[j].first;
        }
        const end = out.imgEnds.find(e => e > b.first && e <= next);
        b.until = end !== undefined ? end : Math.min(stop, next);
    }
}

// A paragraph of images: loadable ones → one "img" row, the rest → their
// names as a note block after it.
function addImages(out, text) {
    const images = [], lost = [];
    const re = new RegExp(IMAGE.source, "g");
    let m;
    while ((m = re.exec(text)) !== null) {
        const src = resolveSrc(m[2], out.opts);
        const alt = imageLabel(m[1], m[2]);
        if (src.length > 0)
            images.push({ src: src, alt: alt });
        else
            lost.push(`[${alt}]`);
    }
    if (images.length > 0)
        out.blocks.push({ kind: "img", level: 0, pieces: [], images: images, first: out.words.length, count: 0 });
    if (lost.length > 0)
        addBlock(out, "note", 0, lost.join(" "), "", true, true);
}

// Inline markup → runs { t, b, i, c, n, h } (text with uniform style),
// plus { mark: "img-end" } where a %%/img%% sits.
// raw: take the text as is (names of lost images: already a note).
function inlineRuns(text, allNote, raw) {
    const runs = [];
    let b = false, it = false, c = false, n = !!allNote, h = "";
    let buf = "";
    const push = () => {
        if (buf.length > 0)
            runs.push({ t: buf, b: b, i: it, c: c, n: n, h: h });
        buf = "";
    };
    if (raw) {
        buf = text;
        push();
        return runs;
    }
    for (let p = 0; p < text.length; p++) {
        const ch = text[p];
        if (ch === "\\" && p + 1 < text.length && !c) {
            buf += text[++p];
            continue;
        }
        if (ch === "`") {
            push();
            c = !c;
            continue;
        }
        if (c) {
            buf += ch;
            continue;
        }
        if (text.startsWith("%%", p)) {
            // Obsidian comment: hidden; %%/img%% = end of the shown images.
            const end = text.indexOf("%%", p + 2);
            push();
            if (text.slice(p + 2, end < 0 ? text.length : end).trim() === "/img")
                runs.push({ mark: "img-end" });
            p = end < 0 ? text.length : end + 1;
            continue;
        }
        if (text.startsWith("<!--", p)) {
            const end = text.indexOf("-->", p + 4);
            push();
            const prev = n;
            n = true;
            buf = text.slice(p + 4, end < 0 ? text.length : end).trim();
            push();
            n = prev;
            p = end < 0 ? text.length : end + 2;
            continue;
        }
        if (ch === "=" && text[p + 1] === "=") {
            push();
            p++;
            if (h.length > 0) {
                h = "";
            } else {
                // Colour circle right after the opening == (+ VS16).
                const circle = text.slice(p + 1, p + 3);
                h = HIGHLIGHTS[circle] ?? "default";
                if (h !== "default")
                    p += 2;
                if (text[p + 1] === "\uFE0F")
                    p++;
            }
            continue;
        }
        if (ch === "*" || (ch === "_" && text[p + 1] === "_")) {
            push();
            if (text[p + 1] === ch) {
                b = !b;
                p++;
            } else {
                it = !it;
            }
            continue;
        }
        if (ch === "!" && text[p + 1] === "[") {
            // Image inside text: its name as a note, never spoken.
            IMAGE.lastIndex = p;
            const m = IMAGE.exec(text);
            if (m) {
                push();
                const prev = n;
                n = true;
                buf = `[${imageLabel(m[1], m[2])}]`;
                push();
                n = prev;
                p += m[0].length - 1;
                continue;
            }
        }
        if (ch === "[") {
            const close = text.indexOf("]", p + 1);
            if (close > p) {
                const inner = text.slice(p + 1, close);
                push();
                if (text[close + 1] === "(") {
                    const paren = text.indexOf(")", close + 2);
                    buf = inner;
                    push();
                    p = paren < 0 ? text.length : paren;
                } else {
                    const prev = n;
                    n = true;
                    buf = `[${inner}]`;
                    push();
                    n = prev;
                    p = close;
                }
                continue;
            }
        }
        buf += ch;
    }
    push();
    return runs;
}

function addBlock(out, kind, level, text, prefix, allNote, raw) {
    const note = kind === "note" || !!allNote;
    const block = { kind: note ? "note" : kind, level: level, pieces: [], first: out.words.length, count: 0 };
    if (prefix.length > 0)
        block.pieces.push({ t: prefix, b: false, i: false, c: false, n: false, h: "", w: -1 });
    // Split runs into words; a word may span several runs (mid-word style).
    // A separator is highlighted when the space and the next word share
    // the highlight (no tails past a closing ==).
    let wordOpen = false;
    let spaceH = "";
    for (const r of inlineRuns(text, note, raw)) {
        if (r.mark === "img-end") {
            out.imgEnds.push(out.words.length);
            continue;
        }
        const parts = r.t.split(/(\s+)/);
        for (const part of parts) {
            if (part.length === 0)
                continue;
            if (/^\s+$/.test(part)) {
                wordOpen = false;
                spaceH = r.h;
                continue;
            }
            if (!wordOpen) {
                if (block.count > 0)
                    block.pieces.push({ t: " ", b: false, i: false, c: false, n: false, h: spaceH === r.h ? r.h : "", w: -1 });
                out.words.push({ text: "", norm: "", spoken: true, block: out.blocks.length });
                block.count++;
                wordOpen = true;
            }
            const wi = out.words.length - 1;
            const w = out.words[wi];
            w.text += part;
            w.norm = normalize(w.text);
            if (r.n || r.c)
                w.spoken = false;
            block.pieces.push({ t: part, b: r.b, i: r.i, c: r.c, n: r.n, h: r.h, w: wi });
        }
    }
    for (let i = block.first; i < block.first + block.count; i++)
        out.words[i].spoken = out.words[i].spoken && out.words[i].norm.length > 0;
    if (block.count > 0 || prefix.length > 0)
        out.blocks.push(block);
}

function addCode(out, body) {
    const block = { kind: "code", level: 0, pieces: [], first: out.words.length, count: 0 };
    body.forEach((line, li) => {
        if (li > 0)
            block.pieces.push({ t: "\n", b: false, i: false, c: true, n: false, h: "", w: -1 });
        for (const part of line.split(/(\s+)/)) {
            if (part.length === 0)
                continue;
            if (/^\s+$/.test(part)) {
                block.pieces.push({ t: part, b: false, i: false, c: true, n: false, h: "", w: -1 });
                continue;
            }
            out.words.push({ text: part, norm: normalize(part), spoken: false, block: out.blocks.length });
            block.pieces.push({ t: part, b: false, i: false, c: true, n: false, h: "", w: out.words.length - 1 });
            block.count++;
        }
    });
    out.blocks.push(block);
}

// Char offset of word `w` inside its block's TextEdit (see header).
function charOffset(block, w) {
    let off = 0;
    for (const p of block.pieces) {
        if (p.w === w)
            return off;
        off += p.t.length;
    }
    return off;
}

function esc(s, code) {
    const e = s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    return code ? e.replace(/ /g, "&nbsp;").replace(/\n/g, "<br/>") : e;
}

// "#rrggbb" / "#aarrggbb" (QML color.toString()) → CSS rgba() with alpha
// `a`: Qt rich text takes rgba(); a bare 8-digit hex would be read as ARGB.
function rgba(hex, a) {
    const v = parseInt(String(hex).replace("#", "").slice(-6), 16) || 0;
    return `rgba(${(v >> 16) & 255},${(v >> 8) & 255},${v & 255},${a})`;
}

// Rich text for a block with read / current / ahead colouring. `cursor` =
// word index of the next word to read. colors: { read, current, ahead,
// note, noteRead, mono, hl: { default, red, … }, hlAlpha, hlReadAlpha }.
// A highlight is a translucent background under that colouring (fainter
// once read); a separator counts as read with the word after it.
function htmlFor(block, cursor, colors) {
    let html = "";
    let lastW = block.first - 1;
    for (const p of block.pieces) {
        const w = p.w >= 0 ? p.w : -1;
        if (w >= 0)
            lastW = w;
        let col;
        if (p.n || block.kind === "note")
            col = w >= 0 && w < cursor ? colors.noteRead : colors.note;
        else if (w < 0)
            col = "";
        else
            col = w < cursor ? colors.read : (w === cursor ? colors.current : colors.ahead);
        let s = esc(p.t, p.c || block.kind === "code");
        if (p.b)
            s = `<b>${s}</b>`;
        if (p.i || p.n)
            s = `<i>${s}</i>`;
        if (p.c && block.kind !== "code")
            s = `<span style="font-family:'${colors.mono}'">${s}</span>`;
        const css = [];
        if (col.length > 0)
            css.push(`color:${col}`);
        if ((p.h ?? "").length > 0) {
            const read = (w >= 0 ? w : lastW + 1) < cursor;
            const a = read ? (colors.hlReadAlpha ?? 0.14) : (colors.hlAlpha ?? 0.35);
            css.push(`background-color:${rgba(colors.hl?.[p.h] ?? colors.hl?.default ?? "#D8BE52", a)}`);
        }
        html += css.length > 0 ? `<span style="${css.join(";")}">${s}</span>` : s;
    }
    return html;
}

// Dominant script of the spoken words: "ru" / "en" (ASR session language).
function detectLang(words) {
    let cyr = 0, lat = 0;
    for (const w of words) {
        if (!w.spoken)
            continue;
        cyr += (w.norm.match(/[а-я]/g) ?? []).length;
        lat += (w.norm.match(/[a-z]/g) ?? []).length;
    }
    return cyr >= lat ? "ru" : "en";
}
