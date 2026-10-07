.pragma library

// Speech → script position tracker (pure; tested in a node harness).
//
// The script is the list of SPOKEN normalized words; `heard` the tail of
// recognized words (finals + the live partial, normalized). A local
// Smith-Waterman alignment of the heard tail against the script finds where
// the speaker is: fuzzy word match (Levenshtein, so inflections / ASR typos
// still count), short words weigh little (they match everywhere), small
// gaps on both sides (skipped script words, inserted heard words) cost a
// bit, unmatched heard words at the END of the tail cost more (the speaker
// is not there any more).
//
// step() = one update:
//  1. local window around the cursor (behind a little, ahead `ahead`
//     words), distance-penalized → normal word-by-word tracking. The cursor
//     only moves forward, except a strong match well behind (re-reading).
//  2. once `globalAfter` heard words in a row matched nothing nearby
//     (ad-lib, skipped section) — search the WHOLE script, accept only a
//     strong, unique run (≥ minGlobalMatches words ending at the newest
//     heard words) → jump there. That is the "drifted off topic, came back"
//     recovery: the off-script talk is simply never matched, and the first
//     few words back on the script re-acquire the position.
//  3. `lost` = lostAfter heard words without any match (UI: searching).

const DEF = {
    tail: 8,          // heard words considered
    back: 8,          // local window behind the cursor
    ahead: 60,        // local window ahead of the cursor
    gapHeard: 2,      // max inserted heard words between two matches
    gapScript: 3,     // max skipped script words between two matches
    gapCost: 0.3,
    trailCost: 0.45,  // per unmatched heard word after the last match
    minSim: 0.6,
    minLocal: 1.4,
    minGlobal: 2.6,
    minGlobalMatches: 3,
    uniqueMargin: 0.8,
    globalAfter: 3,
    lostAfter: 6
};

function lev(a, b) {
    const m = a.length, n = b.length;
    let prev = new Array(n + 1), cur = new Array(n + 1);
    for (let j = 0; j <= n; j++)
        prev[j] = j;
    for (let i = 1; i <= m; i++) {
        cur[0] = i;
        for (let j = 1; j <= n; j++)
            cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
        const t = prev;
        prev = cur;
        cur = t;
    }
    return prev[n];
}

function sim(a, b, minSim) {
    if (a === b)
        return 1;
    const la = a.length, lb = b.length;
    const mx = Math.max(la, lb), mn = Math.min(la, lb);
    if (mn <= 2 || la === 0 || lb === 0)
        return 0;
    if (mx - mn > mx * 0.5)
        return 0;
    let s = 1 - lev(a, b) / mx;
    // Same stem, different ending (ru inflection): "работы" ~ "работа".
    let p = 0;
    while (p < mn && a[p] === b[p])
        p++;
    if (p >= 4 && p >= mn * 0.6)
        s = Math.max(s, 0.8);
    return s >= minSim ? s : 0;
}

function weight(w) {
    return w.length <= 2 ? 0.35 : (w.length === 3 ? 0.7 : 1);
}

