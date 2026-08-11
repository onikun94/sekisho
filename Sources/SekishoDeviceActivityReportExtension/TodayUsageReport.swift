import DeviceActivity
import ExtensionKit
import Foundation
import SwiftUI

struct TodayUsageSummary: Hashable {
    let totalDuration: TimeInterval
    let limitMinutes: Int
    let applications: [UsageBreakdownItem]
    let categories: [UsageBreakdownItem]
    let webDomains: [UsageBreakdownItem]

    var minuteText: String {
        Self.minuteText(for: totalDuration)
    }

    var usedMinutes: Int {
        Int(totalDuration / 60)
    }

    var remainingMinutes: Int {
        max(limitMinutes - usedMinutes, 0)
    }

    var isLimited: Bool {
        limitMinutes > 0 && totalDuration >= TimeInterval(limitMinutes * 60)
    }

    var progress: Double {
        guard limitMinutes > 0 else {
            return 0
        }

        return min(Double(usedMinutes) / Double(limitMinutes), 1)
    }

    var primaryTargetName: String {
        applications.first?.displayTitle ?? categories.first?.displayTitle ?? webDomains.first?.displayTitle ?? "対象"
    }

    var hasBreakdown: Bool {
        !applications.isEmpty || !categories.isEmpty || !webDomains.isEmpty
    }

    static func minuteText(for duration: TimeInterval) -> String {
        guard duration >= 60 else {
            return duration > 0 ? "1分未満" : "0分"
        }

        return "\(Int(duration / 60))分"
    }
}

struct UsageBreakdownItem: Hashable, Identifiable {
    enum Kind: String, Hashable {
        case application
        case category
        case webDomain
    }

    let id: String
    let kind: Kind
    let title: String
    var totalDuration: TimeInterval

    var displayTitle: String {
        switch title {
        case "com.google.ios.youtube":
            "YouTube"
        default:
            title
        }
    }
}

struct TodayUsageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .sekishoTodayUsage
    let content: (TodayUsageSummary) -> TodayUsageReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TodayUsageSummary {
        var totalDuration: TimeInterval = 0
        var applications: [String: UsageBreakdownItem] = [:]
        var categories: [String: UsageBreakdownItem] = [:]
        var webDomains: [String: UsageBreakdownItem] = [:]

        for await activityData in data {
            for await segment in activityData.activitySegments {
                totalDuration += segment.totalActivityDuration

                for await categoryActivity in segment.categories {
                    merge(
                        item: UsageBreakdownItem(
                            id: "category-\(categoryActivity.category.hashValue)",
                            kind: .category,
                            title: categoryActivity.category.localizedDisplayName ?? "カテゴリ",
                            totalDuration: categoryActivity.totalActivityDuration
                        ),
                        into: &categories
                    )

                    for await applicationActivity in categoryActivity.applications {
                        merge(
                            item: UsageBreakdownItem(
                                id: "application-\(applicationActivity.application.hashValue)",
                                kind: .application,
                                title: applicationActivity.application.localizedDisplayName ?? "名称非公開のアプリ",
                                totalDuration: applicationActivity.totalActivityDuration
                            ),
                            into: &applications
                        )
                    }

                    for await webDomainActivity in categoryActivity.webDomains {
                        merge(
                            item: UsageBreakdownItem(
                                id: "webDomain-\(webDomainActivity.webDomain.hashValue)",
                                kind: .webDomain,
                                title: webDomainActivity.webDomain.domain ?? "Webサイト",
                                totalDuration: webDomainActivity.totalActivityDuration
                            ),
                            into: &webDomains
                        )
                    }
                }
            }
        }

        return TodayUsageSummary(
            totalDuration: totalDuration,
            limitMinutes: UsageLimitSettingsStore.load(),
            applications: sortedItems(applications),
            categories: sortedItems(categories),
            webDomains: sortedItems(webDomains)
        )
    }

    private func merge(item: UsageBreakdownItem, into items: inout [String: UsageBreakdownItem]) {
        guard item.totalDuration > 0 else {
            return
        }

        if var existing = items[item.id] {
            existing.totalDuration += item.totalDuration
            items[item.id] = existing
        } else {
            items[item.id] = item
        }
    }

    private func sortedItems(_ items: [String: UsageBreakdownItem]) -> [UsageBreakdownItem] {
        Array(items.values.sorted { lhs, rhs in
            lhs.totalDuration > rhs.totalDuration
        }.prefix(5))
    }
}
