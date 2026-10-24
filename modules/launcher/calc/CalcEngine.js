.pragma library
.import "CalcUnits.js" as Units

// Launcher calculator: arithmetic, percentages, units, currencies, number
// bases, dates. Pure and synchronous (runs on every keystroke). No eval():
// a tokenizer + precedence-climbing parser over quantities
// { v (value in base units), d (dimension exponents), u (display unit) }.
//
// evaluate(query, ctx) → null (not a calculation) or
//   { ok, error, needRates, kind, expr, exprCaption, partial,
//     results: [{ text, copy, caption, icon }] }
// ctx = { forced, rates ({CODE: per USD}), currencies ([codes]), lang,
//         ans (number), tr(s), formatDate(Date), now (Date) }

const glyph = {
    math: "",      // calculator
    unit: "",      // arrows-exchange
    money: "",     // coins
    date: "",      // calendar-event
    time: "",      // clock
    base: "",      // binary
    temp: ""       // temperature
};

// ---------------------------------------------------------------- tokens

const opChars = {
    "+": "+", "-": "-", "−": "-", "–": "-", "*": "*", "×": "*", "·": "*", "⋅": "*",
    "/": "/", "÷": "/", "^": "^", "%": "%", "‰": "‰", "(": "(", ")": ")", "[": "(", "]": ")",
    ",": ",", ";": ",", "!": "!", "²": "²", "³": "³", "√": "√", "∛": "∛"
};
const scales = {
    "k": 1e3, "к": 1e3, "тыс": 1e3, "тысяч": 1e3, "тысячи": 1e3, "тысяча": 1e3, "thousand": 1e3,
    "mln": 1e6, "млн": 1e6, "миллион": 1e6, "миллиона": 1e6, "миллионов": 1e6, "million": 1e6,
    "mlrd": 1e9, "млрд": 1e9, "миллиард": 1e9, "миллиарда": 1e9, "миллиардов": 1e9, "billion": 1e9, "bn": 1e9,
    "трлн": 1e12, "trillion": 1e12
};

