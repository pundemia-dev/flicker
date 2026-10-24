import QtQuick
import Quickshell
import Quickshell.Io
import "CalcEngine.js" as Engine
import "../../../config"

// Inline calculator of the launcher (CalcEngine.js): a result card on top
// of the default plugin's list while the query is a calculation ("2^10",
// "15% of 200", "5 usd to rub", "90 min", "days until 31.12"), `=` forces
// it, the Calculator plugin (plugins/calc) adds the history.
// Rows are FIXED objects whose `live` CalcSlot changes in place: the list
// diffs rows by identity, so typing updates the card instead of fading a
// new one in per keystroke. While typing breaks the expression ("100 / 0",
// "2 +") the last good result stays, dimmed.
// Enter copies the result, Alt+Enter pastes it into the focused window
// (launcher.clipboard.pasteCommand); both close the launcher.
Item {
    id: root
    // config.launcher (calc settings under .calc).
    required property var cfg

    readonly property var calcCfg: root.cfg?.calc ?? ({})
    readonly property bool enabled: root.calcCfg.enabled ?? true
    readonly property int maxRows: 4

    // Rows for the launcher list (card first), [] when idle.
    property var entries: []
    // The query asked for the card only (`=` / the plugin): hide the rest.
    property bool exclusive: false

    signal requestClose
    // One of the calculator's own rows became the current one.
    signal cardSelected

    property string query: ""
    property bool forced: false
    property var lastOk: null
    property string lastOkQuery: ""

    CalcRates {
        id: rates
        url: root.calcCfg.ratesUrl ?? "https://open.er-api.com/v6/latest/USD"
        maxAgeHours: root.calcCfg.ratesMaxAgeHours ?? 12
        onRatesChanged: root.refresh()
        onFailedChanged: root.refresh()
    }

    component CalcSlot: QtObject {
        // List row view (LauncherItem reads these through entry.live).
        property string header: ""
        property string text: ""
        property string leftIcon: ""
        property string rightText: ""
        // Card extras.
        property string expr: ""
        property string exprCaption: ""
        property bool stale: false
        // An older answer kept while the expression is mid-edit.
        property bool held: false
        property bool error: false
        property bool placeholder: false
        property string copy: ""
    }

    readonly property list<QtObject> slots: [
        CalcSlot {},
        CalcSlot {},
        CalcSlot {},
        CalcSlot {}
    ]
    readonly property var slotEntries: root.slots.map((s, i) => ({
                calcCard: i === 0,
                live: s,
                onClicked: () => root.take(i, false),
                onAltClicked: () => root.take(i, true),
                onSelected: () => root.cardSelected()
            }))

    function update(query: string, forced: bool): void {
        root.query = query ?? "";
        root.forced = forced;
        root.refresh();
    }

    function clear(): void {
        root.update("", false);
    }

    function context(): var {
        // `ans` = the last copied plain number ("1 h 30 min" is none).
        const last = root.history[0]?.copy ?? "";
        const ans = /^-?\d+(\.\d+)?(e[+-]?\d+)?$/i.test(last) ? parseFloat(last) : NaN;
        return {
            forced: root.forced,
            rates: rates.rates,
            currencies: (root.calcCfg.currencies ?? ["RUB", "USD", "EUR"]).map(c => String(c).trim().toUpperCase()),
            angle: root.calcCfg.angle ?? "deg",
            lang: I18n.lang,
            ans: isFinite(ans) ? ans : undefined,
            tr: s => I18n.tr(s),
            formatDate: d => d.toLocaleDateString(I18n.locale, "ddd, d MMM yyyy")
        };
    }

    function refresh(): void {
        const q = root.query.trim();
        if (!root.enabled || (!q && !root.forced)) {
            root.show(null);
            return;
        }
        let r = null;
        try {
            r = Engine.evaluate(q, root.context());
        } catch (e) {
            console.warn("[Calc]", e);
        }
        root.exclusive = root.forced || q.startsWith("=");
        if (r?.needRates) {
            rates.ensure();
            r = rates.failed && !rates.rates
                ? { ok: false, error: I18n.tr("Exchange rates unavailable"), expr: r.expr, exprCaption: r.exprCaption, results: [] }
                : { ok: true, loading: true, expr: r.expr, exprCaption: r.exprCaption, results: [{ text: "…", copy: "", caption: I18n.tr("Loading exchange rates…"), icon: "" }] };
        } else if (r?.ok && r.kind === "money" && rates.updated > 0) {
            // How fresh the rates are, on the card.
            const when = new Date(rates.updated * 1000).toLocaleDateString(I18n.locale, "d MMM");
            r.results[0].caption += " · " + I18n.tr("rates of %1").arg(when);
            rates.ensure();
        }
        if (r?.ok && !r.loading) {
            root.lastOk = r;
            root.lastOkQuery = q;
            root.show(r);
            return;
        }
        // Mid-edit of the same expression ("100 / 0" on the way to
        // "100 / 0.5", a deleted digit): keep the last answer, dimmed and
        // not copyable (it is not the answer to what is typed). Words typed
        // after it ("7 days to die") are a search, a bare number is no
        // expression any more.
        const related = root.lastOk && /\d/.test(q) && /[^\d\s.,]/.test(q)
            && ((q.startsWith(root.lastOkQuery) && /^[\d\s.,+\-−*\/×÷^()%!=]*$/.test(q.slice(root.lastOkQuery.length)))
                || root.lastOkQuery.startsWith(q));
        if (related && !r?.loading) {
            root.show(Object.assign({}, root.lastOk, { partial: true, held: true, expr: r?.expr ?? q }), r?.ok === false ? r.error : "");
            return;
        }
        root.lastOk = null;
        root.show(r);
    }

    // Fill the slots from an engine result (null = no card).
    function show(r: var, hint: var): void {
        if (!r) {
            root.entries = [];
            return;
        }
        const results = r.results ?? [];
        const s0 = root.slots[0];
        s0.expr = r.expr ?? "";
        s0.exprCaption = r.exprCaption ?? "";
        s0.stale = !!r.partial;
        s0.held = !!r.held;
        s0.placeholder = !!r.empty;
        s0.error = !r.ok && !r.empty;
        if (r.ok && results.length > 0) {
            s0.header = results[0].text;
            s0.text = hint || results[0].caption;
            s0.leftIcon = results[0].icon;
            s0.copy = results[0].copy;
        } else {
            s0.header = r.empty ? I18n.tr("Type an expression") : (r.error ?? "");
            s0.text = r.empty ? I18n.tr("2^10 · 15% of 200 · 5 usd to rub · 90 min · days until 31.12") : "";
            s0.leftIcon = "";
            s0.copy = "";
        }
        const n = Math.min(root.maxRows, Math.max(1, results.length));
        for (let i = 1; i < n; i++) {
            const s = root.slots[i], x = results[i];
            s.header = x.text;
            s.text = x.caption;
            s.leftIcon = x.icon;
            s.copy = x.copy;
            s.stale = !!r.partial;
            s.held = !!r.held;
        }
        if (root.entries.length !== n)
            root.entries = root.slotEntries.slice(0, n);
    }

    function take(i: int, paste: bool): void {
        const s = root.slots[i];
        if (!s || !s.copy || s.held)
            return;
        root.remember(root.slots[0].expr, s.header, s.copy);
        root.copyText(s.copy, paste);
    }

    // ------------------------------------------------------------ history

    property var history: []

    FileView {
        id: historyFile
        path: Quickshell.statePath("calc-history.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(historyFile.text());
                root.history = Array.isArray(s?.items) ? s.items.filter(x => x && typeof x.expr === "string") : [];
            } catch (e) {
                console.warn("[Calc] bad history, ignoring:", e);
            }
        }
    }

    function remember(expr: string, text: string, copy: string): void {
        if (!expr)
            return;
        const limit = root.calcCfg.historyLimit ?? 50;
        const items = [{ expr: expr, text: text, copy: copy, at: Date.now() }]
            .concat(root.history.filter(x => x.expr !== expr)).slice(0, limit);
        root.history = items;
        historyFile.setText(JSON.stringify({ version: 1, items: items }));
    }

    function forget(expr: string): void {
        root.history = root.history.filter(x => x.expr !== expr);
        historyFile.setText(JSON.stringify({ version: 1, items: root.history }));
    }

    function copyText(text: string, paste: bool): void {
        // The paste lands after the launcher let go of the keyboard.
        const shq = t => `'${String(t).replace(/'/g, `'\\''`)}'`;
        const pasteCmd = root.cfg?.clipboard?.pasteCommand ?? "wtype -M ctrl v -m ctrl";
        Quickshell.execDetached(["bash", "-c", `printf %s ${shq(text)} | wl-copy` + (paste ? `; sleep 0.12; ${pasteCmd}` : "")]);
        root.requestClose();
    }
}
