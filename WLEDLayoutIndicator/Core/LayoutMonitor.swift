import Foundation
import Carbon.HIToolbox
import AppKit
import os

/// Observes the active keyboard input source on macOS.
///
/// Uses Carbon's Text Input Sources API (`TISCopyCurrentKeyboardInputSource`) —
/// still the only supported way on modern macOS — and subscribes to the
/// distributed notification that the system posts on each input-source change.
///
/// Also re-emits the current source on wake-from-sleep so the WLED device is
/// re-synced after the Mac (or the device itself) may have dropped state.
@MainActor
public final class LayoutMonitor {

    /// Async stream of input source IDs (e.g. "com.apple.keylayout.Russian").
    /// Emits the current value immediately on `start()`, then one event per change.
    public var updates: AsyncStream<String> { stream }

    private let stream: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private var observer: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.wledlayout.indicator", category: "layout")

    public init() {
        var cont: AsyncStream<String>.Continuation!
        self.stream = AsyncStream<String> { c in cont = c }
        self.continuation = cont
    }

    public func start() {
        emitCurrent()

        // Distributed notification posted by the system on input source change.
        // The name below matches `kTISNotifySelectedKeyboardInputSourceChanged`.
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleSelectedInputSourcesChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Small delay: the notification fires before TIS reflects the new
            // value in some edge cases (reported on older macOS). 10 ms is
            // imperceptible and makes the read reliable.
            // The closure itself is Sendable/nonisolated; we hop back to the
            // main actor explicitly since `emitCurrent()` is @MainActor.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                MainActor.assumeIsolated {
                    self?.emitCurrent()
                }
            }
        }

        // Re-sync on wake — WLED may have lost state while we were asleep.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Queue is .main, so we're physically on the main thread; assume
            // main actor isolation to satisfy Swift 6 without an extra hop.
            MainActor.assumeIsolated {
                self?.emitCurrent()
            }
        }
    }

    public func stop() {
        if let o = observer {
            DistributedNotificationCenter.default().removeObserver(o)
            observer = nil
        }
        if let o = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            wakeObserver = nil
        }
        continuation.finish()
    }

    // MARK: -

    private func emitCurrent() {
        guard let id = Self.currentSourceID() else {
            logger.warning("TIS returned no current input source")
            return
        }
        continuation.yield(id)
    }

    /// Reads the currently-selected keyboard input source ID from Carbon TIS.
    /// Returns nil if the API fails (extremely rare outside of misconfigured sandbox).
    static func currentSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        let cfString = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue()
        return cfString as String
    }

    /// Programmatically selects the keyboard input source with the given ID.
    /// Used by per-app layout memory to restore the saved layout on focus.
    /// Returns `true` on success, `false` if the source isn't found among
    /// installed keyboard sources or `TISSelectInputSource` returns non-zero.
    @discardableResult
    static func selectInputSource(id: String) -> Bool {
        let logger = Logger(subsystem: "com.wledlayout.indicator", category: "layout")
        guard let allSources = TISCreateInputSourceList(nil, false)?
                .takeRetainedValue() as? [TISInputSource] else {
            logger.warning("selectInputSource: TISCreateInputSourceList returned nil")
            return false
        }
        for source in allSources {
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                continue
            }
            let candidate = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            guard candidate == id else { continue }
            let status = TISSelectInputSource(source)
            if status == noErr {
                return true
            } else {
                logger.warning("TISSelectInputSource(\(id, privacy: .public)) -> \(status)")
                return false
            }
        }
        logger.warning("selectInputSource: no enabled source matches id \(id, privacy: .public)")
        return false
    }

    /// Returns all *enabled, selectable* keyboard layouts installed in the
    /// system, as an array of source IDs (e.g. `["com.apple.keylayout.US",
    /// "com.apple.keylayout.Russian"]`).
    ///
    /// This uses `TISCreateInputSourceList` with filters for keyboard layouts
    /// that are both enabled (`kTISPropertyInputSourceIsEnabled`) and
    /// selectable (`kTISPropertyInputSourceIsSelectCapable`).
    static func enabledKeyboardSourceIDs() -> [String] {
        // First get ALL input sources (no filter), then filter in Swift.
        // Building a CF filter dictionary from Swift is fragile across
        // macOS / Swift versions, so we do it the reliable way.
        guard let allSources = TISCreateInputSourceList(nil, false)?
                .takeRetainedValue() as? [TISInputSource] else {
            return []
        }

        return allSources.compactMap { source in
            // Must be a keyboard layout.
            guard let catPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory) else {
                return nil
            }
            let category = Unmanaged<CFString>.fromOpaque(catPtr).takeUnretainedValue() as String
            guard category == (kTISCategoryKeyboardInputSource as String) else {
                return nil
            }

            // Must be enabled.
            guard let enabledPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else {
                return nil
            }
            let enabled = Unmanaged<CFBoolean>.fromOpaque(enabledPtr).takeUnretainedValue()
            guard CFBooleanGetValue(enabled) else { return nil }

            // Must be selectable (user can switch to it).
            guard let selectPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else {
                return nil
            }
            let selectable = Unmanaged<CFBoolean>.fromOpaque(selectPtr).takeUnretainedValue()
            guard CFBooleanGetValue(selectable) else { return nil }

            // Get the source ID.
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                return nil
            }
            return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        }
    }
}
