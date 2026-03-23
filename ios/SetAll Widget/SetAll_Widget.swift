import WidgetKit
import SwiftUI

private let appGroup = "group.com.jafa.setall.app.widget"
private let teal = Color(red: 0.082, green: 0.722, blue: 0.639)
private let bgDark = Color(red: 0.059, green: 0.090, blue: 0.165)

struct WidgetData {
    let netWorth: Double
    let income: Double
    let expenses: Double
    let currency: String

    static func load() -> WidgetData {
        let d = UserDefaults(suiteName: appGroup)
        return WidgetData(
            netWorth: d?.double(forKey: "widget_net_worth") ?? 0,
            income:   d?.double(forKey: "widget_income")   ?? 0,
            expenses: d?.double(forKey: "widget_expenses") ?? 0,
            currency: d?.string(forKey:  "widget_currency") ?? "USD"
        )
    }

    func fmt(_ v: Double) -> String {
        String(format: "%@ %.2f", currency, v)
    }
}

struct SAEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct SAProvider: TimelineProvider {
    func placeholder(in context: Context) -> SAEntry {
        SAEntry(date: Date(), data: WidgetData(
            netWorth: 1234.56, income: 2000, expenses: 765.44, currency: "USD"))
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

struct MediumView: View {
    let data: WidgetData
    var body: some View {
        ZStack {
            bgDark.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("SetAll")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(teal)
                    Spacer()
                }
                .padding(.bottom, 2)

                Text(data.fmt(data.netWorth))
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text("Net Worth")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Income")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(data.fmt(data.income))
                            .font(.caption.bold())
                            .foregroundColor(.green)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Expenses")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(data.fmt(data.expenses))
                            .font(.caption.bold())
                            .foregroundColor(.red)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                Spacer()

                HStack(spacing: 8) {
                    Link(destination: URL(string: "setall://add-expense")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("Expense")
                        }
                        .font(.caption.bold())
                        .foregroundColor(bgDark)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(teal)
                        .cornerRadius(8)
                    }
                    Link(destination: URL(string: "setall://wallet/add")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "wallet.pass.fill")
                            Text("Wallet")
                        }
                        .font(.caption.bold())
                        .foregroundColor(teal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(teal.opacity(0.15))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(teal.opacity(0.5), lineWidth: 1)
                        )
                    }
                    Spacer()
                }
            }
            .padding(14)
        }
    }
}

struct SmallView: View {
    var body: some View {
        ZStack {
            bgDark.ignoresSafeArea()
            VStack(spacing: 10) {
                Text("SetAll")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(teal)
                Link(destination: URL(string: "setall://add-expense")!) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Expense")
                    }
                    .font(.caption.bold())
                    .foregroundColor(bgDark)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(teal)
                    .cornerRadius(10)
                }
                Link(destination: URL(string: "setall://wallet/add")!) {
                    HStack {
                        Image(systemName: "wallet.pass.fill")
                        Text("Add Wallet")
                    }
                    .font(.caption.bold())
                    .foregroundColor(teal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(teal.opacity(0.15))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(teal.opacity(0.5), lineWidth: 1)
                    )
                }
            }
            .padding(12)
        }
    }
}

struct SetAllWidgetEntryView: View {
    var entry: SAEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        switch family {
        case .systemSmall: SmallView()
        default:           MediumView(data: entry.data)
        }
    }
}

@main
struct SetAllWidget: Widget {
    let kind = "SetAllWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SAProvider()) { entry in
            SetAllWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("SetAll")
        .description("Net worth and quick actions.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
