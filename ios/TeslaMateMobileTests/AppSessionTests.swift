import XCTest
@testable import TeslaMateMobile

final class AppSessionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var credentials: MemoryCredentials!

    @MainActor
    override func setUp() async throws {
        suite = "TeslaMateMobileTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        credentials = MemoryCredentials()
    }

    @MainActor
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    @MainActor
    func testInvalidAddressesAreRejected() {
        for address in ["", "example.com", "ftp://example.com", "https://user:secret@example.com",
                        "https://example.com/?token=x", "https://example.com/#fragment"] {
            XCTAssertThrowsError(try APIClient.normalizedServerURL(address), address)
        }
        XCTAssertEqual(try APIClient.normalizedServerURL(" https://example.com/teslamate "),
                       "https://example.com/teslamate/")
        XCTAssertEqual(try APIClient.normalizedServerURL("http://100.64.0.1:4000"),
                       "http://100.64.0.1:4000/")
    }

    @MainActor
    func testFailedConnectionPreservesExistingConfigurationAndData() async throws {
        let session = makeSession { server, _ in
            if server.contains("new.example") { throw APIError.unauthorized }
            return try self.vehicles(named: "Original")
        }
        try await session.connect(serverURL: "https://old.example", token: "old-token")
        do {
            try await session.connect(serverURL: "https://new.example", token: "new-token")
            XCTFail("Expected failure")
        } catch { }
        XCTAssertEqual(session.serverURL, "https://old.example/")
        XCTAssertEqual(credentials.token, "old-token")
        XCTAssertEqual(defaults.string(forKey: "serverURL"), "https://old.example/")
        XCTAssertEqual(session.vehicles.first?.name, "Original")
        XCTAssertFalse(session.isConnecting)
    }

    @MainActor
    func testKeychainFailureDoesNotCommitVerifiedConnection() async throws {
        let session = makeSession { _, _ in [] }
        try await session.connect(serverURL: "https://old.example", token: "old-token")
        credentials.failWrites = true
        do {
            try await session.connect(serverURL: "https://new.example", token: "new-token")
            XCTFail("Expected credential failure")
        } catch { }
        XCTAssertEqual(session.serverURL, "https://old.example/")
        XCTAssertEqual(credentials.token, "old-token")
        XCTAssertEqual(defaults.string(forKey: "serverURL"), "https://old.example/")
    }

    @MainActor
    func testOldRefreshCannotOverwriteNewConnection() async throws {
        let pending = PendingFetch()
        var calls = 0
        let session = makeSession { _, _ in
            calls += 1
            if calls == 2 { return try await pending.fetch() }
            return try self.vehicles(named: calls == 1 ? "Original" : "New")
        }
        try await session.connect(serverURL: "https://old.example", token: "old-token")
        let refresh = Task { await session.refresh() }
        await pending.waitUntilStarted()
        try await session.connect(serverURL: "https://new.example", token: "new-token")
        pending.resolve(.success(try vehicles(named: "Old response")))
        await refresh.value
        XCTAssertEqual(session.vehicles.first?.name, "New")
        XCTAssertEqual(session.serverURL, "https://new.example/")
        XCTAssertFalse(session.isLoading)
        XCTAssertNil(session.errorMessage)
    }

    @MainActor
    func testRefreshFailurePreservesDataAndFetchTimeButExposesError() async throws {
        var calls = 0
        let session = makeSession { _, _ in
            calls += 1
            if calls > 1 { throw APIError.unauthorized }
            return try self.vehicles(named: "Original")
        }
        try await session.connect(serverURL: "https://old.example", token: "token")
        let receivedAt = session.lastReceivedAt
        await session.refresh()
        XCTAssertEqual(session.vehicles.first?.name, "Original")
        XCTAssertEqual(session.lastReceivedAt, receivedAt)
        XCTAssertNotNil(session.errorMessage)
        XCTAssertFalse(session.isLoading)
    }

    @MainActor
    func testDisconnectInvalidatesPendingRefresh() async throws {
        let pending = PendingFetch()
        var calls = 0
        let session = makeSession { _, _ in
            calls += 1
            return calls == 1 ? [] : try await pending.fetch()
        }
        try await session.connect(serverURL: "https://old.example", token: "token")
        let refresh = Task { await session.refresh() }
        await pending.waitUntilStarted()
        try session.disconnect()
        pending.resolve(.success(try vehicles(named: "Old response")))
        await refresh.value
        XCTAssertFalse(session.isConfigured)
        XCTAssertTrue(session.vehicles.isEmpty)
        XCTAssertNil(credentials.token)
        XCTAssertNil(session.lastReceivedAt)
        XCTAssertNil(defaults.string(forKey: "serverURL"))
    }

    @MainActor
    func testCancelledConnectionDoesNotSaveCredentials() async throws {
        let pending = PendingFetch()
        let session = makeSession { _, _ in try await pending.fetch() }
        let connection = Task { try await session.connect(serverURL: "https://new.example", token: "token") }
        await pending.waitUntilStarted()
        connection.cancel()
        pending.resolve(.success([]))
        do { try await connection.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        XCTAssertFalse(session.isConfigured)
        XCTAssertNil(credentials.token)
        XCTAssertFalse(session.isConnecting)
    }

    @MainActor
    func testUnknownAndFalseVehicleValuesRemainDistinct() throws {
        let vehicle = try vehicles(named: "Unknown").first!
        XCTAssertNil(vehicle.batteryLevel)
        XCTAssertNil(vehicle.locked)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let known = try decoder.decode(Vehicle.self, from: Data(
            #"{"id":1,"name":"Known","vin_suffix":"123456","battery_level":0,"locked":false}"#.utf8))
        XCTAssertEqual(known.batteryLevel, 0)
        XCTAssertEqual(known.locked, false)
    }

    @MainActor
    func testVehicleSelectionPersistsAndFallsBackWhenCarDisappears() async throws {
        let first = try vehicles(named: "First", id: 1)
        let second = try vehicles(named: "Second", id: 2)
        var cars = first + second
        let session = makeSession { _, _ in cars }
        try await session.connect(serverURL: "https://old.example", token: "token")
        XCTAssertEqual(session.selectedVehicle?.id, 1)
        session.selectVehicle(2)
        cars = second + first
        await session.refresh()
        XCTAssertEqual(session.selectedVehicle?.id, 2)
        let restored = makeSession { _, _ in cars }
        await restored.refresh()
        XCTAssertEqual(restored.selectedVehicle?.id, 2)
        cars = first
        await session.refresh()
        XCTAssertEqual(session.selectedVehicle?.id, 1)
        XCTAssertEqual(defaults.integer(forKey: "selectedVehicleID"), 1)
        session.selectVehicle(999)
        XCTAssertEqual(session.selectedVehicle?.id, 1)
    }

    @MainActor
    func testNewServerResetsSelectionAndHistoryIdentity() async throws {
        let cars = try vehicles(named: "First", id: 1) + vehicles(named: "Second", id: 2)
        let session = makeSession { _, _ in cars }
        try await session.connect(serverURL: "https://old.example", token: "token")
        session.selectVehicle(2)
        let oldIdentity = session.connectionID
        try await session.connect(serverURL: "https://new.example", token: "new-token")
        XCTAssertNotEqual(session.connectionID, oldIdentity)
        XCTAssertEqual(session.selectedVehicleID, 1)
        try session.disconnect()
        XCTAssertNil(session.selectedVehicleID)
        XCTAssertNil(defaults.object(forKey: "selectedVehicleID"))
    }

    @MainActor
    private func makeSession(fetch: @escaping (String, String) async throws -> [Vehicle]) -> AppSession {
        AppSession(defaults: defaults, credentials: credentials, fetch: fetch)
    }

    @MainActor
    private func vehicles(named name: String, id: Int = 1) throws -> [Vehicle] {
        let data = try JSONSerialization.data(withJSONObject: [
            ["id": id, "name": name, "vin_suffix": "123456"]
        ])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([Vehicle].self, from: data)
    }
}

@MainActor
private final class MemoryCredentials: CredentialStore {
    var token: String?
    var failWrites = false
    func read() throws -> String? { token }
    func save(_ token: String) throws {
        if failWrites { throw APIError.invalidResponse }
        self.token = token
    }
    func delete() throws {
        if failWrites { throw APIError.invalidResponse }
        token = nil
    }
}

@MainActor
private final class PendingFetch {
    private var continuation: CheckedContinuation<[Vehicle], Error>?
    private var started: CheckedContinuation<Void, Never>?

    func fetch() async throws -> [Vehicle] {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func resolve(_ result: Result<[Vehicle], Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
