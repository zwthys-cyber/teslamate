import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TeslaMateMobile

final class APIClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        StubURLProtocol.handler = nil
    }

    func testRequestPreservesServerSubpathAndDecodesNullableValues() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/teslamate/api/mobile/v1/vehicles")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            return (200, Data(#"{"data":[{"id":1,"name":"Car","vin_suffix":"123456","locked":false,"battery_level":null}],"generated_at":"2026-09-05T00:00:00Z"}"#.utf8))
        }
        let vehicles = try await client().vehicles()
        XCTAssertEqual(vehicles.count, 1)
        XCTAssertEqual(vehicles.first?.locked, false)
        XCTAssertNil(vehicles.first?.batteryLevel)
    }

    func testUnauthorizedResponseHasActionableError() async throws {
        for status in [401, 403] {
            StubURLProtocol.handler = { _ in (status, Data()) }
            do { _ = try await client().vehicles(); XCTFail("Expected authorization error") }
            catch APIError.unauthorized { }
        }
    }

    func testMalformedPayloadIsReportedAsInvalidResponse() async throws {
        StubURLProtocol.handler = { _ in (200, Data("<html>Login</html>".utf8)) }
        do { _ = try await client().vehicles(); XCTFail("Expected invalid response") }
        catch APIError.invalidResponse { }
    }

    func testTransportFailureIsPreserved() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await client().vehicles(); XCTFail("Expected transport failure") }
        catch let error as URLError { XCTAssertEqual(error.code, .notConnectedToInternet) }
    }

    func testHistoryQueryIncludesCarCursorAndUTCDateBounds() async throws {
        StubURLProtocol.handler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: true)!
            XCTAssertEqual(components.path, "/teslamate/api/mobile/v1/drives")
            let query = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })
            XCTAssertEqual(query["car_id"], "2")
            XCTAssertEqual(query["limit"], "50")
            XCTAssertEqual(query["cursor"], "cursor+/=")
            XCTAssertEqual(query["from"], "1970-01-01T00:00:00Z")
            XCTAssertEqual(query["to"], "1970-01-02T00:00:00Z")
            return (200, Data(#"{"data":[{"id":1,"car_id":2,"start_date":"2026-09-01T00:00:00.123456Z","end_date":null}],"pagination":{"next_cursor":"next"}}"#.utf8))
        }
        let page: HistoryPage<DriveRecord> = try await client().history(carID: 2,
            filter: HistoryFilter(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 86400)), cursor: "cursor+/=")
        XCTAssertEqual(page.data.first?.carId, 2)
        XCTAssertNil(page.data.first?.endDate)
        XCTAssertEqual(page.pagination.nextCursor, "next")
    }

    func testLegacyHistoryWithoutPaginationIsNotReportedAsComplete() async throws {
        StubURLProtocol.handler = { _ in (200, Data(#"{"data":[]}"#.utf8)) }
        do {
            let _: HistoryPage<DriveRecord> = try await client().history(carID: 1, filter: .all)
            XCTFail("Expected incompatible response")
        } catch APIError.historyUpgradeRequired { }
    }

    func testDetailValidatesCarAndRecordIdentity() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/teslamate/api/mobile/v1/charging/7")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: true)?.queryItems?.first?.value, "2")
            return (200, Data(#"{"data":{"id":7,"car_id":1,"start_date":"2026-09-01T00:00:00Z"}}"#.utf8))
        }
        do {
            _ = try await client().detail(ChargingRecord.self, id: 7, carID: 2)
            XCTFail("Expected wrong-car response to be rejected")
        } catch APIError.invalidResponse { }
    }

    func testChargingDetailDecodesWholeSecondDatesAndZeroPower() async throws {
        StubURLProtocol.handler = { _ in
            (200, Data(#"{"data":{"id":7,"car_id":2,"start_date":"2026-09-01T00:00:00Z","cost":null,"samples":[{"date":"2026-09-01T00:01:00Z","charger_power":0,"battery_level":80,"energy_added_kwh":2.5}],"sampling":{"total":1,"returned":1,"downsampled":false}}}"#.utf8))
        }
        let detail = try await client().detail(ChargingRecord.self, id: 7, carID: 2)
        XCTAssertNil(detail.cost)
        XCTAssertEqual(detail.samples?.first?.chargerPower, 0)
        XCTAssertEqual(detail.samples?.first?.energyAddedKwh, 2.5)
        XCTAssertEqual(detail.sampling?.downsampled, false)
    }

    private func client() -> APIClient {
        APIClient(serverURL: "https://example.com/teslamate", token: "test-token", session: session)
    }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
