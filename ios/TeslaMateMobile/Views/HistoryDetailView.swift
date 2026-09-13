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
                Section {
                    RecordSummaryCard(record: record)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                Section("时间") {
                    LabeledContent("开始", value: record.startDate.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("结束", value: record.endDate?.formatted(date: .abbreviated, time: .shortened) ?? "进行中")
                }
                content(record)
            } else if isLoading {
                ProgressView("正在加载详情…")
            }
        }
        .listStyle(.insetGrouped)
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

private struct RecordSummaryCard<Item: HistoryEntry>: View {
    let record: Item
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(Item.resource == "drives" ? "行程回顾" : "充电回顾",
                  systemImage: Item.resource == "drives" ? "steeringwheel" : "bolt.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            Text(record.primaryValue).font(.largeTitle.bold()).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Label(record.secondaryValue, systemImage: "clock")
                .font(.subheadline)
            if record.endDate == nil { Text("进行中 · 数据尚未完整").font(.footnote) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .foregroundStyle(.white)
        .background(AppDesign.hero, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
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
                DriveRouteMap(points: drive.positions ?? [], downsampled: drive.sampling?.downsampled == true)
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
    let downsampled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .automatic
    @State private var showsFullScreen = false

    private var coordinates: [CLLocationCoordinate2D] {
        points.filter(\.hasValidCoordinate).compactMap { point in
            guard let latitude = point.latitude, let longitude = point.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    var body: some View {
        let coordinates = coordinates
        if !coordinates.isEmpty {
            RouteMapCanvas(coordinates: coordinates, camera: $camera)
                .frame(height: 280)
                .clipShape(.rect(cornerRadius: 12))
            Button("全屏查看路线", systemImage: "arrow.up.left.and.arrow.down.right") {
                showsFullScreen = true
            }
            .accessibilityHint("打开可缩放和拖动的全屏行程地图")
            .fullScreenCover(isPresented: $showsFullScreen) {
                FullScreenRouteView(coordinates: coordinates, downsampled: downsampled)
            }
            Button("显示完整路线", systemImage: "scope") {
                if reduceMotion { camera = .automatic }
                else { withAnimation(.easeInOut(duration: 0.2)) { camera = .automatic } }
            }
        } else {
            Label("这段行程没有可用的位置记录", systemImage: "map")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct RouteMapCanvas: View {
    let coordinates: [CLLocationCoordinate2D]
    @Binding var camera: MapCameraPosition

    var body: some View {
        Map(position: $camera) {
            if let first = coordinates.first, let last = coordinates.last {
                if coordinates.count > 1 { MapPolyline(coordinates: coordinates).stroke(.blue, lineWidth: 4) }
                Marker(coordinates.count == 1 ? "记录位置" : "起点", systemImage: "flag", coordinate: first).tint(.green)
                if coordinates.count > 1 { Marker("终点", systemImage: "flag.checkered", coordinate: last).tint(.red) }
            }
        }
        .accessibilityLabel(coordinates.count == 1 ? "行程地图，仅有一个记录位置" : "行程路线地图，包含起点和终点")
    }
}

private struct FullScreenRouteView: View {
    let coordinates: [CLLocationCoordinate2D]
    let downsampled: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            RouteMapCanvas(coordinates: coordinates, camera: $camera)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 8) {
                        if downsampled {
                            Text("长行程路线已简化，起点和终点保留。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("显示完整路线", systemImage: "scope") {
                            if reduceMotion { camera = .automatic }
                            else { withAnimation(.easeInOut(duration: 0.2)) { camera = .automatic } }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                }
                .navigationTitle("行程路线")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭") { dismiss() }
                            .accessibilityHint("返回行程详情")
                    }
                }
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
