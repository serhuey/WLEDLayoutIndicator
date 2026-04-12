import Foundation
import os

/// WLED JSON API client for a single solid-colour segment update.
///
/// Contract per plan:
/// - POST `http://<host>/json/state` with a segment that covers the full strip.
/// - Debounce: repeated calls with the same colour are coalesced to the last one.
/// - Retry with backoff on 5xx and transport errors (100 ms → 300 ms → 1 s).
/// - Per-request timeout: 2 seconds.
/// - Coalescing: while a send is in flight or waiting to retry, newer colours
///   replace the pending one so only the most recent state is ever delivered.
public actor WLEDClient {

    // MARK: - Wire format

    struct Body: Encodable {
        let on: Bool
        let bri: Int
        /// Transition time in 100 ms units. 1 = 100 ms, 7 = 700 ms (WLED default).
        let transition: Int
        let seg: [Segment]
        /// Only sends `id`, `col` and `fx`. Does NOT send `start`/`stop` —
        /// those are already configured in WLED itself (e.g. 2D matrix 5×5).
        /// Overriding them would clobber the device's own segment setup.
        struct Segment: Encodable {
            let id: Int
            let col: [[Int]]
            let fx: Int
        }
    }

    public enum ClientError: Error, Equatable {
        case badResponse(status: Int)
        case transport(String)
        case allRetriesFailed
    }

    // MARK: - State

    private let session: URLSession
    private let logger = Logger(subsystem: "com.wledlayout.indicator", category: "client")

    /// Currently in-flight (or pending) state. When set, the run loop
    /// will pick up the latest value, sleep after a retry, and re-check.
    private var pending: (rgb: RGB, wled: Config.WLED)?
    /// Last successfully-sent state for debouncing (colour + brightness).
    private var lastSentKey: DedupKey?
    private var runner: Task<Void, Never>?

    /// Captures everything that should trigger a re-send when changed.
    private nonisolated struct DedupKey: Equatable {
        let rgb: RGB
        let brightness: Int
    }

    /// Retry schedule in nanoseconds.
    private let retryDelays: [UInt64] = [
        100_000_000,   // 100 ms
        300_000_000,   // 300 ms
        1_000_000_000, // 1 s
    ]

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Queue a colour to be sent to WLED. Returns immediately.
    /// The actor will coalesce rapid calls and deliver only the latest.
    public func setColor(_ rgb: RGB, wled: Config.WLED) {
        let key = DedupKey(rgb: rgb, brightness: wled.brightness)
        if key == lastSentKey && runner == nil {
            // Debounce: same colour+brightness as last successful send.
            return
        }
        pending = (rgb, wled)
        if runner == nil {
            runner = Task { await self.drain() }
        }
    }

    /// Synchronous one-shot send, used by "Test connection" in settings.
    /// Does not interact with the debounce/coalesce state.
    public func sendOnce(_ rgb: RGB, wled: Config.WLED) async throws {
        try await performSend(rgb: rgb, wled: wled)
    }

    // MARK: - Run loop

    private func drain() async {
        defer { runner = nil }

        while let current = pending {
            pending = nil
            do {
                try await sendWithRetry(rgb: current.rgb, wled: current.wled)
                lastSentKey = DedupKey(rgb: current.rgb, brightness: current.wled.brightness)
            } catch {
                logger.error("WLED send failed: \(String(describing: error), privacy: .public)")
                // Failures do not clobber the caller — status surfaces via AppCoordinator observation.
            }
        }
    }

    private func sendWithRetry(rgb: RGB, wled: Config.WLED) async throws {
        var lastError: Error = ClientError.allRetriesFailed
        for (attempt, delay) in ([0] + retryDelays).enumerated() {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
                // If a newer colour arrived during backoff, abandon this attempt
                // and let the outer loop pick up the fresh value.
                if let next = pending, next.rgb != rgb {
                    return
                }
            }
            do {
                try await performSend(rgb: rgb, wled: wled)
                if attempt > 0 {
                    logger.info("WLED recovered after \(attempt) retries")
                }
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func performSend(rgb: RGB, wled: Config.WLED) async throws {
        guard let url = URL(string: "http://\(wled.host)/json/state") else {
            throw ClientError.transport("invalid host: \(wled.host)")
        }

        let body = Body(
            on: true,
            bri: max(0, min(255, wled.brightness)),
            transition: 1,  // 100 ms — fast but still smooth
            seg: [
                .init(
                    id: wled.segmentId,
                    col: [rgb.jsonArray],
                    fx: 0
                )
            ]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 2
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ClientError.transport("non-HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw ClientError.badResponse(status: http.statusCode)
            }
        } catch let error as ClientError {
            throw error
        } catch {
            throw ClientError.transport(error.localizedDescription)
        }
    }
}
