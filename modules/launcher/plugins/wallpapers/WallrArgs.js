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
    // Effect tuning (params(cfg)); "" / null = wallr's own default.
    const p = opts.params || {};
    const flag = (name, v) => {
        if (v !== undefined && v !== null && v !== "")
            a.push(name, String(v));
    };
    if (effect !== "island")
        flag("-o", p.origin);
    flag("-a", p.angle);
    flag("--direction", p.direction);
    flag("--easing", p.easing);
    flag("--from", p.from);
    flag("--to", p.to);
    flag("--frequency", p.frequency);
    flag("--amplitude", p.amplitude);
    flag("--softness", p.softness);
    if (mode)
        a.push("--mode", mode);
    const theme = opts.theme || "";
    if (theme === "none")
        a.push("--no-theme");
    else if (theme.length)
        a.push("-t", theme);
    return a;
}

// Effect tuning from the merged config (launcher.wallpapers + settings
// panel overrides): origin (grow/outer/wave), angle (wipe), direction
// (wipe/slide), easing (all), from/to (fade opacity), frequency/amplitude
// (wave), softness (wipe edge).
function params(cfg) {
    return {
        origin: cfg.effectOrigin,
        angle: cfg.effectAngle,
        direction: cfg.effectDirection,
        easing: cfg.effectEasing,
        from: cfg.fadeFrom,
        to: cfg.fadeTo,
        frequency: cfg.waveFrequency,
        amplitude: cfg.waveAmplitude,
        softness: cfg.wipeSoftness
    };
}
