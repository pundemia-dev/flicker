.pragma library

// Settings search: every row of every section (drill-down pages included)
// whose label, group title, section title or keywords hold all the query
// words — in English and in the UI language (`tr`). One result group per
// section; the rows are the real rows (plus `section`, so a drill-down
// from the results opens in its section), so they stay live controls.

function haystack(parts, tr) {
    return parts.filter(p => p).map(p => p + " " + tr(p)).join(" ").toLowerCase();
}

function collect(groups, context, words, tr, out) {
    for (const g of groups) {
        for (const row of g.rows) {
            if (row.kind === "page") {
                collect(row.page.groups, context.concat([row.label]), words, tr, out);
                continue;
            }
            const text = haystack(context.concat([g.title, row.label, row.keywords]), tr);
            if (words.every(w => text.includes(w)))
                out.push(row);
        }
    }
}

function groups(sections, query, tr) {
    const words = query.toLowerCase().split(/\s+/).filter(w => w);
    const result = [];
    for (const s of sections) {
        const rows = [];
        collect(s.groups, [s.title], words, tr, rows);
        if (rows.length > 0)
            result.push({ title: s.title, section: s.id, rows: rows.map(r => Object.assign({ section: s.id }, r)) });
    }
    return result;
}
