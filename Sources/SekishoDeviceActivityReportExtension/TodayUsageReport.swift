import DeviceActivity
import ExtensionKit
import FamilyControls
import Foundation
import ManagedSettings
import SwiftUI

struct TodayUsageSummary: Hashable {
    let totalDuration: TimeInterval
    let limitMinutes: Int
    let isLocked: Bool
    let targets: [UsageBreakdownItem]
    let mode: UsageLimitMode

    init(
        totalDuration: TimeInterval,
        limitMinutes: Int,
        isLocked: Bool,
        targets: [UsageBreakdownItem],
        mode: UsageLimitMode = .combined
    ) {
        self.totalDuration = totalDuration
        self.limitMinutes = limitMinutes
        self.isLocked = isLocked
        self.targets = targets
        self.mode = mode
    }

    var minuteText: String {
        Self.minuteText(for: totalDuration)
    }

    var usedMinutes: Int {
        Int(totalDuration / 60)
    }

    var remainingMinutes: Int {
        if mode == .individual {
            return targets
                .filter { !$0.isLocked }
                .map(\.remainingMinutes)
                .min() ?? 0
        }

        return max(limitMinutes - usedMinutes, 0)
    }

    var isLimited: Bool {
        if mode == .individual {
            return !targets.isEmpty && lockedTargetCount >= targets.count
        }

        return isLocked
    }

    var hasLockedTargets: Bool {
        mode == .individual ? lockedTargetCount > 0 : isLocked
    }

    var hasReachedUnlockedTargets: Bool {
        mode == .individual
            && targets.contains { $0.hasReachedLimit && !$0.isLocked }
    }

    var progress: Double {
        if mode == .individual {
            let unlockedTargets = targets.filter { !$0.isLocked }
            return unlockedTargets.isEmpty
                ? (targets.isEmpty ? 0 : 1)
                : unlockedTargets.map(\.progress).max() ?? 0
        }

        guard limitMinutes > 0 else {
            return 0
        }

        return min(Double(usedMinutes) / Double(limitMinutes), 1)
    }

    var hasBreakdown: Bool {
        !targets.isEmpty
    }

    var lockedTargetCount: Int {
        targets.filter(\.isLocked).count
    }

    static func minuteText(for duration: TimeInterval) -> String {
        guard duration >= 60 else {
            return duration > 0 ? "1分未満" : "0分"
        }

        return "\(Int(duration / 60))分"
    }
}

struct UsageBreakdownItem: Hashable, Identifiable {
    enum Target: Hashable {
        case application(ManagedSettings.ApplicationToken)
        case category(ManagedSettings.ActivityCategoryToken)
        case webDomain(ManagedSettings.WebDomainToken)
        case preview(title: String, systemImage: String)

        fileprivate var sortOrder: Int {
            switch self {
            case .application:
                return 0
            case .category:
                return 1
            case .webDomain:
                return 2
            case .preview:
                return 3
            }
        }
    }

    let target: Target
    var totalDuration: TimeInterval
    var limitMinutes: Int?
    var isLocked: Bool

    init(
        target: Target,
        totalDuration: TimeInterval,
        limitMinutes: Int? = nil,
        isLocked: Bool = false
    ) {
        self.target = target
        self.totalDuration = totalDuration
        self.limitMinutes = limitMinutes
        self.isLocked = isLocked
    }

    var id: Target {
        target
    }

    var usedMinutes: Int {
        Int(totalDuration / 60)
    }

    var remainingMinutes: Int {
        max((limitMinutes ?? 0) - usedMinutes, 0)
    }

    var progress: Double {
        guard let limitMinutes, limitMinutes > 0 else {
            return 0
        }

        return min(Double(usedMinutes) / Double(limitMinutes), 1)
    }

    var hasReachedLimit: Bool {
        guard let limitMinutes else {
            return false
        }

        return usedMinutes >= limitMinutes
    }

}

