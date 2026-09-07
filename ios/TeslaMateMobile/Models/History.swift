import Foundation

struct HistoryFilter: Equatable {
    var from: Date?
    var to: Date?

    static let all = HistoryFilter()

    // End date is inclusive in the UI and exclusive on the wire, including DST days.
    static func days(from start: Date, through end: Date, calendar: Calendar = .current) -> HistoryFilter {
        HistoryFilter(from: calendar.startOfDay(for: start),
                      to: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)))
    }
}

struct HistoryPage<Item: Decodable>: Decodable {
    let data: [Item]
    let pagination: Pagination
}

struct Pagination: Decodable {
    let nextCursor: String?
}

struct DetailEnvelope<Item: Decodable>: Decodable {
    let data: Item
}

protocol HistoryEntry: Decodable {
    var id: Int { get }
    static var resource: String { get }
    var carId: Int { get }
    var startDate: Date { get }
    var endDate: Date? { get }
    var title: String { get }
    var subtitle: String { get }
    var primaryValue: String { get }
    var secondaryValue: String { get }
}

struct DriveRecord: HistoryEntry {
    static let resource = "drives"
    let id: Int
    let carId: Int
    let startDate: Date
    let endDate: Date?
    let durationMin: Int?
    let distanceKm: Double?
    let speedMax: Double?
    let outsideTempAvg: Double?
    let startName: String?
    let endName: String?
    let positions: [TrackPoint]?
    let sampling: SamplingInfo?

    var title: String { startName ?? "未知起点" }
    var subtitle: String { endName ?? "未知终点" }
    var primaryValue: String { HistoryFormat.number(distanceKm, unit: "km") }
    var secondaryValue: String { HistoryFormat.duration(durationMin) }
}

struct ChargingRecord: HistoryEntry {
    static let resource = "charging"
    let id: Int
    let carId: Int
    let startDate: Date
    let endDate: Date?
    let durationMin: Int?
    let energyAddedKwh: Double?
    let energyUsedKwh: Double?
    let startBatteryLevel: Int?
    let endBatteryLevel: Int?
    let cost: Double?
    let name: String?
    let samples: [ChargingSample]?
    let sampling: SamplingInfo?

    var title: String { name ?? "未知充电地点" }
    var subtitle: String { "\(HistoryFormat.percent(startBatteryLevel)) → \(HistoryFormat.percent(endBatteryLevel))" }
    var primaryValue: String { HistoryFormat.number(energyAddedKwh, unit: "kWh") }
    var secondaryValue: String { HistoryFormat.duration(durationMin) }
}

struct TrackPoint: Decodable {
    let date: Date
    let latitude: Double?
    let longitude: Double?
    let speed: Double?

    var hasValidCoordinate: Bool {
        guard let latitude, let longitude else { return false }
        return latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

struct ChargingSample: Decodable {
    let date: Date
    let batteryLevel: Int?
    let chargerPower: Double?
    let energyAddedKwh: Double?
}

struct SamplingInfo: Decodable {
    let total: Int
    let returned: Int
    let downsampled: Bool
}

enum HistoryFormat {
    static func number(_ value: Double?, unit: String) -> String {
        guard let value, value.isFinite else { return "—" }
        return decimal(value, minimumDigits: 0, maximumDigits: 1) + " " + unit
    }

    private static func decimal(_ value: Double, minimumDigits: Int, maximumDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = minimumDigits
        formatter.maximumFractionDigits = maximumDigits
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }

    static func duration(_ minutes: Int?) -> String {
        guard let minutes else { return "时长未知" }
        if minutes < 60 { return "\(minutes) 分钟" }
        return "\(minutes / 60) 小时 \(minutes % 60) 分钟"
    }

    static func percent(_ value: Int?) -> String { value.map { "\($0)%" } ?? "—" }
    static func cost(_ value: Double?) -> String {
        guard let value else { return "未记录" }
        return decimal(value, minimumDigits: 2, maximumDigits: 2)
    }
}
