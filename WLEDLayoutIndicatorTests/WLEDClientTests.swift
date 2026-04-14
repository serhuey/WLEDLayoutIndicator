import XCTest
@testable import WLEDLayoutIndicator

/// Stubs out URLSession at the protocol level so we can assert on request
/// bodies and inject specific responses / errors.
final class StubURLProtocol: URLProtocol {

    struct Response {
        var status: Int
        var body: Data
    }

    /// Thread-safe because URLProtocol is invoked from arbitrary queues.
    private static let lock = NSLock()
    private static var _handler: ((URLRequest) throws -> Response)?
    private static var _recordedBodies: [Data] = []

    static func setHandler(_ handler: @escaping (URLRequest) throws -> Response) {
        lock.lock(); defer { lock.unlock() }
        _handler = handler
        _recordedBodies = []
    }

    static var recordedBodies: [Data] {
        lock.lock(); defer { lock.unlock() }
        return _recordedBodies
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let stream = request.httpBodyStream {
            let data = Self.readAll(stream: stream)
            Self.lock.lock()
            Self._recordedBodies.append(data)
            Self.lock.unlock()
        } else if let body = request.httpBody {
            Self.lock.lock()
            Self._recordedBodies.append(body)
            Self.lock.unlock()
        }

        do {
            Self.lock.lock()
            let handler = Self._handler
            Self.lock.unlock()
            let result = try handler!(request)
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: result.status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func readAll(stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var out = Data()
        let bufSize = 1024
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buf, maxLength: bufSize)
            if n > 0 { out.append(buf, count: n) } else { break }
        }
        return out
    }
}

final class WLEDClientTests: XCTestCase {

    private var session: URLSession!
    private let wled = Config.WLED(
        host: "wled-test.local",
        brightness: 128,
        segmentId: 0,
        ledCount: 25
    )

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
    }

    // MARK: - Success with solid pattern

    func test_sendOnce_solid_sendsPerPixelJSON() async throws {
        StubURLProtocol.setHandler { _ in
            .init(status: 200, body: Data("{\"success\":true}".utf8))
        }
        let client = WLEDClient(session: session)
        let entry = LayoutEntry(color: RGB(r: 255, g: 0, b: 0), pattern: .solid)

        try await client.sendOnce(entry, wled: wled)

        let bodies = StubURLProtocol.recordedBodies
        XCTAssertEqual(bodies.count, 1)
        let json = try JSONSerialization.jsonObject(with: bodies[0]) as? [String: Any]
        XCTAssertEqual(json?["on"] as? Bool, true)
        XCTAssertEqual(json?["bri"] as? Int, 128)
        let segs = json?["seg"] as? [[String: Any]]
        XCTAssertEqual(segs?.first?["id"] as? Int, 0)
        XCTAssertEqual(segs?.first?["on"] as? Bool, true)
        XCTAssertEqual(segs?.first?["fx"] as? Int, 0)
        XCTAssertEqual(segs?.first?["col"] as? [[Int]], [[255, 0, 0]])
        // "i" should be an array of 25 [R,G,B] triples
        let pixels = segs?.first?["i"] as? [[Int]]
        XCTAssertEqual(pixels?.count, 25)
        XCTAssertEqual(pixels?.first, [255, 0, 0])
        XCTAssertEqual(pixels?.last, [255, 0, 0])
    }

    // MARK: - Pattern with some pixels off

    func test_sendOnce_partialPattern_sendsCorrectPixels() async throws {
        StubURLProtocol.setHandler { _ in
            .init(status: 200, body: Data("{\"success\":true}".utf8))
        }
        let client = WLEDClient(session: session)
        var pattern = Pattern.blank
        pattern[0, 0] = true  // index 0
        pattern[2, 2] = true  // index 12
        let entry = LayoutEntry(color: RGB(r: 0, g: 255, b: 0), pattern: pattern)

        try await client.sendOnce(entry, wled: wled)

        let bodies = StubURLProtocol.recordedBodies
        let json = try JSONSerialization.jsonObject(with: bodies[0]) as? [String: Any]
        let segs = json?["seg"] as? [[String: Any]]
        let pixels = segs?.first?["i"] as? [[Int]]
        XCTAssertEqual(pixels?.count, 25)
        XCTAssertEqual(pixels?[0], [0, 255, 0])   // LED 0: on, green
        XCTAssertEqual(pixels?[1], [0, 0, 0])     // LED 1: off, black
        XCTAssertEqual(pixels?[12], [0, 255, 0])  // LED 12 (row 2 col 2): on, green
    }

    // MARK: - 5xx → failure bubbles up for sendOnce

    func test_sendOnce_onServerError_throws() async {
        StubURLProtocol.setHandler { _ in .init(status: 500, body: Data()) }
        let client = WLEDClient(session: session)
        let entry = LayoutEntry(color: RGB(r: 1, g: 2, b: 3))
        do {
            try await client.sendOnce(entry, wled: wled)
            XCTFail("expected throw")
        } catch let err as WLEDClient.ClientError {
            XCTAssertEqual(err, .badResponse(status: 500))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Debounce

    func test_setEntry_debouncesIdenticalEntry() async throws {
        StubURLProtocol.setHandler { _ in .init(status: 200, body: Data()) }
        let client = WLEDClient(session: session)

        let entry = LayoutEntry(color: RGB(r: 10, g: 20, b: 30))
        await client.setEntry(entry, wled: wled)
        try await Task.sleep(nanoseconds: 100_000_000)
        await client.setEntry(entry, wled: wled)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(StubURLProtocol.recordedBodies.count, 1,
                       "second identical send should have been debounced")
    }

    // MARK: - Different pattern triggers re-send

    func test_setEntry_differentPattern_sendsAgain() async throws {
        StubURLProtocol.setHandler { _ in .init(status: 200, body: Data()) }
        let client = WLEDClient(session: session)

        let entry1 = LayoutEntry(color: RGB(r: 10, g: 20, b: 30), pattern: .solid)
        await client.setEntry(entry1, wled: wled)
        try await Task.sleep(nanoseconds: 100_000_000)

        var pattern2 = Pattern.solid
        pattern2[0, 0] = false
        let entry2 = LayoutEntry(color: RGB(r: 10, g: 20, b: 30), pattern: pattern2)
        await client.setEntry(entry2, wled: wled)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(StubURLProtocol.recordedBodies.count, 2,
                       "different pattern should trigger a new send")
    }
}
