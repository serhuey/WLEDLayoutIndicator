import Foundation
import AppKit
import os

/// Observes which application currently holds front-app focus.
///
/// Subscribes to `NSWorkspace.didActivateApplicationNotification` and emits
/// the bundle identifier of the activated app on each focus change. Also
/// emits the current frontmost app on `start()` so consumers see initial
/// state immediately.
///
/// Apps without a bundle identifier (system overlays, transient processes)
/// produce a `nil` event — consumers skip those.
@MainActor
public final class AppFocusMonitor {

    /// Async stream of bundle identifiers of the activated app.
    /// `nil` when the activated app has no bundle ID.
    public var updates: AsyncStream<String?> { stream }

    private let stream: AsyncStream<String?>
    private let continuation: AsyncStream<String?>.Continuation
    private var observer: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.wledlayout.indicator", category: "focus")

    public init() {
        var cont: AsyncStream<String?>.Continuation!
        self.stream = AsyncStream<String?> { c in cont = c }
        self.continuation = cont
    }

    public func start() {
        emitCurrent()

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Queue is .main, so we are physically on the main thread.
            MainActor.assumeIsolated {
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.emit(app?.bundleIdentifier)
            }
        }
    }

    public func stop() {
        if let o = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            observer = nil
        }
        continuation.finish()
    }

    // MARK: -

    private func emitCurrent() {
        emit(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    private func emit(_ bundleID: String?) {
        continuation.yield(bundleID)
    }
}
