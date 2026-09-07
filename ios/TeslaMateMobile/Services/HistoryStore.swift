import Foundation
import Observation

@MainActor @Observable
final class HistoryStore<Item: HistoryEntry> {
    private(set) var items: [Item] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var filter = HistoryFilter.all

    @ObservationIgnored private let carID: Int
    @ObservationIgnored private let fetch: (HistoryFilter, String?) async throws -> HistoryPage<Item>
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var retryFirstPage = true
    @ObservationIgnored private var usedCursors: Set<String> = []

    init(carID: Int, fetch: @escaping (HistoryFilter, String?) async throws -> HistoryPage<Item>) {
        self.carID = carID
        self.fetch = fetch
    }

    func reload(filter: HistoryFilter) async {
        revision = UUID()
        if self.filter != filter {
            items = []
            nextCursor = nil
            hasLoaded = false
            usedCursors = []
        }
        self.filter = filter
        await load(firstPage: true)
    }

    func loadMore() async {
        guard !isLoading, hasLoaded, nextCursor != nil else { return }
        await load(firstPage: false)
    }

    func retry() async {
        guard !isLoading else { return }
        if retryFirstPage { await reload(filter: filter) }
        else { await loadMore() }
    }

    private func load(firstPage: Bool) async {
        let requestRevision = revision
        let cursor = firstPage ? nil : nextCursor
        isLoading = true
        errorMessage = nil
        defer { if revision == requestRevision { isLoading = false } }
        do {
            let page = try await fetch(filter, cursor)
            try Task.checkCancellation()
            guard revision == requestRevision else { return }
            guard page.data.allSatisfy({ $0.carId == carID }) else { throw APIError.invalidResponse }
            if let next = page.pagination.nextCursor,
               next.isEmpty || next == cursor || (!firstPage && usedCursors.contains(next)) {
                throw APIError.invalidResponse
            }
            var ids = Set<Int>()
            let merged = firstPage ? page.data : items + page.data
            var uniqueItems: [Item] = []
            for item in merged {
                if ids.insert(item.id).inserted { uniqueItems.append(item) }
            }
            items = uniqueItems
            if firstPage { usedCursors = [] }
            if let cursor { usedCursors.insert(cursor) }
            nextCursor = page.pagination.nextCursor
            hasLoaded = true
        } catch {
            guard revision == requestRevision else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            retryFirstPage = firstPage
            errorMessage = error.localizedDescription
        }
    }
}
