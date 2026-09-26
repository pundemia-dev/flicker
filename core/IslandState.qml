import QtQuick

QtObject {
    id: root

    readonly property string island: "island"
    readonly property string minimal: "minimal"
    readonly property string module: "module"

    property string currentState: island
    property string previousState: island
    property string activeModule: ""
    property var activePayload: null
    // Bumped on every openModule so ContentSwap can replay the blur->fade
    // pattern even when the same module opens again (e.g. queued notifs).
    property int openCount: 0

    function setMinimal(): void {
        if (currentState === module)
            return;
        currentState = minimal;
    }

    function setIsland(): void {
        if (currentState === module)
            return;
        currentState = island;
    }

    function openModule(name: string, payload: var): void {
        previousState = currentState;
        // Payload first: ModuleHost's Loader creates the module when
        // activeModule changes and reads activePayload at that moment.
        activePayload = payload;
        activeModule = name;
        openCount += 1;
        currentState = module;
    }

    function closeModule(): void {
        activeModule = "";
        activePayload = null;
        currentState = previousState;
    }
}
