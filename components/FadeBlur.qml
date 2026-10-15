import QtQuick

// Appear / disappear through our blur-fade (the ContentSwap look for a
// single element): `shown` drives one spring p 0..1; opacity follows p and
// the content blur rises as it fades (BlurSurface amount = 1 - p). At rest
// (p = 1) the blur layer is off, so idle content stays crisp and takes
// input; fully hidden it takes no input and drops the blur layer. NOT
// `visible: false`: CurveRenderer Shapes inside (VolumeIcon, ...) never
// repaint after an ancestor's visible flips back (seen in the OSD).
BlurSurface {
    id: root
    property bool shown: true
    property real stiffness: 4
    property real damp: 0.5
    property real p: root.shown ? 1 : 0
    Behavior on p { Spring { stiffness: root.stiffness; damp: root.damp; eps: 0.005 } }

    amount: root.p > 0.01 ? 1 - root.p : 0
    opacity: root.p
    enabled: root.p > 0.01
}
