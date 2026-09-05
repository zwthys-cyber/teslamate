import SwiftUI

@MainActor
struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !session.isConfigured {
                NavigationStack { ConnectionView() }
            } else {
                TabView {
                    NavigationStack {
                        overview
                            .navigationTitle("车辆")
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) { VehiclePicker() }
                            }
                            .refreshable { await session.refresh() }
                    }
                    .tabItem { Label("车辆", systemImage: "car.side") }

                    NavigationStack {
                        if let vehicle = session.selectedVehicle {
                            HistoryListView<DriveRecord>(client: client, carID: vehicle.id, title: "行程")
                        } else { noVehicle }
                    }
                    .id("drives-\(session.selectedVehicleID ?? 0)")
                    .tabItem { Label("行程", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }

                    NavigationStack {
                        if let vehicle = session.selectedVehicle {
                            HistoryListView<ChargingRecord>(client: client, carID: vehicle.id, title: "充电")
                        } else { noVehicle }
                    }
                    .id("charging-\(session.selectedVehicleID ?? 0)")
                    .tabItem { Label("充电", systemImage: "bolt") }

                    NavigationStack { ConnectionView() }
                        .tabItem { Label("设置", systemImage: "gearshape") }
                }
                .id(session.connectionID)
            }
        }
        .task { await session.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await session.refresh() } }
        }
    }

    private var client: APIClient { APIClient(serverURL: session.serverURL, token: session.token) }

    private var overview: some View {
        VStack(spacing: 0) {
            connectionStatus
            if session.vehicles.isEmpty && session.isLoading {
                ProgressView("正在连接车辆…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let vehicle = session.selectedVehicle {
                VehicleDashboard(vehicle: vehicle).id(vehicle.id)
            } else {
                ContentUnavailableView {
                    Label(session.errorMessage == nil ? "暂时没有车辆数据" : "无法获取车辆数据", systemImage: "car.side")
                } description: {
                    Text(session.errorMessage ?? "服务器已连接，尚未记录车辆。")
                } actions: {
                    Button("重试") { Task { await session.refresh() } }
                }
            }
        }
    }

    private var noVehicle: some View {
        ContentUnavailableView("尚未选择车辆", systemImage: "car.side",
                               description: Text("请先在车辆页面获取车辆数据。"))
    }

    private var connectionStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = session.errorMessage, !session.vehicles.isEmpty {
                Label("刷新失败，当前显示上次数据", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error).foregroundStyle(.secondary)
                Button("重试") { Task { await session.refresh() } }
                    .disabled(session.isLoading)
            }
            if let receivedAt = session.lastReceivedAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("上次获取：\(receivedAt.formatted(date: .omitted, time: .standard))")
                        if context.date.timeIntervalSince(receivedAt) > 120 {
                            Text("已有一段时间未刷新，下拉获取最新记录。")
                        }
                    }
                }
                Text("车辆采样时间未知，显示的是服务器保存的最近状态。")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

@MainActor
struct VehiclePicker: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        if session.vehicles.count > 1 {
            Menu {
                Picker("车辆", selection: Binding(get: { session.selectedVehicleID }, set: { value in
                    if let value { session.selectVehicle(value) }
                })) {
                    ForEach(session.vehicles) { vehicle in
                        Text("\(vehicle.name) · \(vehicle.vinSuffix)").tag(Optional(vehicle.id))
                    }
                }
            } label: {
                Label(session.selectedVehicle?.name ?? "选择车辆", systemImage: "car.2")
                    .lineLimit(1)
            }
            .accessibilityLabel("切换车辆，当前\(session.selectedVehicle?.name ?? "未选择")")
        }
    }
}
