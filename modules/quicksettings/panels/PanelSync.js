.pragma library

// Syncs a ListModel to `list` (array of plain objects) IN PLACE, matched by
// `key`: removes gone rows, moves / updates kept ones, inserts new ones —
// a reassigned array model rebuilt every row and reset the scroll.
function sync(model, list, key) {
    for (let i = model.count - 1; i >= 0; i--) {
        const k = model.get(i)[key];
        if (!list.some(n => n[key] === k))
            model.remove(i);
    }
    list.forEach((n, i) => {
        let j = -1;
        for (let m = i; m < model.count; m++)
            if (model.get(m)[key] === n[key]) {
                j = m;
                break;
            }
        if (j < 0)
            model.insert(i, n);
        else {
            if (j !== i)
                model.move(j, i, 1);
            model.set(i, n);
        }
    });
}
