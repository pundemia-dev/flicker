.pragma library

// Units for CalcEngine.js. A unit = { sym, f, d, o?, name? }: value in the
// base unit = (x + o) * f (o only for temperatures); d = dimension
// exponents over L (length), M (mass), T (time), K (temperature),
// D (data, byte), A (angle), C (money, USD). Aliases: exact-case first
// (B byte / b bit, MB / Mb), then lower-case; Russian words are stems that
// take any case ending ("километр" → километра, километров...).

const units = {};
const exact = {};
const lower = {};
const stems = [];

function def(sym, f, d, aliases, extra) {
    const u = Object.assign({ sym: sym, f: f, d: d }, extra || {});
    units[sym] = u;
    exact[sym] = u;
    for (const a of aliases || []) {
        if (a.endsWith("*"))
            stems.push([a.slice(0, -1), u]);
        else if (a.startsWith("="))
            exact[a.slice(1)] = u;
        else
            lower[a.toLowerCase()] = u;
    }
    if (!lower[sym.toLowerCase()])
        lower[sym.toLowerCase()] = u;
    return u;
}

const L = { L: 1 }, M = { M: 1 }, T = { T: 1 }, K = { K: 1 }, D = { D: 1 }, A = { A: 1 };
const L2 = { L: 2 }, L3 = { L: 3 }, V = { L: 1, T: -1 }, R = { D: 1, T: -1 }, HZ = { T: -1 };
const E = { M: 1, L: 2, T: -2 }, P = { M: 1, L: 2, T: -3 }, PA = { M: 1, L: -1, T: -2 };

// Length
def("nm", 1e-9, L, ["nanometer*", "нанометр*", "нм"]);
def("µm", 1e-6, L, ["um", "micron", "micrometer*", "микрон*", "микрометр*", "мкм"]);
def("mm", 1e-3, L, ["millimeter*", "millimetre*", "миллиметр*", "мм"]);
def("cm", 1e-2, L, ["centimeter*", "centimetre*", "сантиметр*", "см"]);
def("dm", 0.1, L, ["decimeter*", "дециметр*", "дм"]);
def("m", 1, L, ["meter*", "metre*", "метр*", "м"]);
def("km", 1000, L, ["kilometer*", "kilometre*", "километр*", "км"]);
def("in", 0.0254, L, ["inch", "inches", "дюйм*", "\"", "″"]);
def("ft", 0.3048, L, ["foot", "feet", "фут*", "′"]);
def("yd", 0.9144, L, ["yard*", "ярд*"]);
def("mi", 1609.344, L, ["mile*", "мил*"]);
def("nmi", 1852, L, ["nautical mile", "nautical miles"]);
def("au", 149597870700, L, ["astronomical unit", "а.е."]);
def("ly", 9460730472580800, L, ["lightyear*", "light-year*", "светов*"]);

// Mass
def("mg", 1e-6, M, ["milligram*", "миллиграмм*", "мг"]);
def("g", 1e-3, M, ["gram*", "gramme*", "грамм*", "гр", "г"]);
def("kg", 1, M, ["kilogram*", "kilo", "kilos", "килограмм*", "кило", "кг"]);
def("t", 1000, M, ["ton", "tons", "tonne*", "тонн*", "т"]);
def("ct", 2e-4, M, ["carat*", "карат*"]);
def("oz", 0.028349523125, M, ["ounce*", "унци*"]);
def("lb", 0.45359237, M, ["lbs", "pound*", "фунт*"]);
def("st", 6.35029318, M, ["stone*"]);

// Time
def("ns", 1e-9, T, ["nanosecond*", "наносекунд*"]);
def("µs", 1e-6, T, ["us", "microsecond*", "микросекунд*", "мкс"]);
def("ms", 1e-3, T, ["millisecond*", "миллисекунд*", "мс"]);
def("s", 1, T, ["sec", "secs", "second*", "секунд*", "сек", "с"]);
def("min", 60, T, ["mins", "minute*", "минут*", "мин"]);
def("h", 3600, T, ["hr", "hrs", "hour*", "час*", "ч"]);
def("d", 86400, T, ["day", "days", "дн*", "ден*", "сут*", "сутки", "суток", "дн"]);
def("wk", 604800, T, ["week*", "недел*", "нед"]);
def("mo", 2629746, T, ["month*", "месяц*", "мес"]);
def("yr", 31556952, T, ["y", "year*", "год*", "лет", "г."]);

