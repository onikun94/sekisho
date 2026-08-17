import FamilyControls
import SwiftUI

struct WeeklyRulesView: View {
    @EnvironmentObject private var model: AppModel
    let allowsLockedOverride: Bool

    init(allowsLockedOverride: Bool = false) {
        self.allowsLockedOverride = allowsLockedOverride
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                modeCard

                if model.isIndividualLimitMode {
                    individualLimitSection
                } else {
                    combinedLimitSection
                    strictModeCard
                }

                Text(privacyMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.sekishoSecondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 32)
        }
        .foregroundStyle(Color.sekishoInk)
        .background(Color.sekishoPaper.ignoresSafeArea())
        .navigationTitle(allowsLockedOverride ? "Pro設定・検証" : "関所Pro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("時間の約束")
                .font(.title2.weight(.bold))

            Text("合計時間で見守るか、対象ごとに別々の上限を決められます。")
                .font(.subheadline)
                .foregroundStyle(Color.sekishoSecondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("制限方法")
                .font(.headline)

            Picker("制限方法", selection: modeBinding) {
                ForEach(UsageLimitMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isConfigurationLocked)
            .accessibilityHint(
                isConfigurationLocked
                    ? "見守り中のため変更できません"
                    : "合計時間または対象ごとの上限を選びます"
            )

            Label(modeDescription, systemImage: modeDescriptionIcon)
                .font(.caption)
                .foregroundStyle(Color.sekishoSecondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            if isConfigurationLocked {
                Label("見守り中の約束は変更できません", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.sekishoVermilion)
            }
        }
        .padding(18)
        .background(Color.sekishoCardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.sekishoInk.opacity(0.11), lineWidth: 1)
        }
    }

    private var combinedLimitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("曜日ごとの上限")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(UsageWeekday.displayOrder) { weekday in
                    WeekdayLimitRow(
                        weekday: weekday,
                        minutes: model.usageLimit(for: weekday),
                        canDecrease: allowsLockedOverride
                            || weekday != .current()
                            || !model.isDailyConfigurationLocked,
                        canIncrease: allowsLockedOverride
                            || model.canIncreaseUsageLimit(for: weekday),
                        decrease: {
                            updateWeekdayLimit(
                                model.usageLimit(for: weekday) - 5,
                                weekday: weekday
                            )
                        },
                        increase: {
                            updateWeekdayLimit(
                                model.usageLimit(for: weekday) + 5,
                                weekday: weekday
                            )
                        }
                    )

                    if weekday != UsageWeekday.displayOrder.last {
                        Divider()
                            .overlay(Color.sekishoInk.opacity(0.10))
                            .padding(.leading, 18)
                    }
                }
            }
            .background(Color.sekishoCardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.sekishoInk.opacity(0.11), lineWidth: 1)
            }
        }
    }

    private var individualLimitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("対象ごとの上限")
                    .font(.headline)

                Text("上限に達した対象だけを閉じ、ほかの対象は引き続き使えます。")
                    .font(.caption)
                    .foregroundStyle(Color.sekishoSecondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.targetUsageLimitRules.isEmpty {
                Label("先に見守る対象を選んでください", systemImage: "scope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.sekishoSecondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .background(Color.sekishoCardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.targetUsageLimitRules.enumerated()), id: \.element.id) { index, rule in
                        TargetLimitRow(
                            rule: rule,
                            canDecrease: allowsLockedOverride || !model.isDailyConfigurationLocked,
                            canIncrease: allowsLockedOverride || !model.isDailyConfigurationLocked,
                            decrease: {
                                updateTargetLimit(
                                    ruleID: rule.id,
                                    minutes: rule.limitMinutes - 5
                                )
                            },
                            increase: {
                                updateTargetLimit(
                                    ruleID: rule.id,
                                    minutes: rule.limitMinutes + 5
                                )
                            }
                        )

                        if index < model.targetUsageLimitRules.count - 1 {
                            Divider()
                                .overlay(Color.sekishoInk.opacity(0.10))
                                .padding(.leading, 18)
                        }
                    }
                }
                .background(Color.sekishoCardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.sekishoInk.opacity(0.11), lineWidth: 1)
                }
            }
        }
    }

    private var strictModeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: strictModeBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("厳格モード", systemImage: "lock.shield.fill")
                        .font(.body.weight(.semibold))

                    Text(strictModeDescription)
                        .font(.caption)
                        .foregroundStyle(Color.sekishoSecondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Color.sekishoVermilion)
            .disabled(isConfigurationLocked)
            .accessibilityHint(
                isConfigurationLocked
                    ? "見守り中のため変更できません"
                    : "オンにすると上限を増やしにくくします"
            )

            if model.areRuleChangesLockedToday {
                Label("今日以外は、上限を下げる変更ができます。", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.sekishoSage)
            }
        }
        .padding(18)
        .background(Color.sekishoVermilion.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.sekishoVermilion.opacity(0.20), lineWidth: 1)
        }
    }

    private var modeBinding: Binding<UsageLimitMode> {
        Binding(
            get: { model.targetLimitConfiguration.mode },
            set: { mode in
                if allowsLockedOverride {
                    #if DEBUG || INTERNAL_TESTING
                    model.debugSetUsageLimitMode(mode)
                    #endif
                } else {
                    model.setUsageLimitMode(mode)
                }
            }
        )
    }

    private var strictModeBinding: Binding<Bool> {
        Binding(
            get: { model.strictModeEnabled },
            set: { isEnabled in
                if allowsLockedOverride {
                    #if DEBUG || INTERNAL_TESTING
                    model.debugSetStrictModeEnabled(isEnabled)
                    #endif
                } else {
                    model.setStrictModeEnabled(isEnabled)
                }
            }
        )
    }

    private var isConfigurationLocked: Bool {
        model.isDailyConfigurationLocked && !allowsLockedOverride
    }

    private var modeDescription: String {
        switch model.targetLimitConfiguration.mode {
        case .combined:
            "選んだ対象の利用時間を合計し、曜日ごとの上限でまとめて閉じます。"
        case .individual:
            "アプリ・カテゴリ・Webサイトごとに別々の上限で見守ります。"
        }
    }

    private var modeDescriptionIcon: String {
        model.isIndividualLimitMode ? "square.grid.2x2.fill" : "sum"
    }

    private var strictModeDescription: String {
        if model.strictModeEnabled {
            return "見守り中の今日の約束は変更できません。ほかの曜日も上限を増やせません。"
        }

        return "約束をゆるめにくくして、上限を延ばす瞬間を減らします。"
    }

    private var privacyMessage: String {
        "利用時間と個別の上限は端末内だけに保存され、端末の外へ送信しません。"
    }

    private func updateWeekdayLimit(_ minutes: Int, weekday: UsageWeekday) {
        if allowsLockedOverride {
            #if DEBUG || INTERNAL_TESTING
            model.debugUpdateUsageLimit(minutes, for: weekday)
            #endif
        } else {
            model.updateUsageLimit(minutes, for: weekday)
        }
    }

    private func updateTargetLimit(ruleID: String, minutes: Int) {
        if allowsLockedOverride {
            #if DEBUG || INTERNAL_TESTING
            model.debugUpdateTargetUsageLimit(ruleID: ruleID, minutes: minutes)
            #endif
        } else {
            model.updateTargetUsageLimit(ruleID: ruleID, minutes: minutes)
        }
    }
}

