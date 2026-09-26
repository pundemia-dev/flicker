import QtQuick
import Quickshell

QtObject {
    readonly property string backendName: {
        const niriSocket = Quickshell.env("NIRI_SOCKET") ?? "";
        const sig = `${niriSocket} ${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? ""} ${Quickshell.env("XDG_CURRENT_DESKTOP") ?? ""}`.toLowerCase();
        if (sig.indexOf("niri") !== -1 || niriSocket.length > 0)
            return "niri";
        if (sig.indexOf("hypr") !== -1)
            return "hyprland";
        return "drift";
    }
}