function tokenize(src) {
    const out = [];
    let i = 0;
    while (i < src.length) {
        const ch = src[i];
        if (/\s/.test(ch)) {
            i++;
            continue;
        }
        const space = i > 0 && /\s/.test(src[i - 1]);
        const rest = src.slice(i);
        let m = /^0x[0-9a-f]+|^0b[01]+|^0o[0-7]+/i.exec(rest);
        if (m) {
            const base = { x: 16, b: 2, o: 8 }[m[0][1].toLowerCase()];
            out.push({ t: "num", v: parseInt(m[0].slice(2), base), base: base, space: space, at: i });
            i += m[0].length;
            continue;
        }
        // 1,000,000.5 | 1 000 000,5 | 2,5 | .5 | 1e-3
        m = /^\d{1,3}(?:,\d{3})+(?![\d,])(?:\.\d+)?/.exec(rest)
            || /^\d{1,3}(?:[   ']\d{3})+(?![\d])(?:[.,]\d+)?/.exec(rest)
            || /^(?:\d+(?:[.,]\d+)?|[.,]\d+)(?:e[+-]?\d+)?/i.exec(rest);
        if (m && /\d/.test(m[0][0] === "." || m[0][0] === "," ? m[0][1] : m[0][0])) {
            let s = m[0];
            if (/^\d{1,3}(,\d{3})+/.test(s) && !/[   ']/.test(s))
                s = s.replace(/,/g, "");
            s = s.replace(/[   ']/g, "").replace(",", ".");
            out.push({ t: "num", v: parseFloat(s), space: space, at: i });
            i += m[0].length;
            continue;
        }
        if (rest.startsWith("**")) {
            out.push({ t: "op", v: "^", space: space, at: i });
            i += 2;
            continue;
        }
        if (/^(->|→|=>)/.test(rest)) {
            out.push({ t: "op", v: "->", space: space, at: i });
            i += rest[0] === "→" ? 1 : 2;
            continue;
        }
        // Multi-character unit aliases (km/h, m², °C, $, мм рт ст) win over
        // operators: "/" inside km/h is not a division.
        const sp = Units.matchSpecial(rest);
        if (sp && !(sp.len === 1 && opChars[rest[0]])) {
            out.push({ t: "unit", unit: sp.unit, text: rest.slice(0, sp.len), space: space, at: i });
            i += sp.len;
            continue;
        }
        if (opChars[ch]) {
            out.push({ t: "op", v: opChars[ch], space: space, at: i });
            i++;
            continue;
        }
        if (ch === "=") {
            out.push({ t: "op", v: "=", space: space, at: i });
            i++;
            continue;
        }
        m = /^[A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FFµ°_π][A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF\d_µ°]*/.exec(rest);
        if (m) {
            // Words stop before digits that follow letters ("km2" was a
            // special above; "sqrt2" = sqrt 2).
            const w = /^[^\d]+/.exec(m[0])[0];
            out.push({ t: "word", v: w, space: space, at: i });
            i += w.length;
            continue;
        }
        throw new Error("Unexpected “" + ch + "”");
    }
    return out;
}

// ------------------------------------------------------------ quantities

function scalar(v) {
    return { v: v, d: {}, u: null };
}
function isScalar(q) {
    return Units.dimKey(q.d) === "";
}
function sameDim(a, b) {
    return Units.dimKey(a.d) === Units.dimKey(b.d);
}
function dimOp(a, b, sign) {
    const d = Object.assign({}, a);
    for (const k in b)
        d[k] = (d[k] || 0) + sign * b[k];
    for (const k in d)
        if (d[k] === 0)
            delete d[k];
    return d;
}
// Value in the display unit / back (temperatures carry an offset).
function toUnit(q, u) {
    return q.v / u.f - (u.o || 0);
}
function fromUnit(x, u) {
    return (x + (u.o || 0)) * u.f;
}

const sup = { "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻" };
function superscript(n) {
    return String(n).split("").map(c => sup[c] || c).join("");
}

// Display unit for a product / quotient of two units.
function composeUnit(a, b, sign) {
    if (!a && !b)
        return null;
    const fa = a ? a.f : 1, fb = b ? b.f : 1;
    const d = dimOp(a ? a.d : {}, b ? b.d : {}, sign);
    if (Units.dimKey(d) === "")
        return null;
    let sym;
    if (!a)
        sym = sign > 0 ? b.sym : "1/" + b.sym;
    else if (!b)
        sym = a.sym;
    else if (a.sym === b.sym && sign > 0)
        sym = a.sym + "²";
    else if (a.sym + "²" === b.sym && sign > 0)
        sym = a.sym + "³";
    else
        sym = a.sym + (sign > 0 ? "·" : "/") + b.sym;
    const known = Units.units[sym];
    if (known)
        return known;
    return { sym: sym, f: sign > 0 ? fa * fb : fa / fb, d: d };
}

function powUnit(u, n) {
    if (!u)
        return null;
    const d = {};
    for (const k in u.d)
        d[k] = u.d[k] * n;
    const sym = u.sym + superscript(n);
    return Units.units[sym] || { sym: sym, f: Math.pow(u.f, n), d: d };
}

// m/s^2 = m/s²: a power after a compound unit belongs to its denominator.
function powLast(u, n) {
    const slash = u.sym.lastIndexOf("/");
    if (slash > 0) {
        const num = Units.lookup(u.sym.slice(0, slash)), den = Units.lookup(u.sym.slice(slash + 1));
        if (num && den && !num.currency && !den.currency)
            return composeUnit(num, powUnit(den, n), -1);
    }
    return powUnit(u, n);
}

// ---------------------------------------------------------------- parser

const functions = {
    sqrt: Math.sqrt, "√": Math.sqrt, cbrt: Math.cbrt, "∛": Math.cbrt, abs: Math.abs,
    round: Math.round, floor: Math.floor, ceil: Math.ceil, trunc: Math.trunc, sign: Math.sign,
    ln: Math.log, log: Math.log10, lg: Math.log10, log10: Math.log10, log2: Math.log2, exp: Math.exp,
    sin: Math.sin, cos: Math.cos, tan: Math.tan, tg: Math.tan, cot: x => 1 / Math.tan(x), ctg: x => 1 / Math.tan(x),
    asin: Math.asin, acos: Math.acos, atan: Math.atan, arcsin: Math.asin, arccos: Math.acos, arctan: Math.atan, arctg: Math.atan,
    sinh: Math.sinh, cosh: Math.cosh, tanh: Math.tanh, fact: factorial,
    корень: Math.sqrt, кор: Math.sqrt, модуль: Math.abs, окр: Math.round
};
const multiFunctions = {
    min: a => Math.min(...a), max: a => Math.max(...a),
    avg: a => a.reduce((s, x) => s + x, 0) / a.length, mean: a => a.reduce((s, x) => s + x, 0) / a.length,
    sum: a => a.reduce((s, x) => s + x, 0), gcd: a => a.reduce(gcd), lcm: a => a.reduce((x, y) => x / gcd(x, y) * y),
    hypot: a => Math.hypot(...a), pow: a => Math.pow(a[0], a[1]), root: a => Math.pow(a[0], 1 / a[1]),
    ncr: a => choose(a[0], a[1]), npr: a => factorial(a[0]) / factorial(a[0] - a[1]),
    мин: a => Math.min(...a), макс: a => Math.max(...a), сумма: a => a.reduce((s, x) => s + x, 0),
    среднее: a => a.reduce((s, x) => s + x, 0) / a.length
};
const constants = {
    pi: Math.PI, "π": Math.PI, пи: Math.PI, e: Math.E, tau: 2 * Math.PI, "τ": 2 * Math.PI,
    phi: (1 + Math.sqrt(5)) / 2, "φ": (1 + Math.sqrt(5)) / 2, inf: Infinity, "∞": Infinity
};
const trig = { sin: 1, cos: 1, tan: 1, tg: 1, cot: 1, ctg: 1 };
const inverseTrig = { asin: 1, acos: 1, atan: 1, arcsin: 1, arccos: 1, arctan: 1, arctg: 1 };

// sin(180°) is 1.2e-16 in floating point: snap such dust to 0.
function clean(x) {
    return Math.abs(x) < 1e-14 ? 0 : x;
}
const ofWords = { of: 1, от: 1, из: 1 };

function gcd(a, b) {
    a = Math.abs(a);
    b = Math.abs(b);
    while (b) [a, b] = [b, a % b];
    return a;
}
function factorial(n) {
    if (n < 0 || !Number.isInteger(n))
        throw new Error("Factorial needs a whole number");
    if (n > 170)
        return Infinity;
    let r = 1;
    for (let i = 2; i <= n; i++)
        r *= i;
    return r;
}
function choose(n, k) {
    if (k < 0 || k > n)
        return 0;
    let r = 1;
    for (let i = 1; i <= k; i++)
        r = r * (n - k + i) / i;
    return Math.round(r);
}

function Parser(tokens, ctx) {
    this.t = tokens;
    this.i = 0;
    this.ctx = ctx;
    this.trivial = true;   // a bare number, nothing computed
    this.hasBase = false;
    this.money = false;
    this.needRates = false;
}

Parser.prototype.peek = function (o) {
    return this.t[this.i + (o || 0)] || { t: "end" };
};
Parser.prototype.next = function () {
    return this.t[this.i++] || { t: "end" };
};
Parser.prototype.isOp = function (v, o) {
    const p = this.peek(o);
    return p.t === "op" && p.v === v;
};

// Unit (resolved, with the rate for currencies) for a unit token or word.
Parser.prototype.resolve = function (tok) {
    let u = tok.t === "unit" ? tok.unit : (tok.t === "word" ? Units.lookup(tok.v, this.ctx.rates) : null);
    if (!u)
        return null;
    if (u.currency) {
        this.money = true;
        const rates = this.ctx.rates;
        const rate = u.currency === "USD" ? 1 : (rates ? rates[u.currency] : undefined);
        if (!rates)
            this.needRates = true;
        u = { sym: u.currency, f: rate ? 1 / rate : NaN, d: u.d, currency: u.currency };
    }
    return u;
};

Parser.prototype.parse = function () {
    const q = this.additive();
    if (this.peek().t !== "end")
        throw new Error("Unexpected “" + (this.peek().v || this.peek().text || "") + "”");
    return q;
};

Parser.prototype.additive = function () {
    let a = this.multiplicative();
    for (;;) {
        if (!(this.isOp("+") || this.isOp("-")))
            return a;
        const op = this.next().v;
        const b = this.multiplicative();
        this.trivial = false;
        a = add(a, b, op === "-" ? -1 : 1);
    }
};

// Starts a value (implicit multiplication / juxtaposition).
Parser.prototype.startsValue = function () {
    const p = this.peek();
    if (p.t === "num" || (p.t === "op" && (p.v === "(" || p.v === "√" || p.v === "∛")))
        return true;
    if (p.t === "unit")
        return !!p.unit.currency && Units.prefixSymbols[p.text] !== undefined;
    if (p.t === "word") {
        const w = p.v.toLowerCase();
        return functions[w] !== undefined || multiFunctions[w] !== undefined || constants[w] !== undefined
            || constants[p.v] !== undefined || w === "ans";
    }
    return false;
};

Parser.prototype.multiplicative = function () {
    let a = this.unary();
    for (;;) {
        const p = this.peek();
        let op = null;
        if (p.t === "op" && (p.v === "*" || p.v === "/"))
            op = this.next().v;
        else if (p.t === "word" && (p.v.toLowerCase() === "mod" || p.v === "%"))
            op = (this.next(), "mod");
        else if (p.t === "word" && ofWords[p.v.toLowerCase()] && a.pct)
            op = (this.next(), "*");
        else if (this.startsValue() && !(p.t === "num" && !a.u))
            // "2 pi", "2(3)", "1 h 30 min" — but "5 10" is no product.
            op = "juxt";
        if (!op)
            return a;
        const b = this.unary();
        this.trivial = false;
        if (op === "juxt" && !isScalar(a) && sameDim(a, b) && !a.pct && !b.pct) {
            // 1 h 30 min, 5 ft 11 in, 1 kg 200 g
            a = add(a, b, 1);
            continue;
        }
        if (op === "mod") {
            if (!isScalar(b))
                throw new Error("Incompatible units");
            a = { v: fromUnit(((toUnit(a, a.u || { f: 1 }) % b.v) + b.v) % b.v, a.u || { f: 1 }), d: a.d, u: a.u };
            continue;
        }
        a = mul(a, b, op === "/" ? -1 : 1);
    }
};

Parser.prototype.unary = function () {
    if (this.isOp("-")) {
        this.next();
        const q = this.unary();
        this.trivial = false;
        return Object.assign({}, q, { v: q.u && q.u.o ? fromUnit(-toUnit(q, q.u), q.u) : -q.v });
    }
    if (this.isOp("+")) {
        this.next();
        return this.unary();
    }
    return this.power();
};

Parser.prototype.power = function () {
    const base = this.postfix();
    if (this.isOp("^")) {
        this.next();
        const e = this.unary();
        this.trivial = false;
        return pow(base, e);
    }
    return base;
};

Parser.prototype.postfix = function () {
    let q = this.primary();
    for (;;) {
        const p = this.peek();
        if (p.t === "op" && p.v === "!" && !this.isOp("=", 1)) {
            this.next();
            if (!isScalar(q))
                throw new Error("Factorial needs a number");
            q = scalar(factorial(q.v));
            this.trivial = false;
            continue;
        }
        if (p.t === "op" && (p.v === "%" || p.v === "‰")) {
            // x % y (no "of") = modulo; a lone x% = percent.
            const after = this.peek(1);
            if (p.v === "%" && (after.t === "num" || (after.t === "op" && after.v === "("))) {
                this.next();
                const b = this.unary();
                this.trivial = false;
                q = scalar(((q.v % b.v) + b.v) % b.v);
                continue;
            }
            this.next();
            q = Object.assign({}, q, { v: q.v / (p.v === "%" ? 100 : 1000), pct: true });
            this.trivial = false;
            continue;
        }
        if ((p.t === "op" && (p.v === "²" || p.v === "³")) && !p.space) {
            this.next();
            q = pow(q, scalar(p.v === "²" ? 2 : 3));
            this.trivial = false;
            continue;
        }
        if (p.t === "word" && !q.u && !q.pct) {
            // "k" = thousand, but "K" = kelvin: one letter matches exactly.
            const sc = scales[p.v] !== undefined ? scales[p.v] : (p.v.length > 1 ? scales[p.v.toLowerCase()] : undefined);
            if (sc && isScalar(q) && !this.isOp("(", 1)) {
                this.next();
                q = scalar(q.v * sc);
                continue;
            }
        }
        if ((p.t === "word" || p.t === "unit") && isScalar(q) && !q.u && !q.pct && !this.isOp("(", 1)) {
            if (p.t === "word" && ofWords[p.v.toLowerCase()])
                return q;
            const u = this.unitExpr();
            if (u) {
                q = { v: fromUnit(q.v, u), d: Object.assign({}, u.d), u: u };
                this.trivial = false;
                continue;
            }
        }
        return q;
    }
};

// unit ( (/|·) unit | ² | ^n )* written without spaces: km/h, m/s², kW·h.
Parser.prototype.unitExpr = function () {
    const tok = this.peek();
    let u = this.resolve(tok);
    if (!u)
        return null;
    this.next();
    for (;;) {
        const p = this.peek();
        if (p.space)
            return u;
        if (p.t === "op" && (p.v === "²" || p.v === "³")) {
            this.next();
            u = powLast(u, p.v === "²" ? 2 : 3);
            continue;
        }
        if (p.t === "op" && p.v === "^" && this.peek(1).t === "num" && !this.peek(1).space) {
            this.next();
            u = powLast(u, this.next().v);
            continue;
        }
        if (p.t === "op" && (p.v === "/" || p.v === "*") && !this.peek(1).space) {
            const v = this.resolve(this.peek(1));
            if (!v)
                return u;
            this.next();
            this.next();
            u = composeUnit(u, v, p.v === "/" ? -1 : 1);
            continue;
        }
        return u;
    }
};

Parser.prototype.args = function () {
    // After "(": expr (, expr)* ")"
    const list = [this.additive()];
    while (this.isOp(",")) {
        this.next();
        list.push(this.additive());
    }
    this.expect(")");
    return list;
};

Parser.prototype.expect = function (v) {
    const p = this.next();
    if (!(p.t === "op" && p.v === v))
        throw new Error("Expected “" + v + "”");
};

Parser.prototype.primary = function () {
    const p = this.next();
    if (p.t === "num") {
        if (p.base)
            this.hasBase = true;
        return scalar(p.v);
    }
    if (p.t === "op" && p.v === "(") {
        const q = this.additive();
        this.expect(")");
        return q;
    }
    if (p.t === "op" && (p.v === "√" || p.v === "∛")) {
        this.trivial = false;
        return applyFn(p.v, this.power(), this.ctx);
    }
    if (p.t === "unit" || p.t === "word") {
        // $5, €3.50
        if (p.t === "unit" && p.unit.currency && this.peek().t === "num") {
            const u = this.resolve(p);
            const n = this.next();
            let v = n.v;
            const w = this.peek();
            if (w.t === "word" && scales[w.v.toLowerCase()]) {
                this.next();
                v *= scales[w.v.toLowerCase()];
            }
            this.trivial = false;
            return { v: fromUnit(v, u), d: Object.assign({}, u.d), u: u };
        }
        const w = p.t === "word" ? p.v.toLowerCase() : "";
        if (w && (functions[w] || multiFunctions[w])) {
            this.trivial = false;
            if (this.isOp("(")) {
                this.next();
                const args = this.args();
                if (multiFunctions[w]) {
                    if (args.some(a => !isScalar(a)))
                        throw new Error("Incompatible units");
                    return scalar(multiFunctions[w](args.map(a => a.v)));
                }
                if (args.length !== 1)
                    throw new Error("Too many arguments");
                return applyFn(w, args[0], this.ctx);
            }
            if (multiFunctions[w])
                throw new Error("Expected “(”");
            return applyFn(w, this.power(), this.ctx);
        }
        if (p.t === "word" && (constants[p.v] !== undefined || constants[w] !== undefined)) {
            this.trivial = false;
            return scalar(constants[p.v] !== undefined ? constants[p.v] : constants[w]);
        }
        if (w === "ans" || w === "_") {
            this.trivial = false;
            if (this.ctx.ans === undefined || this.ctx.ans === null)
                throw new Error("No previous result");
            return scalar(this.ctx.ans);
        }
        // A bare unit = one of it ("mi to km").
        this.i--;
        const u = this.unitExpr();
        if (u) {
            this.trivial = false;
            return { v: fromUnit(1, u), d: Object.assign({}, u.d), u: u };
        }
        throw new Error("Unknown “" + p.v + "”");
    }
    if (p.t === "end")
        throw new Error("Incomplete expression");
    throw new Error("Unexpected “" + (p.v || "") + "”");
};

// ctx.angle "deg" (default): plain numbers in sin/cos/tan are degrees and
// asin/acos/atan answer in degrees; "rad" = radians both ways.
function applyFn(name, q, ctx) {
    const deg = (ctx && ctx.angle) !== "rad";
    if (trig[name] && Units.dimKey(q.d) === "A1")
        return scalar(clean(functions[name](q.v)));
    if (trig[name] && isScalar(q))
        return scalar(clean(functions[name](deg ? q.v * Math.PI / 180 : q.v)));
    if (inverseTrig[name] && isScalar(q) && deg) {
        const u = Units.units["°"];
        return { v: functions[name](q.v), d: Object.assign({}, u.d), u: u };
    }
    if (name === "sqrt" || name === "√" || name === "корень" || name === "кор") {
        if (isScalar(q))
            return scalar(Math.sqrt(q.v));
        for (const k in q.d)
            if (q.d[k] % 2)
                throw new Error("Incompatible units");
        const d = {};
        for (const k in q.d)
            d[k] = q.d[k] / 2;
        return { v: Math.sqrt(q.v), d: d, u: null };
    }
    if (!isScalar(q)) {
        if (["abs", "round", "floor", "ceil", "trunc", "модуль", "окр"].indexOf(name) >= 0 && q.u)
            return Object.assign({}, q, { v: fromUnit(functions[name](toUnit(q, q.u)), q.u) });
        throw new Error("Incompatible units");
    }
    return scalar(functions[name](q.v));
}

function add(a, b, sign) {
    if (b.pct && !a.pct)
        return Object.assign({}, a, {
            v: a.u && a.u.o ? fromUnit(toUnit(a, a.u) * (1 + sign * b.v), a.u) : a.v * (1 + sign * b.v)
        });
    if (isScalar(b) && !isScalar(a) && a.u)
        return Object.assign({}, a, { v: fromUnit(toUnit(a, a.u) + sign * b.v, a.u) });
    if (isScalar(a) && !isScalar(b) && b.u)
        return Object.assign({}, b, { v: fromUnit(a.v + sign * toUnit(b, b.u), b.u) });
    if (!sameDim(a, b))
        throw new Error("Incompatible units");
    if (a.u && a.u.o !== undefined && b.u && b.u.o !== undefined) {
        // Temperatures: the right one is a difference in the left's scale.
        const bx = toUnit(b, b.u) * b.u.f / a.u.f;
        return Object.assign({}, a, { v: fromUnit(toUnit(a, a.u) + sign * (b.u === a.u ? toUnit(b, b.u) : bx), a.u) });
    }
    return { v: a.v + sign * b.v, d: a.d, u: a.u || b.u, pct: a.pct && b.pct };
}

function mul(a, b, sign) {
    if (sign < 0 && isScalar(b) && b.v === 0 && !b.pct)
        throw new Error("Division by zero");
    const d = dimOp(a.d, b.d, sign);
    // Temperatures scale as differences (no offset) once multiplied.
    const av = a.u && a.u.o ? toUnit(a, a.u) * a.u.f : a.v;
    const bv = b.u && b.u.o ? toUnit(b, b.u) * b.u.f : b.v;
    const v = sign > 0 ? av * bv : av / bv;
    if (Units.dimKey(d) === "")
        return scalar(v);
    let u;
    if (isScalar(b))
        u = a.u;
    else if (isScalar(a))
        u = sign > 0 ? b.u : composeUnit(null, b.u, -1);
    else
        u = composeUnit(a.u, b.u, sign);
    if (u && u.o) {
        // 20 °C * 2 = 40 °C, not twice the kelvins.
        const x = sign > 0 ? toUnit(isScalar(b) ? a : b, u) * (isScalar(b) ? b.v : a.v) : toUnit(a, u) / b.v;
        return { v: fromUnit(x, u), d: d, u: u };
    }
    return { v: v, d: d, u: u };
}

function pow(a, e) {
    if (!isScalar(e))
        throw new Error("Incompatible units");
    if (isScalar(a))
        return scalar(Math.pow(a.v, e.v));
    if (!Number.isInteger(e.v))
        throw new Error("Incompatible units");
    const d = {};
    for (const k in a.d)
        d[k] = a.d[k] * e.v;
    return { v: Math.pow(a.v, e.v), d: d, u: powUnit(a.u, e.v) };
}

// ------------------------------------------------------------ formatting

function round12(n) {
    return Number(n.toPrecision(12));
}

function groupInt(s, sep) {
    return s.replace(/\B(?=(\d{3})+(?!\d))/g, sep);
}

// Display string (grouped, locale decimal) and the plain one for copying.
function formatNumber(n, ctx, maxFrac) {
    if (!isFinite(n))
        return { text: isNaN(n) ? "—" : (n > 0 ? "∞" : "−∞"), copy: String(n) };
    const ru = ctx.lang === "ru";
    const neg = n < 0;
    let a = Math.abs(n);
    const sign = neg ? "−" : "";
    if (a !== 0 && (a >= 1e15 || a < 1e-7)) {
        const e = Math.floor(Math.log10(a));
        let m = round12(a / Math.pow(10, e));
        if (m >= 10) {
            m /= 10;
            return formatSci(neg, m, e + 1, ru);
        }
        return formatSci(neg, m, e, ru);
    }
    a = round12(a);
    let s = maxFrac !== undefined ? a.toFixed(maxFrac).replace(/\.?0+$/, "") : String(a);
    if (/e/.test(s))
        s = a.toFixed(12).replace(/\.?0+$/, "");
    const parts = s.split(".");
    const int = groupInt(parts[0], ru ? " " : ",");
    const text = sign + int + (parts[1] ? (ru ? "," : ".") + parts[1] : "");
    return { text: text, copy: (neg ? "-" : "") + s };
}

function formatSci(neg, m, e, ru) {
    const ms = String(Number(m.toPrecision(10)));
    return {
        text: (neg ? "−" : "") + (ru ? ms.replace(".", ",") : ms) + " × 10" + superscript(e),
        copy: (neg ? "-" : "") + ms + "e" + e
    };
}

function formatMoney(n, ctx) {
    const a = Math.abs(n);
    const frac = a === 0 || a >= 1 ? 2 : Math.min(8, 2 - Math.floor(Math.log10(a)) + 1);
    const f = formatNumber(n, ctx, frac);
    // Keep two decimals for amounts (12.50, not 12.5).
    if (a >= 1 && a < 1e15) {
        const fixed = round12(Math.abs(n)).toFixed(2);
        const parts = fixed.split(".");
        const ru = ctx.lang === "ru";
        f.text = (n < 0 ? "−" : "") + groupInt(parts[0], ru ? " " : ",") + (ru ? "," : ".") + parts[1];
        f.copy = (n < 0 ? "-" : "") + fixed;
    }
    return f;
}

// Fraction digits that keep `sig` significant ones (undefined = all).
function sigFrac(x, sig) {
    const a = Math.abs(x);
    if (a === 0 || a >= 1e15 || a < 1e-7)
        return undefined;
    return Math.max(0, Math.min(12, sig - 1 - Math.floor(Math.log10(a))));
}

// Continued fraction: 0.375 → "3/8" (small denominators only).
function fraction(x) {
    if (Number.isInteger(x) || !isFinite(x) || Math.abs(x) > 1e9)
        return "";
    let h1 = 1, h0 = 0, k1 = 0, k0 = 1, b = x;
    for (let i = 0; i < 20; i++) {
        const a = Math.floor(b);
        [h1, h0] = [a * h1 + h0, h1];
        [k1, k0] = [a * k1 + k0, k1];
        if (k1 > 1000 || Math.abs(h1) > 99999)
            return "";
        if (Math.abs(x - h1 / k1) < 1e-12 * Math.max(1, Math.abs(x)))
            return k1 === 1 ? "" : (h1 < 0 ? "−" : "") + Math.abs(h1) + "/" + k1;
        b = 1 / (b - a);
        if (!isFinite(b))
            break;
    }
    return "";
}

const dimCaption = {
    "L1": "Length", "M1": "Mass", "T1": "Time", "K1": "Temperature", "L2": "Area", "L3": "Capacity",
    "L1 T-1": "Speed", "D1": "Data size", "D1 T-1": "Data rate", "T-1": "Frequency",
    "L1 T-2": "Acceleration", "L1 M1 T-2": "Force", "L2 M1 T-2": "Energy", "L2 M1 T-3": "Power", "L-1 M1 T-2": "Pressure", "A1": "Angle", "C1": "Currency"
};

const currencyNames = {
    USD: "US dollar", EUR: "Euro", RUB: "Russian ruble", GBP: "British pound", JPY: "Japanese yen",
    CNY: "Chinese yuan", KZT: "Kazakhstani tenge", UAH: "Ukrainian hryvnia", BYN: "Belarusian ruble",
    TRY: "Turkish lira", INR: "Indian rupee", KRW: "South Korean won", CHF: "Swiss franc",
    PLN: "Polish złoty", AMD: "Armenian dram", GEL: "Georgian lari", AED: "UAE dirham",
    THB: "Thai baht", UZS: "Uzbekistani som", KGS: "Kyrgyzstani som", CZK: "Czech koruna",
    VND: "Vietnamese dong", BTC: "Bitcoin", CAD: "Canadian dollar", AUD: "Australian dollar",
    SEK: "Swedish krona", NOK: "Norwegian krone", ILS: "Israeli shekel", RSD: "Serbian dinar",
    AZN: "Azerbaijani manat", MDL: "Moldovan leu", TJS: "Tajikistani somoni", HKD: "Hong Kong dollar",
    SGD: "Singapore dollar", BRL: "Brazilian real", MXN: "Mexican peso", EGP: "Egyptian pound"
};

function unitLabel(u) {
    return u.sym;
}

// One result line for quantity q shown in unit u.
function quantityResult(q, u, ctx, extra) {
    const tr = ctx.tr;
    if (u.currency) {
        const f = formatMoney(toUnit(q, u), ctx);
        return Object.assign({ text: f.text + " " + u.sym, copy: f.copy, caption: tr(currencyNames[u.sym] || u.sym), icon: glyph.money }, extra || {});
    }
    const x = toUnit(q, u);
    const f = formatNumber(x, ctx, sigFrac(x, 6));
    f.copy = formatNumber(x, ctx).copy;
    const key = Units.dimKey(u.d);
    return Object.assign({
        text: f.text + (u.sym === "°" ? "°" : " " + unitLabel(u)),
        copy: f.copy,
        caption: tr(dimCaption[key] || "Result"),
        icon: key === "K1" ? glyph.temp : (key === "T1" ? glyph.time : glyph.unit)
    }, extra || {});
}

// 5400 s → "1 h 30 min".
function humanizeTime(sec, ctx) {
    const tr = ctx.tr;
    const parts = [];
    let s = Math.abs(sec);
    const steps = [[31556952, "yr"], [86400, "d"], [3600, "h"], [60, "min"], [1, "s"]];
    for (const [n, sym] of steps) {
        if (s >= n || (sym === "s" && parts.length === 0)) {
            const k = sym === "s" ? round12(s / n) : Math.floor(s / n + 1e-9);
            if (k > 0 || parts.length === 0) {
                parts.push(formatNumber(k, ctx, 3).text + " " + tr(sym));
                s -= k * n;
            }
        }
        if (parts.length === 3)
            break;
    }
    return (sec < 0 ? "−" : "") + parts.join(" ");
}

// Best SI / IEC unit for a byte count.
function dataUnits(bytes) {
    const si = ["B", "kB", "MB", "GB", "TB", "PB"], iec = ["B", "KiB", "MiB", "GiB", "TiB"];
    const pick = (list, step) => {
        let i = 0;
        while (i < list.length - 1 && Math.abs(bytes) >= Math.pow(step, i + 1))
            i++;
        return Units.units[list[i]];
    };
    return [pick(si, 1000), pick(iec, 1024)];
}

// Results for a quantity with no explicit target.
function autoResults(q, ctx, hasBase) {
    const tr = ctx.tr;
    if (isScalar(q) || !q.u) {
        if (!isScalar(q))
            return [Object.assign(quantityResult(q, baseUnitFor(q), ctx))];
        const f = formatNumber(q.v, ctx);
        if (q.pct) {
            const p = formatNumber(q.v * 100, ctx);
            return [{ text: p.text + "%", copy: p.copy + "%", caption: tr("Result"), icon: glyph.math }];
        }
        const frac = (f.copy.split(".")[1] || "").length >= 3 ? fraction(q.v) : "";
        const out = [{ text: f.text, copy: f.copy, caption: frac ? "= " + frac : tr("Result"), icon: glyph.math }];
        if (hasBase && Number.isInteger(q.v) && Math.abs(q.v) < 2 ** 53)
            out.push(baseResult(q.v, 16, ctx), baseResult(q.v, 2, ctx));
        return out;
    }
    const u = q.u;
    if (u.currency) {
        const out = [];
        const list = (ctx.currencies || ["RUB", "USD", "EUR"]).filter(c => c !== u.sym);
        for (const code of list) {
            const rate = code === "USD" ? 1 : ctx.rates && ctx.rates[code];
            if (rate)
                out.push(quantityResult(q, { sym: code, f: 1 / rate, d: u.d, currency: code }, ctx));
        }
        return out.length ? out : [quantityResult(q, u, ctx)];
    }
    const key = Units.dimKey(q.d);
    const out = [quantityResult(q, u, ctx)];
    // Mixed units only ("1 h 30 min"; a lone "3 d" says nothing new).
    const human = Math.abs(q.v) >= 60 && key === "T1" ? humanizeTime(q.v, ctx) : "";
    if (human.indexOf(" ") > 0)
        out.push({ text: human, copy: human.replace(/\u2009/g, " "), caption: tr("Duration"), icon: glyph.time });
    if (key === "D1")
        for (const du of dataUnits(q.v))
            if (du.sym !== u.sym && !out.some(r => r.unitSym === du.sym))
                out.push(quantityResult(q, du, ctx, { unitSym: du.sym }));
    for (const sym of Units.partners[u.sym] || [])
        out.push(quantityResult(q, Units.units[sym], ctx));
    // "5 km" typed as is: its own value is no news, the conversions are.
    if (out.length > 1 && !q.computed)
        out.shift();
    return out.filter((r, i) => out.findIndex(x => x.text === r.text) === i);
}

function baseUnitFor(q) {
    const key = Units.dimKey(q.d);
    for (const sym in Units.units) {
        const u = Units.units[sym];
        if (u.f === 1 && !u.o && Units.dimKey(u.d) === key)
            return u;
    }
    const parts = Object.keys(q.d).sort().map(k => (Units.dimNames[k] || k) + (q.d[k] === 1 ? "" : superscript(q.d[k])));
    return { sym: parts.join("·"), f: 1, d: q.d };
}

function baseResult(n, base, ctx) {
    const prefix = { 16: "0x", 2: "0b", 8: "0o", 10: "" }[base];
    const neg = n < 0;
    let digits = Math.abs(n).toString(base).toUpperCase();
    if (base === 2)
        digits = digits.replace(/\B(?=(\d{4})+(?!\d))/g, " ");
    const name = { 16: "Hexadecimal", 2: "Binary", 8: "Octal", 10: "Decimal" }[base];
    return {
        text: (neg ? "−" : "") + prefix + digits,
        copy: (neg ? "-" : "") + prefix + digits.replace(/ /g, ""),
        caption: ctx.tr(name),
        icon: glyph.base
    };
}

// ------------------------------------------------------------ conversion

const baseWords = [
    [/^(hex|hexadecimal|шестнадцатеричн[A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]*|16-?ричн[A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]*|base\s*16)$/i, 16],
    [/^(bin|binary|двоичн[A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]*|base\s*2)$/i, 2],
    [/^(oct|octal|восьмеричн[A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]*|base\s*8)$/i, 8],
    [/^(dec|decimal|десятичн[A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]*|base\s*10)$/i, 10]
];
const timeWords = /^(hms|h:m:s|duration|длительность|время)$/i;

// Target units of "x to a, b": [{ unit } | { base }] or null.
function parseTargets(text, ctx) {
    const list = text.split(/\s*,\s*|\s+(?:and|и)\s+/i).filter(s => s.length);
    if (!list.length)
        return null;
    const out = [];
    for (const s of list) {
        const bw = baseWords.find(b => b[0].test(s.trim()));
        if (bw) {
            out.push({ base: bw[1] });
            continue;
        }
        if (timeWords.test(s.trim())) {
            out.push({ hms: true });
            continue;
        }
        let toks;
        try {
            toks = tokenize(s);
        } catch (e) {
            return null;
        }
        const p = new Parser(toks, ctx);
        const u = p.unitExpr();
        if (!u || p.peek().t !== "end")
            return null;
        out.push({ unit: u, needRates: p.needRates });
    }
    return out;
}

// Trailing space as a lookahead: "5 in to cm" must find both words.
const keywordRe = /\s+(?:to|in|into|as|в|во|на)(?=\s)|\s*(?:->|→|=>)|\s+=(?=\s)/gi;

function evalExpr(text, ctx) {
    const toks = tokenize(text);
    if (!toks.length)
        throw new Error("Incomplete expression");
    const p = new Parser(toks, ctx);
    const q = p.parse();
    return { q: q, p: p };
}

function convert(text, ctx) {
    // Rightmost keyword first: "5 in in cm" = inches to cm.
    const hits = [];
    let m;
    keywordRe.lastIndex = 0;
    while ((m = keywordRe.exec(text)) !== null)
        hits.push({ at: m.index, len: m[0].length, word: m[0].trim().toLowerCase() });
    for (let k = hits.length - 1; k >= 0; k--) {
        const h = hits[k];
        const left = text.slice(0, h.at), right = text.slice(h.at + h.len);
        if (!left.trim() || !right.trim())
            continue;
        const targets = parseTargets(right.trim(), ctx);
        if (!targets)
            continue;
        let r;
        try {
            r = evalExpr(left, ctx);
        } catch (e) {
            continue;
        }
        const q = r.q;
        if (r.p.needRates || targets.some(t => t.needRates))
            return { needRates: true, kind: "money" };
        // "5 in cm": a scalar with a word that is also a unit — not a split.
        if (isScalar(q) && targets.some(t => t.unit))
            continue;
        if (!isFinite(q.v))
            throw new Error(q.u && q.u.currency ? "No rate for “" + q.u.sym + "”" : "Not a number");
        const results = [];
        for (const t of targets) {
            if (t.base !== undefined) {
                if (!isScalar(q) || !Number.isInteger(round12(q.v)))
                    throw new Error("Needs a whole number");
                results.push(baseResult(round12(q.v), t.base, ctx));
            } else if (t.hms) {
                if (Units.dimKey(q.d) !== "T1")
                    throw new Error("Incompatible units");
                const h = humanizeTime(q.v, ctx);
                results.push({ text: h, copy: h.replace(/\u2009/g, " "), caption: ctx.tr("Duration"), icon: glyph.time });
            } else {
                if (Units.dimKey(q.d) !== Units.dimKey(t.unit.d))
                    throw new Error("Incompatible units");
                if (t.unit.currency && !isFinite(t.unit.f))
                    throw new Error("No rate for “" + t.unit.sym + "”");
                results.push(quantityResult(q, t.unit, ctx));
            }
        }
        return {
            ok: true, results: results, q: q,
            kind: r.p.money ? "money" : (targets[0].base ? "base" : "unit")
        };
    }
    return null;
}

// --------------------------------------------------------------- dates

const monthStems = [
    ["jan", "янв"], ["feb", "фев"], ["mar", "мар"], ["apr", "апр"], ["may", "ма"], ["jun", "июн"],
    ["jul", "июл"], ["aug", "авг"], ["sep", "сен"], ["oct", "окт"], ["nov", "ноя"], ["dec", "дек"]
];

function monthIndex(w) {
    w = w.toLowerCase();
    for (let i = 0; i < 12; i++)
        for (const s of monthStems[i])
            if (w.startsWith(s) && (s !== "ма" || /^ма[йяе]$/.test(w)) && (s !== "мар" || !w.startsWith("ма") || w.startsWith("мар")))
                return i;
    return -1;
}

function startOfDay(d) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

// A date word / literal → Date (midnight), or null. `future`: a date with no
// year that already passed this year means next year.
function parseDate(s, now, future) {
    s = s.trim().toLowerCase().replace(/^(the|этого|этот)\s+/, "");
    const today = startOfDay(now);
    const shift = n => new Date(today.getFullYear(), today.getMonth(), today.getDate() + n);
    if (/^(today|now|сегодня|сейчас|сегодняшнего дня)$/.test(s))
        return today;
    if (/^(tomorrow|завтра|завтрашнего дня)$/.test(s))
        return shift(1);
    if (/^(yesterday|вчера|вчерашнего дня)$/.test(s))
        return shift(-1);
    if (/^(new year|new year's|нового года|новый год|нг)$/.test(s))
        return new Date(today.getFullYear() + 1, 0, 1);
    let m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(s);
    if (m)
        return valid(+m[1], +m[2] - 1, +m[3]);
    m = /^(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?$/.exec(s);
    if (m)
        return withYear(+m[1], +m[2] - 1, m[3]);
    m = /^(\d{1,2})\s+([A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]+)\.?(?:\s+(\d{4}))?$/.exec(s);
    if (m && monthIndex(m[2]) >= 0)
        return withYear(+m[1], monthIndex(m[2]), m[3]);
    m = /^([A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]+)\.?\s+(\d{1,2})(?:,?\s+(\d{4}))?$/.exec(s);
    if (m && monthIndex(m[1]) >= 0)
        return withYear(+m[2], monthIndex(m[1]), m[3]);
    return null;

    function withYear(day, month, y) {
        if (y) {
            const year = y.length === 2 ? 2000 + +y : +y;
            return valid(year, month, day);
        }
        let d = valid(today.getFullYear(), month, day);
        if (d && future && d < today)
            d = valid(today.getFullYear() + 1, month, day);
        return d;
    }
    function valid(y, mo, d) {
        const r = new Date(y, mo, d);
        return r.getMonth() === mo && r.getDate() === d ? r : null;
    }
}

const dayMs = 86400000;
function dayDiff(a, b) {
    return Math.round((startOfDay(b) - startOfDay(a)) / dayMs);
}

function daysText(n, ctx) {
    const a = Math.abs(n);
    if (ctx.lang === "ru") {
        const m10 = a % 10, m100 = a % 100;
        const w = m10 === 1 && m100 !== 11 ? "день" : (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? "дня" : "дней");
        return formatNumber(a, ctx).text + " " + w;
    }
    return formatNumber(a, ctx).text + (a === 1 ? " day" : " days");
}

function weeksCaption(n, ctx) {
    const a = Math.abs(n);
    if (a < 14)
        return "";
    const w = Math.floor(a / 7), d = a % 7;
    return ctx.tr("%1 wk").replace("%1", w) + (d ? " " + ctx.tr("%1 d").replace("%1", d) : "");
}

const dateUnitDays = { d: 1, wk: 7 };

function tryDate(text, ctx) {
    const now = ctx.now || new Date();
    const s = text.trim().replace(/\s+/g, " ").replace(/[?？]$/, "");
    const fmt = d => ctx.formatDate ? ctx.formatDate(d) : d.toDateString();
    let m;
    // days until X / сколько дней до X / до X
    m = /^(?:(?:how many\s+)?days?\s+|(?:сколько\s+)?(?:дней|дня)\s+|осталось\s+)?(?:until|till|to|до)\s+(.+)$/i.exec(s);
    if (m) {
        const d = parseDate(m[1], now, true);
        if (d) {
            const n = dayDiff(now, d);
            return dateResult(daysText(n, ctx) + (n < 0 ? " " + ctx.tr("ago") : ""), String(n), fmt(d), ctx);
        }
    }
    // days since X / прошло с X
    m = /^(?:days?\s+|(?:сколько\s+)?(?:дней|дня)\s+|прошло\s+)?(?:since|from|с|со|после)\s+(.+)$/i.exec(s);
    if (m) {
        const d = parseDate(m[1], now, false);
        if (d) {
            const n = dayDiff(d, now);
            return dateResult(daysText(n, ctx), String(n), fmt(d), ctx);
        }
    }
    // X ± N units
    m = /^(.+?)\s*([+-])\s*(\d+)\s*([A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]+)$/.exec(s);
    if (m) {
        const d = parseDate(m[1], now, false);
        const u = Units.lookup(m[4]);
        if (d && u && Units.dimKey(u.d) === "T1") {
            const n = (+m[3]) * (m[2] === "-" ? -1 : 1);
            const r = new Date(d);
            if (u.sym === "mo")
                r.setMonth(r.getMonth() + n);
            else if (u.sym === "yr")
                r.setFullYear(r.getFullYear() + n);
            else if (dateUnitDays[u.sym])
                r.setDate(r.getDate() + n * dateUnitDays[u.sym]);
            else
                return null;
            const diff = dayDiff(now, r);
            return dateResult(fmt(r), fmt(r), diff === 0 ? ctx.tr("Today") : (diff > 0 ? ctx.tr("In %1").replace("%1", daysText(diff, ctx)) : daysText(diff, ctx) + " " + ctx.tr("ago")), ctx);
        }
    }
    // X - Y (two dates)
    m = /^(.+?)\s+-\s+(.+)$/.exec(s) || /^(\d[\d./-]+)\s*-\s*(\d[\d./-]+)$/.exec(s);
    if (m) {
        const a = parseDate(m[1], now, false), b = parseDate(m[2], now, false);
        if (a && b) {
            const n = dayDiff(b, a);
            return dateResult(daysText(n, ctx), String(n), fmt(b) + " → " + fmt(a), ctx);
        }
    }
    // Unix time: @1700000000 / unix 1700000000
    m = /^(?:@|unix\s+|timestamp\s+)(\d{9,13})$/i.exec(s);
    if (m) {
        const ms = m[1].length > 11 ? +m[1] : +m[1] * 1000;
        const d = new Date(ms);
        const t = fmt(d) + ", " + String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
        return dateResult(t, d.toISOString(), ctx.tr("Unix time"), ctx);
    }
    return null;
}

function dateResult(text, copy, caption, ctx) {
    return { ok: true, kind: "date", results: [{ text: text, copy: copy, caption: caption, icon: glyph.date }] };
}

// ---------------------------------------------------------------- entry

// Pretty input for the card's left side.
function prettyExpr(s) {
    return s.trim()
        .replace(/\*\*/g, "^")
        .replace(/\s*\*\s*/g, " × ")
        .replace(/(\S)\s*\/\s*(?=[\d(])/g, "$1 ÷ ")
        .replace(/\s*->\s*|\s*=>\s*/g, " → ")
        .replace(/(^|[\s(])-(?=\d)/g, "$1−")
        .replace(/\s{2,}/g, " ");
}

// Unfinished input while typing: "2 +" → "2", "sqrt(2" → "sqrt(2)".
function repair(s) {
    let r = s.replace(/[\s+\-−*×·/÷^(,;=]+$/, "");
    r = r.replace(/\s+(?:to|in|into|as|в|во|на|of|от|mod)$/i, "");
    let depth = 0;
    for (const ch of r)
        depth += ch === "(" || ch === "[" ? 1 : (ch === ")" || ch === "]" ? -1 : 0);
    while (depth-- > 0)
        r += ")";
    return r;
}

function evaluate(query, ctx) {
    let text = (query || "").trim();
    const tr = ctx.tr || (s => s);
    ctx.tr = tr;
    let forced = !!ctx.forced;
    if (text.startsWith("=")) {
        forced = true;
        text = text.slice(1).trim();
    }
    if (text.endsWith("=") && text.length > 1)
        text = text.slice(0, -1).trim();
    if (!text)
        return forced ? { ok: false, empty: true, expr: "", results: [] } : null;
    const expr = prettyExpr(text);
    const date = tryDate(text, ctx);
    if (date)
        return Object.assign(date, { expr: expr, exprCaption: tr("Date") });
    // Plain typing needs a digit somewhere (keeps app names like "pi" or
    // "e" off the calculator), forced mode takes anything.
    if (!forced && !/\d/.test(text))
        return null;

    // As typed first; unfinished input ("2 +", "sqrt(2") on a second try.
    let err = null;
    for (const src of [text, repair(text)]) {
        if (!src || (err && src === text))
            continue;
        try {
            return attempt(src, src !== text);
        } catch (e) {
            if (!err)
                err = e;
        }
    }
    if (!forced)
        return null;
    const msg = String(err ? err.message || err : "Incomplete expression");
    const arg = (/“(.*)”/.exec(msg) || [])[1] || "";
    return { ok: false, error: tr(msg.replace(/“.*”/, "“%1”")).replace("%1", arg), expr: expr, exprCaption: tr("Expression"), results: [] };

    function attempt(src, partial) {
        const conv = convert(src, ctx);
        if (conv && conv.needRates)
            return { ok: false, needRates: true, kind: "money", expr: expr, exprCaption: tr("Currency"), results: [] };
        if (conv)
            return {
                ok: true, kind: conv.kind, expr: expr, partial: partial, results: conv.results,
                exprCaption: sourceCaption(conv.q, tr)
            };
        const r = evalExpr(src, ctx);
        if (r.p.needRates)
            return { ok: false, needRates: true, kind: "money", expr: expr, exprCaption: tr("Currency"), results: [] };
        // A bare number is not worth a card while typing ("2048", "2 +"
        // cut back to "2" still is: the operator says a sum is coming).
        if (r.p.trivial && !forced && !r.p.hasBase && (!partial || !/[+\-−*×·/÷^]/.test(text.slice(1))))
            return null;
        const q = r.q;
        q.computed = !r.p.trivial && !(q.u && isUnitLiteral(src));
        // "3d", "4k", "7z": app names more often than units.
        if (!forced && isTerseLiteral(src))
            return null;
        const results = autoResults(q, ctx, r.p.hasBase);
        if (q.u && q.u.currency && !isFinite(q.v))
            throw new Error("No rate for “" + q.u.sym + "”");
        if (results.some(x => x.text === "—"))
            throw new Error("Not a number");
        return {
            ok: true, partial: partial, expr: expr, results: results,
            kind: r.p.money ? "money" : (isScalar(q) ? (r.p.hasBase ? "base" : "math") : "unit"),
            exprCaption: sourceCaption(q, tr)
        };
    }
}

// "3d": a number glued to a one-letter word.
function isTerseLiteral(s) {
    try {
        const toks = tokenize(s);
        // Currency marks stay: "5$", "500р".
        return toks.length === 2 && toks[0].t === "num" && !toks[1].space && toks[1].t === "word"
            && toks[1].v.length === 1 && !(Units.lookup(toks[1].v) || {}).currency;
    } catch (e) {
        return false;
    }
}

// "5 km": a number and a unit, nothing else.
function isUnitLiteral(s) {
    try {
        const toks = tokenize(s);
        return toks.length >= 2 && toks[0].t === "num" && toks.slice(1).every(t => t.t === "word" || t.t === "unit" || (t.t === "op" && /[\/²³^]/.test(t.v)) || (t.t === "num" && false));
    } catch (e) {
        return false;
    }
}

function sourceCaption(q, tr) {
    if (!q)
        return tr("Expression");
    if (q.u && q.u.currency)
        return tr(currencyNames[q.u.sym] || q.u.sym);
    const key = Units.dimKey(q.d);
    return key ? tr(dimCaption[key] || "Expression") : tr("Expression");
}
