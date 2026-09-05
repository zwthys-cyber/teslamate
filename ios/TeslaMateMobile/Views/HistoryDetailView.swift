import Charts
import MapKit
import SwiftUI

@MainActor
private struct RecordDetailView<Item: HistoryEntry, Content: View>: View {
    let client: APIClient
    let carID: Int
    let id: Int
    let title: String
    @ViewBuilder var content: (Item) -> Content
    @State private var record: Item?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label("详情加载失败", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(errorMessage).font(.subheadline)
                    Button("重试") { Task { await load() } }.disabled(isLoading)
                }
            }
            if let record {
                Section("时间") {
                    LabeledContent("开始", value: record.startDate.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("结束", value: record.endDate?.formatted(date: .abbreviated, time: .shortened) ?? "进行中")
                }
                content(record)
            } else if isLoading {
                ProgressView("正在加载详情…")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await client.detail(Item.self, id: id, carID: carID)
            try Task.checkCancellation()
            record = result
            errorMessage = nil
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
struct DriveDetailView: View {
    let client: APIClient
    let carID: Int
    let id: Int

    var body: some View {
        RecordDetailView(client: client, carID: carID, id: id, title: "行程详情") { (drive: DriveRecord) in
            Section("路线") {
                LabeledContent("起点", value: drive.title)
                LabeledContent("终点", value: drive.subtitle)
                DriveRouteMap(points: drive.positions ?? [])
            }
            Section("行程数据") {
                LabeledContent("里程", value: drive.primaryValue)
                LabeledContent("时长", value: drive.secondaryValue)
                LabeledContent("最高速度", value: HistoryFormat.number(drive.speedMax, unit: "km/h"))
                LabeledContent("平均外部温度", value: HistoryFormat.number(drive.outsideTempAvg, unit: "°C"))
            }
            if drive.sampling?.downsampled == true {
                Section { Text("长行程路线已简化，起点和终点保留。").font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct DriveRouteMap: View {
    let points: [TrackPoint]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .automatic

    private var coordinates: [CLLocationCoordinate2D] {
        points.filter(\.hasValidCoordinate).compactMap { point in
            guard let latitude = point.latitude, let longitude = point.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    var body: some View {
        let coordinates = coordinates
        if let first = coordinates.first, let last = coordinates.last {
            Map(position: $camera) {
                if coordinates.count > 1 { MapPolyline(coordinates: coordinates).stroke(.blue, lineWidth: 4) }
                Marker("起点", systemImage: "flag", coordinate: first).tint(.green)
                if coordinates.count > 1 { Marker("终点", systemImage: "flag.checkered", coordinate: last).tint(.red) }
            }
            .frame(height: 280)
            .clipShape(.rect(cornerRadius: 12))
            .accessibilityLabel("行程路线地图，包含起点和终点")
            Button("显示完整路线", systemImage: "arrow.up.left.and.arrow.down.right") {
                if reduceMotion { camera = .automatic }
                else { withAnimation(.easeInOut(duration: 0.2)) { camera = .automatic } }
            }
        } else {
            Label("这段行程没有可用的位置记录", systemImage: "map")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

@MainActor
struct ChargingDetailView: View {
    let client: APIClient
    let carID: Int
    let id: Int

    var body: some View {
        RecordDetailView(client: client, carID: carID, id: id, title: "充电详情") { (charge: ChargingRecord) in
            Section("充电数据") {
                LabeledContent("地点", value: charge.title)
                LabeledContent("时长", value: charge.secondaryValue)
                LabeledContent("起始电量", value: HistoryFormat.percent(charge.startBatteryLevel))
                LabeledContent("结束电量", value: HistoryFormat.percent(charge.endBatteryLevel))
                LabeledContent("充入电量", value: charge.primaryValue)
                LabeledContent("消耗电量", value: HistoryFormat.number(charge.energyUsedKwh, unit: "kWh"))
            }
            Section {
                LabeledContent("费用", value: HistoryFormat.cost(charge.cost))
            } footer: {
                Text(charge.cost == nil ? "本次费用尚未记录，不代表免费充电。" : "服务器未提供币种，金额保持原始计价单位。")
            }
            Section("充电功率") { ChargingPowerChart(samples: charge.samples ?? []) }
            if charge.sampling?.downsampled == true {
                Section { Text("较长的充电曲线已抽样，短时功率峰值可能未显示。").font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct ChargingPowerChart: View {
    let samples: [ChargingSample]
    private var values: [ChargingSample] { samples.filter { $0.chargerPower?.isFinite == true } }

    var body: some View {
        if values.isEmpty {
            Label("没有可用的功率记录", systemImage: "chart.xyaxis.line")
                .font(.subheadline).foregroundStyle(.secondary)
        } else {
            Chart(Array(values.enumerated()), id: \.offset) { _, sample in
                if let power = sample.chargerPower {
                    LineMark(x: .value("时间", sample.date), y: .value("功率（kW）", power))
                        .interpolationMethod(.linear)
                    if values.count == 1 {
                        PointMark(x: .value("时间", sample.date), y: .value("功率（kW）", power))
                    }
                }
            }
            .chartYAxisLabel("kW")
            .frame(height: 220)
            .accessibilityLabel("充电功率曲线")
            if let peak = values.compactMap(\.chargerPower).max() {
                Text("所示采样点最高功率：\(HistoryFormat.number(peak, unit: "kW"))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
