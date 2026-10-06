import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import "../config"

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
    // Trackpad haptics (Config.haptics.polkit): deep on a wrong response,
    // release on success.
    property var haptics: null

    readonly property var agent: agentLoader.item
    readonly property var flow: root.agent?.flow ?? null
    readonly property bool active: root.agent?.isActive ?? false
    readonly property bool registered: root.agent?.isRegistered ?? false

    // idle | input (waiting for the response) | checking (submitted, PAM
    // busy or a non-interactive step like a fingerprint) | success
    property string phase: "idle"
    // Bumped on every wrong response: the module shakes on change.
    property int failCount: 0
    // { title, message, actionId, iconName } of the current/last request.
    property var request: null

    readonly property string prompt: (root.flow?.inputPrompt ?? "").trim().replace(/[\s:]+$/, "")
    readonly property bool responseVisible: root.flow?.responseVisible ?? false
    readonly property string supplementary: root.flow?.supplementaryMessage ?? ""
    readonly property bool supplementaryIsError: root.flow?.supplementaryIsError ?? false
    readonly property var identities: (root.flow?.identities ?? []).filter(i => !i.isGroup)
    readonly property string identityName: root.flow?.selectedIdentity?.string ?? ""

    // pam_faillock lockout: "(N minutes left to unlock)" / "The account is
    // locked due to N failed logins" arrive as supplementary info. Latched as
    // a deadline (the message only comes with each PAM round) and counted
    // down by `lockTick`; `lockedText` is what the password field shows,
    // split at the %1 placeholder into a static `lockPrefix` and the rolling
    // `lockValue` ("4 min" → "3 min", RollingText in the field).
    property real lockUntil: 0
    property real now: Date.now()
    readonly property bool locked: root.lockUntil > root.now
    readonly property var lockParts: {
        if (!root.locked)
            return ["", ""];
        const s = Math.ceil((root.lockUntil - root.now) / 1000);
        const tpl = s >= 60 ? I18n.tr("Locked · %1 min") : I18n.tr("Locked · %1 s");
        const n = s >= 60 ? Math.ceil(s / 60) : s;
        const i = tpl.indexOf("%1");
        return i < 0 ? [tpl, ""] : [tpl.slice(0, i), tpl.slice(i).replace("%1", String(n))];
    }
    readonly property string lockPrefix: root.lockParts[0]
    readonly property string lockValue: root.lockParts[1]
    readonly property string lockedText: root.lockPrefix + root.lockValue
    // The lock message itself: the module hides it from the status line.
    readonly property bool supplementaryIsLock: /left to unlock|account is locked/i.test(root.supplementary)

    onSupplementaryChanged: {
        const m = root.supplementary.match(/(\d+)\s*(minute|second)s?\s+left to unlock/i);
        if (m)
            root.lockUntil = Date.now() + Number(m[1]) * (m[2].toLowerCase() === "minute" ? 60000 : 1000);
        else if (/account is locked/i.test(root.supplementary) && !root.locked)
            root.lockUntil = Date.now() + root.cfg.lockFallbackMs;
        root.now = Date.now();
    }

    Timer {
        id: lockTick
        interval: 1000
        repeat: true
        running: root.lockUntil > root.now
        onTriggered: root.now = Date.now()
    }

    // A new request needs the prompt (Shell routes it to the focused island).
    signal started
    // The flow ended (success / cancel / caller gone): islands close the module.
    signal finished(bool success)

    // The polkit message is shown verbatim (the module's big card), minus a
    // trailing dot; the action id goes under it as the small detail line.
    function parse(flow: var): var {
        const msg = (flow?.message ?? "").trim();
        return {
            title: I18n.tr("Authentication required"),
            message: msg.endsWith(".") ? msg.slice(0, -1) : msg,
            actionId: flow?.actionId ?? "",
            iconName: flow?.iconName ?? ""
        };
    }

    function submit(text: string): void {
        if (!root.flow || root.phase !== "input" || !root.flow.isResponseRequired)
            return;
        root.phase = "checking";
        root.submitted = true;
        root.flow.submit(text);
    }

    // Haptic only for failures that answer a submit (a PAM round that fails
    // on its own, e.g. at session restart, never buzzes).
    property bool submitted: false
    function buzz(effect: string): void {
        if (root.haptics && (root.haptics.cfg?.polkit ?? true))
            root.haptics.play(effect);
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
            root.submitted = false;
            root.now = Date.now();
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
            if (root.submitted)
                root.buzz("deep");
            root.submitted = false;
            root.phase = root.flow.isResponseRequired ? "input" : "checking";
        }
        function onAuthenticationSucceeded(): void {
            root.submitted = false;
            root.buzz("release");
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
