import Foundation

enum APIError: LocalizedError {
    case invalidURL, invalidResponse, unauthorized, server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "服务器地址无效"
        case .invalidResponse: "服务器返回了无效数据"
        case .unauthorized: "访问令牌不正确"
        case .server(let code): "服务器错误（\(code)）"
        }
    }
}

struct APIClient {
    let serverURL: String
    let token: String

    func vehicles() async throws -> [Vehicle] {
        guard let base = URL(string: serverURL),
              let url = URL(string: "api/mobile/v1/vehicles", relativeTo: base) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw APIError.server(http.statusCode) }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(VehicleEnvelope.self, from: data).data
    }
}
