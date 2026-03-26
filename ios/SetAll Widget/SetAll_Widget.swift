import WidgetKit
import SwiftUI

private let appGroup  = "group.com.jafa.setall.app.widget"
private let urlScheme = "com.jafa.setall.app"
private let teal   = Color(red: 0.082, green: 0.722, blue: 0.639)
private let bgDark = Color(red: 0.059, green: 0.090, blue: 0.165)

// MARK: — Data model

struct WidgetData {
    struct RecentEntry { let desc: String; let amount: Double; let isIncome: Bool }

    let netWorth:   Double
    let trueNet:    Double
    let income:     Double
    let expenses:   Double
    let sharedOwed: Double
    let sharedOwe:  Double
    let currency:   String
    let recent:     [RecentEntry]

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
            netWorth:   d?.double(forKey: "widget_net_worth")   ?? 0,
            trueNet:    d?.double(forKey: "widget_true_net")    ?? 0,
            income:     d?.double(forKey: "widget_income")      ?? 0,
            expenses:   d?.double(forKey: "widget_expenses")    ?? 0,
            sharedOwed: d?.double(forKey: "widget_shared_owed") ?? 0,
            sharedOwe:  d?.double(forKey: "widget_shared_owe")  ?? 0,
            currency:   d?.string(forKey: "widget_currency")    ?? "USD",
            recent:     entries
        )
    }

    func fmt(_ v: Double) -> String { String(format: "%@ %.2f", currency, v) }
    var netColor:     Color { netWorth >= 0 ? teal : .red }
    var trueNetColor: Color { trueNet  >= 0 ? teal : .red }
}

struct SAEntry: TimelineEntry { let date: Date; let data: WidgetData }

// MARK: — Provider

struct SAProvider: TimelineProvider {
    func placeholder(in context: Context) -> SAEntry {
        SAEntry(date: Date(), data: WidgetData(
            netWorth: 1234.56, trueNet: 1360.56, income: 2000, expenses: 765.44,
            sharedOwed: 200, sharedOwe: 74, currency: "USD",
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
        HStack(spacing: 10) {
            Link(destination: URL(string: "\(urlScheme):///add-expense")!) {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Expense").lineLimit(1)
                }
                .fixedSize()
                .font(.footnote.bold())
                .foregroundColor(bgDark)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(teal)
                .cornerRadius(10)
            }
            Link(destination: URL(string: "\(urlScheme):///wallet/add")!) {
                HStack(spacing: 5) {
                    Image(systemName: "creditcard.fill")
                    Text("Wallet Entry").lineLimit(1)
                }
                .fixedSize()
                .font(.footnote.bold())
                .foregroundColor(bgDark)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(teal)
                .cornerRadius(10)
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
        .widgetURL(URL(string: "\(urlScheme):///"))
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
                Text("Dashboard").font(.caption2).foregroundColor(.secondary)
            }.padding(.bottom, 10)

            // True net worth hero
            Text(data.fmt(data.trueNet))
                .font(.largeTitle.bold()).foregroundColor(data.trueNetColor)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text("True Net Worth").font(.caption).foregroundColor(.secondary)
                .padding(.bottom, 14)

            // Divider
            Rectangle().fill(teal.opacity(0.2)).frame(height: 1).padding(.bottom, 12)

            // Dashboard totals grid
            VStack(spacing: 10) {
                dashRow(label: "Wallet Net",    value: data.netWorth,    color: data.netColor,     prefix: data.netWorth >= 0 ? "+" : "")
                dashRow(label: "Income",        value: data.income,      color: Color(red: 0.133, green: 0.773, blue: 0.369), prefix: "+")
                dashRow(label: "Expenses",      value: data.expenses,    color: Color(red: 0.957, green: 0.247, blue: 0.369), prefix: "-")
                dashRow(label: "Shared Owed",   value: data.sharedOwed,  color: Color(red: 0.133, green: 0.773, blue: 0.369), prefix: "+")
                dashRow(label: "You Owe",       value: data.sharedOwe,   color: Color(red: 0.957, green: 0.247, blue: 0.369), prefix: "-")
            }

            Spacer()
            ActionButtons()
        }
        .padding(14)
        .containerBackground(bgDark, for: .widget)
        .widgetURL(URL(string: "\(urlScheme):///"))
    }

    func dashRow(label: String, value: Double, color: Color, prefix: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text("\(prefix)\(data.fmt(value))")
                .font(.caption.bold()).foregroundColor(color).lineLimit(1)
        }
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
