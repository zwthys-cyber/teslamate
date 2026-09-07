import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum APIError: LocalizedError {
    case invalidURL, invalidToken, invalidResponse, unauthorized, notFound, historyUpgradeRequired, server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "请输入完整的 HTTP 或 HTTPS 服务器地址，不要包含账号、查询参数或片段"
        case .invalidToken: "请输入有效的访问令牌"
        case .invalidResponse: "服务器返回了无效数据，请检查服务器版本与地址"
        case .unauthorized: "访问令牌无效或已撤销，请更新连接设置"
        case .historyUpgradeRequired: "请先升级 TeslaMate 服务器，当前版本尚不支持历史分页和车辆隔离字段"
        case .notFound: "记录或车辆不存在，可能已被服务器删除，请刷新列表"
        case .server(let code): "服务器错误（\(code)），请稍后重试"
        }
    }
}

struct APIClient {
    let serverURL: String
    let token: String
    var session: URLSession = .shared

    static func normalizedServerURL(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: value),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true else {
            throw APIError.invalidURL
        }
        parts.scheme = scheme
        if !parts.path.hasSuffix("/") { parts.path += "/" }
        guard let url = parts.url else { throw APIError.invalidURL }
        return url.absoluteString
    }

    func vehicles() async throws -> [Vehicle] {
        let envelope: VehicleEnvelope = try await get("vehicles")
        return envelope.data
    }

    func history<Item: HistoryEntry>(carID: Int, filter: HistoryFilter, cursor: String? = nil) async throws -> HistoryPage<Item> {
        var query = [URLQueryItem(name: "car_id", value: String(carID)), URLQueryItem(name: "limit", value: "50")]
        let formatter = ISO8601DateFormatter()
        if let from = filter.from { query.append(.init(name: "from", value: formatter.string(from: from))) }
        if let to = filter.to { query.append(.init(name: "to", value: formatter.string(from: to))) }
        if let cursor { query.append(.init(name: "cursor", value: cursor)) }
        return try await get(Item.resource, query: query, requiresHistorySupport: true)
    }

    func detail<Item: HistoryEntry>(_ type: Item.Type, id: Int, carID: Int) async throws -> Item {
        let envelope: DetailEnvelope<Item> = try await get("\(Item.resource)/\(id)", query: [.init(name: "car_id", value: String(carID))], requiresHistorySupport: true)
        guard envelope.data.carId == carID, envelope.data.id == id else { throw APIError.invalidResponse }
        return envelope.data
    }

    private func get<Value: Decodable>(_ path: String, query: [URLQueryItem] = [], requiresHistorySupport: Bool = false) async throws -> Value {
        let normalized = try Self.normalizedServerURL(serverURL)
        guard let base = URL(string: normalized),
              let endpoint = URL(string: "api/mobile/v1/" + path, relativeTo: base),
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw APIError.unauthorized }
        if http.statusCode == 404 { throw APIError.notFound }
        guard (200..<300).contains(http.statusCode) else { throw APIError.server(http.statusCode) }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let wholeSeconds = ISO8601DateFormatter()
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = fractional.date(from: value) ?? wholeSeconds.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date")
            }
            return date
        }
        do { return try decoder.decode(Value.self, from: data) }
        catch DecodingError.keyNotFound(let key, _) where requiresHistorySupport && ["pagination", "carId"].contains(key.stringValue) {
            throw APIError.historyUpgradeRequired
        }
        catch { throw APIError.invalidResponse }
    }
}
