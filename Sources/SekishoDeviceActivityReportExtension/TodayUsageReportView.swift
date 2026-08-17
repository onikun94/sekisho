import FamilyControls
import SwiftUI
import UIKit

struct TodayUsageReportView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let summary: TodayUsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            statusSummary
                            usageSummary
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            statusSummary
                            Spacer(minLength: 8)
                            usageSummary
                        }
                    }
                }

                WoodenReportProgressBar(
                    progress: summary.hasLockedTargets || summary.hasReachedUnlockedTargets
                        ? 1
                        : max(1 - summary.progress, 0),
                    isLimited: summary.hasLockedTargets || summary.hasReachedUnlockedTargets
                )
                .frame(height: 30)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)

            if summary.hasBreakdown {
                targetBreakdown
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Color.reportInk)
        .accessibilityElement(children: .contain)
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(statusTitle)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(
                    summary.hasLockedTargets || summary.hasReachedUnlockedTargets
                        ? Color.reportRed
                        : Color.reportInk
                )

            if summary.hasLockedTargets || summary.hasReachedUnlockedTargets {
                Text(limitReason)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.reportRed.opacity(0.82))
            }
        }
    }

    private var usageSummary: some View {
        Text(
            summary.mode == .individual
                ? "対象ごとに見守り中"
                : "利用 \(summary.usedMinutes) / \(summary.limitMinutes)分"
        )
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Color.reportInk.opacity(0.72))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var accessibilityLabel: String {
        if summary.mode == .individual {
            if summary.isLimited {
                return "すべての対象を制限中です"
            }

            if summary.hasLockedTargets {
                return "\(summary.lockedTargetCount)件を制限中です。ほかの対象は利用できます。次の上限まで残り\(summary.remainingMinutes)分です"
            }

            if summary.hasReachedUnlockedTargets {
                return "上限に達した対象の制限を反映しています"
            }

            return "対象ごとに見守り中です。次の上限まで残り\(summary.remainingMinutes)分です"
        }

        if summary.isLimited {
            return "上限\(summary.limitMinutes)分を使ったため制限中です。今日の利用は\(summary.usedMinutes)分です"
        }

        return "残り\(summary.remainingMinutes)分。今日の利用は\(summary.usedMinutes)分、上限は\(summary.limitMinutes)分です"
    }

    private var statusTitle: String {
        if summary.mode == .individual {
            if summary.isLimited {
                return "すべて制限中"
            }

            if summary.hasLockedTargets {
                return "\(summary.lockedTargetCount)件 制限中"
            }

            if summary.hasReachedUnlockedTargets {
                return "制限を反映中"
            }

            return "次の上限まで \(summary.remainingMinutes)分"
        }

        return summary.isLimited ? "制限中" : "あと \(summary.remainingMinutes)分"
    }

    private var limitReason: String {
        if summary.mode == .individual {
            if summary.hasReachedUnlockedTargets, !summary.hasLockedTargets {
                return "上限への到達を確認しました"
            }

            return summary.isLimited
                ? "すべての対象が上限に達しました"
                : "ほかの対象は引き続き使えます"
        }

        return "上限 \(summary.limitMinutes)分を使ったため"
    }

    private var targetBreakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.reportInk.opacity(0.12))
                .frame(height: 1)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(
                    summary.mode == .individual
                        ? "対象ごとの利用と上限"
                        : "見守り対象ごとの今日"
                )
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 8)

                Text("\(summary.targets.count)件")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.reportInk.opacity(0.72))
            }
            .padding(.top, 14)
            .padding(.bottom, 6)

            ForEach(Array(summary.targets.enumerated()), id: \.element.id) { index, item in
                UsageTargetRow(item: item)

                if index < summary.targets.count - 1 {
                    Rectangle()
                        .fill(Color.reportInk.opacity(0.08))
                        .frame(height: 1)
                        .padding(.leading, 36)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct UsageTargetRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: UsageBreakdownItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    targetLabel

                    Spacer(minLength: 8)

                    durationText
                }

                VStack(alignment: .leading, spacing: 6) {
                    targetLabel
                    durationText
                }
            }

            if item.limitMinutes != nil {
                ProgressView(value: item.progress)
                    .tint(item.isLocked || item.hasReachedLimit ? Color.reportRed : Color.reportSage)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 80 : 56, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var targetLabel: some View {
        Group {
            switch item.target {
            case .application(let token):
                Label(token)
            case .category(let token):
                Label(token)
            case .webDomain(let token):
                Label(token)
            case .preview(let title, let systemImage):
                Label(title, systemImage: systemImage)
            }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }

    private var durationText: some View {
        Group {
            if let limitMinutes = item.limitMinutes {
                if item.isLocked {
                    Label {
                        Text("制限中・\(item.usedMinutes)/\(limitMinutes)分")
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
                    .foregroundStyle(Color.reportRed)
                } else if item.hasReachedLimit {
                    Label {
                        Text("上限到達・\(item.usedMinutes)/\(limitMinutes)分")
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                    }
                    .foregroundStyle(Color.reportRed)
                } else {
                    Text("\(item.usedMinutes)/\(limitMinutes)分")
                        .foregroundStyle(Color.reportInk.opacity(0.78))
                }
            } else {
                Text(TodayUsageSummary.minuteText(for: item.totalDuration))
                    .foregroundStyle(Color.reportInk.opacity(0.78))
            }
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
    }
}

private struct WoodenReportProgressBar: View {
    let progress: Double
    let isLimited: Bool

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)
            let innerHeight = max(proxy.size.height - 10, 4)
            let innerWidth = max(proxy.size.width - 18, 0)

            ZStack {
                Capsule()
                    .fill(Color(red: 0.37, green: 0.22, blue: 0.13))

                Capsule()
                    .fill(Color(red: 0.77, green: 0.61, blue: 0.42))
                    .padding(3)

                Capsule()
                    .fill(Color.reportPaper.opacity(0.9))
                    .frame(width: innerWidth, height: innerHeight)

                HStack(spacing: 0) {
                    Capsule()
                        .fill(isLimited ? Color.reportRed : Color.reportSage)
                        .frame(
                            width: max(innerWidth * clampedProgress, clampedProgress > 0 ? innerHeight : 0),
                            height: innerHeight
                        )

                    Spacer(minLength: 0)
                }
                .frame(width: innerWidth, height: innerHeight)
                .clipShape(Capsule())

                HStack {
                    ReportWoodEndCap()
                    Spacer()
                    ReportWoodEndCap()
                }
            }
        }
    }
}

