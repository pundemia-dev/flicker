.pragma library

// `wallr set` argv. opts: { output (""/null = all outputs), effect
// ("island" = grow from originX/originY, else a wallr effect), durationMs,
// originX/originY (normalized, y from the top), theme ("" = wallr config,
// "none" = --no-theme, else a provider) }; mode = scaling (fill/fit/...).
function set(path, opts, mode) {
    const a = ["wallr", "set", path];
    if (opts.output)
        a.push("-m", opts.output);
    const effect = opts.effect || "fade";
    if (effect === "island")
        a.push("-e", "grow", "-o", (opts.originX ?? 0.5).toFixed(4) + "," + (opts.originY ?? 0).toFixed(4));
    else
        a.push("-e", effect);
    a.push("-d", Math.round(opts.durationMs ?? 1000) + "ms");
    if (mode)
        a.push("--mode", mode);
    const theme = opts.theme || "";
    if (theme === "none")
        a.push("--no-theme");
    else if (theme.length)
        a.push("-t", theme);
    return a;
}
