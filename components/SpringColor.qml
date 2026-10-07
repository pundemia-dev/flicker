import QtQuick

// A colour that springs to `target` channel by channel (r, g, b, a each on
// a Spring — no timed colour tweens, project rule). `value` is the live
// colour; channels are clamped, a spring overshoot past 0/1 would make
// Qt warn ("setAlphaF: invalid value") and tint wrongly.
QtObject {
    id: root
    property color target: "transparent"
    property real stiffness: 2
    property real damping: 0.6

    property real r: root.target.r
    property real g: root.target.g
    property real b: root.target.b
    property real a: root.target.a
    Behavior on r { Spring { stiffness: root.stiffness; damp: root.damping; eps: 0.002 } }
    Behavior on g { Spring { stiffness: root.stiffness; damp: root.damping; eps: 0.002 } }
    Behavior on b { Spring { stiffness: root.stiffness; damp: root.damping; eps: 0.002 } }
    Behavior on a { Spring { stiffness: root.stiffness; damp: root.damping; eps: 0.002 } }

    function clamp(v: real): real {
        return Math.max(0, Math.min(1, v));
    }
    readonly property color value: Qt.rgba(root.clamp(root.r), root.clamp(root.g), root.clamp(root.b), root.clamp(root.a))
}
