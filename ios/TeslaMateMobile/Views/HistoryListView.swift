import SwiftUI

@MainActor
struct HistoryListView<Item: HistoryEntry>: View {
    let client: APIClient
    let carID: Int
    let title: String
    @State private var store: HistoryStore<Item>
    @State private var filter = HistoryFilter.all
    @State private var showingFilter = false

    init(client: APIClient, carID: Int, title: String) {
        self.client = client
        self.carID = carID
        self.title = title
        _store = State(initialValue: HistoryStore(carID: carID) { filter, cursor in
            try await client.history(carID: carID, filter: filter, cursor: cursor)
        })
    }

    var body: some View {
        List {
            Section {
                Button { showingFilter = true } label: {
                    Label(filterDescription, systemImage: "calendar")
                }
            }
            if let error = store.errorMessage {
                Section {
                    Label(store.items.isEmpty ? "加载失败" : "加载失败，保留上次记录", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    Button("重试") { Task { await store.retry() } }
                        .disabled(store.isLoading)
                }
            }
            if store.items.isEmpty {
                if store.isLoading {
                    ProgressView("正在加载记录…")
                } else if store.hasLoaded && store.errorMessage == nil {
                    ContentUnavailableView("没有记录", systemImage: "calendar.badge.minus",
                                           description: Text("这辆车在所选时间内没有记录，可以调整日期范围。"))
                }
            } else {
                Section {
                    ForEach(store.items, id: \.id) { item in
                        NavigationLink {
                            if Item.resource == DriveRecord.resource {
                                DriveDetailView(client: client, carID: carID, id: item.id)
                            } else {
                                ChargingDetailView(client: client, carID: carID, id: item.id)
                            }
                        } label: { HistoryRow(item: item) }
                    }
                }
                Section {
                    if store.isLoading {
                        ProgressView("正在加载…")
                    } else if store.nextCursor != nil {
                        Button("加载更多") { Task { await store.loadMore() } }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        Text("已显示全部记录").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { VehiclePicker() }
            ToolbarItem(placement: .topBarTrailing) {
                Button("筛选日期", systemImage: "line.3.horizontal.decrease.circle") { showingFilter = true }
            }
        }
        .sheet(isPresented: $showingFilter) {
            HistoryDateFilterView(filter: filter) { filter = $0 }
        }
        .task(id: filter) { await store.reload(filter: filter) }
        .refreshable { await store.reload(filter: filter) }
    }

    private var filterDescription: String {
        guard let from = filter.from, let to = filter.to else { return "全部时间" }
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: to) ?? to
        return "\(from.formatted(date: .abbreviated, time: .omitted)) – \(lastDay.formatted(date: .abbreviated, time: .omitted))"
    }
}

private struct HistoryRow<Item: HistoryEntry>: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.startDate.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(.secondary)
            Text(item.title).font(.headline)
            Label(item.subtitle, systemImage: Item.resource == "drives" ? "arrow.down" : "battery.100percent")
                .font(.subheadline).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack { Text(item.primaryValue); Spacer(); Text(item.secondaryValue) }
                VStack(alignment: .leading, spacing: 4) { Text(item.primaryValue); Text(item.secondaryValue) }
            }
            .font(.subheadline.monospacedDigit())
            if item.endDate == nil {
                Text("进行中，记录尚未结束").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryDateFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var from: Date
    @State private var through: Date
    let apply: (HistoryFilter) -> Void

    init(filter: HistoryFilter, apply: @escaping (HistoryFilter) -> Void) {
        self.apply = apply
        _enabled = State(initialValue: filter.from != nil)
        _from = State(initialValue: filter.from ?? Calendar.current.date(byAdding: .day, value: -30, to: .now)!)
        _through = State(initialValue: filter.to.flatMap { Calendar.current.date(byAdding: .day, value: -1, to: $0) } ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Toggle("按日期筛选", isOn: $enabled)
                if enabled {
                    DatePicker("开始日期", selection: $from, displayedComponents: .date)
                    DatePicker("结束日期", selection: $through, in: from..., displayedComponents: .date)
                }
                Section {
                    Text("按记录开始时间筛选，包含结束日期当天。日期使用手机当前时区。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("筛选日期")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        apply(enabled ? .days(from: from, through: max(from, through)) : .all)
                        dismiss()
                    }
                }
            }
            .onChange(of: from) { _, value in if through < value { through = value } }
        }
    }
}
