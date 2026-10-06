import QtQuick
import Quickshell
import Quickshell.Services.Polkit

// Polkit authentication agent (DMS / end-4 / caelestia pattern: one
// Quickshell PolkitAgent per session). Only one agent can be registered per
// session: `cfg.enabled: false` (or another agent such as polkit-gnome
// already running) leaves it unregistered.
//
// The prompt itself is the island module `polkit` (modules/polkit). The
// service keeps a SNAPSHOT of the request (`request`) so the module can show
// the success tick after the flow is gone. AuthFlow restarts the PAM session
// by itself after a wrong password (authenticationFailed → setupSession), so
// a retry is just another submit().
Scope {
    id: root
    required property var cfg

    readonly property var agent: agentLoader.item
    readonly property var flow: root.agent?.flow ?? null
    readonly property bool active: root.agent?.isActive ?? false
    readonly property bool registered: root.agent?.isRegistered ?? false

    // idle | input (waiting for the response) | checking (submitted, PAM
    // busy or a non-interactive step like a fingerprint) | success
    property string phase: "idle"
    // Bumped on every wrong response: the module shakes on change.
    property int failCount: 0
    // { title, message, command, actionId, iconName } of the current/last request.
    property var request: null

    readonly property string prompt: (root.flow?.inputPrompt ?? "").trim().replace(/[\s:]+$/, "")
    readonly property bool responseVisible: root.flow?.responseVisible ?? false
    readonly property string supplementary: root.flow?.supplementaryMessage ?? ""
    readonly property bool supplementaryIsError: root.flow?.supplementaryIsError ?? false
    readonly property var identities: (root.flow?.identities ?? []).filter(i => !i.isGroup)
    readonly property string identityName: root.flow?.selectedIdentity?.string ?? ""

    // A new request needs the prompt (Shell routes it to the focused island).
    signal started
    // The flow ended (success / cancel / caller gone): islands close the module.
    signal finished(bool success)

    // pkexec: "Authentication is needed to run `/usr/bin/x' as the super user"
    // → the command goes on its own monospace line (caelestia).
    function parse(flow: var): var {
        let msg = (flow?.message ?? "").trim();
        let cmd = "";
        const pk = msg.match(/run [`'"](.+?)['`"] as the super user/);
        if (pk) {
            cmd = pk[1];
            msg = "Запуск от имени суперпользователя";
        } else if (msg.endsWith(".")) {
            msg = msg.slice(0, -1);
        }
        return {
            title: "Требуется аутентификация",
            message: msg,
            command: cmd,
            actionId: flow?.actionId ?? "",
            iconName: flow?.iconName ?? ""
        };
    }

    function submit(text: string): void {
        if (!root.flow || root.phase !== "input" || !root.flow.isResponseRequired)
            return;
        root.phase = "checking";
        root.flow.submit(text);
    }

    function cancel(): void {
        if (root.flow && !root.flow.isCompleted)
            root.flow.cancelAuthenticationRequest();
    }

    // Several identities (wheel members / admin group): cycle them. Assigning
    // selectedIdentity cancels and restarts the session (no failure counted:
    // `switching`).
    property bool switching: false
    function nextIdentity(): void {
        const ids = root.identities;
        if (!root.flow || ids.length < 2)
            return;
        const i = ids.indexOf(root.flow.selectedIdentity);
        root.selectIdentity(ids[(i + 1) % ids.length]);
    }

    function selectIdentity(identity: var): void {
        if (!identity || identity === root.flow?.selectedIdentity)
            return;
        root.switching = true;
        root.flow.selectedIdentity = identity;
        root.switching = false;
    }

    // Polkit pre-selects the first admin (often root); prefer the logged-in
    // user (DMS selectCurrentUserIdentity).
    function preferCurrentUser(): void {
        const user = Quickshell.env("USER");
        const own = root.identities.find(i => i.string === user);
        if (own)
            root.selectIdentity(own);
    }

    Connections {
        target: root.agent
        function onAuthenticationRequestStarted(): void {
            root.request = root.parse(root.flow);
            root.failCount = 0;
            root.phase = root.flow?.isResponseRequired ? "input" : "checking";
            if (root.cfg?.preferCurrentUser ?? true)
                root.preferCurrentUser();
            root.started();
        }
        function onIsActiveChanged(): void {
            if (root.agent.isActive || root.phase === "idle")
                return;
            const ok = root.phase === "success";
            if (!ok)
                root.phase = "idle";
            root.finished(ok);
        }
    }

    Connections {
        target: root.flow
        function onIsResponseRequiredChanged(): void {
            if (root.flow.isResponseRequired && root.phase !== "success")
                root.phase = "input";
        }
        function onAuthenticationFailed(): void {
            if (root.switching)
                return;
            root.failCount++;
            root.phase = root.flow.isResponseRequired ? "input" : "checking";
        }
        function onAuthenticationSucceeded(): void {
            root.phase = "success";
        }
    }

    // After the success tick has been shown (Island closes the module).
    function settle(): void {
        if (root.phase === "success" && !root.active)
            root.phase = "idle";
    }

    Loader {
        id: agentLoader
        active: root.cfg?.enabled ?? true
        sourceComponent: PolkitAgent {
            onIsRegisteredChanged: console.info(`[polkit] agent ${isRegistered ? "registered" : "unregistered"}`)
        }
    }
}
