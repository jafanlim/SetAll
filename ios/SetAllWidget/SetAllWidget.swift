import WidgetKit
import SwiftUI

// FEAT-10: SetAll Net Worth Widget
// Reads net worth from App Group UserDefaults written by SyncService._writeWidgetData().
// To add to Xcode: File → New → Target → Widget Extension → name: SetAllWidget

struct NetWorthEntry: TimelineEntry {
    let date: Date
    let netWorth: String
    let currency: String
    let lastUpdated: String
}

struct NetWorthProvider: TimelineProvider {
    let appGroup = "group.com.jafa.setall.app.widget"

    func placeholder(in context: Context) -> NetWorthEntry {
        NetWorthEntry(date: Date(), netWorth: "0.00", currency: "USD", lastUpdated: "")
    }

    func getSnapshot(in context: Context, completion: @escaping (NetWorthEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NetWorthEntry>) -> Void) {
        let e = entry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [e], policy: .after(nextUpdate)))
    }

    private func entry() -> NetWorthEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        let raw = defaults?.double(forKey: "widget_net_worth") ?? 0
        let currency = defaults?.string(forKey: "widget_currency") ?? "USD"
        let updated = defaults?.string(forKey: "widget_updated") ?? ""
        let formatted = String(format: "%@ %.2f", currency, raw)
        return NetWorthEntry(date: Date(), netWorth: formatted,
                             currency: currency, lastUpdated: updated)
    }
}

struct SetAllWidgetEntryView: View {
    var entry: NetWorthEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("SetAll")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            Spacer()
            Text(entry.netWorth)
                .font(.title2.bold())
                .foregroundColor(Color(red: 0.08, green: 0.72, blue: 0.64)) // teal #14B8A6
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("Net Worth")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .containerBackground(.ultraThinMaterial, for: .widget)
    }
}

@main
struct SetAllWidget: Widget {
    let kind = "SetAllWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NetWorthProvider()) { entry in
            SetAllWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Net Worth")
        .description("Your current net worth at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
