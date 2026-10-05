import QtQuick

// Shared card shell: dark rounded surface on the true-black island body.
// Cards inherit this (WeatherCard { ... }) and only declare their content.
// Per-card placement (order, spans) lives in DashboardModule — reordering
// is moving blocks there; spans travel with the card (Layout attached
// props are set at the use site next to the card, not inside it).
Rectangle {
    id: root
    required property var theme
    required property var dash

    // NOTE: grid spans (spanCols/spanRows) are declared in each card file,
    // not here — QML forbids redeclaring an inherited property.

    radius: (dash?.cardRadius) ?? 20
    color: theme?.cardBg ?? "#1C1C1E"
    clip: true
}
