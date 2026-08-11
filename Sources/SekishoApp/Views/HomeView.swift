import DeviceActivity
import FamilyControls
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @AppStorage("selectedMascotStyle") private var selectedMascotStyle = MascotStyle.standard.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header

                    MascotHero(
                        assetName: mascotAssetName,
                        isLimited: isLimited
                    )
                    .padding(.top, 8)

                    Text(isLimited ? "今日はここまで。少し休もう。" : "今日も静かに見守ります。")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(isLimited ? Color.limitRed : Color.sekishoInk.opacity(0.78))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                        .animation(.easeInOut(duration: 0.2), value: isLimited)

                    usageReport
                        .padding(.top, 22)

                    MonitoringStateLine(
                        isLimited: isLimited,
                        isConfigured: canShowUsageReport
                    )
                    .padding(.top, 14)

                    if let rejectedDate = model.lastRejectedThresholdDate,
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
            DeviceActivityReport(.sekishoTodayUsage, filter: todayUsageFilter)
                .frame(maxWidth: .infinity, minHeight: 116, alignment: .top)
        } else {
            HomeUsagePlaceholder(
                limitMinutes: model.usageLimitMinutes,
                isLimited: isLimited
            )
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .top)
        }
    }

    private var mascotAssetName: String {
        if isLimited {
            return "SekishoMascotLimited"
        }

        let style = MascotStyle(rawValue: selectedMascotStyle) ?? .standard
        if style == .sakura, purchaseManager.canUseSakura {
            return style.assetName
        }

        return MascotStyle.standard.assetName
    }

    private var isLimited: Bool {
        model.isUsageLimitMonitoringEnabled && model.barrierState == .locked
    }

    private var canShowUsageReport: Bool {
        screenTimeApproved && model.selectedTokenCount > 0
    }

    private var todayUsageFilter: DeviceActivityFilter {
        let now = Date()
        let interval = DateInterval(start: Calendar.current.startOfDay(for: now), end: now)

        return DeviceActivityFilter(
            segment: .daily(during: interval),
            applications: model.selectedApps.applicationTokens,
            categories: model.selectedApps.categoryTokens,
            webDomains: model.selectedApps.webDomainTokens
        )
    }

    private var screenTimeApproved: Bool {
        if model.authorizationStatus == .approved {
            return true
        }

        if #available(iOS 26.4, *) {
            return model.authorizationStatus == .approvedWithDataAccess
        }

        return false
    }
}

private struct MascotHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let assetName: String
    let isLimited: Bool

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
        .frame(height: 300)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: assetName)
    }
}

private struct MonitoringStateLine: View {
    @EnvironmentObject private var model: AppModel
    let isLimited: Bool
    let isConfigured: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: stateSymbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(stateColor)

            Text(stateLabel)
                .font(.footnote.weight(.semibold))

            Spacer(minLength: 8)

            Text("上限 \(model.usageLimitMinutes)分")
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Color.sekishoInk.opacity(0.58))
        }
        .frame(minHeight: 44)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.sekishoInk.opacity(0.12))
                .frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stateLabel)、1日の上限は\(model.usageLimitMinutes)分")
    }

    private var stateLabel: String {
        if !isConfigured {
            return "設定タブで制限を設定してください"
        }

        if isLimited {
            return "対象アプリを制限中"
        }

        return model.isUsageLimitMonitoringEnabled ? "自動制限は有効です" : "自動制限は停止中です"
    }

    private var stateSymbol: String {
        if !isConfigured {
            return "gearshape"
        }

        if isLimited {
            return "lock.fill"
        }

        return model.isUsageLimitMonitoringEnabled ? "checkmark.circle.fill" : "pause.circle"
    }

    private var stateColor: Color {
        if !isConfigured {
            return .sekishoInk.opacity(0.5)
        }

        if isLimited {
            return .limitRed
        }

        return model.isUsageLimitMonitoringEnabled ? .sekishoSage : .sekishoInk.opacity(0.4)
    }
}

private struct HomeUsagePlaceholder: View {
    let limitMinutes: Int
    let isLimited: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(isLimited ? "制限中" : "あと \(limitMinutes)分")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(isLimited ? Color.limitRed : Color.sekishoInk)

                Spacer(minLength: 8)

                Text(isLimited ? "上限 \(limitMinutes)分" : "残り時間")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.sekishoInk.opacity(0.52))
            }

            WoodenProgressBar(progress: 1, isLimited: isLimited)
                .frame(height: 30)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isLimited
                ? "対象アプリを制限中。上限は\(limitMinutes)分です"
                : "残り\(limitMinutes)分。今日の利用は0分です"
        )
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

#Preview {
    HomeView()
        .environmentObject(AppModel())
        .environmentObject(PurchaseManager(configureSDK: false))
}
