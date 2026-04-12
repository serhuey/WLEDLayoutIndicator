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
        // URLSession strips httpBody from requests delivered here; it sets
        // `httpBodyStream` instead. Read it for assertions.
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

    // MARK: - Success

    func test_sendOnce_sendsExpectedJSON() async throws {
        StubURLProtocol.setHandler { _ in
            .init(status: 200, body: Data("{\"success\":true}".utf8))
        }
        let client = WLEDClient(session: session)

        try await client.sendOnce(RGB(r: 255, g: 0, b: 0), wled: wled)

        let bodies = StubURLProtocol.recordedBodies
        XCTAssertEqual(bodies.count, 1)
        let json = try JSONSerialization.jsonObject(with: bodies[0]) as? [String: Any]
        XCTAssertEqual(json?["on"] as? Bool, true)
        XCTAssertEqual(json?["bri"] as? Int, 128)
        let segs = json?["seg"] as? [[String: Any]]
        XCTAssertEqual(segs?.first?["start"] as? Int, 0)
        XCTAssertEqual(segs?.first?["stop"] as? Int, 25)
        let col = segs?.first?["col"] as? [[Int]]
        XCTAssertEqual(col, [[255, 0, 0]])
    }

    // MARK: - 5xx → failure bubbles up for sendOnce

    func test_sendOnce_onServerError_throws() async {
        StubURLProtocol.setHandler { _ in .init(status: 500, body: Data()) }
        let client = WLEDClient(session: session)
        do {
            try await client.sendOnce(RGB(r: 1, g: 2, b: 3), wled: wled)
            XCTFail("expected throw")
        } catch let err as WLEDClient.ClientError {
            XCTAssertEqual(err, .badResponse(status: 500))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Debounce

    func test_setColor_debouncesIdenticalColour() async throws {
        StubURLProtocol.setHandler { _ in .init(status: 200, body: Data()) }
        let client = WLEDClient(session: session)

        let color = RGB(r: 10, g: 20, b: 30)
        await client.setColor(color, wled: wled)
        // Give the internal task time to drain.
        try await Task.sleep(nanoseconds: 100_000_000)
        await client.setColor(color, wled: wled)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(StubURLProtocol.recordedBodies.count, 1,
                       "second identical send should have been debounced")
    }
}
