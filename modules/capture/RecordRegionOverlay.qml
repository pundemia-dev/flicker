import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../../components"
import "../../config"

// Marks the zone of a REGION recording on its output: everything outside the
// recorded crop dims lightly and a dashed frame runs just outside it. Both
// stay strictly OUTSIDE the crop (Recorder.regionCrop = the exact even-rounded
// physical box wf-recorder crops to), so none of it lands in the video.
// Continuity with the capture editor: it maps the moment the capture overlay
// starts fading (`Recorder.regionPending`), looking exactly like the editor's
// selection frame (solid, `capture.selectionBorder`, `captureSelection`) —
// then ONE spring driver `k` turns it into the marker: colour → recordFrame,
// width → frameWidth, the line splits into dashes (gap 0 → dashGap), corners
// round. So the selection frame reads as staying and changing colour.
// Top layer (below the Overlay island, so the red plate is not dimmed); an
// EMPTY input region — clicks pass through. Paused = the frame fades back.
Scope {
    id: root
    required property ShellScreen targetScreen
    required property var recorder
    required property var theme
    required property var lock

    readonly property var cfg: Config.data.recorder?.region ?? ({})
    readonly property var capCfg: Config.data.capture ?? ({})
    readonly property bool wantShown: (root.cfg.show ?? true)
        && (root.recorder.recording || root.recorder.regionPending)
        && root.recorder.regionCrop !== null && root.recorder.regionOutput === root.targetScreen.name
        && !root.lock.locked
    // Last crop, held while the marker fades out after the stop.
    property var heldCrop: null
    // 0 = the editor's selection frame, 1 = the recording marker.
    property real k: 1
    property real shownLevel: 0
    Behavior on k {
        id: kAnim
        Spring { stiffness: root.cfg.stiffness ?? 3; damp: root.cfg.damping ?? 1; eps: 0.005 }
    }
    Behavior on shownLevel {
        id: shownAnim
        Spring { stiffness: root.cfg.stiffness ?? 3; damp: root.cfg.damping ?? 1; eps: 0.005 }
    }

    onWantShownChanged: {
        if (root.wantShown) {
            root.heldCrop = root.recorder.regionCrop;
            // Already on screen (a re-show mid fade-out): keep the morph going.
            if (root.shownLevel > 0.01) {
                root.shownLevel = 1;
                root.k = 1;
                return;
            }
            // Appear at once, in the selection frame's look (the capture
            // overlay fading above it hides the swap), then morph.
            shownAnim.enabled = false;
            root.shownLevel = 1;
            shownAnim.enabled = true;
            kAnim.enabled = false;
            root.k = root.recorder.recording ? 1 : 0;
            kAnim.enabled = true;
            root.k = 1;
        } else {
            root.shownLevel = 0;
        }
    }
    Connections {
        target: root.recorder
        function onRegionCropChanged(): void {
            if (root.wantShown)
                root.heldCrop = root.recorder.regionCrop;
        }
    }

    function mix(a: real, b: real): real {
        return a + (b - a) * root.k;
    }

    PanelWindow {
        id: win
        screen: root.targetScreen
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "pillShell-record-region"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        mask: Region {}
        visible: root.heldCrop !== null && (root.wantShown || root.shownLevel > 0.01)

        readonly property real dpr: root.targetScreen.devicePixelRatio || 1
        // Crop in logical px, rounded OUTWARD so a fractional scale never
        // lets a dim / frame pixel bleed into the recorded box.
        readonly property real cx: root.heldCrop ? Math.floor(root.heldCrop.x / dpr) : 0
        readonly property real cy: root.heldCrop ? Math.floor(root.heldCrop.y / dpr) : 0
        readonly property real cr: root.heldCrop ? Math.ceil((root.heldCrop.x + root.heldCrop.width) / dpr) : 0
        readonly property real cb: root.heldCrop ? Math.ceil((root.heldCrop.y + root.heldCrop.height) / dpr) : 0

        Item {
            anchors.fill: parent
            opacity: root.shownLevel

            CaptureDim {
                anchors.fill: parent
                color: Qt.alpha(root.theme.recordDim, root.cfg.dim ?? 0.22)
                cut: Qt.rect(win.cx, win.cy, win.cr - win.cx, win.cb - win.cy)
            }

            // Inner stroke edge stays `frameGap` outside the crop at every k;
            // only the outer edge moves as the width springs.
            Shape {
                id: frame
                readonly property real lw: root.mix(root.capCfg.selectionBorder ?? 1, root.cfg.frameWidth ?? 2)
                readonly property real inner: root.cfg.frameGap ?? 2
                // Path runs along the stroke centre.
                readonly property real off: inner + lw / 2
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                opacity: root.recorder.paused ? (root.cfg.pausedOpacity ?? 0.35) : root.mix(1, root.cfg.frameOpacity ?? 0.85)
                Behavior on opacity {
                    Spring { stiffness: root.cfg.stiffness ?? 3; damp: root.cfg.damping ?? 1; eps: 0.005 }
                }

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Qt.rgba(
                        root.mix(root.theme.captureSelection.r, root.theme.recordFrame.r),
                        root.mix(root.theme.captureSelection.g, root.theme.recordFrame.g),
                        root.mix(root.theme.captureSelection.b, root.theme.recordFrame.b),
                        1)
                    strokeWidth: frame.lw
                    joinStyle: ShapePath.MiterJoin
                    capStyle: ShapePath.FlatCap
                    strokeStyle: ShapePath.DashLine
                    // In stroke widths. Gap 0 = solid (the selection frame).
                    dashPattern: [root.cfg.dashLength ?? 4, Math.max(0.001, root.k * (root.cfg.dashGap ?? 3))]

                    PathRectangle {
                        x: win.cx - frame.off
                        y: win.cy - frame.off
                        width: win.cr - win.cx + 2 * frame.off
                        height: win.cb - win.cy + 2 * frame.off
                        radius: root.k * (root.cfg.frameRadius ?? 4)
                    }
                }
            }
        }
    }
}
