import WidgetKit
import SwiftUI

// FEAT-10: SetAll Net Worth Widget
// Reads balances from App Group UserDefaults written by SyncService._writeWidgetData().

private let appGroup = "group.com.jafa.setall.app.widget"
private let teal = Color(red: 0.08, green: 0.72, blue: 0.64)   // #14B8A6
private let purple = Color(red: 0.545, green: 0.361, blue: 0.965) // #8B5CF6
private let green = Color(red: 0.133, green: 0.773, blue: 0.369)  // #22C55E
private let red = Color(red: 0.957, green: 0.247, blue: 0.369)    // #F43F5E

struct NetWorthEntry: TimelineEntry {
    let date: Date
    let currency: String
    let walletNet: Double
    let trueNet: Double
    let sharedOwed: Double
    let sharedOwe: Double
    let income: Double
    let expenses: Double
    let lastUpdated: String
}

struct NetWorthProvider: TimelineProvider {
    func placeholder(in context: Context) -> NetWorthEntry {
        NetWorthEntry(date: Date(), currency: "USD", walletNet: 0,
                      trueNet: 0, sharedOwed: 0, sharedOwe: 0,
                      income: 0, expenses: 0, lastUpdated: "")
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
        let d = UserDefaults(suiteName: appGroup)
        return NetWorthEntry(
            date: Date(),
            currency:    d?.string(forKey: "widget_currency")    ?? "USD",
            walletNet:   d?.double(forKey: "widget_net_worth")   ?? 0,
            trueNet:     d?.double(forKey: "widget_true_net")    ?? 0,
            sharedOwed:  d?.double(forKey: "widget_shared_owed") ?? 0,
            sharedOwe:   d?.double(forKey: "widget_shared_owe")  ?? 0,
            income:      d?.double(forKey: "widget_income")      ?? 0,
            expenses:    d?.double(forKey: "widget_expenses")    ?? 0,
            lastUpdated: d?.string(forKey: "widget_updated")     ?? ""
        )
    }
}

private func fmt(_ ccy: String, _ val: Double) -> String {
    String(format: "%@ %.2f", ccy, val)
}

struct SetAllWidgetEntryView: View {
    var entry: NetWorthEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    var smallView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("SetAll")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            Spacer()
            Text(fmt(entry.currency, entry.trueNet))
                .font(.title3.bold())
                .foregroundColor(entry.trueNet >= 0 ? teal : red)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("True Net Worth")
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Label(fmt(entry.currency, entry.walletNet), systemImage: "wallet.pass")
                    .font(.caption2)
                    .foregroundColor(purple)
                    .lineLimit(1)
            }
        }
        .padding()
        .containerBackground(.ultraThinMaterial, for: .widget)
        .widgetURL(URL(string: "com.jafa.setall.app://wallet")!)
    }

    var mediumView: some View {
        HStack(spacing: 12) {
            // Left: true net + wallet
            VStack(alignment: .leading, spacing: 4) {
                Text("SetAll")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(fmt(entry.currency, entry.trueNet))
                    .font(.title2.bold())
                    .foregroundColor(entry.trueNet >= 0 ? teal : red)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("True Net Worth")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Wallet: \(fmt(entry.currency, entry.walletNet))")
                    .font(.caption2)
                    .foregroundColor(purple)
            }
            Divider()
            // Right: income / expenses / owed / owe
            VStack(alignment: .leading, spacing: 5) {
                balanceRow(label: "Income",   value: entry.income,     color: green, prefix: "+")
                balanceRow(label: "Expenses", value: entry.expenses,   color: red,   prefix: "-")
                balanceRow(label: "Owed to you", value: entry.sharedOwed, color: green, prefix: "+")
                balanceRow(label: "You owe",     value: entry.sharedOwe,  color: red,   prefix: "-")
            }
            Spacer()
        }
        .padding()
        .containerBackground(.ultraThinMaterial, for: .widget)
        .widgetURL(URL(string: "com.jafa.setall.app://wallet/add")!)
    }

    func balanceRow(label: String, value: Double, color: Color, prefix: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(prefix)\(entry.currency) \(String(format: "%.2f", value))")
                .font(.caption2.bold())
                .foregroundColor(color)
        }
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
        .description("Your true net worth including shared balances.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