private struct WeekdayLimitRow: View {
    let weekday: UsageWeekday
    let minutes: Int
    let canDecrease: Bool
    let canIncrease: Bool
    let decrease: () -> Void
    let increase: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(weekday.title)
                .font(.body.weight(.medium))
                .frame(width: 46, alignment: .leading)

            Spacer(minLength: 8)

            adjustmentButton(
                systemImage: "minus",
                accessibilityLabel: "\(weekday.title)の上限を5分減らす",
                action: decrease
            )
            .disabled(minutes <= 5 || !canDecrease)

            Text("\(minutes)分")
                .font(.body.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.sekishoVermilion)
                .frame(minWidth: 54)
                .accessibilityLabel("\(weekday.title)の上限、\(minutes)分")

            adjustmentButton(
                systemImage: "plus",
                accessibilityLabel: "\(weekday.title)の上限を5分増やす",
                action: increase
            )
            .disabled(minutes >= 240 || !canIncrease)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 64)
    }
}

private struct TargetLimitRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let rule: TargetUsageLimitRule
    let canDecrease: Bool
    let canIncrease: Bool
    let decrease: () -> Void
    let increase: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                targetLabel
                Spacer(minLength: 8)
                controls
            }

            VStack(alignment: .leading, spacing: 8) {
                targetLabel
                controls
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 104 : 72)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var targetLabel: some View {
        Group {
            switch rule.target {
            case .application(let token):
                Label(token)
            case .category(let token):
                Label(token)
            case .webDomain(let token):
                Label(token)
            }
        }
        .font(.body.weight(.medium))
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }

    private var controls: some View {
        HStack(spacing: 4) {
            adjustmentButton(
                systemImage: "minus",
                accessibilityLabel: "上限を5分減らす",
                action: decrease
            )
            .disabled(rule.limitMinutes <= 5 || !canDecrease)

            Text("\(rule.limitMinutes)分")
                .font(.body.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.sekishoVermilion)
                .frame(minWidth: 56)
                .accessibilityLabel("上限\(rule.limitMinutes)分")

            adjustmentButton(
                systemImage: "plus",
                accessibilityLabel: "上限を5分増やす",
                action: increase
            )
            .disabled(rule.limitMinutes >= 240 || !canIncrease)
        }
    }
}

private func adjustmentButton(
    systemImage: String,
    accessibilityLabel: String,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Image(systemName: systemImage)
            .font(.body.weight(.bold))
            .foregroundStyle(Color.sekishoInk)
            .frame(width: 44, height: 44)
            .background(Color.sekishoSand.opacity(0.16), in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
}

#Preview {
    NavigationStack {
        WeeklyRulesView()
            .environmentObject(AppModel())
    }
}
