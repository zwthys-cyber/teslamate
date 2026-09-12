import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    SymbolTile(symbol: "car.side.fill")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TeslaMate").font(.title2.bold())
                        Text("你的车辆记录，随时回看").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
            }
            Section("服务器") {
                NavigationLink { ConnectionView() } label: {
                    Label("管理连接", systemImage: "network")
                }
                LabeledContent("地址", value: URL(string: session.serverURL)?.host ?? session.serverURL)
                    .font(.subheadline)
                Label(session.errorMessage == nil ? "已保存连接" : "最近请求失败，请检查连接",
                      systemImage: session.errorMessage == nil ? "checkmark.shield" : "exclamationmark.triangle")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let vehicle = session.selectedVehicle {
                Section {
                    LabeledContent("当前车辆", value: vehicle.name)
                    Toggle(isOn: Binding(get: { session.isHistoricalVehicle }, set: { session.setHistoricalVehicle($0) })) {
                        Label("历史车辆模式", systemImage: "archivebox")
                    }
                } header: { Text("车辆显示") } footer: {
                    Text("适用于已出售或不再查看实时状态的车辆。设置只保存在本机，不删除记录，也不停止服务器采集。")
                }
            }
            Section("使用说明") {
                DisclosureGroup("数据与时间") {
                    Text("App 获取时间代表服务器响应时间，不代表车辆采样时间。未知电量、车锁、费用等不会用零值代替。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                DisclosureGroup("历史与地图") {
                    Text("日期按手机时区筛选。长路线可能经过抽样；详情中的全屏路线可缩放和拖动。地图使用苹果 MapKit，数据来源随地区而异。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                DisclosureGroup("隐私与连接") {
                    Text("访问令牌保存在本机钥匙串。断开连接会清除凭据；服务器上的车辆记录不会被删除。使用私网服务器时，请保持对应网络连接。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("版本", value: version)
                Text("独立客户端，与 Tesla 官方无关联。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设置")
    }

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "—") (\(info["CFBundleVersion"] as? String ?? "—"))"
    }
}