// Best local alignment of `heard` against script[lo..hi]. penalty(j) is
// subtracted from candidates ending at script j. Returns per-candidate
// best + the best one far from it (uniqueness).
function align(heard, script, lo, hi, opt, penalty) {
    const K = heard.length, W = hi - lo + 1;
    if (K === 0 || W <= 0)
        return null;
    const M = new Float64Array(K * W).fill(-1);
    const C = new Int32Array(K * W);      // matched words on the path
    const S = new Int32Array(K * W);      // path start (script j)
    const cache = new Map();
    let best = null;
    const perJ = new Float64Array(W).fill(-Infinity);
    for (let t = 0; t < K; t++) {
        for (let jj = 0; jj < W; jj++) {
            const j = lo + jj;
            const key = heard[t] + "\u0001" + script[j];
            let s = cache.get(key);
            if (s === undefined) {
                s = sim(heard[t], script[j], opt.minSim) * weight(script[j]);
                cache.set(key, s);
            }
            if (s <= 0)
                continue;
            let bp = 0, bc = 0, bs = j;
            for (let tp = Math.max(0, t - 1 - opt.gapHeard); tp < t; tp++) {
                for (let jp = Math.max(0, jj - 1 - opt.gapScript); jp < jj; jp++) {
                    const v = M[tp * W + jp];
                    if (v < 0)
                        continue;
                    const sc = v - opt.gapCost * ((t - 1 - tp) + (jj - 1 - jp));
                    if (sc > bp) {
                        bp = sc;
                        bc = C[tp * W + jp];
                        bs = S[tp * W + jp];
                    }
                }
            }
            const idx = t * W + jj;
            M[idx] = s + bp;
            C[idx] = bc + 1;
            S[idx] = bs;
            const f = M[idx] - opt.trailCost * (K - 1 - t) - (penalty ? penalty(j) : 0);
            if (f > perJ[jj])
                perJ[jj] = f;
            if (!best || f > best.score)
                best = { score: f, raw: M[idx], end: j, start: S[idx], t: t, matched: C[idx] };
        }
    }
    if (!best)
        return null;
    let second = -Infinity;
    for (let jj = 0; jj < W; jj++)
        if (Math.abs(lo + jj - best.end) > 10 && perJ[jj] > second)
            second = perJ[jj];
    best.second = second;
    return best;
}

// One tracking update.
// st: { cursor (spoken index of the next word to read), lastMatch (abs
//       heard index of the newest matched heard word, -1 = none) }
// heard: normalized words, heardEnd: abs index just past heard's last word.
// Returns the new { cursor, lastMatch, lost, jumped, searched (global ran) }.
// options override DEF; allowGlobal: false skips the whole-script search
// (the caller throttles it — it is the expensive part on long scripts).
function step(script, st, heard, heardEnd, options) {
    const opt = Object.assign({}, DEF, options ?? {});
    const n = script.length;
    const res = { cursor: st.cursor, lastMatch: Math.min(st.lastMatch, heardEnd - 1), lost: false, jumped: false, searched: false };
    if (n === 0 || heard.length === 0)
        return res;
    const tail = heard.slice(-opt.tail);
    const absOf = t => heardEnd - tail.length + t;
    const cur = st.cursor;
    const lo = Math.max(0, cur - opt.back), hi = Math.min(n - 1, cur + opt.ahead);
    const local = align(tail, script, lo, hi, opt, j => {
        const d = j - (cur - 1);
        return d >= 0 ? 0.015 * d : 0.25 * -d;
    });
    let accepted = false;
    if (local) {
        const sure = local.matched >= 2 && local.score >= opt.minLocal;
        // A single solid word right at the cursor: word-by-word progress
        // while the partial grows.
        const single = local.matched === 1 && local.t === tail.length - 1
            && local.end >= cur && local.end <= cur + 1 && local.raw >= 0.75;
        if ((sure || single) && local.end >= cur - 3) {
            accepted = true;
            res.cursor = Math.max(cur, local.end + 1);
        } else if (local.matched >= 3 && local.score >= 2.5 && local.t >= tail.length - 2) {
            accepted = true; // re-reading an earlier passage
            res.cursor = local.end + 1;
        }
        if (accepted)
            res.lastMatch = Math.max(res.lastMatch, absOf(local.t));
    }
    if (!accepted && opt.allowGlobal !== false && heardEnd - 1 - res.lastMatch >= opt.globalAfter) {
        res.searched = true;
        const g = align(tail, script, 0, n - 1, opt, j => j < cur ? 0.002 * (cur - j) : 0);
        if (g && g.matched >= opt.minGlobalMatches && g.score >= opt.minGlobal
            && g.t >= tail.length - 2 && g.score - g.second >= opt.uniqueMargin) {
            res.jumped = g.end + 1 !== cur;
            res.cursor = g.end + 1;
            res.lastMatch = absOf(g.t);
            accepted = true;
        }
    }
    res.lost = heardEnd - 1 - res.lastMatch >= opt.lostAfter;
    return res;
}
