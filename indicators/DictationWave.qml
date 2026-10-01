import QtQuick
import Quickshell.Services.Pipewire
import "../components"

// Dictation indicator: a live audio wave driven by the real mic peak level
// (PwNodePeakMonitor on the default source), not a canned animation. Peaks
// arrive cbrt-compressed from the monitor, so the gate below is tuned for
// that scale (1.15x, not linear 1.5x). Levels are auto-scaled (noise-floor
// gate + running maximum with a speech-level prior), so silence sits flat
// and any mic — quiet or hot — swings full height on voice. While the
// backend is (re)starting and the model isn't loaded yet (dictation phase
// "switching") the wave renders grey. Appears via fade + width growth from
// its left anchor while the island expands alongside it (desiredWidth feeds
// Island.islandWidth). Position: after music, before the clock.
Item {
    id: root
    // Plain (not required): Loader creates the item before onLoaded injects
    // the services bundle, and all reads below are null-safe.
    property var services: null
    property bool evicted: false

    readonly property var dictation: services?.dictation ?? null
    readonly property var audioSvc: services?.audio ?? null
    readonly property var src: root.audioSvc?.source ?? null
    readonly property var theme: services?.theme ?? null
    readonly property var cfg: services?.cfg ?? null
    readonly property bool active: dictation?.active ?? false
    readonly property bool switching: (dictation?.phase ?? "") === "switching"
    readonly property real waveWidth: cfg?.waveWidth ?? 28
    // Stable width for the eviction math (never depends on `evicted`).
    readonly property real desiredWidth: active ? waveWidth : 0
    // Enter animation (see Microphone.qml): grow in instead of popping.
    property bool entered: false
    Component.onCompleted: entered = true
    // Smoothed mic level 0..1 (fast attack from the sampler, slow release).
    // Scaled, not absolute: a quiet mic would sit near zero forever on a
    // 0..1 scale. noiseFloor seeds from the first sample (the background is
    // known immediately), dives fast on dips and climbs very slowly, so it
    // never chases sustained speech; the 1.15x gate kills background while
    // passing voice (peaks arrive cbrt-compressed, so linear ratios shrink);
    // peakMax tracks the gated excess with slow release and starts at a
    // speech-level prior (0.05) so pre-speech silence maps flat instead of
    // normalizing noise to full height. Loud transients desensitize briefly,
    // then sensitivity recovers on its own.
    property real peakMax: 0.05
    property real noiseFloor: 0
    property bool floorUnset: true
    property real displayLevel: 0
    // Capture hinge for the freeze watchdog below (toggling enabled forces
    // the monitor to rebuild its stream).
    property bool monHinge: true
    property real _lastPeak: -1
    property int _stuckTicks: 0
    onActiveChanged: {
        if (!active)
            displayLevel = 0;
    }
    // A new source node means a new background: reseed the meter instead of
    // judging the new mic by the old one's floor/max.
    onSrcChanged: {
        root.noiseFloor = 0;
        root.floorUnset = true;
        root.peakMax = 0.05;
        root.displayLevel = 0;
        root._lastPeak = -1;
        root._stuckTicks = 0;
    }

    function barGain(i: int): real {
        return [1.0, 0.7, 0.85, 0.55][i] ?? 1.0;
    }

    width: (entered && !evicted) ? desiredWidth : 0
    height: 14
    visible: width > 0.5
    opacity: active && !evicted ? 1 : 0
    Behavior on width { Spring {} }
    Behavior on opacity { NumberAnimation { duration: 160 } }

    PwNodePeakMonitor {
        id: peakMon
        node: root.src
        // Ready-guard: binding a not-yet-ready node captures nothing and
        // never rebuilds, leaving peak at 0 (flat dots) for the session.
        // Disabled (like null node) resets peak to 0 by itself.
        enabled: root.active && root.monHinge && (root.src?.ready ?? false)
    }

    // Peak sampler: attack follows the voice instantly, release decays so
    // bars fall smoothly instead of flickering between frames.
    Timer {
        interval: 70
        repeat: true
        running: root.active
        onTriggered: {
            const p = peakMon.peak ?? 0;
            if (root.floorUnset) {
                root.noiseFloor = p;
                root.floorUnset = false;
            } else {
                root.noiseFloor += (p - root.noiseFloor) * (p < root.noiseFloor ? 0.3 : 0.001);
            }
            const excess = Math.max(0, p - root.noiseFloor * 1.15);
            root.peakMax = Math.max(excess, root.peakMax * 0.97);
            const norm = Math.max(0, Math.min(1, excess / Math.max(root.peakMax, 0.004)));
            root.displayLevel = Math.max(norm, root.displayLevel * 0.65);
        }
    }

    // Freeze watchdog: on a channel mismatch the monitor stops updating and
    // peak sticks at its last (nonzero) value instead of falling to dots.
    // Real audio always jitters at float precision, so an identical nonzero
    // peak for 3s straight means a dead capture — bounce enabled to force a
    // rebuild. Legit silence reads exactly 0 and never triggers this.
    Timer {
        interval: 1000
        repeat: true
        running: root.active
        onTriggered: {
            const p = peakMon.peak ?? 0;
            if (p > 0.02 && Math.abs(p - root._lastPeak) < 1e-6) {
                root._stuckTicks += 1;
                if (root._stuckTicks >= 3) {
                    root._stuckTicks = 0;
                    root.monHinge = false;
                    hingeTimer.restart();
                }
            } else {
                root._stuckTicks = 0;
            }
            root._lastPeak = p;
        }
    }

    Timer {
        id: hingeTimer
        interval: 200
        onTriggered: root.monHinge = true
    }

    Repeater {
        model: 4
        Rectangle {
            width: 3
            // Dots at silence (2px), full swing on voice (up to 13px):
            // the contrast lives in the minimum, not the maximum.
            height: 2 + Math.round(root.displayLevel * 11 * root.barGain(index))
            radius: 1
            color: root.switching ? (root.theme?.waveDim ?? "#6E7683") : (root.theme?.waveColor ?? "#A8C1FF")
            x: index * 6
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
