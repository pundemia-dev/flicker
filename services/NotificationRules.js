.pragma library

// Notification rule basics shared by the service (Notifications.qml) and
// the settings pages (SettingsNotifs.js), so both agree on what is live
// and what is a valid pattern.

// Enabled and not past its `until` (ms epoch, 0 = forever).
function live(rule, now) {
    return !!rule && rule.enabled !== false && !((rule.until ?? 0) > 0 && rule.until <= now);
}

// A timed rule whose time is up (the service removes it).
function expired(rule, now) {
    return (rule?.until ?? 0) > 0 && rule.until <= now;
}

// Case-insensitive RegExp of a rule pattern, null when it is invalid.
function compile(pattern) {
    try {
        return new RegExp(pattern, "i");
    } catch (e) {
        return null;
    }
}