// Temperature (base kelvin)
def("°C", 1, K, ["C", "degc", "celsius", "цельси*", "℃", "°c", "°ц", "ц"], { o: 273.15, name: "Celsius" });
def("°F", 5 / 9, K, ["F", "degf", "fahrenheit", "фаренгейт*", "℉", "°f"], { o: 459.67, name: "Fahrenheit" });
def("K", 1, K, ["=K", "kelvin*", "кельвин*"], { o: 0 });

// Area
def("mm²", 1e-6, L2, ["mm2", "mm^2", "мм2", "мм²"]);
def("cm²", 1e-4, L2, ["cm2", "cm^2", "см2", "см²"]);
def("m²", 1, L2, ["m2", "m^2", "sqm", "м2", "м²"]);
def("km²", 1e6, L2, ["km2", "km^2", "км2", "км²"]);
def("in²", 0.00064516, L2, ["in2", "sqin"]);
def("ft²", 0.09290304, L2, ["ft2", "sqft"]);
def("a", 100, L2, ["are", "сотк*", "соток", "сот", "ар", "ары"]);
def("ha", 1e4, L2, ["hectare*", "гектар*", "га"]);
def("acre", 4046.8564224, L2, ["acres", "акр*"]);
def("mi²", 2589988.110336, L2, ["mi2", "sqmi"]);

// Volume
def("ml", 1e-6, L3, ["mL", "milliliter*", "millilitre*", "миллилитр*", "мл"]);
def("cl", 1e-5, L3, ["centiliter*", "сл"]);
def("dl", 1e-4, L3, ["deciliter*", "дл"]);
def("l", 1e-3, L3, ["L", "liter*", "litre*", "литр*", "л"]);
def("cm³", 1e-6, L3, ["cm3", "cc", "см3", "см³"]);
def("m³", 1, L3, ["m3", "м3", "м³", "кубометр*", "куб"]);
def("tsp", 4.92892159375e-6, L3, ["teaspoon*"]);
def("tbsp", 1.478676478125e-5, L3, ["tablespoon*"]);
def("floz", 2.95735295625e-5, L3, ["fl oz", "fluid ounce*"]);
def("cup", 2.365882365e-4, L3, ["cups", "чашк*", "стакан*"]);
def("pt", 4.73176473e-4, L3, ["pint*", "пинт*"]);
def("qt", 9.46352946e-4, L3, ["quart*", "кварт*"]);
def("gal", 3.785411784e-3, L3, ["gallon*", "галлон*"]);
def("bbl", 0.158987294928, L3, ["barrel*", "баррел*"]);

// Speed
def("m/s", 1, V, ["mps", "м/с", "м/сек"]);
def("km/h", 1 / 3.6, V, ["kmh", "kph", "kmph", "км/ч", "кмч", "км/час"]);
def("mph", 0.44704, V, ["mi/h", "миль/ч"]);
def("kn", 0.514444, V, ["knot*", "kt", "узел", "узл*"]);
def("ft/s", 0.3048, V, ["fps"]);

// Data (base byte; SI prefixes are decimal, the i-forms binary)
def("bit", 1 / 8, D, ["=b", "bits", "бит*"]);
def("B", 1, D, ["byte*", "байт*", "=Б"]);
def("kbit", 125, D, ["=Kb", "kilobit*", "килобит*", "кбит"]);
def("Mbit", 125e3, D, ["=Mb", "megabit*", "мегабит*", "мбит"]);
def("Gbit", 125e6, D, ["=Gb", "gigabit*", "гигабит*", "гбит"]);
def("kB", 1e3, D, ["KB", "=kB", "kilobyte*", "килобайт*", "кб"]);
def("MB", 1e6, D, ["megabyte*", "мегабайт*", "мб"]);
def("GB", 1e9, D, ["gigabyte*", "гигабайт*", "гб"]);
def("TB", 1e12, D, ["terabyte*", "терабайт*", "тб"]);
def("PB", 1e15, D, ["petabyte*", "петабайт*", "пб"]);
def("KiB", 1024, D, ["kibibyte*", "кибибайт*", "киб"]);
def("MiB", 1048576, D, ["mebibyte*", "мебибайт*", "миб"]);
def("GiB", 1073741824, D, ["gibibyte*", "гибибайт*", "гиб"]);
def("TiB", 1099511627776, D, ["tebibyte*", "тиб"]);

