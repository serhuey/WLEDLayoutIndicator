# WLED Layout Indicator

macOS menu-bar app that watches the active keyboard layout and sets the colour
of a WLED device (tested against M5Stack **Atom Matrix**, 5×5 = 25 LEDs) on the
local network.

- `ABC` / `US` → blue
- `Russian` → red
- Anything else → configurable default grey

All colours, brightness, host and mappings are editable from the in-app
Settings panel (Cmd+,).

## Requirements

- macOS 13 Ventura or newer
- Xcode 15 or newer (tested with 26.4)
- M5Stack Atom Matrix (or any ESP32) running **WLED**, reachable on your LAN
  by IP or `<name>.local` mDNS name

## First-time setup — create the Xcode project

Source files are on disk but the `.xcodeproj` is not generated automatically
(that file format is fragile without `xcodegen`). Create the shell in Xcode
once and the source files plug straight in:

1. Open Xcode → **File → New → Project…**
2. Choose **macOS → App**. Next.
3. Fill in:
   - **Product Name:** `WLEDLayoutIndicator`
   - **Team:** your personal team (or "None" for local-only)
   - **Organization Identifier:** e.g. `com.yourname`
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Testing System:** XCTest
   - **Include Tests:** ✅
4. **Save it to `~/Projects/`** — select the existing `WLEDLayoutIndicator`
   folder. Xcode will create `WLEDLayoutIndicator.xcodeproj` alongside the
   existing `WLEDLayoutIndicator/` and `WLEDLayoutIndicatorTests/` folders.
5. When Xcode asks about overwriting, let it create the project file only.
   If Xcode insists on generating its own starter `ContentView.swift` /
   `WLEDLayoutIndicatorApp.swift` inside `WLEDLayoutIndicator/`, **delete
   those new files** (the ones we ship replace them).
6. In Xcode's Project Navigator, right-click the `WLEDLayoutIndicator`
   group → **Add Files to "WLEDLayoutIndicator"…** and add:
   - `WLEDLayoutIndicator/AppCoordinator.swift`
   - `WLEDLayoutIndicator/WLEDLayoutIndicatorApp.swift`
   - everything inside `WLEDLayoutIndicator/Core/`
   - everything inside `WLEDLayoutIndicator/UI/`
7. Do the same for the test target: add files under
   `WLEDLayoutIndicatorTests/` to the **WLEDLayoutIndicatorTests** target.
8. Target **WLEDLayoutIndicator** → **General**:
   - Minimum Deployments → macOS **13.0**
9. Target → **Info**: add row **Application is agent (UIElement)** = `YES`.
   (Or copy the keys from `WLEDLayoutIndicator/Resources/Info.plist` shipped
   in this repo into the target's generated Info.plist.)
10. Target → **Signing & Capabilities**:
    - Keep **App Sandbox**
    - Enable **Outgoing Connections (Client)** under Network
    - (Optional) under Capability → **Hardened Runtime** if you plan to
      notarize later
11. Build & run. The app icon will appear in the menu bar; nothing in the
    Dock.

## Verifying it works

1. Open **Settings** from the menu bar (or Cmd+,)
2. Enter the host of your WLED device (`192.168.1.xx` or `wled-atom.local`)
3. Click **Test connection** — the matrix should light up in the current
   layout's colour and the UI should show "OK"
4. Flip between layouts with Ctrl+Space (or whatever you configured); the
   matrix should follow within 100 ms
5. Run the unit tests: Cmd+U in Xcode

## Files

```
WLEDLayoutIndicator/
├── WLEDLayoutIndicatorApp.swift   # @main, NSApplicationDelegateAdaptor, MenuBarExtra
├── AppCoordinator.swift           # Monitor → Mapper → Client wiring, status publishing
├── Core/
│   ├── Models.swift               # Config, RGB, LinkStatus
│   ├── SettingsStore.swift        # JSON in ~/Library/Application Support
│   ├── LayoutMonitor.swift        # Carbon TIS + DistributedNotificationCenter
│   ├── ColorMapper.swift          # pure (sourceID, Config) -> RGB
│   └── WLEDClient.swift           # actor: URLSession + retry + debounce + coalesce
├── UI/
│   ├── StatusBarIcon.swift        # menu-bar label (tinted grid glyph)
│   └── SettingsView.swift         # SwiftUI Form: host, brightness, mappings
├── Resources/Info.plist           # template — use LSUIElement=YES
└── Entitlements/WLEDLayoutIndicator.entitlements  # sandbox + network.client

WLEDLayoutIndicatorTests/
├── ColorMapperTests.swift         # mapping + fallback + case sensitivity
├── SettingsStoreTests.swift       # round-trip, first-launch defaults
└── WLEDClientTests.swift          # URLProtocol stub: JSON shape, 5xx, debounce
```

## Architecture at a glance

```
LayoutMonitor ── sourceID ──▶ AppCoordinator ── RGB ──▶ WLEDClient ──▶ POST /json/state
      ▲                             ▲
      │                             │ publishes currentSourceID,
 Carbon TIS +                       │ currentColor, LinkStatus
 DistributedNotif                   │
                                    ▼
                              MenuBarExtra + SettingsView
                              (observes via @EnvironmentObject)
```

Config is a single `Codable` struct persisted to
`~/Library/Application Support/WLEDLayoutIndicator/config.json`. The coordinator
subscribes to both the layout stream and config edits and re-sends on either.

## Open items

- Heartbeat send to recover from WLED reboots (off by default — add when needed)
- WLED `transition` field for smooth colour fades
- Developer-ID signing / notarization if distributing the `.app`
