.pragma library

// When the sun crosses two elevations on a local day: `day` (sun this high
// = full day, +3°) and `night` (civil twilight, -6°). wlsunset's NOAA
// approximation (DMS ports it too), no network: the fade follows the real
// sky — long at high latitudes in winter, short near the equator.
// Returns { dawn, sunrise, sunset, dusk } (epoch ms; dawn → sunrise =
// morning fade, sunset → dusk = evening fade) and `cond`: "normal",
// "polarDay" (never below `day`) or "polarNight" (never above `night`).

const RAD = Math.PI / 180;

function daysInYear(y) {
    return (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0 ? 366 : 365;
}

// Seconds after UTC midnight of a mean-solar-time hour angle.
function hourAngleToSec(ha, eqtime) {
    return (4 * Math.PI - 4 * ha - eqtime) / RAD * 60;
}

function hourAngle(lat, decl, elevation) {
    const zenith = (90.833 - elevation) * RAD;
    const c = Math.cos(zenith) / (Math.cos(lat) * Math.cos(decl)) - Math.tan(lat) * Math.tan(decl);
    if (c < -1)
        return { ha: Math.PI, state: "above" };
    if (c > 1)
        return { ha: 0, state: "below" };
    return { ha: Math.acos(c), state: "crosses" };
}

// `date`: any moment of the wanted local day.
function compute(lat, lon, date, dayElev, nightElev) {
    const lonOffsetMs = -lon * 4 * 60000;
    // The solar day the local civil day falls in (anchored on local noon:
    // right for zones a day away from their meridian too — DMS #3179).
    const noon = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 12).getTime();
    const ref = new Date(noon - lonOffsetMs);
    const dayStart = Date.UTC(ref.getUTCFullYear(), ref.getUTCMonth(), ref.getUTCDate());
    const yday = Math.round((dayStart - Date.UTC(ref.getUTCFullYear(), 0, 1)) / 86400000);
    const g = 2 * Math.PI / daysInYear(ref.getUTCFullYear()) * yday;
    const decl = 0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g) - 0.006758 * Math.cos(2 * g)
        + 0.000907 * Math.sin(2 * g) - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g);
    const eqtime = 4 * (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g)
        - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g));

    const latR = lat * RAD;
    const tw = hourAngle(latR, decl, nightElev ?? -6);
    const dl = hourAngle(latR, decl, dayElev ?? 3);
    if (dl.state === "above")
        return { cond: "polarDay" };
    if (tw.state === "below")
        return { cond: "polarNight" };
    const at = s => dayStart + s * 1000 + lonOffsetMs;
    return {
        cond: "normal",
        dawn: at(hourAngleToSec(Math.abs(tw.ha), eqtime)),
        sunrise: at(hourAngleToSec(Math.abs(dl.ha), eqtime)),
        sunset: at(hourAngleToSec(-Math.abs(dl.ha), eqtime)),
        dusk: at(hourAngleToSec(-Math.abs(tw.ha), eqtime))
    };
}
