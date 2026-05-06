import Foundation
import IOKit.pwr_mgt
import AppKit
import os

/// Polls every 2 s to detect fullscreen video playback: requires BOTH a
/// `PreventUserIdleDisplaySleep` IOKit assertion AND a window that covers
/// the full screen. The assertion alone fires for any video (even in a
/// browser tab), so the window check prevents false positives.
@MainActor
public final class FullscreenVideoMonitor {

    public var updates: AsyncStream<Bool> { stream }

    private let stream: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation
    private var timerTask: Task<Void, Never>?
    private var lastState = false
    private let logger = Logger(subsystem: "com.wledlayout.indicator", category: "video")

    public init() {
        var cont: AsyncStream<Bool>.Continuation!
        self.stream = AsyncStream<Bool> { c in cont = c }
        self.continuation = cont
    }

    public func start() {
        poll()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                self?.poll()
            }
        }
    }

    public func stop() {
        timerTask?.cancel()
        timerTask = nil
        continuation.finish()
    }

    // MARK: -

    private func poll() {
        let active = Self.hasDisplaySleepPrevention() && Self.hasFullscreenWindow()
        guard active != lastState else { return }
        lastState = active
        logger.info("Fullscreen video active: \(active)")
        continuation.yield(active)
    }

    /// Returns true when any process holds a PreventUserIdleDisplaySleep assertion.
    static func hasDisplaySleepPrevention() -> Bool {
        var outData: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&outData) == kIOReturnSuccess,
              let dict = outData?.takeRetainedValue() as? [String: Any]
        else { return false }
        let key = kIOPMAssertionTypePreventUserIdleDisplaySleep as String
        return (dict[key] as? Int ?? 0) > 0
    }

    /// Returns true when a normal-layer window covers the full dimensions of
    /// any screen — the reliable sign of a true macOS fullscreen app. Maximised
    /// (zoomed) windows stop short of the menu bar and don't match.
    static func hasFullscreenWindow() -> Bool {
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else { return false }

        for screen in NSScreen.screens {
            let sw = screen.frame.width
            let sh = screen.frame.height
            for window in windows {
                guard let layer = window[kCGWindowLayer as String] as? Int32,
                      layer == 0,  // normal window layer; menu bar / dock are higher
                      let bounds = window[kCGWindowBounds as String] as? [String: Any]
                else { continue }
                let ww = bounds["Width"]  as? CGFloat ?? 0
                let wh = bounds["Height"] as? CGFloat ?? 0
                if ww >= sw && wh >= sh { return true }
            }
        }
        return false
    }
}
