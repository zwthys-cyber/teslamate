import SwiftUI

struct RootView: View {
    @Environment(AppSession.self) private var session
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if !session.isConfigured {
                    ConnectionView()
                } else if session.vehicles.isEmpty && session.isLoading {
                    ProgressView("正在连接车辆…")
                } else if let vehicle = session.vehicles.first {
                    VehicleDashboard(vehicle: vehicle)
                } else {
                    ContentUnavailableView(
                        "暂时没有车辆数据",
                        systemImage: "car.side",
                        description: Text(session.errorMessage ?? "请检查 Tailscale 和服务器设置")
                    )
                }
            }
            .navigationTitle("TeslaMate")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("设置", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .sheet(isPresented: $showingSettings) { ConnectionView() }
            .task { await session.refresh() }
            .refreshable { await session.refresh() }
        }
    }
}
