pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// UI translations. Source strings are English and double as keys:
//   I18n.tr("Cancel")                        → "Отмена"
//   I18n.tr("from %1").arg(name)             → placeholders via String.arg
//   I18n.trN(n, "%1 file", "%1 files")       → plural form for n, %1 = n
// Catalogs: assets/i18n/<lang>.json, a flat object { "English": "Перевод" };
// a plural entry is keyed by the singular form and holds an array of forms in
// the order of the language's plural rule (ru: [one, few, many]). A missing or
// empty entry falls back to the English source. Language = Config i18n.language
// ("auto" → Qt.locale()); the catalog is watched and hot-reloads.
// Bindings re-evaluate on a language switch because tr()/trN() read `table`.
Singleton {
    id: root

    readonly property string language: {
        const cfg = Config.data.i18n?.language ?? "auto";
        return cfg === "auto" || cfg === "" ? Qt.locale().name : cfg;
    }
    readonly property string lang: language.split(/[_-]/)[0].toLowerCase()
    // For date/number formatting (day and month names, ...).
    readonly property var locale: Qt.locale(language)

    // Catalog files tried in order: full tag, then the bare language.
    // English is the source language and has no catalog.
    readonly property var candidates: {
        if (lang === "en" || lang === "c" || lang === "")
            return [];
        const full = language.replace("-", "_");
        return full === lang ? [lang] : [full, lang];
    }
    property int candidateIndex: 0
    onCandidatesChanged: candidateIndex = 0

    property var table: ({})

    FileView {
        id: catalog
        path: root.candidateIndex < root.candidates.length
            ? `${Quickshell.shellDir}/assets/i18n/${root.candidates[root.candidateIndex]}.json` : ""
        watchChanges: true
        printErrors: false
        onPathChanged: if (path === "") root.table = {}
        onFileChanged: reload()
        onLoaded: {
            try {
                root.table = JSON.parse(text());
            } catch (e) {
                console.warn(`I18n: bad catalog ${path}: ${e}`);
                root.table = {};
            }
        }
        onLoadFailed: {
            if (root.candidateIndex + 1 < root.candidates.length)
                root.candidateIndex++;
            else
                root.table = {};
        }
    }

    function tr(text) {
        const v = root.table[text];
        return typeof v === "string" && v !== "" ? v : text;
    }

    function trN(n, one, other) {
        const v = root.table[one];
        let s;
        if (Array.isArray(v) && v.length > 0)
            s = v[Math.min(pluralIndex(n), v.length - 1)] || (n === 1 ? one : other);
        else
            s = n === 1 ? one : other;
        return s.replace(/%1/g, String(n));
    }

    // CLDR cardinal rules for integers; default = English (one / other).
    function pluralIndex(n) {
        const a = Math.abs(Math.trunc(n)), m10 = a % 10, m100 = a % 100;
        switch (root.lang) {
        case "ru":
        case "uk":
        case "be":
            return m10 === 1 && m100 !== 11 ? 0 : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? 1 : 2;
        case "pl":
            return a === 1 ? 0 : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? 1 : 2;
        default:
            return a === 1 ? 0 : 1;
        }
    }

    // Locale day/month names come lowercase in some languages (ru).
    function capitalize(s) {
        return s ? s.charAt(0).toUpperCase() + s.slice(1) : s;
    }
}