private struct ReportWoodEndCap: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(red: 0.45, green: 0.29, blue: 0.17))
            .frame(width: 8)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.reportInk.opacity(0.26), lineWidth: 1)
            }
    }
}

private extension Color {
    static let reportPaper = adaptiveReportColor(
        light: UIColor(red: 250 / 255, green: 243 / 255, blue: 230 / 255, alpha: 1),
        dark: UIColor(red: 0.12, green: 0.10, blue: 0.09, alpha: 1)
    )
    static let reportInk = adaptiveReportColor(
        light: UIColor(red: 0.22, green: 0.18, blue: 0.15, alpha: 1),
        dark: UIColor(red: 0.96, green: 0.91, blue: 0.84, alpha: 1)
    )
    static let reportSage = adaptiveReportColor(
        light: UIColor(red: 0.38, green: 0.47, blue: 0.35, alpha: 1),
        dark: UIColor(red: 0.58, green: 0.72, blue: 0.54, alpha: 1)
    )
    static let reportRed = adaptiveReportColor(
        light: UIColor(red: 0.70, green: 0.20, blue: 0.16, alpha: 1),
        dark: UIColor(red: 0.98, green: 0.39, blue: 0.32, alpha: 1)
    )

    private static func adaptiveReportColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

#Preview("利用中") {
    TodayUsageReportView(
        summary: TodayUsageSummary(
            totalDuration: 22 * 60,
            limitMinutes: 60,
            isLocked: false,
            targets: [
                UsageBreakdownItem(
                    target: .preview(title: "YouTube", systemImage: "play.rectangle.fill"),
                    totalDuration: 14 * 60
                ),
                UsageBreakdownItem(
                    target: .preview(title: "Instagram", systemImage: "camera.fill"),
                    totalDuration: 8 * 60
                )
            ]
        )
    )
    .padding(24)
    .frame(height: 260)
    .background(Color(red: 250 / 255, green: 243 / 255, blue: 230 / 255))
}

#Preview("制限中") {
    TodayUsageReportView(
        summary: TodayUsageSummary(
            totalDuration: 60 * 60,
            limitMinutes: 60,
            isLocked: true,
            targets: [
                UsageBreakdownItem(
                    target: .preview(title: "YouTube", systemImage: "play.rectangle.fill"),
                    totalDuration: 44 * 60
                ),
                UsageBreakdownItem(
                    target: .preview(title: "Instagram", systemImage: "camera.fill"),
                    totalDuration: 16 * 60
                )
            ]
        )
    )
    .padding(24)
    .frame(height: 280)
    .background(Color(red: 250 / 255, green: 243 / 255, blue: 230 / 255))
}
