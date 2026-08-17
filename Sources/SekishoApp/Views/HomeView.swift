import DeviceActivity
import FamilyControls
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("selectedMascotStyle") private var selectedMascotStyle = MascotStyle.standard.rawValue
    let openSettings: () -> Void

    init(openSettings: @escaping () -> Void = {}) {
        self.openSettings = openSettings
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        header

                        MascotHero(
                            assetName: mascotAssetName,
                            isLimited: hasAnyLimitedTarget,
                            height: heroHeight(for: proxy.size.height)
                        )
                        .padding(.top, 8)

                        VStack(spacing: 7) {
                            Text(mascotStatusMessage)
                                .font(.headline)

                            if isLimited {
                                Label("明日 0:00 にまた開きます", systemImage: "moon.stars.fill")
                                    .font(.footnote.weight(.semibold))
                            } else if model.hasPartialIndividualLimit {
                                Label("制限中の対象は明日 0:00 に開きます", systemImage: "lock.fill")
                                    .font(.footnote.weight(.semibold))
                            }
                        }
                        .multilineTextAlignment(.center)
                        .foregroundStyle(
                            mascotExpression == .limited
                                ? Color.limitRed
                                : mascotExpression == .warning
                                    ? Color.sekishoVermilion
                                    : Color.sekishoInk.opacity(0.82)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                        .animation(.easeInOut(duration: 0.2), value: mascotExpression)

                        if canShowUsageReport {
                            usageReport
                                .padding(.top, 22)

                            MonitoringStateLine(isLimited: isLimited)
                                .padding(.top, 14)

                            WeeklyGateLog()
                                .padding(.top, 20)
                        } else {
                            HomeSetupState(
                                isScreenTimeAuthorized: model.isScreenTimeAuthorized,
                                openSettings: openSettings
                            )
                            .padding(.top, 22)
                        }

                        if canShowUsageReport,
                           let rejectedDate = model.lastRejectedThresholdDate,
                           Calendar.current.isDateInToday(rejectedDate) {
                            LimitReliabilityNotice()
                                .padding(.top, 16)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
                .foregroundStyle(Color.sekishoInk)
                .background(Color.sekishoPaper.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
            }
        }
        .sensoryFeedback(.warning, trigger: model.lockedIndividualTargetCount)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            HandwrittenAssetText(
                assetName: "HandTitleHome",
                label: "今日の関所",
                height: 46
            )

            Spacer(minLength: 12)

            NavigationLink {
                MascotWardrobeView()
            } label: {
                Image(systemName: "tshirt.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.sekishoInk)
                    .frame(width: 44, height: 44)
                    .background(Color.sekishoSand.opacity(0.17), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.sekishoInk.opacity(0.12), lineWidth: 1)
                    }
            }
            .accessibilityLabel("番人の着せ替え")
        }
    }

    @ViewBuilder
    private var usageReport: some View {
        if canShowUsageReport {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                DeviceActivityReport(
                    .sekishoTodayUsage,
                    filter: todayUsageFilter(at: context.date)
                )
            }
            .frame(maxWidth: .infinity, minHeight: usageReportHeight, alignment: .top)
        }
    }

    private var mascotAssetName: String {
        switch mascotExpression {
        case .limited:
            return "SekishoMascotLimited"
        case .watchful:
            return "SekishoMascotWatchful"
        case .warning:
            return "SekishoMascotWarning"
        case .normal:
            let style = MascotStyle(rawValue: selectedMascotStyle) ?? .standard
            if style == .sakura, purchaseManager.canUseSakura {
                return style.assetName
            }

            return MascotStyle.standard.assetName
        }
    }

    private var mascotExpression: MascotExpression {
        if isLimited {
            return .limited
        }

        if model.hasPartialIndividualLimit {
            return .warning
        }

        guard model.isUsageLimitMonitoringEnabled, model.selectedTokenCount > 0 else {
            return .normal
        }

        return isNearUsageLimit ? .warning : .watchful
    }

    private var isLimited: Bool {
        model.isEveryMonitoredTargetLimited
    }

    private var hasAnyLimitedTarget: Bool {
        model.barrierState == .locked
    }

    private var isNearUsageLimit: Bool {
        let snapshot = SekishoWidgetSnapshotStore.read()
        guard snapshot.isMonitoringActive,
              Calendar.current.isDateInToday(snapshot.updatedAt)
        else {
            return false
        }

        let remainingMinutes = max(snapshot.usageLimitMinutes - snapshot.usedMinutes, 0)
        let warningThreshold = min(10, max(snapshot.usageLimitMinutes / 4, 3))
        return remainingMinutes > 0 && remainingMinutes <= warningThreshold
    }

    private var mascotStatusMessage: String {
        guard canShowUsageReport else {
            return "見守りの準備がまだです。"
        }

        if model.hasPartialIndividualLimit {
            return "\(model.lockedIndividualTargetCount)件は制限中。ほかの対象は使えます。"
        }

        switch mascotExpression {
        case .limited:
            if model.isIndividualLimitMode {
                return "上限に達した\(model.lockedIndividualTargetCount)件を見張っています。"
            }

            return "上限 \(model.usageLimitMinutes)分を使ったため、今日はここまで。"
        case .warning:
            return "もうすぐ上限。番人もそっと気にしています。"
        case .watchful:
            return "番人が静かに見守っています。"
        case .normal:
            return "今日も静かに見守ります。"
        }
    }

    private var canShowUsageReport: Bool {
        model.isScreenTimeAuthorized && model.selectedTokenCount > 0
    }

    private func todayUsageFilter(at now: Date) -> DeviceActivityFilter {
        let startOfDay = Calendar.current.startOfDay(for: now)
        let monitoringStart = UsageLimitMonitoringStateStore.load()?.startedAt
        let intervalStart = monitoringStart.map {
            max($0, startOfDay)
        } ?? startOfDay
        let interval = DateInterval(start: intervalStart, end: now)

        return DeviceActivityFilter(
            segment: .daily(during: interval),
            applications: model.monitoredApps.applicationTokens,
            categories: model.monitoredApps.categoryTokens,
            webDomains: model.monitoredApps.webDomainTokens
        )
    }

    private var monitoredTargetCount: Int {
        let selection = model.monitoredApps
        return selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }

    private var usageReportHeight: CGFloat {
        let baseHeight: CGFloat = dynamicTypeSize.isAccessibilitySize ? 156 : 116
        let sectionHeight: CGFloat = dynamicTypeSize.isAccessibilitySize ? 76 : 52
        let rowHeight: CGFloat = model.isIndividualLimitMode
            ? (dynamicTypeSize.isAccessibilitySize ? 88 : 64)
            : (dynamicTypeSize.isAccessibilitySize ? 72 : 45)
        return baseHeight + sectionHeight + (CGFloat(monitoredTargetCount) * rowHeight)
    }

    private func heroHeight(for availableHeight: CGFloat) -> CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return 176
        }

        return availableHeight < 720 ? 230 : 280
    }

}