struct TodayUsageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .sekishoTodayUsage
    let content: (TodayUsageSummary) -> TodayUsageReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TodayUsageSummary {
        let selection = FamilyActivitySelectionStore.loadActive()
            ?? FamilyActivitySelectionStore.load()
        let weeklyLimit = WeeklyUsageRulesStore.load().limit(for: .current())
        let targetConfiguration = (TargetUsageLimitConfigurationStore.loadActive()
            ?? TargetUsageLimitConfigurationStore.loadConfigured(
                selection: selection,
                defaultLimitMinutes: weeklyLimit
            )).normalized(
                for: selection,
                defaultLimitMinutes: weeklyLimit
            )
        let lockedRuleIDs = IndividualLimitDayStateStore.lockedRuleIDs()
        var totalDuration: TimeInterval = 0
        var targetDurations: [UsageBreakdownItem.Target: TimeInterval] = [:]

        // Keep every configured target visible, including targets with no use
        // today. FamilyControls resolves the private app/category/domain name
        // and icon from these opaque tokens inside the report extension.
        for token in selection.applicationTokens {
            targetDurations[.application(token)] = 0
        }
        for token in selection.categoryTokens {
            targetDurations[.category(token)] = 0
        }
        for token in selection.webDomainTokens {
            targetDurations[.webDomain(token)] = 0
        }

        for await activityData in data {
            for await segment in activityData.activitySegments {
                for await categoryActivity in segment.categories {
                    let categoryToken = categoryActivity.category.token
                    let isSelectedCategory = categoryToken.map(selection.categoryTokens.contains) ?? false

                    // Do not derive the displayed total from the segment-wide
                    // aggregate. Match the immutable monitored tokens directly
                    // so legacy or stale report data cannot broaden the scope.
                    if isSelectedCategory {
                        totalDuration += categoryActivity.totalActivityDuration
                        if let categoryToken {
                            targetDurations[.category(categoryToken), default: 0] += categoryActivity.totalActivityDuration
                        }
                    }

                    for await applicationActivity in categoryActivity.applications {
                        let applicationToken = applicationActivity.application.token
                        let isSelectedApplication = applicationToken.map(selection.applicationTokens.contains) ?? false

                        // A selected category already accounts for every app in
                        // it. Do not add the same app twice when an app and its
                        // category have both been selected.
                        if isSelectedApplication, let applicationToken {
                            targetDurations[.application(applicationToken), default: 0] += applicationActivity.totalActivityDuration
                        }
                        if isSelectedApplication && !isSelectedCategory {
                            totalDuration += applicationActivity.totalActivityDuration
                        }
                    }

                    for await webDomainActivity in categoryActivity.webDomains {
                        let webDomainToken = webDomainActivity.webDomain.token
                        let isSelectedWebDomain = webDomainToken.map(selection.webDomainTokens.contains) ?? false

                        if isSelectedWebDomain, let webDomainToken {
                            targetDurations[.webDomain(webDomainToken), default: 0] += webDomainActivity.totalActivityDuration
                        }
                        if isSelectedWebDomain && !isSelectedCategory {
                            totalDuration += webDomainActivity.totalActivityDuration
                        }
                    }
                }
            }
        }

        return TodayUsageSummary(
            totalDuration: totalDuration,
            limitMinutes: targetConfiguration.mode == .individual
                ? targetConfiguration.minimumIndividualLimit ?? weeklyLimit
                : weeklyLimit,
            isLocked: targetConfiguration.mode == .individual
                ? !lockedRuleIDs.isEmpty
                : SharedShieldStore.readSnapshot().isLockedToday(),
            targets: sortedItems(
                targetDurations,
                configuration: targetConfiguration,
                lockedRuleIDs: lockedRuleIDs
            ),
            mode: targetConfiguration.mode
        )
    }

    private func sortedItems(
        _ durations: [UsageBreakdownItem.Target: TimeInterval],
        configuration: TargetUsageLimitConfiguration,
        lockedRuleIDs: Set<String>
    ) -> [UsageBreakdownItem] {
        durations
            .map { target, duration in
                let rule = target.usageLimitTarget.flatMap(configuration.rule(for:))
                return UsageBreakdownItem(
                    target: target,
                    totalDuration: duration,
                    limitMinutes: configuration.mode == .individual
                        ? rule?.limitMinutes
                        : nil,
                    isLocked: rule.map { lockedRuleIDs.contains($0.id) } ?? false
                )
            }
            .sorted { lhs, rhs in
                if configuration.mode == .individual {
                    if lhs.isLocked != rhs.isLocked {
                        return lhs.isLocked
                    }

                    if lhs.remainingMinutes != rhs.remainingMinutes {
                        return lhs.remainingMinutes < rhs.remainingMinutes
                    }
                }

                if lhs.totalDuration != rhs.totalDuration {
                    return lhs.totalDuration > rhs.totalDuration
                }

                return lhs.target.sortOrder < rhs.target.sortOrder
            }
    }
}

private extension UsageBreakdownItem.Target {
    var usageLimitTarget: UsageLimitTarget? {
        switch self {
        case .application(let token):
            .application(token)
        case .category(let token):
            .category(token)
        case .webDomain(let token):
            .webDomain(token)
        case .preview:
            nil
        }
    }
}
