import QtQuick

SpringAnimation {
    // Optional tuning (defaults = island-geometry feel). Fractional
    // properties (like ring 0..1 fills) need a tiny epsilon, otherwise
    // the animation stops up to epsilon away from the target value.
    property real stiffness: 4
    property real damp: 0.35
    property real eps: 0.2

    spring: stiffness
    damping: damp
    epsilon: eps
}
