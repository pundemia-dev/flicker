import QtQuick

// Shared card shell: dark rounded surface on the true-black island body.
// Cards inherit this (WeatherCard { ... }) and only declare their content.
// Placement is layout state (services/DashboardLayout, edited in place);
// allowed footprints per card are in DashCatalog.js. A card fills the rect
// it is given (the DashTile slot) and lays its content out by that rect.
Rectangle {
    id: root
    required property var theme
    required property var dash

    radius: (dash?.cardRadius) ?? 20
    color: theme?.cardBg ?? "#1C1C1E"
    clip: true
}
