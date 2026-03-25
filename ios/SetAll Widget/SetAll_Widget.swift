import WidgetKit
import SwiftUI

private let appGroup  = "group.com.jafa.setall.app.widget"
private let urlScheme = "com.jafa.setall.app"
private let teal   = Color(red: 0.082, green: 0.722, blue: 0.639)
private let bgDark = Color(red: 0.059, green: 0.090, blue: 0.165)

// MARK: — Data model

struct WidgetData {
    struct RecentEntry { let desc: String; let amount: Double; let isIncome: Bool }

    let netWorth: Double
    let income:   Double
    let expenses: Double
    let currency: String
    let recent:   [RecentEntry]

    static func load() -> WidgetData {
        let d = UserDefaults(suiteName: appGroup)
        var entries: [RecentEntry] = []
        for i in 1...3 {
            let desc   = d?.string(forKey: "widget_entry_\(i)_desc")   ?? ""
            let amount = d?.double(forKey: "widget_entry_\(i)_amount") ?? 0
            let income = d?.bool(  forKey: "widget_entry_\(i)_income") ?? false
            if !desc.isEmpty || amount > 0 {
                entries.append(RecentEntry(desc: desc, amount: amount, isIncome: income))
            }
        }
        return WidgetData(
            netWorth: d?.double(forKey: "widget_net_worth") ?? 0,
            income:   d?.double(forKey: "widget_income")    ?? 0,
            expenses: d?.double(forKey: "widget_expenses")  ?? 0,
            currency: d?.string(forKey: "widget_currency")  ?? "USD",
            recent:   entries
        )
    }

    func fmt(_ v: Double) -> String { String(format: "%@ %.2f", currency, v) }
    var netColor: Color { netWorth >= 0 ? teal : .red }
}

struct SAEntry: TimelineEntry { let date: Date; let data: WidgetData }

// MARK: — Provider

struct SAProvider: TimelineProvider {
    func placeholder(in context: Context) -> SAEntry {
        SAEntry(date: Date(), data: WidgetData(
            netWorth: 1234.56, income: 2000, expenses: 765.44, currency: "USD",
            recent: [
                .init(desc: "Coffee",    amount: 4.50,  isIncome: false),
                .init(desc: "Salary",    amount: 1500,  isIncome: true),
                .init(desc: "Groceries", amount: 45.20, isIncome: false),
            ]))
    }
    func getSnapshot(in context: Context, completion: @escaping (SAEntry) -> Void) {
        completion(SAEntry(date: Date(), data: .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SAEntry>) -> Void) {
        let e = SAEntry(date: Date(), data: .load())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [e], policy: .after(next)))
    }
}

// MARK: — Shared action buttons

struct ActionButtons: View {
    var body: some View {
        HStack(spacing: 8) {
            Link(destination: URL(string: "\(urlScheme)://add-expense")!) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                    Text("Expense")
                }
                .font(.caption.bold())
                .foregroundColor(bgDark)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(teal)
                .cornerRadius(8)
            }
            Link(destination: URL(string: "\(urlScheme)://wallet/add")!) {
                HStack(spacing: 4) {
                    Image(systemName: "wallet.pass.fill")
                    Text("Wallet")
                }
                .font(.caption.bold())
                .foregroundColor(teal)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(teal.opacity(0.15))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(teal.opacity(0.5), lineWidth: 1))
            }
            Spacer()
        }
    }
}

// MARK: — Medium widget (2×4)

struct MediumView: View {
    let data: WidgetData
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SetAll").font(.caption2.weight(.bold)).foregroundColor(teal)
                Spacer()
                Text("Net Worth").font(.caption2).foregroundColor(.secondary)
            }
            Text(data.fmt(data.netWorth))
                .font(.title2.bold()).foregroundColor(data.netColor)
                .minimumScaleFactor(0.6).lineLimit(1)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Income").font(.caption2).foregroundColor(.secondary)
                    Text(data.fmt(data.income)).font(.caption.bold()).foregroundColor(.green)
                        .minimumScaleFactor(0.7).lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Expenses").font(.caption2).foregroundColor(.secondary)
                    Text(data.fmt(data.expenses)).font(.caption.bold()).foregroundColor(.red)
                        .minimumScaleFactor(0.7).lineLimit(1)
                }
                Spacer()
            }
            Spacer()
            ActionButtons()
        }
        .padding(14)
        .containerBackground(bgDark, for: .widget)
    }
}

// MARK: — Large widget (2×4 tall)

struct LargeView: View {
    let data: WidgetData
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("SetAll").font(.caption2.weight(.bold)).foregroundColor(teal)
                Spacer()
                Text("Wallet summary").font(.caption2).foregroundColor(.secondary)
            }.padding(.bottom, 8)

            // Net worth hero
            Text(data.fmt(data.netWorth))
                .font(.largeTitle.bold()).foregroundColor(data.netColor)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text("Net Worth").font(.caption).foregroundColor(.secondary)
                .padding(.bottom, 12)

            // Income / expenses row
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(data.fmt(data.income), systemImage: "arrow.down.circle.fill")
                        .font(.caption.bold()).foregroundColor(.green).lineLimit(1)
                    Text("Income").font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Label(data.fmt(data.expenses), systemImage: "arrow.up.circle.fill")
                        .font(.caption.bold()).foregroundColor(.red).lineLimit(1)
                    Text("Expenses").font(.caption2).foregroundColor(.secondary)
                }
            }.padding(.bottom, 12)

            // Divider
            Rectangle().fill(teal.opacity(0.2)).frame(height: 1).padding(.bottom, 8)

            // Recent entries
            Text("Recent").font(.caption2.weight(.semibold)).foregroundColor(.secondary)
                .padding(.bottom, 4)
            ForEach(Array(data.recent.enumerated()), id: \.offset) { _, e in
                HStack {
                    Image(systemName: e.isIncome ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.caption).foregroundColor(e.isIncome ? .green : .red)
                    Text(e.desc.isEmpty ? "Entry" : e.desc)
                        .font(.caption).foregroundColor(.white).lineLimit(1)
                    Spacer()
                    Text(String(format: "%@%.2f", e.isIncome ? "+" : "-", e.amount))
                        .font(.caption.bold())
                        .foregroundColor(e.isIncome ? .green : .red)
                }.padding(.vertical, 2)
            }
            if data.recent.isEmpty {
                Text("No entries yet — open the app to sync")
                    .font(.caption2).foregroundColor(.secondary)
            }

            Spacer()
            ActionButtons()
        }
        .padding(14)
        .containerBackground(bgDark, for: .widget)
    }
}

// MARK: — Entry view dispatcher

struct SetAllWidgetEntryView: View {
    var entry: SAEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        switch family {
        case .systemLarge: LargeView(data: entry.data)
        default:           MediumView(data: entry.data)
        }
    }
}

// MARK: — Widget declaration

struct SetAllWidget: Widget {
    let kind = "SetAllWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SAProvider()) { entry in
            SetAllWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("SetAll")
        .description("Wallet summary and quick actions.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
