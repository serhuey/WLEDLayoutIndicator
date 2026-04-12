# WLED Layout Indicator

A macOS menu-bar app that watches the active keyboard layout and sets the colour of a [WLED](https://kno.wled.ge/) device on the local network in real time. Tested with **M5Stack Atom Matrix** (5×5 RGB LED matrix), but works with any WLED-powered device.

Switch between English and Russian — the indicator instantly changes from blue to red. At a glance, from across the room, you know which layout is active.

## Features

- **Real-time layout tracking** via Carbon Text Input Sources API — event-driven, zero polling, zero CPU at idle
- **Automatic setup on first launch:**
  - Detects all installed keyboard layouts and assigns preset colours
  - Discovers WLED devices via mDNS/Bonjour (filters by hostname containing "wled" + "key")
- **Preset colours** for common layouts (all configurable):
  - English (ABC / US / British / Dvorak / Colemak) → blue
  - Russian / Ukrainian / Belarusian → red
  - German → yellow
  - French → cyan
  - Spanish → orange
  - Unknown layouts → grey (fallback)
- **Real-time brightness slider** — adjusts WLED brightness as you drag
- **Fast transitions** — 100 ms colour fade (smooth but snappy)
- **Menu-bar only** — no Dock icon, no main window, just a tinted icon showing current colour
- **"Re-detect layouts & WLED device"** button — one-click reset to re-scan everything
- **Launch at login** via `SMAppService`
- **Resilient networking** — retry with exponential backoff (100 ms → 300 ms → 1 s), request coalescing, 2 s timeout
- **Wake-from-sleep re-sync** — re-sends current colour when the Mac wakes up

## Requirements

- macOS 13 Ventura or newer
- Xcode 15+ (developed and tested with Xcode 26.4 / Swift 6.3)
- Any ESP32 device running [WLED](https://kno.wled.ge/) firmware, reachable on your LAN by IP or mDNS (`.local`)
- Tested with M5Stack Atom Matrix (5×5 = 25 SK6812 LEDs)

## Getting started

### 1. Clone the repo

```bash
git clone https://github.com/serhuey/WLEDLayoutIndicator.git
cd WLEDLayoutIndicator
```

### 2. Create the Xcode project

The `.xcodeproj` is already in the repo (committed by Xcode). Open it:

```bash
open WLEDLayoutIndicator.xcodeproj
```

### 3. Configure the build target

In Xcode, select the **WLEDLayoutIndicator** target:

| Setting | Where | Value |
|---|---|---|
| Minimum Deployments | General | macOS **13.0** |
| Application is agent (UIElement) | Info | **YES** |
| App Sandbox | Signing & Capabilities | **ON** |
| Outgoing Connections (Client) | Signing & Capabilities → App Sandbox → Network | **ON** |

### 4. Build & Run

**Cmd+R**. The app icon appears in the menu bar (a small coloured grid). Nothing in the Dock.

On first launch the app will:
1. Scan your installed keyboard layouts and create a colour mapping
2. Search the local network for a WLED device (mDNS name must contain both "wled" and "key")
3. Start sending colour commands on every layout switch

If auto-discovery doesn't find your device, open **Settings** (click the menu-bar icon → Settings) and enter the host manually (IP address or `device-name.local`).

### 5. Run tests

**Cmd+U** in Xcode. Tests cover:
- `ColorMapperTests` — mapping, fallback, case sensitivity
- `SettingsStoreTests` — first-launch auto-detect, round-trip persistence, no-op update
- `WLEDClientTests` — JSON payload shape, HTTP 5xx handling, debounce

## How it works

```
┌─────────────────┐     sourceID      ┌──────────────────┐     POST /json/state
│  LayoutMonitor  │ ────────────────▶ │  AppCoordinator  │ ──────────────────────▶  WLED device
│                 │                   │                  │
│ Carbon TIS +    │                   │ ColorMapper:     │     ┌──────────────┐
│ DistributedNotif│                   │ sourceID → RGB   │     │  WLEDClient  │
│ + wake listener │                   │                  │────▶│  (actor)     │
└─────────────────┘                   │ publishes:       │     │  retry +     │
                                      │ • currentSourceID│     │  debounce +  │
                                      │ • currentColor   │     │  coalesce    │
                                      │ • LinkStatus     │     └──────────────┘
                                      └────────┬─────────┘
                                               │ @EnvironmentObject
                              ┌────────────────┼────────────────┐
                              ▼                                 ▼
                     ┌─────────────────┐              ┌──────────────────┐
                     │  MenuBarExtra   │              │  SettingsView    │
                     │  (status icon)  │              │  (SwiftUI form)  │
                     └─────────────────┘              └──────────────────┘
```

### Data flow

1. **LayoutMonitor** subscribes to `AppleSelectedInputSourcesChangedNotification` (distributed notification) and emits the current `kTISPropertyInputSourceID` as a `String` via `AsyncStream`.
2. **AppCoordinator** consumes the stream, runs the ID through **ColorMapper** (a pure function: `(sourceID, Config) → RGB`), and hands the result to **WLEDClient**.
3. **WLEDClient** (a Swift actor) sends `POST http://<host>/json/state` with the colour, brightness, and a 100 ms transition. It deduplicates by `(RGB, brightness)`, retries on failure, and coalesces rapid updates so only the latest state is delivered.
4. **AppCoordinator** also subscribes to config changes (via Combine `$config` publisher with 150 ms debounce) — so dragging the brightness slider or changing a colour in Settings immediately updates the device.

### Configuration

Stored as JSON in the app's sandboxed container:

```
~/Library/Containers/<bundle-id>/Data/Library/Application Support/WLEDLayoutIndicator/config.json
```

Structure:

```json
{
  "wled": {
    "host": "wled-key-indicator.local",
    "brightness": 128,
    "segmentId": 0,
    "ledCount": 25
  },
  "mapping": {
    "com.apple.keylayout.ABC": { "r": 0, "g": 120, "b": 255 },
    "com.apple.keylayout.RussianWin": { "r": 255, "g": 40, "b": 40 }
  },
  "defaultColor": { "r": 80, "g": 80, "b": 80 },
  "launchAtLogin": false
}
```

### WLED JSON API

The app sends a single POST per layout change:

```json
{
  "on": true,
  "bri": 128,
  "transition": 1,
  "seg": [{ "id": 0, "col": [[0, 120, 255]], "fx": 0 }]
}
```

- `transition: 1` = 100 ms fade (WLED measures in 100 ms units)
- `seg` only sends `id`, `col`, and `fx` — does NOT override `start`/`stop`, respecting the device's own 2D matrix configuration
- No `start`/`stop` means the app works with any WLED segment setup (1D strip, 2D matrix, etc.)

## Project structure

```
WLEDLayoutIndicator/
├── WLEDLayoutIndicatorApp.swift     # @main, NSApplicationDelegateAdaptor, MenuBarExtra
├── AppCoordinator.swift             # Wires monitor → mapper → client, auto-discovery
├── Core/
│   ├── Models.swift                 # Config, RGB, LinkStatus (nonisolated value types)
│   ├── SettingsStore.swift          # JSON persistence + first-launch auto-detect
│   ├── LayoutMonitor.swift          # Carbon TIS + DistributedNotificationCenter
│   ├── ColorMapper.swift            # Pure (sourceID, Config) → RGB mapping
│   ├── WLEDClient.swift             # Actor: URLSession + retry + debounce + coalesce
│   └── WLEDDiscovery.swift          # mDNS/Bonjour device discovery via NWBrowser
├── UI/
│   ├── StatusBarIcon.swift          # Menu-bar label (tinted grid glyph or warning)
│   └── SettingsView.swift           # SwiftUI Form: host, brightness, mappings, reset
└── Assets.xcassets/

WLEDLayoutIndicatorTests/
├── ColorMapperTests.swift
├── SettingsStoreTests.swift
└── WLEDClientTests.swift
```

## Concurrency notes (Swift 6.3)

The project compiles cleanly under Swift 6's strict concurrency checking (Xcode 26.4):

- **Domain types** (`RGB`, `Config`, `LinkStatus`) are marked `nonisolated struct/enum` to opt out of the module's default `@MainActor` isolation (SE-0466), since they need to be accessed from both the main actor and the `WLEDClient` actor.
- **`WLEDClient`** is a Swift `actor` — all mutable state (`pending`, `lastSentKey`, `runner`) is actor-isolated.
- **`LayoutMonitor`**, **`SettingsStore`**, **`AppCoordinator`** are `@MainActor` — they own UI-observable state and interact with AppKit/SwiftUI.
- **`WLEDDiscovery`** uses `NWBrowser` callbacks on a background queue, then hops to `@MainActor` via `Task { @MainActor in }` with pre-bound `let s = self` to satisfy Swift 6's strict `Sendable` requirements.

## Open items

- **Heartbeat** — periodic re-send to recover from WLED reboots (not yet implemented; device holds state well in practice)
- **Per-app layout tracking** — detect which app is focused and track its layout independently (macOS allows per-app input sources)
- **Developer ID signing / notarization** — currently unsigned (right-click → Open to launch)

## License

MIT
