import Foundation
import IOKit.pwr_mgt
import os

/// Polls IOKit every 5 s to detect whether any process is holding a
/// `PreventUserIdleDisplaySleep` power assertion — the standard mechanism
/// used by all video players (QuickTime, VLC, IINA, browsers) when playing
/// video in fullscreen. Emits `true` on the first positive poll and `false`
/// when the assertion disappears; skips duplicate states.
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
                try? await Task.sleep(for: .seconds(5))
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
        let active = Self.hasDisplaySleepPrevention()
        guard active != lastState else { return }
        lastState = active
        logger.info("Fullscreen video active: \(active)")
        continuation.yield(active)
    }

    static func hasDisplaySleepPrevention() -> Bool {
        var outData: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&outData) == kIOReturnSuccess,
              let dict = outData?.takeRetainedValue() as? [String: Any]
        else { return false }
        let key = kIOPMAssertionTypePreventUserIdleDisplaySleep as String
        return (dict[key] as? Int ?? 0) > 0
    }
}
