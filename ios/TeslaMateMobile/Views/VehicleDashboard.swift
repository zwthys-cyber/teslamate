import MapKit
import SwiftUI

struct VehicleDashboard: View {
    let vehicle: Vehicle

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = vehicle.latitude, let longitude = vehicle.longitude else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if let coordinate {
                    Map(initialPosition: .region(.init(
                        center: coordinate,
                        span: .init(latitudeDelta: 0.015, longitudeDelta: 0.015)
                    ))) {
                        Annotation(vehicle.name, coordinate: coordinate) {
                            Image(systemName: "car.side.fill")
                                .padding(9)
                                .background(.red, in: Circle())
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(height: 230)
                    .clipShape(.rect(cornerRadius: 18))
                }
                metrics
            }
            .padding()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(vehicle.name).font(.largeTitle.bold())
                Text([vehicle.model, vehicle.trimBadging, "VIN \(vehicle.vinSuffix)"].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
                Label(stateName, systemImage: stateIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(stateColor)
            }
            Spacer()
            ZStack {
                Circle().stroke(.secondary.opacity(0.25), lineWidth: 7)
                Circle().trim(from: 0, to: Double(vehicle.batteryLevel ?? 0) / 100)
                    .stroke(batteryColor, style: .init(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(vehicle.batteryLevel ?? 0)%").font(.headline.monospacedDigit())
            }
            .frame(width: 72, height: 72)
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
            MetricCard(title: "预估续航", value: distance(vehicle.estBatteryRangeKm), icon: "road.lanes")
            MetricCard(title: "典型续航", value: distance(vehicle.idealBatteryRangeKm), icon: "bolt.fill")
            MetricCard(title: "车内温度", value: temperature(vehicle.insideTemp), icon: "thermometer.medium")
            MetricCard(title: "车外温度", value: temperature(vehicle.outsideTemp), icon: "sun.max.fill")
            MetricCard(title: "总里程", value: distance(vehicle.odometer), icon: "gauge.with.dots.needle.67percent")
            MetricCard(title: "固件", value: vehicle.version ?? "—", icon: "cpu")
            MetricCard(title: "车锁", value: vehicle.locked == true ? "已锁定" : "未锁定", icon: vehicle.locked == true ? "lock.fill" : "lock.open.fill")
            MetricCard(title: "位置", value: vehicle.geofence ?? "未知", icon: "location.fill")
        }
    }

    private func distance(_ value: Double?) -> String { value.map { String(format: "%.1f km", $0) } ?? "—" }
    private func temperature(_ value: Double?) -> String { value.map { String(format: "%.1f ℃", $0) } ?? "—" }
    private var stateName: String { ["online": "在线", "asleep": "休眠", "offline": "离线", "driving": "行驶中", "charging": "充电中"][vehicle.state ?? ""] ?? "状态未知" }
    private var stateIcon: String { vehicle.state == "online" ? "checkmark.circle.fill" : "moon.zzz.fill" }
    private var stateColor: Color { vehicle.state == "online" ? .green : .secondary }
    private var batteryColor: Color { (vehicle.batteryLevel ?? 0) < 20 ? .red : .green }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }
}