private enum MascotExpression: Equatable {
    case normal
    case watchful
    case warning
    case limited
}

private struct MascotHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let assetName: String
    let isLimited: Bool
    let height: CGFloat

    var body: some View {
        ZStack {
            SekishoSceneBackdrop(isLimited: isLimited)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)

            AnimatedSekishoMascot(
                assetName: assetName,
                accessibilityLabel: isLimited
                    ? "番人が制限中の表情をしています"
                    : "関所の番人が見守っています",
                isLimited: isLimited
            )
            .padding(.horizontal, 34)
            .padding(.vertical, 12)
            .id(assetName)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: assetName)
    }
}

private struct MonitoringStateLine: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let isLimited: Bool

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    stateDescription
                    limitDescription
                }
            } else {
                HStack(spacing: 10) {
                    stateDescription
                    Spacer(minLength: 8)
                    limitDescription
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.sekishoInk.opacity(0.12))
                .frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var stateDescription: some View {
        Label(stateLabel, systemImage: stateSymbol)
            .font(.footnote.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(stateColor)
    }

    private var limitDescription: some View {
        Text(
            model.isIndividualLimitMode
                ? "対象ごとの上限"
                : "上限 \(model.usageLimitMinutes)分"
        )
            .font(.footnote.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Color.sekishoSecondaryInk)
    }

    private var stateLabel: String {
        if isLimited {
            if model.isIndividualLimitMode {
                return "\(model.lockedIndividualTargetCount)件が上限に到達しました"
            }

            return "上限 \(model.usageLimitMinutes)分に到達しました"
        }

        if model.hasPartialIndividualLimit {
            return "\(model.lockedIndividualTargetCount)件を制限中・ほかは利用できます"
        }

        if model.isUsageLimitMonitoringEnabled, model.isIndividualLimitMode {
            return "対象ごとの自動制限は有効です"
        }

        return model.isUsageLimitMonitoringEnabled
            ? "自動制限は有効です"
            : "自動制限の準備中です"
    }

    private var accessibilityLabel: String {
        if model.isIndividualLimitMode {
            return "\(stateLabel)、対象ごとに上限を設定しています"
        }

        return "\(stateLabel)、1日の上限は\(model.usageLimitMinutes)分"
    }

    private var stateSymbol: String {
        if isLimited || model.hasPartialIndividualLimit {
            return "lock.fill"
        }

        return model.isUsageLimitMonitoringEnabled ? "checkmark.circle.fill" : "ellipsis.circle"
    }

    private var stateColor: Color {
        if isLimited || model.hasPartialIndividualLimit {
            return .limitRed
        }

        return model.isUsageLimitMonitoringEnabled ? .sekishoSage : .sekishoSecondaryInk
    }
}

private struct HomeSetupState: View {
    let isScreenTimeAuthorized: Bool
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                Image(systemName: isScreenTimeAuthorized ? "scope" : "lock.shield")
                    .foregroundStyle(Color.sekishoVermilion)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.sekishoSecondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: openSettings) {
                Label("設定を開く", systemImage: "gearshape.fill")
                    .font(.headline)
                    .foregroundStyle(Color.sekishoOnAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.sekishoVermilion, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Color.sekishoInk.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.sekishoInk.opacity(0.13), lineWidth: 1)
        }
    }

    private var title: String {
        isScreenTimeAuthorized ? "見守る対象を選んでください" : "Screen Timeの許可が必要です"
    }

    private var message: String {
        if isScreenTimeAuthorized {
            return "制限するアプリやWebサイトを選ぶと、残り時間の計測が始まります。"
        }

        return "使用時間は端末内で集計されます。まず設定からScreen Timeの利用を許可してください。"
    }
}

