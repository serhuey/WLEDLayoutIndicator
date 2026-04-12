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

    /// Returns all *enabled, selectable* keyboard layouts installed in the
    /// system, as an array of source IDs (e.g. `["com.apple.keylayout.US",
    /// "com.apple.keylayout.Russian"]`).
    ///
    /// This uses `TISCreateInputSourceList` with filters for keyboard layouts
    /// that are both enabled (`kTISPropertyInputSourceIsEnabled`) and
    /// selectable (`kTISPropertyInputSourceIsSelectCapable`).
    static func enabledKeyboardSourceIDs() -> [String] {
        let filter: CFDictionary = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsEnabled as String: true,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary

        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue()
                as? [TISInputSource] else {
            return []
        }

        return list.compactMap { source in
            guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                return nil
            }
            return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        }
    }
}
