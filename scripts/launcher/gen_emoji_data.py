#!/usr/bin/env python3
"""Regenerates the dataset of the launcher emoji plugin (plugins/emoji).

Sources (fetched over IPv4; or pass a directory that already holds them):
  emoji-test.txt         unicode.org — ordered groups, names, versions
  annotations/{en,ru}    Unicode CLDR — names (tts) + keywords; CLDR also
                         annotates ~2000 non-emoji symbols (arrows, math,
                         currency, punctuation …) → the symbol groups.

Output: modules/launcher/plugins/emoji/emoji.tsv, one line per character:
    <char>\t<group>\t<english name>\t<russian name>\t<keywords>
Emoji groups keep the emoji-test order; skin-tone variants and the
"Component" group are dropped. Emoji newer than the installed Noto Color
Emoji covers are dropped too (they would render as tofu / split sequences).
Symbol groups come from the Unicode block of the code point (SYMBOL_GROUPS).

Usage: scripts/launcher/gen_emoji_data.py [source-dir]
"""

import re
import socket
import subprocess
import sys
import unicodedata
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "modules/launcher/plugins/emoji/emoji.tsv"
EMOJI_TEST = "https://unicode.org/Public/emoji/latest/emoji-test.txt"
CLDR = "https://raw.githubusercontent.com/unicode-org/cldr/main/common/annotations/{}.xml"
FONT = "/usr/share/fonts/noto/NotoColorEmoji.ttf"
VS16 = "️"

# IPv6 is broken on this machine: resolve IPv4 only.
_gai = socket.getaddrinfo
socket.getaddrinfo = lambda host, port, family=0, *a, **k: _gai(host, port, socket.AF_INET, *a, **k)


