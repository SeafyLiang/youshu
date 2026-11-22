import SwiftUI
import WidgetKit

struct Summary: TimelineEntry {
    let date: Date
    var ledger: String = "日常账本"
    var expense: String = "0.00"
    var remaining: String = "未设预算"
    var period: String = "打开 App 更新账期"
    var updated: String = "打开 App 后更新"
}
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Summary { Summary(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (Summary) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Summary>) -> Void) { completion(Timeline(entries: [read()], policy: .never)) }
    private func read() -> Summary {
        let defaults = UserDefaults(suiteName: "group.com.seafy.yousu")
        return Summary(date: Date(), ledger: defaults?.string(forKey: "ledger") ?? "日常账本", expense: defaults?.string(forKey: "expense") ?? "0.00", remaining: defaults?.string(forKey: "remaining") ?? "未设预算", period: defaults?.string(forKey: "period") ?? "打开 App 更新账期", updated: String((defaults?.string(forKey: "updated") ?? "打开 App 后更新").prefix(16)).replacingOccurrences(of: "T", with: " "))
    }
}
struct SummaryView: View {
    @Environment(\.colorScheme) var colorScheme
    var entry: Summary
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("有数 · \(entry.ledger)").font(.caption).opacity(0.8).lineLimit(1)
            Spacer(minLength: 1)
            Text("本期支出").font(.caption2).opacity(0.8)
            Text(entry.expense).font(.system(size: 27, weight: .semibold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
            Text("预算剩余 \(entry.remaining)").font(.caption2).lineLimit(1)
            Spacer(minLength: 1)
            HStack { Text("＋ 记一笔").font(.system(size: 14, weight: .semibold)); Spacer() }
            Text(entry.period).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.7)
            Text("更新 \(entry.updated)").font(.system(size: 9)).opacity(0.65).lineLimit(1)
        }.foregroundStyle(.white).containerBackground(colorScheme == .dark ? Color(red: 0.106, green: 0.141, blue: 0.133) : Color(red: 0.071, green: 0.424, blue: 0.384), for: .widget)
            .widgetURL(URL(string: "youshu://record"))
    }
}
@main
struct YousuWidget: Widget {
    let kind = "YousuSummary"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in SummaryView(entry: entry) }
            .configurationDisplayName("有数 · 账期概览")
            .description("当前账本的账期支出与预算，轻点记一笔。")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
