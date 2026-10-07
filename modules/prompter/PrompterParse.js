.pragma library

// Teleprompter markdown → blocks of styled pieces + a flat word list.
// A pragmatic subset: # headings, paragraphs, - / 1. lists, > quotes,
// ``` code, ---, **bold**, *italic*, `code`, [link](url) / ![alt](url) as
// text. Stage directions are NOT spoken: [in square brackets], <!-- html
// comments -->, > quotes and code — drawn as notes and skipped by the
// speech alignment (PrompterAlign), otherwise the tracker stalls on them.
//
// Block: { kind: "h"|"p"|"li"|"note"|"code"|"hr", level, pieces, first, count }
// Piece: { t, b, i, c, n, w } — raw text, bold/italic/code/note, word index
// (-1 = separator). Offsets in a block's TextEdit = running sum of raw
// piece lengths (one space between words, "\n" = one line separator), so
// htmlFor() and charOffset() must stay in lockstep.
// Word: { text, norm, spoken, block }.

function normalize(s) {
    return String(s).toLowerCase().replace(/ё/g, "е").replace(/[^a-z0-9а-яà-öø-ÿ]+/g, "");
}

function parse(src) {
    const lines = String(src ?? "").replace(/\r\n?/g, "\n").split("\n");
    const out = { blocks: [], words: [] };
    let para = [];
    let paraKind = "p";

    function flushPara() {
        if (para.length > 0)
            addBlock(out, paraKind, 0, para.join(" "), "");
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
    return out;
}

// Inline markup → runs { t, b, i, c, n } (text with uniform style).
function inlineRuns(text, allNote) {
    const runs = [];
    let b = false, it = false, c = false, n = !!allNote;
    let buf = "";
    const push = () => {
        if (buf.length > 0)
            runs.push({ t: buf, b: b, i: it, c: c, n: n });
        buf = "";
    };
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
            continue; // image: keep the alt text
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

function addBlock(out, kind, level, text, prefix, allNote) {
    const note = kind === "note" || !!allNote;
    const block = { kind: note ? "note" : kind, level: level, pieces: [], first: out.words.length, count: 0 };
    if (prefix.length > 0)
        block.pieces.push({ t: prefix, b: false, i: false, c: false, n: false, w: -1 });
    // Split runs into words; a word may span several runs (mid-word style).
    let wordOpen = false;
    for (const r of inlineRuns(text, note)) {
        const parts = r.t.split(/(\s+)/);
        for (const part of parts) {
            if (part.length === 0)
                continue;
            if (/^\s+$/.test(part)) {
                wordOpen = false;
                continue;
            }
            if (!wordOpen) {
                if (block.count > 0)
                    block.pieces.push({ t: " ", b: false, i: false, c: false, n: false, w: -1 });
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
            block.pieces.push({ t: part, b: r.b, i: r.i, c: r.c, n: r.n, w: wi });
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
            block.pieces.push({ t: "\n", b: false, i: false, c: true, n: false, w: -1 });
        for (const part of line.split(/(\s+)/)) {
            if (part.length === 0)
                continue;
            if (/^\s+$/.test(part)) {
                block.pieces.push({ t: part, b: false, i: false, c: true, n: false, w: -1 });
                continue;
            }
            out.words.push({ text: part, norm: normalize(part), spoken: false, block: out.blocks.length });
            block.pieces.push({ t: part, b: false, i: false, c: true, n: false, w: out.words.length - 1 });
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

// Rich text for a block with read / current / ahead colouring. `cursor` =
// word index of the next word to read. colors: { read, current, ahead,
// note, noteRead, mono }.
function htmlFor(block, cursor, colors) {
    let html = "";
    for (const p of block.pieces) {
        const w = p.w >= 0 ? p.w : -1;
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
        html += col.length > 0 ? `<span style="color:${col}">${s}</span>` : s;
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
