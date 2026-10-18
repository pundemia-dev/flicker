import QtQuick
import "../../components"

// Expanded QS card = components/DropExpand with the QS specifics: long
// press on a card that has a panel (QsCardFactory.panelFor) → drop →
// flight → panel (free px size `expand.panels.<id>`, inside the grid area —
// never over the rail column). The card keeps its slot (`expandedOut` drops
// its surface); its content is the drop's starting look, the fill starts at
// the card's look (accent when on). The module cuts the grid out under the
// shape and the island clears its frost tint there (`knockoutClear`).
DropExpand {
    id: root
    required property var cfg
    required property var theme
    property var frost: null
    property var cardFactory: null
    // Area the panel must fit in (+ margins): the grid, not the rail.
    property real boundsW: root.width
    property real boundsH: root.height

    readonly property var e: root.cfg.expand ?? ({})
    readonly property string cardId: root.source?.cardId ?? ""
    readonly property bool wantsKeyboard: root.panel?.wantsKeyboard ?? false

    bounds: Qt.rect(0, 0, root.boundsW, root.boundsH)
    margin: root.cfg.margins
    shadowSize: root.cfg.innerShadowSize ?? 14
    shadowStrength: root.cfg.innerShadowStrength ?? 0.06
    panelRadius: (root.e.panelRadius ?? 0) > 0 ? root.e.panelRadius : root.cfg.unit / 2
    panelColor: root.mix(root.theme?.qsCardBg ?? "#000000", root.theme?.qsPanelBg ?? "#8C141416", root.frost?.progress ?? 0)

    readonly property color surfaceColor: root.frost?.surface(root.theme?.qsCardBg ?? "#000000") ?? (root.theme?.qsCardBg ?? "#000000")

    function openCard(c: Item): bool {
        if (root.active)
            return root.open(c, null);
        const comp = root.cardFactory?.panelFor(c.cardId) ?? null;
        if (!comp)
            return false;
        const spec = root.e.panels?.[c.cardId] ?? {};
        return root.open(c, {
            panel: comp,
            width: spec.width,
            height: spec.height,
            sourceRadius: c.radius,
            layer: c.contentLayer,
            color: () => {
                const it = c.contentLayer?.item ?? null;
                return it && typeof it.onP === "number" && it.accent !== undefined
                    ? root.mix(root.surfaceColor, it.accent, it.onP) : root.surfaceColor;
            }
        });
    }

    onLifted: src => src.expandedOut = true
    onLanded: src => src.expandedOut = false
}
