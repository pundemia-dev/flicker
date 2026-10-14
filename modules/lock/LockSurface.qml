import QtQuick
import Quickshell
import Quickshell.Wayland

// One lock surface per screen. Contract for the skin item (initial props):
// lock (WlSessionLock), pam (Pam scope), scope (LockScope: grabPath, cfg),
// screen (ShellScreen).
WlSessionLockSurface {
    id: root

    required property WlSessionLock lock
    required property Pam pam
    required property var scope

    // Opaque base: the session-lock protocol expects full output coverage;
    // transparent lets the compositor's "client not drawing" backdrop show.
    color: "black"

    property Item skinItem: null

    function reloadSkin(): void {
        if (skinItem) {
            skinItem.destroy();
            skinItem = null;
        }
        // screen is assigned by WlSessionLock AFTER instantiation — wait for it.
        if (!screen)
            return;

        skinItem = skinComp.createObject(contentItem, {
            lock: root.lock,
            pam: root.pam,
            scope: root.scope,
            screen: root.screen
        });
        if (skinItem)
            skinItem.anchors.fill = contentItem;
        else
            console.warn("[lock] skin failed to instantiate:", skinComp.errorString());
    }

    Component.onCompleted: reloadSkin()
    onScreenChanged: reloadSkin()

    Component {
        id: skinComp
        LockSkin {}
    }
}
