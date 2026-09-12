import MapKit
import SwiftUI

struct VehicleDashboard: View {
    let vehicle: Vehicle
    @Environment(\.dynamicTypeSize) private var typeSize

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = vehicle.latitude, let longitude = vehicle.longitude else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VehicleIdentityCard(vehicle: vehicle, historical: false)
                header
                if vehicle.healthy == false {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("当前没有可用的实时车辆数据", systemImage: "info.circle")
                        Text("已出售或不再采集的车辆，可在右上角开启历史车辆模式，继续查看行程和充电记录。仍在使用的车辆，请检查服务器采集状态。")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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
                FeatureHeading(title: "车辆状态", subtitle: "服务器保存的最近数据，未知值以横线显示")
                metrics
            }
            .padding(20)
        }
        .background(AppDesign.background)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("最近状态").font(.headline)
                Text([vehicle.model, vehicle.trimBadging, "VIN \(vehicle.vinSuffix)"].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
                Label(stateName, systemImage: stateIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(stateColor)
            }
            Spacer()
            ZStack {
                Circle().stroke(.secondary.opacity(0.25), lineWidth: 7)
                Circle().trim(from: 0, to: Double(min(100, max(0, vehicle.batteryLevel ?? 0))) / 100)
                    .stroke(batteryColor, style: .init(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(vehicle.batteryLevel.map { "\($0)%" } ?? "—").font(.headline.monospacedDigit())
            }
            .frame(width: 72, height: 72)
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: typeSize.isAccessibilitySize ? [.init(.flexible())] : [.init(.flexible()), .init(.flexible())], spacing: 12) {
            MetricCard(title: "预估续航", value: distance(vehicle.estBatteryRangeKm), icon: "road.lanes")
            MetricCard(title: "典型续航", value: distance(vehicle.idealBatteryRangeKm), icon: "bolt.fill")
            MetricCard(title: "车内温度", value: temperature(vehicle.insideTemp), icon: "thermometer.medium")
            MetricCard(title: "车外温度", value: temperature(vehicle.outsideTemp), icon: "sun.max.fill")
            MetricCard(title: "总里程", value: distance(vehicle.odometer), icon: "gauge.with.dots.needle.67percent")
            MetricCard(title: "固件", value: vehicle.version ?? "—", icon: "cpu")
            MetricCard(title: "车锁", value: vehicle.locked.map { $0 ? "已锁定" : "未锁定" } ?? "未知", icon: vehicle.locked.map { $0 ? "lock.fill" : "lock.open.fill" } ?? "questionmark.circle")
            MetricCard(title: "位置", value: vehicle.geofence ?? "未知", icon: "location.fill")
        }
    }

    private func distance(_ value: Double?) -> String { value.map { String(format: "%.1f km", $0) } ?? "—" }
    private func temperature(_ value: Double?) -> String { value.map { String(format: "%.1f ℃", $0) } ?? "—" }
    private var stateName: String { ["online": "在线", "asleep": "休眠", "offline": "离线", "driving": "行驶中", "charging": "充电中", "unavailable": "暂无数据", "suspended": "采集已暂停", "updating": "更新中"][vehicle.state ?? ""] ?? "状态未知" }
    private var stateIcon: String { ["online": "checkmark.circle.fill", "asleep": "moon.zzz.fill", "offline": "wifi.slash", "driving": "car.side.fill", "charging": "bolt.fill"][vehicle.state ?? ""] ?? "questionmark.circle" }
    private var stateColor: Color { vehicle.state == "online" ? .green : .secondary }
    private var batteryColor: Color { vehicle.batteryLevel.map { $0 < 20 ? .red : .green } ?? .secondary }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(14)
        .background(AppDesign.surface, in: .rect(cornerRadius: 18))
    }
}


@MainActor
struct HistoricalVehicleDashboard: View {
    let vehicle: Vehicle
    let client: APIClient
    let showDrives: () -> Void
    let showCharging: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VehicleIdentityCard(vehicle: vehicle, historical: true)
                FeatureHeading(title: "每段旅程，都有记录", subtitle: "回看走过的路线与每一次充电")
                VStack(spacing: 12) {
                    ActionCard(title: "行程记录", subtitle: "路线、里程与驾驶时间",
                               symbol: "point.topleft.down.curvedto.point.bottomright.up", action: showDrives)
                    ActionCard(title: "充电记录", subtitle: "补能、电量与功率曲线",
                               symbol: "bolt.fill", color: .teal, action: showCharging)
                }
                VehicleStatisticsView(client: client, carID: vehicle.id)
                RecentHistoryView(client: client, carID: vehicle.id)
                InlineNotice(title: "只看历史，从容回顾", message: "此模式隐藏实时状态，保留服务器上的记录。可在车辆菜单或设置中关闭，不会改变服务器采集。", symbol: "archivebox")
            }
            .padding(20)
        }
        .background(AppDesign.background)
    }
}

@MainActor
private struct RecentHistoryView: View {
    let client: APIClient
    let carID: Int
    @State private var drives: HistoryStore<DriveRecord>
    @State private var charges: HistoryStore<ChargingRecord>

    init(client: APIClient, carID: Int) {
        self.client = client
        self.carID = carID
        _drives = State(initialValue: HistoryStore(carID: carID) { filter, cursor in
            try await client.history(carID: carID, filter: filter, cursor: cursor)
        })
        _charges = State(initialValue: HistoryStore(carID: carID) { filter, cursor in
            try await client.history(carID: carID, filter: filter, cursor: cursor)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureHeading(title: "最近记录", subtitle: "按开始时间展示最近一次行程和充电")
            recentDrive
            recentCharge
        }
        .task {
            async let loadDrives: Void = drives.reload(filter: .all)
            async let loadCharges: Void = charges.reload(filter: .all)
            _ = await (loadDrives, loadCharges)
        }
    }

    private var recentDrive: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("最近行程", systemImage: "steeringwheel").font(.subheadline.weight(.semibold)).foregroundStyle(.blue)
            if let record = drives.items.first {
                NavigationLink {
                    DriveDetailView(client: client, carID: carID, id: record.id)
                } label: { HistoryRow(item: record) }.buttonStyle(.plain)
            } else if drives.isLoading { ProgressView("正在加载行程…") }
            else if let error = drives.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("重新加载行程") { Task { await drives.retry() } }
            } else { Text("还没有行程记录").foregroundStyle(.secondary) }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppDesign.surface, in: .rect(cornerRadius: 20))
    }

    private var recentCharge: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("最近充电", systemImage: "bolt.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.teal)
            if let record = charges.items.first {
                NavigationLink {
                    ChargingDetailView(client: client, carID: carID, id: record.id)
                } label: { HistoryRow(item: record) }.buttonStyle(.plain)
            } else if charges.isLoading { ProgressView("正在加载充电…") }
            else if let error = charges.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("重新加载充电") { Task { await charges.retry() } }
            } else { Text("还没有充电记录").foregroundStyle(.secondary) }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppDesign.surface, in: .rect(cornerRadius: 20))
    }
}
