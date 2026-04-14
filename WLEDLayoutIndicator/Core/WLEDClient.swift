import Foundation
import os

/// WLED JSON API client with per-pixel pattern support.
///
/// Contract:
/// - POST `http://<host>/json/state` with a segment using the `"i"` (individual
///   LED) array for per-pixel control.
/// - Debounce: repeated calls with the same entry are coalesced to the last one.
/// - Retry with backoff on 5xx and transport errors (100 ms → 300 ms → 1 s).
/// - Per-request timeout: 2 seconds.
/// - Coalescing: while a send is in flight or waiting to retry, newer entries
///   replace the pending one so only the most recent state is ever delivered.
public actor WLEDClient {

    // MARK: - Wire format

    struct Body: Encodable {
        let on: Bool
        let bri: Int
        /// Transition time in 100 ms units. 1 = 100 ms, 7 = 700 ms (WLED default).
        let transition: Int
        let seg: [Segment]
        /// Sends per-segment `on: true`, a base `col` (so the segment is not blank
        /// if the firmware ignores `i`), and `"i"` (individual LED array) for
        /// per-pixel control. `fx: 0` (Solid) is required for `i` to persist.
        /// Does NOT send `start`/`stop` — those are already configured in WLED
        /// itself (e.g. 2D matrix 5×5).
        struct Segment: Encodable {
            let id: Int
            let on: Bool
            let col: [[Int]]
            /// Per-pixel colour data: array of [R,G,B] triples, one per LED.
            /// A flat array is ambiguous — WLED reads `[i, R, G, B]` pairs
            /// when it sees a flat list, so only the nested form is safe.
            let i: [[Int]]
            let fx: Int
            /// Palette id. Must be 0 (default), otherwise WLED colours the
            /// segment from the palette and ignores our `col` / `i`.
            let pal: Int
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
    private var pending: (entry: LayoutEntry, wled: Config.WLED)?
    /// Last successfully-sent state for debouncing.
    private var lastSentKey: DedupKey?
    private var runner: Task<Void, Never>?

    /// Captures everything that should trigger a re-send when changed.
    private nonisolated struct DedupKey: Equatable {
        let entry: LayoutEntry
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

    /// Queue a layout entry (colour + pattern) to be sent to WLED. Returns immediately.
    /// The actor will coalesce rapid calls and deliver only the latest.
    public func setEntry(_ entry: LayoutEntry, wled: Config.WLED) {
        let key = DedupKey(entry: entry, brightness: wled.brightness)
        if key == lastSentKey && runner == nil {
            return
        }
        pending = (entry, wled)
        if runner == nil {
            runner = Task { await self.drain() }
        }
    }

    /// Synchronous one-shot send, used by "Test connection" in settings.
    /// Does not interact with the debounce/coalesce state.
    public func sendOnce(_ entry: LayoutEntry, wled: Config.WLED) async throws {
        try await performSend(entry: entry, wled: wled)
    }

    // MARK: - Run loop

    private func drain() async {
        defer { runner = nil }

        while let current = pending {
            pending = nil
            do {
                try await sendWithRetry(entry: current.entry, wled: current.wled)
                lastSentKey = DedupKey(entry: current.entry, brightness: current.wled.brightness)
            } catch {
                logger.error("WLED send failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func sendWithRetry(entry: LayoutEntry, wled: Config.WLED) async throws {
        var lastError: Error = ClientError.allRetriesFailed
        for (attempt, delay) in ([0] + retryDelays).enumerated() {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
                if let next = pending, next.entry != entry {
                    return
                }
            }
            do {
                try await performSend(entry: entry, wled: wled)
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

    private func performSend(entry: LayoutEntry, wled: Config.WLED) async throws {
        guard let url = URL(string: "http://\(wled.host)/json/state") else {
            throw ClientError.transport("invalid host: \(wled.host)")
        }

        // Build per-pixel "i" array: for each LED, emit [R,G,B] if the
        // pattern pixel is on, or [0,0,0] if off. Nested form is required —
        // WLED parses a flat list as [index, R, G, B] pairs.
        let rgb = entry.color.jsonArray
        let off = [0, 0, 0]
        var pixels: [[Int]] = []
        pixels.reserveCapacity(wled.ledCount)
        for idx in 0..<wled.ledCount {
            let on = idx < entry.pattern.pixels.count ? entry.pattern.pixels[idx] : false
            pixels.append(on ? rgb : off)
        }

        let body = Body(
            on: true,
            bri: max(0, min(255, wled.brightness)),
            transition: 1,
            seg: [
                .init(
                    id: wled.segmentId,
                    on: true,
                    col: [rgb],
                    i: pixels,
                    fx: 0,
                    pal: 0
                )
            ]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 2
        let bodyData = try JSONEncoder().encode(body)
        request.httpBody = bodyData
        logger.debug("POST \(url.absoluteString, privacy: .public) (\(bodyData.count) bytes, \(pixels.count) pixels)")

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