private struct LimitReliabilityNotice: View {
    var body: some View {
        Label("早すぎる制限を見送りました", systemImage: "checkmark.shield")
            .font(.footnote)
            .foregroundStyle(Color.sekishoSage)
            .frame(maxWidth: .infinity)
    }
}

private struct WeeklyGateLog: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        return (-6...0).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }
    }

    private var closedDayCount: Int {
        days.filter { model.recentClosedGateDayKeys.contains(WeeklyGateLogStore.dayKey(for: $0)) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        weeklyTitle
                        closedCount
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        weeklyTitle
                        Spacer(minLength: 8)
                        closedCount
                    }
                }
            }

            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    let isClosed = model.recentClosedGateDayKeys.contains(WeeklyGateLogStore.dayKey(for: day))
                    let isToday = Calendar.current.isDateInToday(day)

                    VStack(spacing: 7) {
                        Image(systemName: isClosed ? "lock.fill" : "circle")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isClosed ? Color.limitRed : Color.sekishoInk.opacity(0.22))
                            .frame(width: 30, height: 30)
                            .background(
                                (isClosed ? Color.limitRed : Color.sekishoSand)
                                    .opacity(isClosed ? 0.12 : 0.10),
                                in: Circle()
                            )

                        Text(isToday ? "今" : UsageWeekday.current(for: day).shortTitle)
                            .font(.caption2.weight(isToday ? .bold : .medium))
                            .foregroundStyle(isToday ? Color.sekishoVermilion : Color.sekishoSecondaryInk)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(isToday ? "今日" : UsageWeekday.current(for: day).title)、\(isClosed ? "関所が閉じました" : "記録なし")"
                    )
                }
            }
        }
        .padding(.top, 16)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.sekishoInk.opacity(0.12))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var weeklyTitle: some View {
        Text("今週の番人の記録")
            .font(.subheadline.weight(.semibold))
    }

    private var closedCount: some View {
        Text("関所が閉じた日 \(closedDayCount)日")
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.sekishoSecondaryInk)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppModel())
        .environmentObject(PurchaseManager(configureSDK: false))
}
