import XCTest
@testable import TeslaMateMobile

final class HistoryStoreTests: XCTestCase {
    @MainActor
    func testPagesAppendWithoutDuplicateIDsAndStopAtEnd() async {
        var calls = 0
        let store = HistoryStore<HistoryStub>(carID: 1) { _, cursor in
            calls += 1
            if cursor == nil { return self.page([3, 2], next: "older") }
            XCTAssertEqual(cursor, "older")
            return self.page([2, 1])
        }
        await store.reload(filter: .all)
        await store.loadMore()
        await store.loadMore()
        XCTAssertEqual(store.items.map(\.id), [3, 2, 1])
        XCTAssertEqual(calls, 2)
        XCTAssertNil(store.nextCursor)
    }

    @MainActor
    func testFailedNextPageCanRetryWithoutLosingExistingRows() async {
        var calls = 0
        let store = HistoryStore<HistoryStub>(carID: 1) { _, cursor in
            calls += 1
            if cursor == nil { return self.page([2], next: "older") }
            if calls == 2 { throw URLError(.notConnectedToInternet) }
            return self.page([1])
        }
        await store.reload(filter: .all)
        await store.loadMore()
        XCTAssertEqual(store.items.map(\.id), [2])
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.nextCursor, "older")
        await store.retry()
        XCTAssertEqual(store.items.map(\.id), [2, 1])
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testOldPageCannotOverwriteChangedDateFilter() async {
        let pending = PendingHistoryPage()
        let filter = HistoryFilter(from: Date(timeIntervalSince1970: 100), to: nil)
        let store = HistoryStore<HistoryStub>(carID: 1) { requested, _ in
            if requested == .all { return try await pending.fetch() }
            return self.page([9])
        }
        let old = Task { await store.reload(filter: .all) }
        await pending.waitUntilStarted()
        await store.reload(filter: filter)
        pending.resolve(page([1], next: "old-cursor"))
        await old.value
        XCTAssertEqual(store.items.map(\.id), [9])
        XCTAssertEqual(store.filter, filter)
        XCTAssertNil(store.nextCursor)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testRefreshSupersedesPendingLoadMore() async {
        let pending = PendingHistoryPage()
        var firstPageCalls = 0
        let store = HistoryStore<HistoryStub>(carID: 1) { _, cursor in
            if cursor != nil { return try await pending.fetch() }
            firstPageCalls += 1
            return self.page([firstPageCalls == 1 ? 2 : 3], next: firstPageCalls == 1 ? "old" : nil)
        }
        await store.reload(filter: .all)
        let more = Task { await store.loadMore() }
        await pending.waitUntilStarted()
        await store.reload(filter: .all)
        pending.resolve(page([1]))
        await more.value
        XCTAssertEqual(store.items.map(\.id), [3])
        XCTAssertNil(store.nextCursor)
    }

    @MainActor
    func testDataFromWrongCarIsRejected() async {
        let store = HistoryStore<HistoryStub>(carID: 1) { _, _ in
            HistoryPage(data: [HistoryStub(id: 1, carId: 2)], pagination: Pagination(nextCursor: nil))
        }
        await store.reload(filter: .all)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(store.hasLoaded)
        XCTAssertNotNil(store.errorMessage)
    }

    @MainActor
    func testRepeatedCursorIsRejectedInsteadOfLooping() async {
        let store = HistoryStore<HistoryStub>(carID: 1) { _, cursor in
            self.page(cursor == nil ? [2] : [1], next: "same")
        }
        await store.reload(filter: .all)
        await store.loadMore()
        XCTAssertEqual(store.items.map(\.id), [2])
        XCTAssertNotNil(store.errorMessage)
    }

    @MainActor
    func testFailedFilterChangeDoesNotShowPreviousFilterRows() async {
        let store = HistoryStore<HistoryStub>(carID: 1) { filter, _ in
            if filter != .all { throw URLError(.timedOut) }
            return self.page([1])
        }
        await store.reload(filter: .all)
        await store.reload(filter: HistoryFilter(from: Date(), to: nil))
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.nextCursor)
    }

    func testInclusiveDateRangeHandlesDaylightSavingTransition() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let noon = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-29T12:00:00+02:00"))
        let filter = HistoryFilter.days(from: noon, through: noon, calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(filter.to).timeIntervalSince(try XCTUnwrap(filter.from)), 23 * 3600)
    }

    func testMissingCostIsDifferentFromFreeChargeAndInvalidCoordinatesAreRejected() {
        XCTAssertEqual(HistoryFormat.cost(nil), "未记录")
        XCTAssertNotEqual(HistoryFormat.cost(0), "未记录")
        XCTAssertFalse(TrackPoint(date: Date(), latitude: 91, longitude: 0, speed: nil).hasValidCoordinate)
        XCTAssertFalse(TrackPoint(date: Date(), latitude: nil, longitude: 0, speed: nil).hasValidCoordinate)
        XCTAssertTrue(TrackPoint(date: Date(), latitude: 0, longitude: 0, speed: nil).hasValidCoordinate)
    }

    private func page(_ ids: [Int], next: String? = nil) -> HistoryPage<HistoryStub> {
        HistoryPage(data: ids.map { HistoryStub(id: $0, carId: 1) }, pagination: Pagination(nextCursor: next))
    }
}

private struct HistoryStub: HistoryEntry {
    static let resource = "drives"
    let id: Int
    let carId: Int
    var startDate: Date { Date(timeIntervalSince1970: 0) }
    var endDate: Date? { nil }
    var title: String { "Test" }
    var subtitle: String { "Test" }
    var primaryValue: String { "0 km" }
    var secondaryValue: String { "1 分钟" }
}

@MainActor
private final class PendingHistoryPage {
    private var continuation: CheckedContinuation<HistoryPage<HistoryStub>, Error>?
    private var started: CheckedContinuation<Void, Never>?
    func fetch() async throws -> HistoryPage<HistoryStub> {
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
    func resolve(_ page: HistoryPage<HistoryStub>) {
        continuation?.resume(returning: page)
        continuation = nil
    }
}