// Data rate
def("bit/s", 1 / 8, R, ["bps"]);
def("kbit/s", 125, R, ["kbps", "=kb/s", "=Kb/s", "кбит/с"]);
def("Mbit/s", 125e3, R, ["mbps", "=Mb/s", "мбит/с", "мбит/сек"]);
def("Gbit/s", 125e6, R, ["gbps", "=Gb/s", "гбит/с"]);
def("B/s", 1, R, ["=Bps", "байт/с"]);
def("kB/s", 1e3, R, ["KB/s", "кб/с"]);
def("MB/s", 1e6, R, ["=MBps", "мб/с"]);
def("GB/s", 1e9, R, ["=GBps", "гб/с"]);

// Frequency
def("Hz", 1, HZ, ["hertz", "герц*", "гц"]);
def("kHz", 1e3, HZ, ["кгц"]);
def("MHz", 1e6, HZ, ["мгц"]);
def("GHz", 1e9, HZ, ["ггц"]);
def("rpm", 1 / 60, HZ, ["об/мин"]);

// Energy / power / pressure
def("J", 1, E, ["joule*", "джоул*", "дж"]);
def("kJ", 1e3, E, ["кдж"]);
def("MJ", 1e6, E, ["мдж"]);
def("cal", 4.184, E, ["calorie*", "калори*", "кал"]);
def("kcal", 4184, E, ["Cal", "kilocalorie*", "килокалори*", "ккал"]);
def("Wh", 3600, E, ["вт·ч", "втч"]);
def("kWh", 3.6e6, E, ["квт·ч", "квтч"]);
def("eV", 1.602176634e-19, E, ["эв"]);
def("W", 1, P, ["watt*", "ватт*", "вт"]);
def("kW", 1e3, P, ["kilowatt*", "киловатт*", "квт"]);
def("MW", 1e6, P, ["мвт"]);
def("hp", 745.69987158227022, P, ["horsepower", "лошадин*", "л.с.", "лс"]);
def("Pa", 1, PA, ["pascal*", "паскал*", "па"]);
def("hPa", 100, PA, ["гпа"]);
def("kPa", 1e3, PA, ["кпа"]);
def("MPa", 1e6, PA, ["мпа"]);
def("bar", 1e5, PA, ["bars", "бар"]);
def("atm", 101325, PA, ["atmosphere*", "атмосфер*", "атм"]);
def("psi", 6894.757293168, PA, []);
def("mmHg", 133.322387415, PA, ["torr", "мм рт. ст.", "мм рт ст", "ммртст"]);

// Angle (base radian)
def("rad", 1, A, ["radian*", "радиан*"]);
def("°", Math.PI / 180, A, ["deg", "degree*", "градус*", "град"]);
def("turn", 2 * Math.PI, A, ["turns", "оборот*"]);

// Currencies (ISO code; any code from the rate table works too). The
// factor is filled from the rates (USD base) at evaluation time.
const currencyAliases = {
    USD: ["$", "us$", "dollar*", "buck*", "доллар*", "бакс*", "долл"],
    EUR: ["€", "euro*", "евро"],
    RUB: ["₽", "руб*", "рубл*", "р.", "р", "ruble*", "rouble*"],
    GBP: ["£", "pound sterling", "sterling", "стерлинг*"],
    JPY: ["¥", "yen", "иен*", "йен*"],
    CNY: ["yuan", "renminbi", "rmb", "юан*"],
    KZT: ["₸", "tenge", "тенге"],
    UAH: ["₴", "hryvni*", "гривн*", "гривен"],
    TRY: ["₺", "lira", "лир*"],
    INR: ["₹", "rupee*", "рупи*"],
    KRW: ["₩", "won", "вон"],
    CHF: ["franc*", "франк*"],
    PLN: ["zł", "zloty*", "злот*"],
    AMD: ["֏", "dram*", "драм*"],
    GEL: ["₾", "lari", "лари"],
    AED: ["dirham*", "дирхам*"],
    THB: ["฿", "baht", "бат*"],
    CZK: ["koruna", "крон*"],
    VND: ["₫", "dong", "донг*"],
    BTC: ["₿", "bitcoin*", "биткоин*", "биткойн*"]
};
const currencyIndex = {};
for (const code in currencyAliases) {
    for (const a of currencyAliases[code]) {
        if (a.endsWith("*"))
            stems.push([a.slice(0, -1), code]);
        else
            currencyIndex[a.toLowerCase()] = code;
    }
}
// Symbols written before the number ($5, €3.50, ₽100).
const prefixSymbols = { "$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₽": "RUB", "₸": "KZT",
    "₴": "UAH", "₺": "TRY", "₹": "INR", "₩": "KRW", "₿": "BTC", "₾": "GEL", "฿": "THB" };

