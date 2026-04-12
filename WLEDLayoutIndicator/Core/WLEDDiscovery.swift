import Foundation
import Network
import Combine
import os

/// Discovers WLED devices on the local network via mDNS/Bonjour.
///
/// WLED firmware advertises itself as `_http._tcp.` (plain HTTP service).
/// We browse for all HTTP services, then filter by hostname containing both
/// "wled" and "key" (case-insensitive) per user convention.
///
/// Usage:
/// ```swift
/// let discovery = WLEDDiscovery()
/// discovery.start()
/// // observe discovery.devices – it publishes on the main actor
/// ```
@MainActor
public final class WLEDDiscovery: ObservableObject {

    /// Discovered device: a hostname like "wled-keyboard.local".
    public nonisolated struct Device: Identifiable, Hashable, Sendable {
        public let hostname: String           // e.g. "wled-keyboard.local"
        public var id: String { hostname }
    }

    @Published public private(set) var devices: [Device] = []
    @Published public private(set) var isSearching: Bool = false

    private var browser: NWBrowser?
    private let logger = Logger(subsystem: "com.wledlayout.indicator", category: "discovery")
    /// Filter keywords — hostname must contain ALL of these (case-insensitive).
    private let keywords: [String]

    /// - Parameter keywords: substrings that the mDNS hostname must contain.
    ///   Defaults to `["wled", "key"]`.
    public init(keywords: [String] = ["wled", "key"]) {
        self.keywords = keywords.map { $0.lowercased() }
    }

    /// Starts browsing. Results arrive asynchronously via `devices`.
    public func start() {
        guard browser == nil else { return }
        devices = []
        isSearching = true

        let params = NWParameters()
        params.includePeerToPeer = true
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_http._tcp.", domain: "local.")
        let b = NWBrowser(for: descriptor, using: params)

        b.stateUpdateHandler = { [weak self] state in
            guard let s = self else { return }
            Task { @MainActor in
                switch state {
                case .failed(let err):
                    s.logger.error("mDNS browse failed: \(err.localizedDescription, privacy: .public)")
                    s.isSearching = false
                case .cancelled:
                    s.isSearching = false
                default:
                    break
                }
            }
        }

        let kw = keywords // capture value type, not self
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> Device? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                let lower = name.lowercased()
                let allMatch = kw.allSatisfy { lower.contains($0) }
                guard allMatch else { return nil }
                return Device(hostname: "\(name).local")
            }
            guard let s = self else { return }
            Task { @MainActor in
                s.devices = found.sorted { $0.hostname < $1.hostname }
            }
        }

        b.start(queue: .global(qos: .utility))
        browser = b

        // Auto-stop after 5 seconds — we only need a quick scan.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.stop()
        }
    }

    /// Stops browsing (safe to call even if not started).
    public func stop() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }
}
