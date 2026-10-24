<h1 align=center>Flicker</h1>

<div align=center>

### One pill instead of a bar

A Dynamic Island desktop shell for Wayland, built with [Quickshell](https://quickshell.org)

![GitHub last commit](https://img.shields.io/github/last-commit/pundemia-dev/flicker?style=for-the-badge&labelColor=000000&color=e6e6e6)
![GitHub Repo stars](https://img.shields.io/github/stars/pundemia-dev/flicker?style=for-the-badge&labelColor=000000&color=e6e6e6)
![GitHub repo size](https://img.shields.io/github/repo-size/pundemia-dev/flicker?style=for-the-badge&labelColor=000000&color=e6e6e6)
![Quickshell](https://img.shields.io/badge/quickshell-0.3.1-e6e6e6?style=for-the-badge&labelColor=000000)
![Written with AI](https://img.shields.io/badge/written_with-AI-e6e6e6?style=for-the-badge&labelColor=000000)

</div>

<!-- VIDEO: drag the demo video into the GitHub editor here; it becomes a
     https://github.com/user-attachments/assets/... link that renders as a player -->
<div align=center>

<img src="https://placehold.co/1280x720/000000/FFFFFF?text=demo+video" alt="Flicker demo (placeholder)" width="100%">

</div>

Flicker replaces the bar with one Dynamic Island per monitor. At rest it's a clock and
a few indicators. When you need something, the island grows into it (launcher, control
center, player, notifications, screen capture, and more) and folds back when you're done.

The goal is **functional minimalism**: it looks minimal and stays out of the way, but
there's a lot under the hood. Nothing gets a permanent spot on screen. Things show up
when they matter and leave when they don't.

> [!NOTE]
> This project is written **primarily with AI** (Claude Code). Design decisions,
> testing on real hardware and every "no, not like that" come from a human. Most of the
> code doesn't.

<!-- FEATURE WALKTHROUGH: to be written -->

## Components

-   Widgets: [`Quickshell`](https://quickshell.org) (pure QML, no build step)
-   Compositors: [`niri`](https://github.com/YaLTeR/niri), [`driftwm`](https://github.com/malbiruk/driftwm)
-   Wallpapers: [`wallr`](https://github.com/programmersd21/wallr)

## Features

**The Island**
Three states: a bar that fits its content, a Minimal strip for fullscreen, and modules.
Every change is a spring, every content swap is a blur-fade, and elements fly between
states (cover → player, clock → dashboard, timer ring → module outline).

**Three kinds of indicators**
*Regular* ones live in the bar. *Events* briefly announce something with a hand-drawn
animated glyph. *Statuses* split off the island as a drop with a progress ring and stay
for as long as a process runs.

**Launcher**
Apps, clipboard history, prompter files, and a wallpaper carousel with semantic search
in any language. A calculator right in the search: math, percentages, units, live
currency rates, number bases and dates, in English or Russian (`5 usd в руб`). Plugin-based.

**Quick Settings**
iOS-style Control Center: tabbed grid of cards in different shapes, expandable Wi‑Fi /
Bluetooth panels, a morphing media card, an edit mode and a frosted-glass look.

**Capture**
Screenshots with an annotation editor, OCR, QR scan, Lens, colour picker, plus screen
recording with audio mixing, pause and a speed ruler.

**And more**
Dashboard, player, notification center with mini-games, OSD, dictation, timer, file
stash with LocalSend, teleprompter, lock screen, polkit agent, session menu, keyboard
layout pill, trackpad haptics.

<details><summary><strong>Indicators</strong></summary>

### Regular

| Indicator | What it shows |
| --- | --- |
| **Clock** | Time. Becomes a red plate with elapsed time while recording, or the hotspot plate. Click for actions. |
| **Privacy dot** | One dot coloured by the most sensitive capture: screen share 🔴 > camera 🟢 > mic 🟠. Hover shows the app. |
| **Music** | Cover of the active MPRIS player (the one that's actually playing). Opens the player. Doubles as the timer ring. |
| **Dictation wave** | Live voice meter while dictating. |
| **Timer ring** | Countdown progress, around the cover or on its own. |
| **Battery / volume arcs** | Side arcs around the island. Low battery = "wipers". |

### Events

Glyph pinned to the left edge, text to the right. The island grows on both sides so the
bar stays centred. Queued FIFO, some are tappable.

| Event | Glyph |
| --- | --- |
| Charger plugged / unplugged | bolt that joins / breaks in two, then % → time to full/empty |
| Battery full / critical | battery |
| Bluetooth connected | AirPods, AirPods Max, HomePod, phone, tablet, laptop, watch, mouse, keyboard, gamepad + device battery |
| Wi‑Fi joined / switched / lost | Wi‑Fi arcs |
| Audio output changed | headphones / display / speaker + volume |
| Display connected / disconnected | display |
| Drive plugged / removed | drive (tap = mount + open) |
| Download finished | transfer (tap = open) |
| Updates available | Pac‑Man (pacman), ghost (AUR) |
| Caffeine on / off | coffee cup filling / draining |
| Shazam, errors, copy, VPN, focus | Shazam, error, copy, lock, moon |

### Statuses

The drop sits on the island's right end, then splits off on a metaball neck. Tap opens the
related module, and a swipe cycles through statuses. When a process ends you get exactly
one outcome: an event for a plain result, a notification for something to act on later.

Timer · recording being saved · Shazam listening · transcription · LocalSend transfer ·
pacman transaction · browser and model downloads · dictation model warm-up · wallpaper
thumbnails, duplicate search, semantic indexing

</details>

<details><summary><strong>Modules</strong></summary>

| Module | Highlights |
| --- | --- |
| **Launcher** | `!` switches plugins: apps (fuzzy), clipboard (text + images), wallpapers, prompter. Animated results, springing selection plate. |
| **Wallpapers** | Carousel for thousands of images / GIFs / videos, live preview, favourites, history, hidden files, slideshow, trash, visual duplicate finder, semantic search ("? cat on a roof", "find similar"), fill-blur for odd aspect ratios, accent colour from the wallpaper, settings panel. |
| **Quick Settings** | Tabs of a 4-column grid, per-shape card layouts, Wi‑Fi / Bluetooth panels, OSD-style sliders, media card morphing across 7 sizes with a visualizer, quick actions. Drag / resize / hide / add tabs in edit mode. |
| **Dashboard** | Calendar, weather (gradient that follows the sun), now playing, CPU/RAM/disk, battery, processes, sensors. |
| **Player** | Blurred-cover backdrop, crossfading art, scrubbable seek bar. |
| **Notifications** | Flow cards (pull down = actions, long press = inline reply), grouped notification center, ticker in Minimal. Empty center = Dino / Flappy. |
| **OSD** | Volume / mic / brightness capsule that reacts to *any* change, including compositor keybinds. |
| **Capture** | Region / window / screen, 10 annotation tools + undo, smart regions, OCR, QR / barcode, Lens, colour picker. Recording: system / mic / both, pause, live audio switch, 0.25×–4× speed. |
| **Dictation** | Streaming speech-to-text into any window, language follows the keyboard layout, optional local LLM cleanup. |
| **Timer** | Minute ruler, the countdown outline drains around the island, alarm. |
| **Stash** | File tray: drop onto the island, multi-select, Quick Look, zip / unpack, transcription (WhisperX), LocalSend. |
| **Prompter** | Teleprompter that follows your voice and recovers when you skip ahead. |
| **Lock screen** | The desktop dissolves window by window, the island becomes the password field, the clock flies out of the bar. Animated avatar, morphing password dots. |
| **Polkit · Session · Keyboard pill** | Auth agent in the island, power menu, layout / Caps Lock pill under the text caret. |

</details>

## Installation

<details><summary id="dependencies">Dependencies</summary>

-   [`quickshell`](https://quickshell.org) 0.3.1+
-   [`niri`](https://github.com/YaLTeR/niri) or [`driftwm`](https://github.com/malbiruk/driftwm)
-   [`pipewire`](https://pipewire.org) (`wpctl`, `pw-record`, `parecord`)
-   [`brightnessctl`](https://github.com/Hummer12007/brightnessctl)
-   [`networkmanager`](https://gitlab.freedesktop.org/NetworkManager/NetworkManager)
-   `upower`, `bluez`
-   [`grim`](https://sr.ht/~emersion/grim), [`wf-recorder`](https://github.com/ammen99/wf-recorder), [`ffmpeg`](https://ffmpeg.org), `imagemagick`, `wl-clipboard`
-   [`tesseract`](https://github.com/tesseract-ocr/tesseract) + `tesseract-data-eng`, `zbar`
-   `python` + `python-pillow` (lock screen, wallpaper duplicates)
-   `curl`, `jq`, `libnotify`, `xdg-utils`, `xdg-user-dirs`, `glib2`, `psmisc`, `polkit`, `openssl`
-   `zip`, `libarchive`, `poppler`, `file` (stash: archives, PDF thumbnails)
-   `qt6-base`, `qt6-declarative`, `qt6-multimedia`
-   Fonts: `otf-san-francisco` (AUR), `ttf-jetbrains-mono-nerd`, tabler-icons 3.31.0 (`install.sh` downloads it)

Optional:

-   [`cliphist`](https://github.com/sentriz/cliphist): clipboard history
-   [`wallr`](https://github.com/programmersd21/wallr), [`matugen`](https://github.com/InioX/matugen): wallpapers, accent colour
-   [`uv`](https://github.com/astral-sh/uv): Python helpers (Shazam, transcription, semantic search, smart regions)
-   [`llama-server`](https://github.com/ggml-org/llama.cpp): dictation refine
-   [`app2unit`](https://github.com/Vladimir-csp/app2unit), `wtype`, `cava`, `udisks2`, `7zip`

</details>

### Manual installation

```sh
git clone https://github.com/pundemia-dev/flicker ~/.config/quickshell/flicker
cd ~/.config/quickshell/flicker
./install.sh   # checks dependencies, fonts, models, Python helpers; idempotent
qs -c flicker  # the first start writes config/config.json
./install.sh   # once more: steps that edit the config (dictation Refine)
```

## Usage

### Shortcuts/IPC

All controls go through `island`, which routes to the island on the focused monitor.
Bind them in your compositor:

```sh
qs -c flicker ipc call island launcher        # toggle the launcher
qs -c flicker ipc call island quicksettings
qs -c flicker ipc call island dashboard
qs -c flicker ipc call island capture         # again while open = next mode
qs -c flicker ipc call island record          # toggle screen recording
qs -c flicker ipc call island session
qs -c flicker ipc call dictation toggle
qs -c flicker ipc call lock activate
```

The full list of targets is in [`AGENTS.md`](AGENTS.md).

## Configuring

Everything lives in `config/config.json` and hot-reloads on save. Visual tokens are in
`services/Theme.qml`. Quick Settings layout and wallpaper settings are edited from the
UI and saved to Quickshell's state directory.

## Credits

-   [Quickshell](https://quickshell.org): shell framework
-   [caelestia](https://github.com/caelestia-dots/shell), [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell), [end-4](https://github.com/end-4/dots-hyprland), [noctalia](https://github.com/noctalia-dev/noctalia-shell): reference implementations and inspiration
-   [midnight-shell](https://github.com/dim-ghub/midnight-shell): the Dino game
-   Apple: Dynamic Island and iOS Control Center, the obvious inspiration

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=pundemia-dev/flicker&type=Date)](https://star-history.com/#pundemia-dev/flicker&Date)