// Stems: longest first; the rest of the word must be a plausible ending.
stems.sort((a, b) => b[0].length - a[0].length);
const ending = /^(s|es|a|у|ы|е|и|ов|ев|ей|ам|ям|ами|ями|ах|ях|ом|ем|ой|ь|я|ю|а|ия|ии|ий|ая|ые|ых|ов)?$/;

function currencyUnit(code) {
    return { sym: code, f: NaN, d: { C: 1 }, currency: code };
}

// Unit for a word: { unit } or { currency: "USD" } or null. `codes` =
// known currency codes from the rate table.
function lookup(word, codes) {
    if (!word)
        return null;
    if (exact[word])
        return exact[word];
    const w = word.toLowerCase();
    if (lower[w])
        return lower[w];
    if (currencyIndex[w])
        return currencyUnit(currencyIndex[w]);
    if (/^[a-z]{3}$/i.test(word)) {
        const code = word.toUpperCase();
        if (currencyAliases[code] || (codes && codes[code]))
            return currencyUnit(code);
    }
    for (const [stem, u] of stems) {
        if (w.startsWith(stem) && ending.test(w.slice(stem.length)))
            return typeof u === "string" ? currencyUnit(u) : u;
    }
    return null;
}

// Longest alias that the text starts with (multi-word aliases, symbols,
// "km/h"). Returns { unit, len } or null.
// [alias, unit, case-sensitive]; longest first, exact-case before folded.
const multi = [];
const special = /[\s/.²³^"″′·\d]/;
for (const k in exact)
    if (special.test(k) || /^[^A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]/.test(k))
        multi.push([k, exact[k], true]);
for (const k in lower)
    if (special.test(k) || /^[^A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]/.test(k))
        multi.push([k, lower[k], false]);
for (const k in currencyIndex)
    if (/[\s.]/.test(k) || /^[^A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]/.test(k))
        multi.push([k, currencyIndex[k], false]);
multi.sort((a, b) => b[0].length - a[0].length || b[2] - a[2]);

function matchSpecial(text) {
    const t = text.toLowerCase();
    for (const [k, u, cs] of multi) {
        if (!(cs ? text : t).startsWith(cs ? k : k.toLowerCase()))
            continue;
        // A word alias must end at a word boundary.
        const next = text.charAt(k.length);
        if (/[A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF]$/.test(k) && /[A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF\d]/.test(next))
            continue;
        return { unit: typeof u === "string" ? currencyUnit(u) : u, len: k.length };
    }
    return null;
}

// Unit shown next to a result when no target was asked for.
const partners = {
    "km": ["mi"], "mi": ["km"], "m": ["ft"], "ft": ["m"], "cm": ["in"], "in": ["cm"],
    "mm": ["in"], "yd": ["m"], "nmi": ["km"], "kg": ["lb"], "lb": ["kg"], "g": ["oz"],
    "oz": ["g"], "st": ["kg"], "°C": ["°F", "K"], "°F": ["°C"], "K": ["°C"], "l": ["gal"],
    "gal": ["l"], "ml": ["floz"], "floz": ["ml"], "cup": ["ml"], "pt": ["l"], "qt": ["l"],
    "km/h": ["mph", "m/s"], "mph": ["km/h"], "m/s": ["km/h"], "kn": ["km/h"],
    "m²": ["ft²"], "ft²": ["m²"], "ha": ["acre"], "acre": ["ha"], "a": ["m²"], "km²": ["mi²"],
    "mi²": ["km²"], "kcal": ["kJ"], "kJ": ["kcal"], "kWh": ["MJ"], "hp": ["kW"], "kW": ["hp"],
    "psi": ["bar"], "bar": ["psi"], "atm": ["bar"], "mmHg": ["kPa"], "kPa": ["mmHg"],
    "Mbit/s": ["MB/s"], "MB/s": ["Mbit/s"], "Gbit/s": ["MB/s"], "°": ["rad"], "rad": ["°"],
    "eV": ["J"], "ly": ["km"], "au": ["km"], "bbl": ["l"], "ct": ["g"],
    "yr": ["d"], "mo": ["d"], "wk": ["d"], "d": ["h"], "h": ["min"], "min": ["s"]
};

const dimNames = { L: "m", M: "kg", T: "s", K: "K", D: "B", A: "rad", C: "USD" };

function dimKey(d) {
    return Object.keys(d).filter(k => d[k] !== 0).sort().map(k => k + d[k]).join(" ");
}
