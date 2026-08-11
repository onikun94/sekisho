import SwiftUI

struct TodayUsageReportView: View {
    let summary: TodayUsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.isLimited ? "制限中" : "あと \(summary.remainingMinutes)分")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(summary.isLimited ? Color.reportRed : Color.reportInk)

                Spacer(minLength: 8)

                Text(summary.isLimited ? "上限 \(summary.limitMinutes)分" : "利用 \(summary.usedMinutes) / \(summary.limitMinutes)分")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.reportInk.opacity(0.52))
            }
            .minimumScaleFactor(0.76)
            .lineLimit(1)

            WoodenReportProgressBar(
                progress: summary.isLimited ? 1 : max(1 - summary.progress, 0),
                isLimited: summary.isLimited
            )
            .frame(height: 30)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Color.reportInk)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if summary.isLimited {
            return "制限中。今日の利用は\(summary.usedMinutes)分、上限は\(summary.limitMinutes)分です"
        }

        return "残り\(summary.remainingMinutes)分。今日の利用は\(summary.usedMinutes)分、上限は\(summary.limitMinutes)分です"
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
                    .fill(Color(red: 250 / 255, green: 243 / 255, blue: 230 / 255).opacity(0.9))
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
    static let reportInk = Color(red: 0.22, green: 0.18, blue: 0.15)
    static let reportSage = Color(red: 0.38, green: 0.47, blue: 0.35)
    static let reportRed = Color(red: 0.70, green: 0.20, blue: 0.16)
}

#Preview("利用中") {
    TodayUsageReportView(
        summary: TodayUsageSummary(
            totalDuration: 22 * 60,
            limitMinutes: 60,
            applications: [],
            categories: [],
            webDomains: []
        )
    )
    .padding(24)
    .background(Color(red: 250 / 255, green: 243 / 255, blue: 230 / 255))
}

#Preview("制限中") {
    TodayUsageReportView(
        summary: TodayUsageSummary(
            totalDuration: 60 * 60,
            limitMinutes: 60,
            applications: [],
            categories: [],
            webDomains: []
        )
    )
    .padding(24)
    .background(Color(red: 250 / 255, green: 243 / 255, blue: 230 / 255))
}
