# WLED Layout Indicator

A macOS menu-bar app that watches the active keyboard layout and drives a [WLED](https://kno.wled.ge/) LED matrix in real time. Tested with **M5Stack Atom Matrix** (5×5 RGB LED matrix).

Switch between English and Russian — the indicator instantly changes from blue to red (or any shape and colour you configure).

## Features

- **Real-time layout tracking** via Carbon Text Input Sources API — event-driven, zero polling, zero CPU at idle
- **Per-layout colour + 5×5 pattern** — each layout has its own colour and pixel bitmap; configure both in Settings
- **Matrix rotation** — rotate the output 0°/90°/180°/270° to match how the device is mounted, without touching stored patterns
- **Automatic setup on first launch:**
  - Detects all installed keyboard layouts and assigns preset colours
  - Discovers WLED devices via mDNS/Bonjour (filters by hostname containing "wled" + "key")
- **Preset colours** for common layouts (all configurable):
  - English (ABC / US / British / Dvorak / Colemak) → blue
  - Russian / Ukrainian / Belarusian → red
  - German → yellow · French → cyan · Spanish → orange
  - Unknown layouts → grey (fallback)
- **Real-time brightness slider** — adjusts WLED brightness as you drag
- **Layout switch animation** — on automatic layout restore (per-app memory) the matrix briefly dims then lights up in the new colour; the brightness change catches peripheral vision. Manual switches are instant
- **Menu-bar only** — no Dock icon, just a 5×5 dot grid that mirrors the WLED pattern (original, un-rotated) in the current layout colour on a dark rounded background; rendered as non-template `NSImage` to bypass macOS menu bar template rendering
- **"Re-detect layouts & WLED device"** — one-click reset to re-scan everything
- **Launch at login + auto-recovery** — registered as a LaunchAgent via `SMAppService.agent`; if macOS kills the process under load (jetsam, ResponsivenessChecker, etc.), launchd respawns it automatically
- **Resilient networking** — retry with exponential backoff (100 ms → 300 ms → 1 s), request coalescing, 2 s timeout
- **Per-app layout memory (opt-in)** — remembers which keyboard layout you last used in each foreground app (by bundle ID) and automatically restores it whenever you focus that app again. First-time apps are not changed; macOS's native *Automatically switch to a document's input source* can stay on (last writer wins, usually no friction) or be turned off if you prefer our scope only.
- **Sleep / screensaver dimming** — dims WLED on sleep/screensaver/screen lock, restores on wake
- **Fullscreen video dimming** — dims WLED while any video player holds a display-sleep prevention assertion (QuickTime, VLC, IINA, browsers), restores when playback ends
- **Heartbeat** — every 5 s verifies the active layout matches TIS and re-syncs if a notification was missed; every 30 s force-resends to WLED as a keepalive (recovers from device reboots and silent network drops)
- **Floating Settings window** — always appears on top (required for agent apps without Dock presence)

## Download

Latest release: **[WLEDLayoutIndicator-1.0.6.dmg](https://github.com/serhuey/WLEDLayoutIndicator/releases/download/v1.0.6/WLEDLayoutIndicator-1.0.6.dmg)** (Apple Silicon only · ad-hoc signed · ~2 MB)

All releases on [GitHub Releases](https://github.com/serhuey/WLEDLayoutIndicator/releases).

Open the DMG, drag the app into **Applications**. Because the build is ad-hoc signed (no Apple Developer ID), the first launch needs Gatekeeper bypass: **right-click the app → Open → Open** (one-time). Or build from source — see [Getting started](#getting-started).

## Requirements

- macOS 13 Ventura or newer · Apple Silicon (the prebuilt DMG is arm64 only; build from source for Intel)
- Xcode 15+ (developed with Xcode 26.4 / Swift 6.3) — only needed if building from source
- Any ESP32 device running [WLED](https://kno.wled.ge/) firmware, reachable on your LAN by IP or `.local` mDNS name
- Tested with M5Stack Atom Matrix (5×5 = 25 SK6812 LEDs)

## Preparing the M5Stack Atom Matrix

The app needs a WLED-flashed ESP32 device on your LAN. The **M5Stack Atom Matrix** is a compact ESP32-PICO board with 25 × SK6812 LEDs wired to **GPIO 27**, powered over USB-C — ideal for this use case. Everything below is doable from a Mac.

### 1. Flash WLED

Easiest path: **WLED Web Installer** — [install.wled.me](https://install.wled.me/). Requires **Chrome or Edge** on macOS (Safari has no WebSerial support).

1. Plug the Atom Matrix into your Mac via USB-C.
2. Open [install.wled.me](https://install.wled.me/) in Chrome/Edge.
3. Click **Install** → select the latest **ESP32** build (the Atom Matrix's ESP32-PICO is covered by the standard ESP32 binary — do *not* pick ESP32-S2/S3/C3 variants).
4. Pick the serial port (`/dev/cu.usbserial-*` or `/dev/cu.usbmodem*`). If none appears, install the **CH9102** (newer Atoms) or **CP210x** USB-UART driver from [m5stack.com/pages/download](https://docs.m5stack.com/en/download).
5. Wait for flash + verify (~30 s). The device reboots into a **WLED-AP** Wi-Fi hotspot.

**Alternative — CLI:**

```bash
brew install esptool
# download WLED_x.y.z_ESP32.bin from https://github.com/Aircoookie/WLED/releases
esptool.py --port /dev/cu.usbserial-XXXX erase_flash
esptool.py --port /dev/cu.usbserial-XXXX write_flash 0x0 WLED_x.y.z_ESP32.bin
```

### 2. Join your Wi-Fi

1. On the Mac, connect to the **WLED-AP** network (default password `wled1234`).
2. A captive portal opens at `http://4.3.2.1` (open manually if it doesn't).
3. **WiFi Setup** → enter your home SSID + password → save. The device reboots and joins your LAN.

### 3. Rename the mDNS hostname

The app's auto-discovery matches devices whose mDNS name contains **both `wled` and `key`** — so unrelated WLED installs on the LAN don't get claimed. Rename the Atom to match:

1. Find the device — default hostname is `wled-XXXXXX.local` (last 6 of the MAC), or check your router.
2. Open it in a browser → **Config → WiFi Setup → mDNS Address** → set to `wled-key-indicator` (anything containing both substrings works).
3. Save & reboot. It's now reachable at `http://wled-key-indicator.local`.

### 4. Configure the 5×5 matrix

**Config → LED Preferences:**

| Field | Value |
|---|---|
| LED Type | WS281x (SK6812 is protocol-compatible) |
| Color Order | GRB |
| Length | 25 |
| GPIO (data pin) | **27** |
| Max current | 1000 mA (conservative — 25 LEDs at full white can peak ~1.5 A, above Atom's USB-C budget) |

**Config → 2D Configuration** (WLED 0.14+):

- **Strip or Matrix:** Matrix
- **Width × Height:** 5 × 5
- **Serpentine / orientation:** match the physical wiring. If the preview in the WLED UI looks mirrored or rotated vs. the device, toggle serpentine here — or leave it and fix orientation from the app side via Settings → **Matrix rotation** (0° / 90° / 180° / 270°).

**Config → Sync Interfaces:** leave defaults. The app talks plain HTTP JSON — no E1.31 / Art-Net / MQTT needed.

### 5. Sanity check

```bash
curl -s http://wled-key-indicator.local/json/state | jq '.seg[] | {id, start, stop, len, pal, fx}'
```

Expect one segment with `start: 0, stop: 25, len: 25`. If `pal` is non-zero, the app resets it to `0` on the next layout switch (it always sends `pal: 0`).

### 6. macOS utilities for WLED (optional)

- **Web UI** — `http://wled-key-indicator.local` is fully featured and works in any browser on the same LAN.
- **[WLED Native for macOS](https://github.com/Moustachauve/wled-native)** — unofficial Mac app for device management, presets, and OTA firmware updates across multiple devices.
- **WLED iOS app** — same-LAN control from the phone.

---

## Getting started

### 1. Clone & open

```bash
git clone https://github.com/serhuey/WLEDLayoutIndicator.git
cd WLEDLayoutIndicator
open WLEDLayoutIndicator.xcodeproj
```

### 2. Build target settings

| Setting | Where | Value |
|---|---|---|
| Minimum Deployments | General | macOS **13.0** |
| Application is agent (UIElement) | Info | **YES** |
| App Sandbox | Signing & Capabilities | **ON** |
| Outgoing Connections (Client) | App Sandbox → Network | **ON** |

### 3. Build & Run

**⌘R**. The app icon appears in the menu bar. Nothing in the Dock.

On first launch the app:
1. Scans installed keyboard layouts and creates a colour + pattern mapping
2. Searches the local network for a WLED device (mDNS name must contain "wled" and "key")
3. Starts sending commands on every layout switch

If auto-discovery doesn't find your device, open **Settings → WLED device** and enter the host manually.

### 4. Troubleshooting the WLED link

- Set **Segment id** in Settings to match your WLED segment (check `GET /json/state` → `seg[].id`).
- If colours seem ignored but brightness changes, the segment likely has a non-default **palette** — the app forces `pal: 0` on every request, so one layout switch will reset it.
- For a 5×5 2D matrix, configure the matrix in WLED (step 4 above) and leave `start`/`stop` alone — the app does not send those fields.

### 5. Run tests

**⌘U** in Xcode. Tests cover:
- `ColorMapperTests` — mapping, fallback, pattern preservation, case sensitivity
- `SettingsStoreTests` — first-launch auto-detect, round-trip persistence, v1 config migration
- `WLEDClientTests` — JSON payload shape (nested `i` array), partial pattern, HTTP 5xx, debounce, pattern-change re-send

## How it works

```
┌─────────────────┐   sourceID    ┌──────────────────────────────┐   POST /json/state
│  LayoutMonitor  │ ────────────▶ │       AppCoordinator         │ ──────────────────▶  WLED
│                 │               │                              │
│ Carbon TIS +    │               │  ColorMapper:                │   ┌──────────────┐
│ DistributedNotif│               │  sourceID → LayoutEntry      │──▶│  WLEDClient  │
│ + wake listener │               │  (color + pattern)           │   │  (actor)     │
└─────────────────┘               │                              │   │  retry +     │
                                  │  rotation applied here       │   │  debounce +  │
                                  │  (pattern only, not stored)  │   │  coalesce    │
                                  └──────────────┬───────────────┘   └──────────────┘
                                                 │ @EnvironmentObject
                                  ┌──────────────┴───────────────┐
                                  ▼                              ▼
                         ┌─────────────────┐           ┌──────────────────┐
                         │  MenuBarExtra   │           │  SettingsView    │
                         │  (status icon)  │           │  (SwiftUI form)  │
                         └─────────────────┘           └──────────────────┘
```

### Data flow

1. **LayoutMonitor** subscribes to `AppleSelectedInputSourcesChangedNotification` and emits the current `kTISPropertyInputSourceID` via `AsyncStream<String>`.
2. **AppCoordinator** runs the ID through **ColorMapper** (`(sourceID, Config) → LayoutEntry`), applies `matrixRotation` to the pattern, and hands it to **WLEDClient**.
3. **WLEDClient** (Swift actor) sends `POST /json/state` with per-pixel `"i"` array, `pal: 0`, `fx: 0`, and a 100 ms transition. Deduplicates by `(LayoutEntry, brightness)`, retries on failure, coalesces rapid updates.
4. **AppCoordinator** also subscribes to `$config` (Combine, 150 ms debounce) — dragging the brightness slider or editing a pattern immediately updates the device.

### WLED JSON API payload

```json
{
  "on": true,
  "bri": 128,
  "transition": 1,
  "seg": [{
    "id": 0,
    "on": true,
    "col": [[0, 120, 255]],
    "i": [[0,120,255],[0,120,255],...,[0,0,0],[0,0,0]],
    "fx": 0,
    "pal": 0
  }]
}
```

- `"i"` — nested `[[R,G,B]]` array (one entry per LED). Pixels where the pattern is off receive `[0,0,0]`.
- `"col"` — base colour (fallback for firmware that ignores `"i"`).
- `"pal": 0` — forces default palette so our colours are not overridden.
- No `start`/`stop` — respects the device's own 2D matrix segment setup.

### Configuration file

Stored in the app's sandboxed container:

```
~/Library/Containers/<bundle-id>/Data/Library/Application Support/WLEDLayoutIndicator/config.json
```

```json
{
  "wled": { "host": "wled-key-indicator.local", "brightness": 128, "segmentId": 0, "ledCount": 25 },
  "mapping": {
    "com.apple.keylayout.ABC": {
      "color": { "r": 0, "g": 120, "b": 255 },
      "pattern": { "pixels": [true, true, ..., true] }
    }
  },
  "defaultEntry": { "color": { "r": 80, "g": 80, "b": 80 }, "pattern": { "pixels": [...] } },
  "matrixRotation": 0,
  "launchAtLogin": false
}
```

Old v1 configs (with `mapping: {String: RGB}` and `defaultColor`) are automatically migrated on first launch.

## Project structure

```
WLEDLayoutIndicator/
├── WLEDLayoutIndicatorApp.swift     # @main, NSApplicationDelegateAdaptor, MenuBarExtra
├── AppCoordinator.swift             # monitor → mapper → rotation → client, sleep/wake/video dimming, heartbeat
├── Core/
│   ├── Models.swift                 # Config, RGB, Pattern, LayoutEntry, LinkStatus
│   ├── SettingsStore.swift          # JSON persistence, first-launch auto-detect, v1 migration
│   ├── LayoutMonitor.swift          # Carbon TIS + DistributedNotificationCenter
│   ├── ColorMapper.swift            # Pure (sourceID, Config) → LayoutEntry
│   ├── WLEDClient.swift             # Actor: URLSession, per-pixel "i" API, retry/debounce
│   ├── WLEDDiscovery.swift          # mDNS/Bonjour discovery via NWBrowser
│   ├── AppFocusMonitor.swift        # NSWorkspace front-app changes (per-app memory)
│   ├── FullscreenVideoMonitor.swift # IOKit PreventUserIdleDisplaySleep poll (video dimming)
│   └── LaunchAgent.swift            # SMAppService.agent registration + Login Item → Agent migration
├── UI/
│   ├── StatusBarIcon.swift          # Menu-bar label (5×5 pattern preview, dark bg)
│   ├── SettingsView.swift           # SwiftUI Form: host, brightness, rotation, patterns
│   ├── PatternEditor.swift          # 5×5 clickable grid + fill/clear presets
│   ├── ColorPaletteControl.swift    # 4×4 preset colour grid + Custom… (NSColorPanel)
│   ├── ColorPalette.swift           # 16 preset colours ordered by hue
│   └── ColorPanelBridge.swift       # Singleton bridge to NSColorPanel
└── Assets.xcassets/

WLEDLayoutIndicatorTests/
├── ColorMapperTests.swift
├── SettingsStoreTests.swift
└── WLEDClientTests.swift
```

## Concurrency (Swift 6.3)

Compiles cleanly under strict concurrency (Xcode 26.4):

- **Domain types** (`RGB`, `Pattern`, `LayoutEntry`, `Config`, `LinkStatus`) are `nonisolated struct/enum` — usable from any actor without `await`.
- **`WLEDClient`** is a Swift `actor` — all mutable send state is actor-isolated.
- **`AppCoordinator`**, **`SettingsStore`**, **`LayoutMonitor`** are `@MainActor`.
- **`WLEDDiscovery`** bridges `NWBrowser` callbacks to `@MainActor` via `Task { @MainActor in }` with pre-captured `self`.

## Building a standalone .app

```bash
xcodebuild -scheme WLEDLayoutIndicator -configuration Release -derivedDataPath build
cp -R build/Build/Products/Release/WLEDLayoutIndicator.app /Applications/
```

First launch: right-click → **Open** → confirm. Enable **Launch at login** in Settings.

## Open items

- **Other LED configurations** — currently hardcoded for 5×5 (M5Stack Atom Matrix); support for arbitrary N×M matrices and multiple simultaneous WLED devices would broaden compatibility
- **Developer ID signing / notarization** — currently unsigned

## License

MIT
