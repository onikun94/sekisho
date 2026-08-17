import FamilyControls
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var isPickerPresented = false
    @State private var draftSelection = FamilyActivitySelection()
    @State private var isAppRemovalProtectionConfirmationPresented = false
    #if DEBUG || INTERNAL_TESTING
    @State private var isDeveloperMenuPresented = false
    @State private var shouldOpenPickerAfterDeveloperMenu = false
    @State private var isDeveloperTargetOverrideActive = false
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HandwrittenAssetText(
                        assetName: "HandTitleSettings",
                        label: "設定",
                        height: 50
                    )
                    #if DEBUG || INTERNAL_TESTING
                    .onLongPressGesture(minimumDuration: 1.2) {
                        isDeveloperMenuPresented = true
                    }
                    .accessibilityAction(named: "開発メニューを開く") {
                        isDeveloperMenuPresented = true
                    }
                    #endif

                    RuleSettingsCard(
                        isScreenTimeAuthorized: model.isScreenTimeAuthorized,
                        selectedTokenCount: model.selectedTokenCount,
                        usageLimitMinutes: Binding(
                            get: { model.usageLimitMinutes },
                            set: { model.updateEverydayUsageLimit($0) }
                        ),
                        status: monitoringStatus,
                        isPremium: purchaseManager.isPremium,
                        isIndividualLimitMode: model.isIndividualLimitMode,
                        isTargetsLocked: model.areTargetsLockedToday,
                        isLimitLocked: model.isDailyConfigurationLocked,
                        requestAuthorization: {
                            Task {
                                await model.requestScreenTimeAuthorization()
                            }
                        }
                    ) {
                        draftSelection = model.selectedApps
                        isPickerPresented = true
                    }

                    AppRemovalProtectionCard(
                        isEnabled: model.isAppRemovalProtectionEnabled,
                        isScreenTimeAuthorized: model.isScreenTimeAuthorized
                    ) { isEnabled in
                        if isEnabled {
                            isAppRemovalProtectionConfirmationPresented = true
                        } else {
                            model.setAppRemovalProtectionEnabled(false)
                        }
                    }

                    if purchaseManager.isPremium {
                        NavigationLink {
                            WeeklyRulesView()
                        } label: {
                            ProSettingsCard(isPremium: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            SekishoProView()
                        } label: {
                            ProSettingsCard(isPremium: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 110)
            }
            .foregroundStyle(Color.sekishoInk)
            .background(Color.sekishoPaper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .alert(
                "すべてのアプリの削除を禁止しますか？",
                isPresented: $isAppRemovalProtectionConfirmationPresented
            ) {
                Button("削除を禁止") {
                    model.setAppRemovalProtectionEnabled(true)
                }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("iOSの仕様により、関所だけでなく端末上のすべてのアプリを削除できなくなります。設定からOFFにすると解除できます。")
            }
            .familyActivityPicker(
                headerText: "見守るアプリやWebサイトを選びます。",
                footerText: pickerFooterText,
                isPresented: $isPickerPresented,
                selection: $draftSelection
            )
            #if DEBUG || INTERNAL_TESTING
            .sheet(
                isPresented: $isDeveloperMenuPresented,
                onDismiss: openPickerAfterDeveloperMenuIfNeeded
            ) {
                DeveloperToolsView {
                    shouldOpenPickerAfterDeveloperMenu = true
                }
                .environmentObject(model)
                .environmentObject(purchaseManager)
            }
            .sensoryFeedback(.success, trigger: isDeveloperMenuPresented)
            #endif
            .onChange(of: isPickerPresented) { wasPresented, isPresented in
                if wasPresented, !isPresented {
                    #if DEBUG || INTERNAL_TESTING
                    if isDeveloperTargetOverrideActive {
                        isDeveloperTargetOverrideActive = false
                        model.debugUpdateSelectedApps(draftSelection)
                    } else {
                        model.updateSelectedApps(draftSelection)
                    }
                    #else
                    model.updateSelectedApps(draftSelection)
                    #endif
                    model.ensureUsageLimitMonitoring()
                }
            }
        }
    }

    private var monitoringStatus: MonitoringStatus {
        if !model.isScreenTimeAuthorized {
            return MonitoringStatus(
                label: "許可が必要",
                systemImage: "exclamationmark.triangle.fill",
                tint: Color.sekishoVermilion
            )
        }

        if model.selectedTokenCount == 0 {
            return MonitoringStatus(
                label: "対象を選択",
                systemImage: "scope",
                tint: Color.sekishoVermilion
            )
        }

        if model.isUsageLimitMonitoringEnabled {
            return MonitoringStatus(
                label: "見守り中",
                systemImage: "checkmark.circle.fill",
                tint: Color.sekishoSage
            )
        }

        return MonitoringStatus(
            label: "準備中",
            systemImage: "ellipsis.circle.fill",
            tint: Color.sekishoSecondaryInk
        )
    }

    private var pickerFooterText: String {
        #if DEBUG || INTERNAL_TESTING
        if isDeveloperTargetOverrideActive {
            return "開発メニューからの変更です。閉じると監視を再登録します。"
        }
        #endif

        if model.isUsageLimitMonitoringEnabled {
            return "見守り中は、通常の設定画面から対象を変更できません。"
        }

        return "選択すると自動で見守りが始まります。内容は端末内に保存されます。"
    }

    #if DEBUG || INTERNAL_TESTING
    private func openPickerAfterDeveloperMenuIfNeeded() {
        guard shouldOpenPickerAfterDeveloperMenu else {
            return
        }

        shouldOpenPickerAfterDeveloperMenu = false
        isDeveloperTargetOverrideActive = true
        draftSelection = model.selectedApps
        isPickerPresented = true
    }
    #endif
}

