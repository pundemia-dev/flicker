import QtQuick
import Quickshell
import Quickshell.Io

// Exchange rates for the calculator: { CODE: units per 1 USD } from
// launcher.calc.ratesUrl (open.er-api.com format: { result, rates,
// time_last_update_unix }), cached in the state dir. Fetched only when a
// calculation needs them and the cache is older than ratesMaxAgeHours;
// a stale cache keeps working offline (`updated` tells how old).
// curl -4: IPv6 is broken on some networks and Qt's loader stalls on it.
Item {
    id: root
    property string url: "https://open.er-api.com/v6/latest/USD"
    property real maxAgeHours: 12

    property var rates: null
    // Unix seconds of the rates (provider time), 0 = none yet.
    property real updated: 0
    property real fetchedAt: 0
    readonly property bool loading: proc.running
    property bool failed: false

    FileView {
        id: cache
        path: Quickshell.statePath("calc-rates.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(cache.text());
                if (s?.rates && typeof s.rates === "object") {
                    // Dates first: a rates change recomputes and reads them.
                    root.updated = s.updated ?? 0;
                    root.fetchedAt = s.fetchedAt ?? 0;
                    root.rates = s.rates;
                }
            } catch (e) {
                console.warn("[Calc] bad rate cache, ignoring:", e);
            }
        }
    }

    // Fetch when missing or old (no-op while a fetch runs or right after a
    // failure: one retry per minute).
    function ensure(): void {
        if (proc.running)
            return;
        const now = Date.now();
        if (root.rates && now - root.fetchedAt < root.maxAgeHours * 3600000)
            return;
        if (root.failed && now - lastTry < 60000)
            return;
        lastTry = now;
        proc.running = true;
    }
    property real lastTry: 0

    Process {
        id: proc
        command: ["curl", "-4", "-sfL", "--max-time", "10", root.url]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (!d?.rates || (d.result && d.result !== "success"))
                        throw new Error(d?.["error-type"] ?? "no rates");
                    const r = Object.assign({}, d.rates);
                    r.USD = 1;
                    root.updated = d.time_last_update_unix ?? Math.floor(Date.now() / 1000);
                    root.fetchedAt = Date.now();
                    root.failed = false;
                    root.rates = r;
                    cache.setText(JSON.stringify({ rates: r, updated: root.updated, fetchedAt: root.fetchedAt }));
                } catch (e) {
                    root.failed = true;
                    console.warn("[Calc] rates:", e);
                }
            }
        }
        onExited: code => {
            if (code !== 0) {
                root.failed = true;
                console.warn("[Calc] rates fetch failed, curl exit", code);
            }
        }
    }
}
