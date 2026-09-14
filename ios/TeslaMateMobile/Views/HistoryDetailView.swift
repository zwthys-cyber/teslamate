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
                JourneySketchCard(drive: drive)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                RouteEndpointsCard(start: drive.title, end: drive.subtitle)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                DriveRouteMap(drive: drive)
            }
            Section("行程数据") {
                DriveMetricsGrid(drive: drive)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if drive.sampling?.downsampled == true {
                Section { Text("长行程路线已简化，起点和终点保留。").font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct JourneySketchCard: View {
    let drive: DriveRecord
    @Environment(\.colorScheme) private var colorScheme

    private var paper: Color {
        colorScheme == .dark ? Color(red: 0.12, green: 0.13, blue: 0.15) : Color(red: 0.98, green: 0.96, blue: 0.89)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("TRIP NOTES")
                    .font(.caption.weight(.black))
                    .tracking(2.2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(drive.startDate.formatted(.dateTime.month().day()))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(Capsule().stroke(.orange, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    .foregroundStyle(.orange)
            }

            RouteDoodle()
                .frame(height: 112)
                .accessibilityHidden(true)

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("这次旅程")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(drive.primaryValue)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                }
                Spacer()
                Label(drive.secondaryValue, systemImage: "clock")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(20)
        .background(paper, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(.primary.opacity(0.16), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        }
        .rotationEffect(.degrees(-0.35))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("旅程手账，\(drive.primaryValue)，\(drive.secondaryValue)")
    }
}

private struct RouteDoodle: View {
    var body: some View {
        Canvas { context, size in
            let start = CGPoint(x: size.width * 0.08, y: size.height * 0.76)
            let end = CGPoint(x: size.width * 0.91, y: size.height * 0.22)
            var route = Path()
            route.move(to: start)
            route.addCurve(to: CGPoint(x: size.width * 0.48, y: size.height * 0.58),
                           control1: CGPoint(x: size.width * 0.18, y: size.height * 0.24),
                           control2: CGPoint(x: size.width * 0.34, y: size.height * 0.98))
            route.addCurve(to: end,
                           control1: CGPoint(x: size.width * 0.67, y: size.height * 0.18),
                           control2: CGPoint(x: size.width * 0.77, y: size.height * 0.53))
            context.stroke(route, with: .color(.blue.opacity(0.22)),
                           style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            context.stroke(route, with: .color(.blue),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [8, 7]))

            context.fill(Path(ellipseIn: CGRect(x: start.x - 7, y: start.y - 7, width: 14, height: 14)), with: .color(.green))
            context.stroke(Path(ellipseIn: CGRect(x: end.x - 8, y: end.y - 8, width: 16, height: 16)),
                           with: .color(.red), lineWidth: 4)

            var car = context.resolve(Image(systemName: "car.side.fill"))
            car.shading = .color(.primary)
            context.draw(car, at: CGPoint(x: size.width * 0.56, y: size.height * 0.42), anchor: .center)
        }
    }
}

private struct RouteEndpointsCard: View {
    let start: String
    let end: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 3) {
                Circle().fill(.green).frame(width: 10, height: 10)
                Rectangle().fill(.secondary.opacity(0.3)).frame(width: 2, height: 38)
                Circle().strokeBorder(.red, lineWidth: 3).frame(width: 10, height: 10)
            }
            .padding(.top, 6)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 14) {
                endpoint(label: "出发", value: start)
                Divider()
                endpoint(label: "到达", value: end)
            }
        }
        .padding(18)
        .background(AppDesign.surface, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .accessibilityElement(children: .combine)
    }

    private func endpoint(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DriveMetricsGrid: View {
    let drive: DriveRecord
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            DriveMetricTile(title: "里程", value: drive.primaryValue, symbol: "road.lanes")
            DriveMetricTile(title: "时长", value: drive.secondaryValue, symbol: "clock")
            DriveMetricTile(title: "最高速度", value: HistoryFormat.number(drive.speedMax, unit: "km/h"), symbol: "speedometer")
            DriveMetricTile(title: "平均外温", value: HistoryFormat.number(drive.outsideTempAvg, unit: "°C"), symbol: "thermometer.medium")
        }
    }
}

private struct DriveMetricTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(14)
        .background(AppDesign.surface, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DriveRouteMap: View {
    let drive: DriveRecord
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .automatic
    @State private var showsFullScreen = false

    private var coordinates: [CLLocationCoordinate2D] {
        (drive.positions ?? []).filter(\.hasValidCoordinate).compactMap { point in
            guard let latitude = point.latitude, let longitude = point.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    var body: some View {
        let coordinates = coordinates
        if !coordinates.isEmpty {
            ZStack(alignment: .bottomLeading) {
                RouteMapCanvas(coordinates: coordinates, camera: $camera)
                LinearGradient(colors: [.clear, .black.opacity(0.52)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                HStack(spacing: 8) {
                    Label(drive.primaryValue, systemImage: "road.lanes")
                    Label(drive.secondaryValue, systemImage: "clock")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(12)
            }
            .frame(height: 300)
            .clipShape(.rect(cornerRadius: 16))

            HStack {
                Button("全屏路线", systemImage: "arrow.up.left.and.arrow.down.right") {
                    showsFullScreen = true
                }
                Spacer()
                Button("适合路线", systemImage: "scope") { fitRoute() }
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.borderless)
            .fullScreenCover(isPresented: $showsFullScreen) {
                FullScreenRouteView(coordinates: coordinates,
                                    startName: drive.title,
                                    endName: drive.subtitle,
                                    distance: drive.primaryValue,
                                    duration: drive.secondaryValue,
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
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .accessibilityLabel(coordinates.count == 1 ? "行程地图，仅有一个记录位置" : "行程路线地图，包含起点和终点")
    }
}

private struct FullScreenRouteView: View {
    let coordinates: [CLLocationCoordinate2D]
    let startName: String
    let endName: String
    let distance: String
    let duration: String
    let downsampled: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            RouteMapCanvas(coordinates: coordinates, camera: $camera)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 18) {
                            Label(distance, systemImage: "road.lanes")
                            Label(duration, systemImage: "clock")
                        }
                        .font(.subheadline.weight(.semibold))
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
