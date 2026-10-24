import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../components"
import "../../config"

// One notification card, used by both flow and center-expanded modes.
// Layout: [avatar | title … time / body]. Max 3 lines total: title is a
// single elided line, body wraps to at most 2 elided lines.
// When the sender provides an image (messenger chat avatars arrive via the
// D-Bus image-data / image-path hints) it is shown instead of the app icon,
// with the app icon as a small badge on the avatar's bottom-right rim.
Item {
    id: root
    property var notif
    property var cfg
    // Group counter on the avatar's top-right rim (center: collapsed
    // stacks); hidden at <= 1.
    property int groupCount: 0
    // Privacy (Notifications.redact): the app name and "Notification"
    // instead of the title / text, the app icon instead of the sender's
    // picture.
    property bool redacted: false

    readonly property real avatarSize: root.cfg?.avatarSize ?? 64
    readonly property real badgeSize: root.cfg?.badgeSize ?? 20
    readonly property string imageSource: root.redacted ? "" : (root.notif?.image ?? "")
    readonly property string appIconName: root.notif?.appIcon ?? ""
    readonly property bool hasImage: root.imageSource.length > 0
    readonly property bool hasAppIcon: root.appIconName.length > 0
    // Shared-element slot "time" (the bar clock flies in and docks here).
    readonly property Item timeSlot: timeBox

    // Relative timestamp: today "18:13", yesterday "Yesterday, 18:13", within
    // a week "Mon 12:57", older = the locale's short date ("23.09.2026" in ru).
    function formatTime(ms) {
        if (!ms)
            return "";
        const d = new Date(ms);
        const now = new Date();
        const pad = n => String(n).padStart(2, "0");
        const hm = pad(d.getHours()) + ":" + pad(d.getMinutes());
        const dayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        const notifStart = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        const diffDays = Math.round((dayStart - notifStart) / 86400000);
        if (diffDays <= 0)
            return hm;
        if (diffDays === 1)
            return I18n.tr("Yesterday, %1").arg(hm);
        if (diffDays < 7)
            return I18n.capitalize(I18n.locale.dayName(d.getDay(), Locale.ShortFormat)) + " " + hm;
        return d.toLocaleDateString(I18n.locale, Locale.ShortFormat);
    }

    // ── Avatar / app icon ──
    Item {
        id: avatarBox
        width: root.avatarSize
        height: root.avatarSize
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        // Sender avatar (chat / group photo).
        ClippingRectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            visible: root.hasImage

            Image {
                anchors.fill: parent
                source: root.hasImage ? Qt.resolvedUrl(root.imageSource) : ""
                fillMode: Image.PreserveAspectCrop
                cache: false
                asynchronous: true
            }
        }

        // App icon fallback when there is no sender image: bare glyph, no
        // background — same treatment as the badge.
        Item {
            anchors.fill: parent
            visible: !root.hasImage

            Image {
                id: bigIcon
                anchors.fill: parent
                source: root.hasAppIcon ? Quickshell.iconPath(root.appIconName) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                // Missing icon in the theme: fall back to the letter below
                // instead of the provider's broken-image placeholder.
                visible: root.hasAppIcon && status !== Image.Error
            }
            Text {
                anchors.centerIn: parent
                text: ((root.notif?.appName ?? "").trim().charAt(0) || "?").toUpperCase()
                color: "#98A4B6"
                font.pixelSize: Math.round(root.avatarSize * 0.42)
                visible: !bigIcon.visible
            }
        }

        // Group counter: pill overlapping the avatar's top-right rim. Keeps
        // its last number while fading out (stack fanning open).
        Rectangle {
            id: countBadge
            property int shown: 0
            readonly property bool on: root.groupCount > 1
            Component.onCompleted: shown = root.groupCount
            Connections {
                target: root
                function onGroupCountChanged() {
                    if (root.groupCount > 1)
                        countBadge.shown = root.groupCount;
                }
            }
            // Pill fitted to the number (circle for one digit), radius
            // capped at half the short side.
            height: 26
            width: Math.max(height, countText.implicitWidth + 14)
            radius: Math.min(width, height) / 2
            x: root.avatarSize - width + Math.round(height / 3)
            y: -Math.round(height / 3)
            color: "#000000"
            border.width: 2
            border.color: "#1C1C1E"
            opacity: on ? 1 : 0
            scale: on ? 1 : 0.6
            visible: opacity > 0.01
            Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
            Behavior on scale { Spring { eps: 0.001 } }

            Text {
                id: countText
                anchors.centerIn: parent
                text: countBadge.shown > 99 ? "99+" : String(countBadge.shown)
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: "#FFFFFF"
            }
        }

        // App-icon badge: bare glyph overlapping the avatar's bottom-right,
        // no background.
        Image {
            width: root.badgeSize
            height: root.badgeSize
            x: root.avatarSize - width + Math.round(width / 4)
            y: root.avatarSize - height + Math.round(height / 4)
            visible: root.hasImage && root.hasAppIcon && status !== Image.Error
            source: (root.hasImage && root.hasAppIcon) ? Quickshell.iconPath(root.appIconName) : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
    }

    // ── Title + body (vertically centered) + time (top-right corner) ──
    Item {
        anchors.left: avatarBox.right
        anchors.leftMargin: 16
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: 0

            Text {
                width: parent.width - timeBox.width - 8
                text: root.redacted ? (root.notif?.appName ?? "") : (root.notif?.summary ?? "")
                color: "#F0F4FB"
                font.pixelSize: 16
                maximumLineCount: 1
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.redacted ? I18n.tr("Notification") : (root.notif?.body ?? "")
                color: "#C0CAD8"
                font.pixelSize: 16
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        // Arrival time. Also the shared-element slot: the flying bar clock
        // morphs to text/color/font read from here and docks inside; the
        // own label hides meanwhile but keeps the layout box.
        Item {
            id: timeBox
            anchors.top: parent.top
            anchors.topMargin: 6
            anchors.right: parent.right
            width: timeText.implicitWidth
            height: timeText.implicitHeight
            property Item docked: null
            readonly property string text: root.formatTime(root.notif?.time)
            readonly property color color: "#98A4B6"
            readonly property font font: timeText.font

            Text {
                id: timeText
                anchors.fill: parent
                visible: timeBox.docked === null
                text: timeBox.text
                color: timeBox.color
                font.pixelSize: 16
            }
        }
    }
}
