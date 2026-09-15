import Charts
import MapKit
import SwiftUI

@MainActor
private struct RecordDetailView<Item: HistoryEntry, Content: View>: View {
    let client: APIClient
    let carID: Int
    let id: Int
    let title: String
    let showsSummary: Bool
    let showsTime: Bool
    @ViewBuilder var content: (Item) -> Content
    @State private var record: Item?
    @State private var errorMessage: String?
    @State private var isLoading = false

    init(client: APIClient, carID: Int, id: Int, title: String,
         showsSummary: Bool = true, showsTime: Bool = true,
         @ViewBuilder content: @escaping (Item) -> Content) {
        self.client = client
        self.carID = carID
        self.id = id
        self.title = title
        self.showsSummary = showsSummary
        self.showsTime = showsTime
        self.content = content
    }

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
                if showsSummary {
                    Section {
                        RecordSummaryCard(record: record)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                if showsTime {
                    Section("时间") {
                        LabeledContent("开始", value: record.startDate.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("结束", value: record.endDate?.formatted(date: .abbreviated, time: .shortened) ?? "进行中")
                    }
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
        RecordDetailView(client: client, carID: carID, id: id, title: "行程详情",
                         showsSummary: false, showsTime: false) { (drive: DriveRecord) in
            Section {
                DriveRouteMap(drive: drive)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            Section("路线") {
                RouteEndpointsCard(drive: drive)
            }
            if drive.sampling?.downsampled == true {
                Section { Text("长行程路线已简化，起点和终点保留。").font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct RouteEndpointsCard: View {
    let drive: DriveRecord

    var body: some View {
        VStack(spacing: 0) {
            endpoint(color: .green, label: "出发", value: drive.title, date: drive.startDate)
            HStack(spacing: 12) {
                Rectangle().fill(.secondary.opacity(0.22)).frame(width: 2, height: 22).padding(.leading, 5)
                Divider()
            }
            endpoint(color: .red, label: "到达", value: drive.subtitle, date: drive.endDate)
        }
        .accessibilityElement(children: .combine)
    }

    private func endpoint(color: Color, label: String, value: String, date: Date?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(color).frame(width: 12, height: 12).padding(.top, 5).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(date?.formatted(date: .omitted, time: .shortened) ?? "进行中")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct RouteSummaryPanel: View {
    let drive: DriveRecord

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 0) {
                metric("里程", drive.primaryValue)
                metric("时长", drive.secondaryValue)
                metric("最高", HistoryFormat.number(drive.speedMax, unit: "km/h"))
                metric("外温", HistoryFormat.number(drive.outsideTempAvg, unit: "°C"))
            }
            SpeedLegend()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct SpeedLegend: View {
    var body: some View {
        HStack(spacing: 5) {
            legendDot(RoutePalette.low, "慢")
            legendDot(RoutePalette.cruise, "巡航")
            legendDot(RoutePalette.fast, "快")
        }
        .accessibilityLabel("路线颜色表示速度，从青绿色低速、靛蓝色巡航到珊瑚色高速")
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
    }
}

private enum RoutePalette {
    static let low = Color(red: 0.20, green: 0.66, blue: 0.59)
    static let cruise = Color(red: 0.20, green: 0.35, blue: 0.72)
    static let fast = Color(red: 0.91, green: 0.47, blue: 0.32)
    static let halo = Color(red: 0.45, green: 0.83, blue: 0.84)
    static let wash = Color(red: 0.40, green: 0.78, blue: 0.78)
    static let ink = Color(red: 0.08, green: 0.20, blue: 0.31)
}

private func speedColor(_ speed: Double?) -> Color {
    guard let speed, speed.isFinite else { return .gray }
    if speed < 30 { return RoutePalette.low }
    if speed < 80 { return RoutePalette.cruise }
    return RoutePalette.fast
}

private struct DriveRouteMap: View {
    let drive: DriveRecord
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .automatic
    @State private var showsFullScreen = false

    private var points: [TrackPoint] { (drive.positions ?? []).filter(\.hasValidCoordinate) }

    var body: some View {
        if !points.isEmpty {
            ZStack(alignment: .bottom) {
                RouteMapCanvas(points: points, camera: $camera)
                RouteSummaryPanel(drive: drive)
                    .padding(12)
            }
            .frame(height: 360)

            HStack {
                Button("全屏路线", systemImage: "arrow.up.left.and.arrow.down.right") {
                    showsFullScreen = true
                }
                Spacer()
                Button("适合路线", systemImage: "scope") { fitRoute() }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .buttonStyle(.borderless)
            .fullScreenCover(isPresented: $showsFullScreen) {
                FullScreenRouteView(drive: drive,
                                    startName: drive.title,
                                    endName: drive.subtitle,
                                    downsampled: drive.sampling?.downsampled == true)
            }
        } else {
            Label("这段行程没有可用的位置记录", systemImage: "map")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func fitRoute() {
        if reduceMotion { camera = .automatic }
        else { withAnimation(.easeInOut(duration: 0.22)) { camera = .automatic } }
    }
}

private struct RouteMapCanvas: View {
    let points: [TrackPoint]
    @Binding var camera: MapCameraPosition

    private var coordinates: [CLLocationCoordinate2D] { points.compactMap(coordinate) }
    private var peakPoint: TrackPoint? {
        points.filter { $0.speed?.isFinite == true }.max { ($0.speed ?? 0) < ($1.speed ?? 0) }
    }

    var body: some View {
        ZStack {
            Map(position: $camera) {
                if let first = coordinates.first, let last = coordinates.last {
                    if coordinates.count > 1 {
                        MapPolyline(coordinates: coordinates)
                            .stroke(RoutePalette.halo.opacity(0.28),
                                    style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                        MapPolyline(coordinates: coordinates)
                            .stroke(.white.opacity(0.92),
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(routeSegments) { segment in
                        MapPolyline(coordinates: segment.coordinates)
                            .stroke(segment.color,
                                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                    Annotation(coordinates.count == 1 ? "记录位置" : "起点", coordinate: first) {
                        RouteEndpointMarker(symbol: "location.fill", color: RoutePalette.low)
                    }
                    if coordinates.count > 1 {
                        Annotation("终点", coordinate: last) {
                            RouteEndpointMarker(symbol: "flag.checkered", color: RoutePalette.fast)
                        }
                    }
                    if let peakPoint, let peakCoordinate = coordinate(peakPoint), let speed = peakPoint.speed {
                        Annotation("最高速度", coordinate: peakCoordinate, anchor: .bottom) {
                            RouteDataBubble(title: "最高", value: HistoryFormat.number(speed, unit: "km/h"))
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted,
                                pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls {
                MapCompass()
                MapScaleView()
            }

            RoutePalette.wash.opacity(0.055)
                .blendMode(.multiply)
                .allowsHitTesting(false)
        }
        .accessibilityLabel(coordinates.count == 1 ? "行程地图，仅有一个记录位置" : "行程路线地图，包含起点和终点")
    }

    private var routeSegments: [RouteSegment] {
        guard points.count > 1 else { return [] }
        return points.indices.dropFirst().compactMap { index in
            guard let previous = coordinate(points[index - 1]), let current = coordinate(points[index]) else { return nil }
            return RouteSegment(id: index, coordinates: [previous, current], color: speedColor(points[index].speed))
        }
    }

    private func coordinate(_ point: TrackPoint) -> CLLocationCoordinate2D? {
        guard let latitude = point.latitude, let longitude = point.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct RouteEndpointMarker: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
            .shadow(color: RoutePalette.ink.opacity(0.22), radius: 5, y: 2)
    }
}

private struct RouteDataBubble: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.bold()).monospacedDigit().foregroundStyle(RoutePalette.ink)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 1))
        .shadow(color: RoutePalette.ink.opacity(0.14), radius: 6, y: 2)
    }
}

private struct RouteSegment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
}

private struct FullScreenRouteView: View {
    let drive: DriveRecord
    let startName: String
    let endName: String
    let downsampled: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .automatic

    private var points: [TrackPoint] { (drive.positions ?? []).filter(\.hasValidCoordinate) }
    private var coordinates: [CLLocationCoordinate2D] {
        points.compactMap { point in
            guard let latitude = point.latitude, let longitude = point.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    var body: some View {
        NavigationStack {
            RouteMapCanvas(points: points, camera: $camera)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        RouteSummaryPanel(drive: drive)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { mapButton(forStart: true); mapButton(forStart: false) }
                            VStack(spacing: 8) { mapButton(forStart: true); mapButton(forStart: false) }
                        }
                        if downsampled {
                            Text("长行程路线已简化，起点和终点保留。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("重新显示完整路线", systemImage: "scope") {
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

    private func mapButton(forStart: Bool) -> some View {
        let coordinate = forStart ? coordinates.first : coordinates.last
        let name = forStart ? startName : endName
        return Button(forStart ? "在地图中查看起点" : "在地图中查看终点",
                      systemImage: forStart ? "location" : "flag.checkered") {
            guard let coordinate else { return }
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            item.name = name
            item.openInMaps()
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .buttonStyle(.bordered)
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
