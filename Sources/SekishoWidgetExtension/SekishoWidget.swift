import FamilyControls
import SwiftUI
import WidgetKit

private let sekishoWidgetKind = "SekishoWidget"

struct SekishoWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: SekishoWidgetSnapshot
}

struct SekishoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SekishoWidgetEntry {
        SekishoWidgetEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SekishoWidgetEntry) -> Void) {
        let snapshot = context.isPreview ? .preview : SekishoWidgetSnapshotStore.read()
        completion(SekishoWidgetEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SekishoWidgetEntry>) -> Void) {
        let snapshot = SekishoWidgetSnapshotStore.read()
        let now = Date()
        let nextDay = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: now)
        ) ?? now.addingTimeInterval(86_400)

        completion(
            Timeline(
                entries: [SekishoWidgetEntry(date: now, snapshot: snapshot)],
                policy: .after(nextDay)
            )
        )
    }
}

struct SekishoWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SekishoWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumLayout
            default:
                smallLayout
            }
        }
        .widgetURL(URL(string: "sekisho://home"))
        .containerBackground(for: .widget) {
            Color.sekishoWidgetPaper
        }
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: stateSymbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(stateTint)

                Text("今日の関所")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.sekishoWidgetInk.opacity(0.72))

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 6) {
                Text(primaryTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(stateTint)
                    .lineLimit(1)

                Spacer(minLength: 0)

                mascot
                    .frame(width: 58, height: 58)
            }

            Text(secondaryTitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.sekishoWidgetInk.opacity(0.68))
                .lineLimit(2)

            if isConfigured {
                targetLine(maximumCount: 1)
            }
        }
        .padding(2)
    }

    private var mediumLayout: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: stateSymbolName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(stateTint)

                    Text("今日の関所")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.sekishoWidgetInk.opacity(0.72))
                }

                Text(primaryTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(stateTint)
                    .lineLimit(1)

                Text(secondaryTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.sekishoWidgetInk.opacity(0.68))
                    .lineLimit(2)

                if isConfigured {
                    targetLine(maximumCount: 2)
                }

                Spacer(minLength: 0)

                Text("タップして関所をひらく")
                    .font(.caption2)
                    .foregroundStyle(Color.sekishoWidgetInk.opacity(0.48))
            }

            Spacer(minLength: 0)

            mascot
                .frame(width: 100, height: 100)
        }
        .padding(2)
    }

    private var mascot: some View {
        Image(mascotAssetName)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }

    private var mascotAssetName: String {
        if isLimited {
            return "SekishoMascotLimited"
        }

        if hasPartialIndividualLimit {
            return "SekishoMascotWarning"
        }

        if isConfigured {
            return remainingMinutes <= warningThreshold
                ? "SekishoMascotWarning"
                : "SekishoMascotWatchful"
        }

        return "SekishoMascotNormal"
    }

    private var isLimited: Bool {
        guard entry.snapshot.barrierState == .locked else {
            return false
        }

        guard isIndividualMode else {
            return true
        }

        return lockedTargetCount >= entry.snapshot.selectedTargetCount
            && entry.snapshot.selectedTargetCount > 0
    }

    private var hasPartialIndividualLimit: Bool {
        entry.snapshot.barrierState == .locked
            && isIndividualMode
            && lockedTargetCount > 0
            && lockedTargetCount < entry.snapshot.selectedTargetCount
    }

    private var lockedTargetCount: Int {
        max(entry.snapshot.lockedTargetCount ?? 0, 0)
    }

    private var isConfigured: Bool {
        entry.snapshot.isMonitoringActive && entry.snapshot.selectedTargetCount > 0
    }

    private var primaryTitle: String {
        if hasPartialIndividualLimit {
            return "\(lockedTargetCount)件 制限中"
        }

        if isLimited {
            if isIndividualMode {
                return "すべて制限中"
            }

            return "制限中"
        }

        if !isConfigured {
            return "準備しよう"
        }

        return isIndividualMode
            ? "次まで約\(remainingMinutes)分"
            : "残り約\(remainingMinutes)分"
    }

    private var secondaryTitle: String {
        if hasPartialIndividualLimit {
            return "ほかの対象は引き続き使えます"
        }

        if isLimited {
            return isIndividualMode
                ? "上限に達した対象だけ閉じています"
                : "上限 \(entry.snapshot.usageLimitMinutes)分を使ったため。また明日。"
        }

        if !isConfigured {
            return "アプリで見守る対象を選ぼう"
        }

        return isIndividualMode
            ? "対象ごとの上限を番人が見守り中"
            : "上限 \(entry.snapshot.usageLimitMinutes)分・番人が見守り中"
    }

    private var stateSymbolName: String {
        if isLimited || hasPartialIndividualLimit {
            return "lock.fill"
        }

        return isConfigured ? "checkmark.shield.fill" : "gearshape.fill"
    }

    private var stateTint: Color {
        if isLimited || hasPartialIndividualLimit {
            return .sekishoWidgetRed
        }

        return isConfigured ? .sekishoWidgetSage : .sekishoWidgetInk
    }

    private var remainingMinutes: Int {
        max(entry.snapshot.usageLimitMinutes - entry.snapshot.usedMinutes, 0)
    }

    private var warningThreshold: Int {
        min(10, max(entry.snapshot.usageLimitMinutes / 4, 3))
    }

    private var isIndividualMode: Bool {
        entry.snapshot.limitModeRawValue == "individual"
    }

    private func targetLine(maximumCount: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.sekishoWidgetInk.opacity(0.50))

            targetLabels(maximumCount: maximumCount)

            Spacer(minLength: 0)

            Text("\(entry.snapshot.selectedTargetCount)件")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.sekishoWidgetInk.opacity(0.52))
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(Color.sekishoWidgetInk.opacity(0.78))
        .lineLimit(1)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func targetLabels(maximumCount: Int) -> some View {
        let selection = FamilyActivitySelectionStore.loadActive()
            ?? FamilyActivitySelectionStore.load()
        let applicationTokens = Array(selection.applicationTokens.prefix(maximumCount))
        let categorySlots = max(maximumCount - applicationTokens.count, 0)
        let categoryTokens = Array(selection.categoryTokens.prefix(categorySlots))
        let domainSlots = max(categorySlots - categoryTokens.count, 0)
        let webDomainTokens = Array(selection.webDomainTokens.prefix(domainSlots))

        ForEach(applicationTokens, id: \.self) { token in
            Label(token)
                .labelStyle(.titleAndIcon)
        }

        ForEach(categoryTokens, id: \.self) { token in
            Label(token)
                .labelStyle(.titleAndIcon)
        }

        ForEach(webDomainTokens, id: \.self) { token in
            Label(token)
                .labelStyle(.titleAndIcon)
        }

        if applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty {
            Text("制限対象")
        }
    }
}

struct SekishoWidget: Widget {
    let kind = sekishoWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SekishoWidgetProvider()) { entry in
            SekishoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("今日の関所")
        .description("今日の上限と関所の状態をひと目で確認できます。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SekishoWidgetBundle: WidgetBundle {
    var body: some Widget {
        SekishoWidget()
    }
}

private extension SekishoWidgetSnapshot {
    static let preview = SekishoWidgetSnapshot(
        barrierState: .passed,
        usageLimitMinutes: 30,
        usedMinutes: 5,
        selectedTargetCount: 3,
        isMonitoringActive: true,
        updatedAt: .now
    )
}

private extension Color {
    static let sekishoWidgetPaper = Color(red: 250 / 255, green: 243 / 255, blue: 230 / 255)
    static let sekishoWidgetInk = Color(red: 0.22, green: 0.18, blue: 0.15)
    static let sekishoWidgetSage = Color(red: 0.38, green: 0.47, blue: 0.35)
    static let sekishoWidgetRed = Color(red: 0.70, green: 0.20, blue: 0.16)
}
