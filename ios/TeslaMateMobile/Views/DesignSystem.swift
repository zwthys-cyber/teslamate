import SwiftUI

// Shared semantic surfaces stay readable in both system appearances.
enum AppDesign {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let accent = Color.blue
    static let charging = Color.teal
    static let hero = LinearGradient(colors: [Color(red: 0.06, green: 0.15, blue: 0.29),
                                               Color(red: 0.08, green: 0.28, blue: 0.43)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct FeatureHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SymbolTile: View {
    let symbol: String
    var color: Color = .blue
    var body: some View {
        Image(systemName: symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 46, height: 46)
            .background(color.opacity(0.12), in: .rect(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

struct ActionCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    var color: Color = .blue
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SymbolTile(symbol: symbol, color: color)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppDesign.surface, in: .rect(cornerRadius: 20))
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(title)
        .accessibilityElement(children: .combine)
    }
}

struct VehicleIdentityCard: View {
    let vehicle: Vehicle
    let historical: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label(historical ? "历史车辆" : "车辆档案", systemImage: historical ? "archivebox" : "car.side")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(vehicle.model ?? "Tesla")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.8))
            Text(vehicle.name).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 74, weight: .light))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(.white.opacity(0.9))
                    .accessibilityHidden(true)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("车辆识别码后六位").font(.caption).foregroundStyle(.white.opacity(0.75))
                    Text(vehicle.vinSuffix).font(.subheadline.monospaced().weight(.semibold))
                }
                Spacer()
                if let trim = vehicle.trimBadging, !trim.isEmpty {
                    Text(trim).font(.subheadline).multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(24)
        .foregroundStyle(.white)
        .background(AppDesign.hero, in: .rect(cornerRadius: 26))
    }
}

struct InlineNotice: View {
    let title: String
    let message: String
    var symbol = "info.circle"
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppDesign.surface, in: .rect(cornerRadius: 18))
    }
}
