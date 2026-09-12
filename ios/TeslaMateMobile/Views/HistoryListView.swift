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
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        SymbolTile(symbol: Item.resource == "drives" ? "steeringwheel" : "bolt.fill",
                                   color: Item.resource == "drives" ? .blue : .teal)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Item.resource == "drives" ? "每段旅程，清晰可见" : "每次补能，心中有数").font(.headline)
                            Text("已加载 \(store.items.count) 条记录")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Button { showingFilter = true } label: {
                        HStack {
                            Label(filterDescription, systemImage: "calendar")
                            Spacer()
                            Image(systemName: "slider.horizontal.3")
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(12)
                        .background(AppDesign.accent.opacity(0.08), in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("筛选日期，\(filterDescription)")
                }
                .padding(.vertical, 8)
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
                ForEach(months, id: \.self) { month in
                    Section(month.formatted(.dateTime.year().month(.wide))) {
                        ForEach(records(in: month), id: \.id) { item in
                            NavigationLink {
                                if Item.resource == DriveRecord.resource {
                                    DriveDetailView(client: client, carID: carID, id: item.id)
                                } else {
                                    ChargingDetailView(client: client, carID: carID, id: item.id)
                                }
                            } label: { HistoryRow(item: item) }
                        }
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
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { VehiclePicker() }
        }
        .sheet(isPresented: $showingFilter) {
            HistoryDateFilterView(filter: filter) { filter = $0 }
        }
        .task(id: filter) { await store.reload(filter: filter) }
        .refreshable { await store.reload(filter: filter) }
    }

    private var months: [Date] {
        Array(Set(store.items.map { monthStart($0.startDate) })).sorted(by: >)
    }

    private func monthStart(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }

    private func records(in month: Date) -> [Item] {
        store.items.filter { monthStart($0.startDate) == month }
    }

    private var filterDescription: String {
        guard let from = filter.from, let to = filter.to else { return "全部时间" }
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: to) ?? to
        return "\(from.formatted(date: .abbreviated, time: .omitted)) – \(lastDay.formatted(date: .abbreviated, time: .omitted))"
    }
}

struct HistoryRow<Item: HistoryEntry>: View {
    let item: Item
    private var isDrive: Bool { Item.resource == "drives" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if item.endDate == nil {
                    Text("进行中").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Label(item.title, systemImage: isDrive ? "circle.fill" : "mappin.circle.fill")
                    .font(.headline).foregroundStyle(.primary)
                Label(item.subtitle, systemImage: isDrive ? "flag.checkered" : "battery.100percent")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { primary; secondary }
                VStack(alignment: .leading, spacing: 8) { primary; secondary }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var primary: some View {
        Text(item.primaryValue).font(.title3.weight(.semibold)).monospacedDigit()
            .foregroundStyle(isDrive ? AppDesign.accent : AppDesign.charging)
    }
    private var secondary: some View {
        Label(item.secondaryValue, systemImage: "clock")
            .font(.subheadline).foregroundStyle(.secondary)
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
