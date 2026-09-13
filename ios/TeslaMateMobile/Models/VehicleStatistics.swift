import Foundation

struct VehicleStatistics: Decodable {
    let carId: Int?
    let driving: DrivingTotals
    let charging: ChargingTotals

    struct DrivingTotals: Decodable {
        let count: Int
        let distanceKm: Double?
        let distanceRecordedCount: Int?
    }
    struct ChargingTotals: Decodable {
        let count: Int
        let energyKwh: Double?
        let energyRecordedCount: Int?
    }

    // Legacy servers coalesce missing values to zero without reporting coverage.
    // Only show a sum once its coverage is known, never turn unknown into free/zero.
    var distance: String {
        guard let count = driving.distanceRecordedCount, count > 0 else { return "—" }
        return HistoryFormat.number(driving.distanceKm, unit: "km")
    }
    var energy: String {
        guard let count = charging.energyRecordedCount, count > 0 else { return "—" }
        return HistoryFormat.number(charging.energyKwh, unit: "kWh")
    }
}
