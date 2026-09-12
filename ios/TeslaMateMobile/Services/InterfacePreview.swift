#if DEBUG
import Foundation

// Only compiled in Debug. UI tests use synthetic data without production credentials or servers.
enum InterfacePreview {
    static var enabled: Bool { CommandLine.arguments.contains("--ui-preview") }
    static var dark: Bool { CommandLine.arguments.contains("--ui-dark") }
    static var large: Bool { CommandLine.arguments.contains("--ui-large") }
    static let urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PreviewURLProtocol.self]
        return URLSession(configuration: config)
    }()

    @MainActor
    static func makeSession() -> AppSession {
        let defaults = UserDefaults(suiteName: "TeslaMate.InterfacePreview")!
        defaults.removePersistentDomain(forName: "TeslaMate.InterfacePreview")
        defaults.set("https://preview.invalid/", forKey: "serverURL")
        defaults.set(["https://preview.invalid/": [1]], forKey: "historicalVehiclesByServer")
        return AppSession(defaults: defaults, credentials: PreviewCredentials())
    }

    static let drive: [String: Any] = [
        "id": 1, "car_id": 1, "start_date": "2026-09-01T08:00:00Z", "end_date": "2026-09-01T08:42:00Z",
        "start_name": "滨海公园", "end_name": "城市艺术中心", "distance_km": 28.6, "duration_min": 42,
        "speed_max": 80, "outside_temp_avg": 24,
        "positions": [
            ["date": "2026-09-01T08:00:00Z", "latitude": 37.78, "longitude": -122.42],
            ["date": "2026-09-01T08:20:00Z", "latitude": 37.79, "longitude": -122.41],
            ["date": "2026-09-01T08:42:00Z", "latitude": 37.80, "longitude": -122.43]
        ]
    ]
    static let charge: [String: Any] = [
        "id": 1, "car_id": 1, "start_date": "2026-09-02T08:00:00Z", "end_date": "2026-09-02T08:35:00Z",
        "name": "城市充电站", "duration_min": 35, "energy_added_kwh": 32.4,
        "start_battery_level": 28, "end_battery_level": 80,
        "samples": [
            ["date": "2026-09-02T08:00:00Z", "charger_power": 90, "battery_level": 28],
            ["date": "2026-09-02T08:15:00Z", "charger_power": 70, "battery_level": 54],
            ["date": "2026-09-02T08:35:00Z", "charger_power": 20, "battery_level": 80]
        ]
    ]

    static func body(path: String) -> [String: Any] {
        if path.hasSuffix("/vehicles") {
            return ["data": [["id": 1, "name": "我的 Model 3", "model": "Model 3", "vin_suffix": "DEMO01", "state": "unavailable", "healthy": false]], "generated_at": "2026-09-01T08:00:00Z"]
        }
        if path.hasSuffix("/statistics") {
            return ["data": ["car_id": 1,
                             "driving": ["count": 128, "distance_km": 3286.4, "distance_recorded_count": 128],
                             "charging": ["count": 32, "energy_kwh": 864.2, "energy_recorded_count": 32]]]
        }
        if path.hasSuffix("/drives/1") { return ["data": drive] }
        if path.hasSuffix("/charging/1") { return ["data": charge] }
        if path.hasSuffix("/drives") { return ["data": [drive], "pagination": ["next_cursor": NSNull()]] }
        return ["data": [charge], "pagination": ["next_cursor": NSNull()]]
    }
}

@MainActor
private struct PreviewCredentials: CredentialStore {
    func read() throws -> String? { "preview-only" }
    func save(_ token: String) throws { }
    func delete() throws { }
}

private final class PreviewURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "preview.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let data = try? JSONSerialization.data(withJSONObject: InterfacePreview.body(path: url.path)) else { return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
#endif
