import FamilyControls
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var isPickerPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HandwrittenAssetText(
                        assetName: "HandTitleSettings",
                        label: "設定",
                        height: 50
                    )

                    RuleSettingsCard(
                        selectedTokenCount: model.selectedTokenCount,
                        usageLimitMinutes: $model.usageLimitMinutes,
                        status: monitoringStatus
                    ) {
                        isPickerPresented = true
                    }

                    if !model.isScreenTimeAuthorized {
                        ScreenTimePermissionCard {
                            Task {
                                await model.requestScreenTimeAuthorization()
                            }
                        }
                    }

                    NavigationLink {
                        SekishoProView()
                    } label: {
                        ProSettingsCard(isPremium: purchaseManager.isPremium)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 110)
            }
            .foregroundStyle(Color.sekishoInk)
            .background(Color.sekishoPaper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .familyActivityPicker(
                headerText: "見守るアプリやWebサイトを選びます。",
                footerText: pickerFooterText,
                isPresented: $isPickerPresented,
                selection: selectedAppsBinding
            )
            .onChange(of: isPickerPresented) { wasPresented, isPresented in
                if wasPresented, !isPresented {
                    model.ensureUsageLimitMonitoring()
                }
            }
        }
    }

    private var selectedAppsBinding: Binding<FamilyActivitySelection> {
        Binding(
            get: { model.selectedApps },
            set: { model.updateSelectedApps($0) }
        )
    }

    private var monitoringStatus: MonitoringStatus {
        if !model.isScreenTimeAuthorized {
            return MonitoringStatus(label: "許可が必要", tint: Color.sekishoSand)
        }

        if model.selectedTokenCount == 0 {
            return MonitoringStatus(label: "対象を選択", tint: Color.sekishoSand)
        }

        if model.isUsageLimitMonitoringEnabled {
            return MonitoringStatus(label: "見守り中", tint: Color.sekishoSage)
        }

        return MonitoringStatus(label: "準備中", tint: Color.sekishoSand)
    }

    private var pickerFooterText: String {
        if model.isUsageLimitMonitoringEnabled {
            return "見守り中は対象を0件にはできません。変更は自動で反映されます。"
        }

        return "選択すると自動で見守りが始まります。内容は端末内に保存されます。"
    }
}

private struct MonitoringStatus {
    let label: String
    let tint: Color
}

private struct RuleSettingsCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let selectedTokenCount: Int
    @Binding var usageLimitMinutes: Int
    let status: MonitoringStatus
    let selectTargets: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日の約束")
                        .font(.headline)

                    Text("決めた内容は自動で見守ります")
                        .font(.caption)
                        .foregroundStyle(Color.sekishoInk.opacity(0.58))
                }

                Spacer(minLength: 8)

                Text(status.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(status.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(status.tint.opacity(0.12), in: Capsule())
            }
            .padding(18)

            Divider()
                .overlay(Color.sekishoInk.opacity(0.10))
                .padding(.horizontal, 18)

            Button(action: selectTargets) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("見守る対象")
                            .font(.body.weight(.medium))

                        Text(selectedTokenCount == 0 ? "アプリやWebサイトを選ぶ" : "選択中のアプリとWebサイト")
                            .font(.caption)
                            .foregroundStyle(Color.sekishoInk.opacity(0.56))
                    }

                    Spacer(minLength: 8)

                    Text("\(selectedTokenCount)件  ›")
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.sekishoVermilion)
                }
                .foregroundStyle(Color.sekishoInk)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 72)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("見守る対象、\(selectedTokenCount)件")
            .accessibilityHint("ダブルタップして対象を変更します")

            Divider()
                .overlay(Color.sekishoInk.opacity(0.10))
                .padding(.horizontal, 18)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        limitLabel
                        LimitAdjuster(value: $usageLimitMinutes)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 16) {
                        limitLabel
                        Spacer(minLength: 8)
                        LimitAdjuster(value: $usageLimitMinutes)
                    }
                }
            }
            .padding(18)
        }
        .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.sekishoInk.opacity(0.11), lineWidth: 1)
        }
    }

    private var limitLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("1日の上限")
                .font(.body.weight(.medium))

            Text("対象すべての合計時間")
                .font(.caption)
                .foregroundStyle(Color.sekishoInk.opacity(0.56))
        }
    }
}

private struct LimitAdjuster: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 4) {
            adjustmentButton(label: "−", accessibilityLabel: "上限を5分減らす") {
                value = max(5, value - 5)
            }
            .disabled(value <= 5)

            Text("\(value)分")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.sekishoVermilion)
                .frame(minWidth: 68)
                .accessibilityLabel("1日の上限、\(value)分")

            adjustmentButton(label: "＋", accessibilityLabel: "上限を5分増やす") {
                value = min(240, value + 5)
            }
            .disabled(value >= 240)
        }
    }

    private func adjustmentButton(
        label: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.sekishoInk)
                .frame(width: 44, height: 44)
                .background(Color.sekishoSand.opacity(0.16), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ScreenTimePermissionCard: View {
    let requestAuthorization: () -> Void

    var body: some View {
        Button(action: requestAuthorization) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screen Timeの利用を許可")
                        .font(.body.weight(.semibold))

                    Text("アプリの利用時間を見守るために必要です")
                        .font(.caption)
                        .foregroundStyle(Color.sekishoInk.opacity(0.58))
                }

                Spacer(minLength: 8)

                Text("許可する")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.sekishoPaper)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Color.sekishoVermilion, in: Capsule())
            }
            .foregroundStyle(Color.sekishoInk)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(Color.sekishoVermilion.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.sekishoVermilion.opacity(0.24), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ProSettingsCard: View {
    let isPremium: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image("SekishoMascotSakura")
                .resizable()
                .scaledToFit()
                .frame(width: 68, height: 68)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("関所Pro")
                    .font(.headline)

                Text(isPremium ? "Proを利用中です" : "曜日別の約束と限定衣装")
                    .font(.caption)
                    .foregroundStyle(Color.sekishoInk.opacity(0.60))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(isPremium ? "利用中" : "見る  ›")
                .font(.caption.weight(.bold))
                .foregroundStyle(isPremium ? Color.sekishoSage : Color.sekishoVermilion)
        }
        .foregroundStyle(Color.sekishoInk)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 92)
        .background(Color.sekishoSand.opacity(0.13), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.sekishoInk.opacity(0.11), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPremium ? "関所Pro、利用中" : "関所Pro、曜日別の約束と限定衣装を見る")
        .accessibilityHint("ダブルタップして関所Proを開きます")
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppModel())
        .environmentObject(PurchaseManager(configureSDK: false))
}
