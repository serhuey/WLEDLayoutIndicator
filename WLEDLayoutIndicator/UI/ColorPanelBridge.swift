import AppKit
import SwiftUI

/// Singleton bridge to the system `NSColorPanel`. Last-clicked swatch wins:
/// `activate(...)` replaces the current setter, and the shared observer
/// forwards every panel colour change to whichever swatch most recently
/// asked. Safe because `NSColorPanel.shared` is itself a singleton — there
/// can be at most one active picker at a time.
@MainActor
final class ColorPanelBridge {

    static let shared = ColorPanelBridge()

    private var setter: ((Color) -> Void)?
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification,
            object: NSColorPanel.shared,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let setter = self.setter else { return }
                let ns = NSColorPanel.shared.color
                setter(Color(nsColor: ns))
            }
        }
    }

    /// Open the system colour panel seeded with `initial`. Subsequent
    /// colour changes are delivered to `setter` until another `activate`
    /// call replaces it.
    func activate(initial: Color, setter: @escaping (Color) -> Void) {
        self.setter = setter
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(initial)
        // Agent app must activate to bring the colour panel to front,
        // otherwise the panel opens behind whatever was focused before.
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFront(nil)
    }
}