def fetch(name: str, url: str, src: Path | None) -> str:
    if src and (src / name).exists():
        return (src / name).read_text(encoding="utf-8")
    print(f"fetching {url}", file=sys.stderr)
    req = urllib.request.Request(url, headers={"User-Agent": "flicker-emoji-gen"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8")


def font_codepoints() -> set[int]:
    try:
        out = subprocess.run(["fc-query", "--format=%{charset}", FONT],
                             capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return set()
    cps: set[int] = set()
    for part in out.split():
        a, _, b = part.partition("-")
        lo = int(a, 16)
        cps.update(range(lo, int(b, 16) + 1) if b else [lo])
    return cps


def cldr(xml: str) -> tuple[dict[str, str], dict[str, list[str]]]:
    names: dict[str, str] = {}
    kws: dict[str, list[str]] = {}
    for cp, attrs, body in re.findall(r'<annotation cp="([^"]+)"([^>]*)>([^<]*)</annotation>', xml):
        cp = cp.replace("&quot;", '"').replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&apos;", "'")
        key = cp.replace(VS16, "")
        if 'type="tts"' in attrs:
            names[key] = body.strip()
        else:
            kws[key] = [p.strip().lower() for p in body.split("|") if p.strip()]
    return names, kws


# (group, first, last) by code point; the first match wins.
SYMBOL_GROUPS = [
    ("Punctuation", 0x0020, 0x00BF),
    ("Punctuation", 0x2000, 0x206F),
    ("Punctuation", 0x2E00, 0x2E7F),
    ("Currency", 0x20A0, 0x20CF),
    ("Letterlike", 0x2100, 0x214F),
    ("Arrows", 0x2190, 0x21FF),
    ("Arrows", 0x27F0, 0x27FF),
    ("Arrows", 0x2900, 0x297F),
    ("Arrows", 0x2B00, 0x2BFF),
    ("Math", 0x00D7, 0x00D7),
    ("Math", 0x00F7, 0x00F7),
    ("Math", 0x2150, 0x218F),
    ("Math", 0x2200, 0x22FF),
    ("Math", 0x27C0, 0x27EF),
    ("Math", 0x2980, 0x2AFF),
    ("Technical", 0x2300, 0x23FF),
    ("Shapes", 0x2500, 0x25FF),
    ("Dingbats", 0x2600, 0x27BF),
    ("Greek", 0x0370, 0x03FF),
    ("Superscripts", 0x2070, 0x209F),
]
SYMBOL_ORDER = ["Punctuation", "Arrows", "Math", "Currency", "Technical", "Letterlike",
                "Superscripts", "Greek", "Shapes", "Dingbats", "Other symbols"]
# Currency signs scattered outside the Currency block.
CURRENCY = set("$¢£¤¥₽﷼")
# Printable ASCII is on every keyboard; CJK / Arabic punctuation, skin-tone
# and hair components are noise in a symbol picker.
SKIP = set(chr(c) for c in range(0x20, 0x7F)) | set("،؛؟、。〈〉《》「」『』【】〔〕〖〗・") \
    | set(chr(c) for c in range(0x1F3FB, 0x1F400)) | set(chr(c) for c in range(0x1F9B0, 0x1F9B4))

# Useful symbols CLDR leaves out: group -> "chars|russian name;…" (one ru
# name per char, in order; the English name is the Unicode name).
CURATED = {
    "Technical": [("⌘", "команда"), ("⌥", "опция, альт"), ("⌃", "контрол"), ("⇧", "шифт"), ("⇪", "капс лок"),
                  ("⎋", "эскейп"), ("⏎", "ввод, энтер"), ("↩", "возврат"), ("⌫", "бэкспейс, удалить"),
                  ("⌦", "удалить вперёд"), ("⇥", "таб"), ("⇤", "таб назад"), ("␣", "пробел"), ("⏏", "извлечь"),
                  ("⌨", "клавиатура"), ("⎈", "штурвал"), ("⌀", "диаметр"), ("⌂", "дом"), ("⌛", "песочные часы"),
                  ("⏻", "питание"), ("⏼", "вкл выкл"), ("⏽", "питание вкл"), ("⭘", "питание выкл"),
                  ("⎇", "альтернатива"), ("⌚", "часы")],
    "Letterlike": [("№", "номер"), ("℃", "градус цельсия"), ("℉", "градус фаренгейта"), ("™", "товарный знак"),
                   ("©", "копирайт"), ("®", "зарегистрировано"), ("℗", "звукозапись"), ("℠", "знак обслуживания"),
                   ("Ω", "ом"), ("µ", "микро"), ("Å", "ангстрем"), ("ℓ", "литр"), ("℮", "оценочный знак"),
                   ("ℹ", "информация"), ("ℕ", "натуральные числа"), ("ℤ", "целые числа"), ("ℚ", "рациональные числа"),
                   ("ℝ", "вещественные числа"), ("ℂ", "комплексные числа"), ("ℵ", "алеф"), ("℘", "вейерштрасс")],
    "Superscripts": [(c, r) for c, r in zip("⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁿⁱ", ["верхний индекс " + x for x in
                     "0 1 2 3 4 5 6 7 8 9 плюс минус равно скобка скобка n i".split()])]
                    + [(c, r) for c, r in zip("₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎", ["нижний индекс " + x for x in
                     "0 1 2 3 4 5 6 7 8 9 плюс минус равно скобка скобка".split()])]
                    + [(c, "дробь " + r) for c, r in zip("½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞⅐⅑⅒",
                       "1/2 1/3 2/3 1/4 3/4 1/5 2/5 3/5 4/5 1/6 5/6 1/8 3/8 5/8 7/8 1/7 1/9 1/10".split())],
    "Greek": [(c, "греческая " + r) for c, r in zip("αβγδεζηθικλμνξοπρστυφχψω",
              "альфа бета гамма дельта эпсилон дзета эта тета йота каппа лямбда мю ню кси омикрон пи ро сигма тау ипсилон фи хи пси омега".split())]
             + [(c, "греческая заглавная " + r) for c, r in zip("ΓΔΘΛΞΠΣΦΨΩ", "гамма дельта тета лямбда кси пи сигма фи пси омега".split())],
    "Dingbats": [("✓", "галочка"), ("✔", "жирная галочка"), ("✗", "крестик"), ("✘", "жирный крестик"),
                 ("☐", "чекбокс"), ("☑", "отмеченный чекбокс"), ("☒", "чекбокс с крестиком"),
                 ("★", "звезда"), ("☆", "пустая звезда"), ("✦", "четырёхконечная звезда"), ("✧", "пустая четырёхконечная звезда"),
                 ("♥", "червы, сердце"), ("♡", "пустое сердце"), ("♦", "бубны"), ("♢", "пустые бубны"), ("♣", "трефы"),
                 ("♧", "пустые трефы"), ("♠", "пики"), ("♤", "пустые пики"), ("♩", "нота"), ("♫", "ноты"), ("♬", "ноты"),
                 ("☀", "солнце"), ("☁", "облако"), ("☂", "зонт"), ("☃", "снеговик"), ("☎", "телефон"), ("☛", "палец вправо"),
                 ("☞", "палец вправо"), ("☚", "палец влево"), ("☜", "палец влево"), ("☯", "инь ян"), ("☮", "мир"),
                 ("✂", "ножницы"), ("✈", "самолёт"), ("✉", "конверт"), ("✎", "карандаш"), ("✏", "карандаш"),
                 ("✒", "перо"), ("❝", "кавычка"), ("❞", "кавычка"), ("❦", "цветок"), ("❧", "цветок"), ("✱", "звёздочка"),
                 ("✳", "звёздочка"), ("❄", "снежинка"), ("❤", "сердце"), ("➔", "стрелка"), ("➜", "стрелка"), ("➤", "стрелка")],
    "Punctuation": [("‹", "одинарная кавычка-ёлочка"), ("›", "одинарная кавычка-ёлочка"), ("‑", "неразрывный дефис"),
                    ("‒", "цифровое тире"), ("¦", "прерывистая черта"), ("¯", "макрон"), ("¸", "седиль"),
                    ("ª", "порядковый индикатор"), ("º", "порядковый индикатор"), ("¤", "знак валюты")],
}


def symbol_group(ch: str) -> str:
    if ch in CURRENCY:
        return "Currency"
    if len(ch) != 1:
        return "Other symbols"
    cp = ord(ch)
    for g, lo, hi in SYMBOL_GROUPS:
        if lo <= cp <= hi:
            return g
    return "Other symbols"


def clean(s: str) -> str:
    return s.replace("\t", " ").replace("\n", " ").strip()


def main() -> int:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    test = fetch("emoji-test.txt", EMOJI_TEST, src)
    en_names, en_kw = cldr(fetch("en.xml", CLDR.format("en"), src))
    ru_names, ru_kw = cldr(fetch("ru.xml", CLDR.format("ru"), src))
    covered = font_codepoints()

    parsed = []  # (emoji, group, name, version)
    group = ""
    for line in test.splitlines():
        if line.startswith("# group:"):
            group = line.split(":", 1)[1].strip()
            continue
        head, _, comment = line.partition("#")
        if ";" not in head or head.split(";", 1)[1].strip() != "fully-qualified":
            continue
        m = re.match(r"^\s*(\S+)\s+E([\d.]+)\s+(.*)$", comment)
        if not m or group == "Component" or "skin tone" in m.group(3):
            continue
        parsed.append((m.group(1), group, m.group(3).strip(), float(m.group(2))))

    # Newest emoji version the font has: the newest single-code-point emoji
    # it covers. Everything newer goes (ZWJ sequences included).
    max_ver = 99.0
    if covered:
        singles = [v for e, _, _, v in parsed if len(e.replace(VS16, "")) == 1 and ord(e[0]) in covered]
        max_ver = max(singles) if singles else 99.0

    rows = []
    seen = set()
    for emoji, group, name, ver in parsed:
        if ver > max_ver or (covered and not all(ord(c) in covered for c in emoji if c not in "‍️")):
            continue
        key = emoji.replace(VS16, "")
        seen.add(key)
        rows.append((emoji, group, name, ru_names.get(key, ""), en_kw.get(key, []) + ru_kw.get(key, [])))
    dropped = len(parsed) - len(rows)

    # Non-emoji symbols CLDR annotates, grouped by block.
    syms: dict[str, list] = {g: [] for g in SYMBOL_ORDER}
    for key, en in en_names.items():
        if key in seen or key in SKIP or any(unicodedata.category(c)[0] in "LNCZM" for c in key):
            continue
        seen.add(key)
        syms[symbol_group(key)].append((key, en, ru_names.get(key, ""), en_kw.get(key, []) + ru_kw.get(key, [])))
    for g, items in CURATED.items():
        for ch, ru in items:
            if ch in seen:
                continue
            seen.add(ch)
            en = unicodedata.name(ch, ch).lower()
            syms[g].append((ch, en, ru, [w for w in ru.replace(",", " ").split() if len(w) > 2]))
    for g in SYMBOL_ORDER:
        # Curated groups keep their hand order; CLDR ones go by code point.
        items = syms[g] if g in CURATED and g not in ("Punctuation", "Dingbats") else sorted(syms[g], key=lambda r: [ord(c) for c in r[0]])
        for ch, en, ru, kw in items:
            rows.append((ch, g, en, ru, kw))

    with OUT.open("w", encoding="utf-8") as f:
        for ch, g, en, ru, kw in rows:
            words = []
            for w in kw:
                if w not in words and w != en.lower():
                    words.append(w)
            f.write("\t".join([ch, g, clean(en), clean(ru), clean(" ".join(words))]) + "\n")
    nsym = sum(len(v) for v in syms.values())
    print(f"wrote {len(rows)} rows ({len(rows) - nsym} emoji up to E{max_ver}, {dropped} dropped; "
          f"{nsym} symbols) -> {OUT}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