#if DEBUG || INTERNAL_TESTING
private struct DeveloperToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var purchaseManager: PurchaseManager

    let requestTargetPicker: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("現在の状態") {
                    LabeledContent("制限") {
                        Label(
                            developerLimitLabel,
                            systemImage: model.barrierState == .locked ? "lock.fill" : "lock.open.fill"
                        )
                        .foregroundStyle(model.barrierState == .locked ? Color.limitRed : Color.sekishoSage)
                    }

                    LabeledContent("見守り対象", value: "\(model.selectedTokenCount)件")
                    LabeledContent("監視", value: model.isUsageLimitMonitoringEnabled ? "稼働中" : "停止中")
                }

                Section {
                    Toggle(isOn: developerPremiumModeBinding) {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Proモード")
                                Text("本画面を購入後の状態に切り替える")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: purchaseManager.isPremium ? "crown.fill" : "crown")
                                .foregroundStyle(
                                    purchaseManager.isPremium
                                        ? Color.sekishoVermilion
                                        : Color.secondary
                                )
                        }
                    }
                    .frame(minHeight: 44)

                    if !model.isIndividualLimitMode {
                        Stepper(
                            value: Binding(
                                get: { model.usageLimitMinutes },
                                set: { model.debugUpdateEverydayUsageLimit($0) }
                            ),
                            in: 5...240,
                            step: 5
                        ) {
                            LabeledContent("全曜日の上限", value: "\(model.usageLimitMinutes)分")
                        }
                    }
                } header: {
                    Text("検証用の設定")
                } footer: {
                    Text("Proモードを切り替えると、ホームと通常の設定画面も同じ購入状態として動作します。")
                }

                Section {
                    if model.isIndividualLimitMode {
                        ForEach(model.targetUsageLimitRules) { rule in
                            Button {
                                model.debugForceIndividualLimitNow(ruleID: rule.id)
                            } label: {
                                DeveloperTargetCommandLabel(
                                    rule: rule,
                                    isLimited: model.isIndividualTargetLimited(ruleID: rule.id)
                                )
                            }
                            .disabled(model.isIndividualTargetLimited(ruleID: rule.id))
                        }
                    } else {
                        Button {
                            model.debugForceLimitNow()
                        } label: {
                            Label("今すぐ制限する", systemImage: "lock.fill")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .disabled(model.selectedTokenCount == 0)
                    }

                    Button {
                        model.debugUnlockToday()
                    } label: {
                        Label("今日の制限を解除", systemImage: "lock.open")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }

                    Button {
                        requestTargetPicker()
                        dismiss()
                    } label: {
                        Label("見守り対象を変更", systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                } header: {
                    Text("コマンド")
                } footer: {
                    Text("対象の変更を含むこの操作は、内部検証ビルドの開発メニューからだけ実行できます。")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("開発メニュー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var developerLimitLabel: String {
        if model.hasPartialIndividualLimit {
            return "\(model.lockedIndividualTargetCount)件だけ制限中"
        }

        return model.barrierState == .locked ? "すべて制限中" : "解除中"
    }

    private var developerPremiumModeBinding: Binding<Bool> {
        Binding(
            get: { purchaseManager.isPremium },
            set: { isEnabled in
                purchaseManager.setDeveloperPremiumMode(isEnabled)

                let requestedMode: UsageLimitMode = isEnabled ? .individual : .combined
                if model.targetLimitConfiguration.mode != requestedMode {
                    // Switching the simulated entitlement also changes the
                    // active monitoring behavior; no Pro-only mode remains
                    // hidden behind the Free screen, and vice versa.
                    model.debugUnlockToday()
                    model.debugSetUsageLimitMode(requestedMode)
                }
            }
        )
    }
}

private struct DeveloperTargetCommandLabel: View {
    let rule: TargetUsageLimitRule
    let isLimited: Bool

    var body: some View {
        HStack(spacing: 12) {
            targetLabel

            Spacer(minLength: 8)

            Label(
                isLimited ? "制限中" : "この1件を制限",
                systemImage: isLimited ? "lock.fill" : "lock"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(isLimited ? Color.limitRed : Color.sekishoVermilion)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    @ViewBuilder
    private var targetLabel: some View {
        switch rule.target {
        case .application(let token):
            Label(token)
        case .category(let token):
            Label(token)
        case .webDomain(let token):
            Label(token)
        }
    }
}
#endif

private struct MonitoringStatus {
    let label: String
    let systemImage: String
    let tint: Color
}

private struct RuleSettingsCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let isScreenTimeAuthorized: Bool
    let selectedTokenCount: Int
    @Binding var usageLimitMinutes: Int
    let status: MonitoringStatus
    let isPremium: Bool
    let isIndividualLimitMode: Bool
    let isTargetsLocked: Bool
    let isLimitLocked: Bool
    let requestAuthorization: () -> Void
    let selectTargets: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        headerTitle
                        statusPill
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        headerTitle
                        Spacer(minLength: 8)
                        statusPill
                    }
                }
            }
            .padding(18)

            Divider()
                .overlay(Color.sekishoInk.opacity(0.10))
                .padding(.horizontal, 18)

            permissionRow

            Divider()
                .overlay(Color.sekishoInk.opacity(0.10))
                .padding(.horizontal, 18)

            Button(action: selectTargets) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 10) {
                            targetDescription
                            targetCount
                                .padding(.leading, 42)
                        }
                    } else {
                        HStack(spacing: 12) {
                            targetDescription
                            Spacer(minLength: 8)
                            targetCount
                        }
                    }
                }
                .foregroundStyle(Color.sekishoInk)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isScreenTimeAuthorized || isTargetsLocked)
            .opacity(!isScreenTimeAuthorized || isTargetsLocked ? 0.78 : 1)
            .accessibilityLabel("見守る対象、\(selectedTokenCount)件")
            .accessibilityHint(
                !isScreenTimeAuthorized
                    ? "先にScreen Timeの利用を許可してください"
                    : isTargetsLocked
                        ? "見守り中のため変更できません"
                        : "ダブルタップして対象を変更します"
            )

            Divider()
                .overlay(Color.sekishoInk.opacity(0.10))
                .padding(.horizontal, 18)

            Group {
                HStack(alignment: .top, spacing: 12) {
                    SetupStepMarker(number: 3, isComplete: hasConfiguredLimit)

                    Group {
                        if isPremium {
                            premiumLimitContent
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(premiumLimitAccessibilityLabel)
                        } else if dynamicTypeSize.isAccessibilitySize {
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
                    .disabled(!canAdjustLimit)
                    .opacity(canAdjustLimit ? 1 : 0.78)
                }
            }
            .padding(18)
        }
        .background(Color.sekishoCardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.sekishoInk.opacity(0.11), lineWidth: 1)
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今日の約束")
                .font(.headline)

            Text("決めた内容は自動で見守ります")
                .font(.caption)
                .foregroundStyle(Color.sekishoSecondaryInk)
        }
    }

    private var statusPill: some View {
        Label(status.label, systemImage: status.systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(status.tint.opacity(0.12), in: Capsule())
    }

    private var targetDescription: some View {
        HStack(alignment: .top, spacing: 12) {
            SetupStepMarker(number: 2, isComplete: selectedTokenCount > 0)

            VStack(alignment: .leading, spacing: 4) {
                Text("見守る対象")
                    .font(.body.weight(.medium))

                Text(targetSubtitle)
                    .font(.caption)
                    .foregroundStyle(Color.sekishoSecondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var targetCount: some View {
        Group {
            if isTargetsLocked {
                Label("\(selectedTokenCount)件", systemImage: "lock.fill")
            } else {
                Text("\(selectedTokenCount)件  ›")
            }
        }
        .font(.body.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(isTargetsLocked ? Color.sekishoSecondaryInk : Color.sekishoVermilion)
    }

    @ViewBuilder
    private var premiumLimitContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                premiumLimitLabel
                premiumLimitValue
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 16) {
                premiumLimitLabel
                Spacer(minLength: 8)
                premiumLimitValue
            }
        }
    }

    private var premiumLimitLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isIndividualLimitMode ? "対象ごとの上限" : "今日の上限")
                .font(.body.weight(.medium))

            Text(limitSubtitle)
                .font(.caption)
                .foregroundStyle(Color.sekishoSecondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var premiumLimitValue: some View {
        Text(isIndividualLimitMode ? "\(selectedTokenCount)件" : "\(usageLimitMinutes)分")
            .font(.title3.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Color.sekishoVermilion)
    }

    @ViewBuilder
    private var permissionRow: some View {
        if isScreenTimeAuthorized {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        authorizedPermissionDescription
                        authorizedPermissionStatus
                            .padding(.leading, 42)
                    }
                } else {
                    HStack(spacing: 12) {
                        authorizedPermissionDescription
                        Spacer(minLength: 8)
                        authorizedPermissionStatus
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 72)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("手順1、Screen Time、許可済み。使用時間は端末内で集計されます")
        } else {
            Button(action: requestAuthorization) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 12) {
                            unauthorizedPermissionDescription
                            authorizationButtonLabel
                                .padding(.leading, 42)
                        }
                    } else {
                        HStack(spacing: 12) {
                            unauthorizedPermissionDescription
                            Spacer(minLength: 8)
                            authorizationButtonLabel
                        }
                    }
                }
                .foregroundStyle(Color.sekishoInk)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 84)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("手順1、Screen Timeの利用を許可")
            .accessibilityHint("使用時間は端末内で集計され、外部には送信しません")
        }
    }

    private var authorizedPermissionDescription: some View {
        HStack(alignment: .top, spacing: 12) {
            SetupStepMarker(number: 1, isComplete: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Screen Time")
                    .font(.body.weight(.medium))

                Text("使用時間は端末内で集計されます")
                    .font(.caption)
                    .foregroundStyle(Color.sekishoSecondaryInk)
            }
        }
    }

    private var authorizedPermissionStatus: some View {
        Label("許可済み", systemImage: "checkmark")
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.sekishoSage)
    }

    private var unauthorizedPermissionDescription: some View {
        HStack(alignment: .top, spacing: 12) {
            SetupStepMarker(number: 1, isComplete: false)

            VStack(alignment: .leading, spacing: 4) {
                Text("Screen Timeの利用を許可")
                    .font(.body.weight(.semibold))

                Text("使用時間は端末内で集計され、外部には送信しません")
                    .font(.caption)
                    .foregroundStyle(Color.sekishoSecondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var authorizationButtonLabel: some View {
        Text("許可する")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.sekishoOnAccent)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color.sekishoVermilion, in: Capsule())
    }

    private var limitLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("1日の上限")
                .font(.body.weight(.medium))

            Text(limitSubtitle)
                .font(.caption)
                .foregroundStyle(Color.sekishoSecondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var targetSubtitle: String {
        if !isScreenTimeAuthorized {
            return "先に手順1の許可が必要です"
        }

        if isTargetsLocked {
            return "見守り中のため変更できません"
        }

        return selectedTokenCount == 0 ? "アプリやWebサイトを選ぶ" : "選択中のアプリとWebサイト"
    }

    private var canAdjustLimit: Bool {
        hasConfiguredLimit && !isLimitLocked
    }

    private var hasConfiguredLimit: Bool {
        isScreenTimeAuthorized && selectedTokenCount > 0
    }

    private var limitSubtitle: String {
        if isLimitLocked {
            return "見守り中のため変更できません"
        }

        return isPremium
            ? isIndividualLimitMode
                ? "アプリごとに別々の時間で見守ります"
                : "曜日ごとの約束はPro設定で変更できます"
            : "対象すべての合計時間"
    }

    private var premiumLimitAccessibilityLabel: String {
        if isIndividualLimitMode {
            return "対象ごとの上限、\(selectedTokenCount)件。\(limitSubtitle)"
        }

        return "今日の上限、\(usageLimitMinutes)分。\(limitSubtitle)"
    }
}

private struct SetupStepMarker: View {
    let number: Int
    let isComplete: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill((isComplete ? Color.sekishoSage : Color.sekishoVermilion).opacity(0.14))

            if isComplete {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
            } else {
                Text("\(number)")
                    .font(.caption.weight(.bold))
            }
        }
        .foregroundStyle(isComplete ? Color.sekishoSage : Color.sekishoVermilion)
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
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

private struct AppRemovalProtectionCard: View {
    let isEnabled: Bool
    let isScreenTimeAuthorized: Bool
    let setEnabled: (Bool) -> Void

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { isEnabled },
                set: setEnabled
            )
        ) {
            HStack(spacing: 14) {
                Image("SekishoMascotWatchful")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("アプリ削除を防ぐ")
                        .font(.headline)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.sekishoSecondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
        .tint(Color.sekishoVermilion)
        .disabled(!isScreenTimeAuthorized && !isEnabled)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 88)
        .background(Color.sekishoCardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.sekishoInk.opacity(0.11), lineWidth: 1)
        }
        .opacity(isScreenTimeAuthorized || isEnabled ? 1 : 0.72)
        .accessibilityLabel("アプリ削除を防ぐ")
        .accessibilityValue(isEnabled ? "オン" : "オフ")
        .accessibilityHint(
            isScreenTimeAuthorized || isEnabled
                ? "オンの間は、関所を含むすべてのアプリを削除できません"
                : "先にScreen Timeの利用を許可してください"
        )
    }

    private var subtitle: String {
        if isEnabled {
            return "ONの間は、関所を含むすべてのアプリを削除できません"
        }

        guard isScreenTimeAuthorized else {
            return "Screen Timeの許可後に利用できます"
        }

        return "ONの間は、関所を含むすべてのアプリを削除できません"
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

                Text(isPremium ? "アプリ別・曜日別の上限を設定" : "アプリ別の上限と限定衣装")
                    .font(.caption)
                    .foregroundStyle(Color.sekishoSecondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(isPremium ? "設定  ›" : "見る  ›")
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
        .accessibilityLabel(isPremium ? "関所Pro、アプリ別と曜日別の上限を設定" : "関所Pro、アプリ別の上限と限定衣装を見る")
        .accessibilityHint(isPremium ? "ダブルタップしてProの時間設定を開きます" : "ダブルタップして関所Proを開きます")
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppModel())
        .environmentObject(PurchaseManager(configureSDK: false))
}
