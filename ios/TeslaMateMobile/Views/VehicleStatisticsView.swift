import SwiftUI

@MainActor
struct VehicleStatisticsView: View {
    let client: APIClient
    let carID: Int
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var statistics: VehicleStatistics?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureHeading(title: "累计记录", subtitle: "这辆车的全部已结束记录")
            if let statistics {
                LazyVGrid(columns: typeSize.isAccessibilitySize ? [.init(.flexible())] : [.init(.flexible()), .init(.flexible())], spacing: 12) {
                    metric("行程次数", value: "\(statistics.driving.count)", symbol: "steeringwheel")
                    metric("已记录里程", value: statistics.distance, symbol: "road.lanes")
                    metric("充电次数", value: "\(statistics.charging.count)", symbol: "bolt.fill")
                    metric("已记录补能", value: statistics.energy, symbol: "battery.100percent")
                }
                Text("仅汇总已记录的数值，不包含进行中的记录。缺少统计口径时显示横线。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if loading { ProgressView("正在读取统计…") }
            if let error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("重新加载统计") { Task { await load() } }.disabled(loading)
            }
        }
        .task { await load() }
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit().fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppDesign.surface, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await client.statistics(carID: carID)
            try Task.checkCancellation()
            statistics = result
            error = nil
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }
}
