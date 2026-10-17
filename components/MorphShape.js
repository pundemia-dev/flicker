.pragma library

// Pure-QML stand-in for M3 expressive MaterialShapes (M3Shapes is a C++
// plugin; Flicker stays QML-only): every shape is a polar radius function
// r(θ) normalised to max 1, so a morph is just a per-angle lerp of two of
// them — always the same point count, no correspondence problem.

function polygon(n, round) {
    // Regular n-gon (vertices at r = 1), corners softened toward a circle.
    return function (a) {
        const seg = 2 * Math.PI / n;
        const local = ((a % seg) + seg) % seg - seg / 2;
        const r = Math.cos(Math.PI / n) / Math.cos(local);
        return r * (1 - round) + round;
    };
}

function cookie(n, depth) {
    return a => 1 - depth + depth * (Math.cos(n * a) + 1) / 2;
}

function star(n, depth) {
    // Smoothstep-shaped spikes (sharper than a cookie, still rounded tips).
    return function (a) {
        const t = Math.abs(((a * n / (2 * Math.PI)) % 1 + 1) % 1 - 0.5) * 2; // 1 at tips
        const s = t * t * (3 - 2 * t);
        return 1 - depth + depth * s;
    };
}

const KINDS = {
    circle: () => 1,
    cookie4: cookie(4, 0.22),
    cookie6: cookie(6, 0.16),
    cookie9: cookie(9, 0.12),
    clover: cookie(4, 0.45),
    sunny: cookie(8, 0.2),
    burst: star(12, 0.28),
    star5: star(5, 0.42),
    triangle: polygon(3, 0.18),
    diamond: polygon(4, 0.15),
    pentagon: polygon(5, 0.12),
    hexagon: polygon(6, 0.1)
};

const RANDOM = ["cookie4", "cookie6", "cookie9", "clover", "sunny", "burst", "star5", "triangle", "diamond", "pentagon", "hexagon"];

function fn(kind) {
    return KINDS[kind] ?? KINDS.circle;
}

// Polyline points (closed) of the morph from → to at t, centred in a
// size × size box; `turn` rotates the outline (radians).
function points(from, to, t, size, n, turn) {
    const f = fn(from), g = fn(to), c = size / 2, out = [];
    for (let i = 0; i <= n; i++) {
        const a = 2 * Math.PI * i / n;
        const r = (f(a) * (1 - t) + g(a) * t) * c;
        out.push(Qt.point(c + r * Math.cos(a + turn), c + r * Math.sin(a + turn)));
    }
    return out;
}
