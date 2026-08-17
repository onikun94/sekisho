import RevenueCat
import SwiftUI

struct SekishoProView: View {
    private enum Plan: String, CaseIterable, Identifiable {
        case annual
        case monthly

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var selectedPlan: Plan = .annual

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                WardrobeHeader(title: "関所Pro") {
                    dismiss()
                }

                ZStack {
                    SekishoSceneBackdrop()
                        .padding(.horizontal, 48)

                    AnimatedSekishoMascot(
                        assetName: "SekishoMascotSakura",
                        accessibilityLabel: "桜の羽織を着た関所の番人"
                    )
                    .padding(.horizontal, 74)
                    .padding(.vertical, 18)
                }
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 170 : 210)

                Text("自分に合う約束を、もっと丁寧に。")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    ProBenefitRow(icon: "square.grid.2x2", text: "アプリごとの個別上限")
                    ProBenefitRow(icon: "calendar", text: "曜日ごとの細かな制限")
                    ProBenefitRow(icon: "lock.shield", text: "今日のルールを守る厳格モード")
                    ProBenefitRow(icon: "tshirt", text: "限定の番人と衣装")
                }
                .padding(.top, 24)

                VStack(spacing: 12) {
                    planButton(.annual)
                    planButton(.monthly)
                }
                .padding(.top, 26)

                Text(purchaseDisclosure)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.sekishoSecondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)

                Button {
                    if purchaseManager.isPremium {
                        return
                    }
                    purchaseManager.purchase(selectedPackage)
                } label: {
                    HStack(spacing: 10) {
                        if purchaseManager.isPurchasing {
                            ProgressView()
                                .tint(Color.sekishoOnAccent)
                        }

                        Text(purchaseButtonTitle)
                    }
                }
                .buttonStyle(WoodenPrimaryButtonStyle())
                .disabled(
                    purchaseManager.isPurchasing
                        || purchaseManager.isPremium
                        || selectedPackage == nil
                )
                .padding(.top, 10)

                Button("購入を復元") {
                    purchaseManager.restorePurchases()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.sekishoSecondaryInk)
                .frame(minHeight: 44)
                .padding(.top, 4)

                HStack(spacing: 20) {
                    NavigationLink {
                        LegalDocumentView(document: .terms)
                    } label: {
                        Text("利用規約")
                    }

                    NavigationLink {
                        LegalDocumentView(document: .privacy)
                    } label: {
                        Text("プライバシー")
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.sekishoSecondaryInk)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 36)
        }
        .foregroundStyle(Color.sekishoInk)
        .background(Color.sekishoPaper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            purchaseManager.refresh()
        }
        .alert("お知らせ", isPresented: purchaseMessageBinding) {
            Button("閉じる") {
                purchaseManager.message = nil
            }
        } message: {
            Text(purchaseManager.message ?? "")
        }
    }

    private var selectedPackage: Package? {
        switch selectedPlan {
        case .annual:
            purchaseManager.annualPackage
        case .monthly:
            purchaseManager.monthlyPackage
        }
    }

    private var purchaseButtonTitle: String {
        if purchaseManager.isPremium {
            return "Proを利用中"
        }

        guard selectedPackage != nil else {
            return "価格を確認中"
        }

        if let freeTrialPeriod {
            return "\(freeTrialPeriod)無料でProを始める"
        }

        return "Proを始める"
    }

    private var freeTrialPeriod: String? {
        purchaseManager.freeTrialPeriodText(selectedPackage)
    }

    private var purchaseDisclosure: String {
        guard selectedPackage != nil else {
            return "App Storeから価格を取得しています。価格と更新条件を確認できるまで購入は始まりません。"
        }

        let renewalPrice = selectedPlan == .annual
            ? "年額\(purchaseManager.annualPrice)"
            : "月額\(purchaseManager.monthlyPrice)"

        if let freeTrialPeriod {
            return "\(freeTrialPeriod)は無料です。その後は\(renewalPrice)で自動更新されます。いつでも解約できます。"
        }

        return "\(renewalPrice)で自動更新されます。購入前にApp Storeの確認画面でも金額を確認できます。"
    }

    private func planButton(_ plan: Plan) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            selectedPlan = plan
        } label: {
            planButtonContent(plan, isSelected: isSelected)
            .foregroundStyle(Color.sekishoInk)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(Color.sekishoCardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.sekishoVermilion : Color.sekishoInk.opacity(0.13), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func planButtonContent(_ plan: Plan, isSelected: Bool) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 14) {
                    planSelectionIcon(isSelected: isSelected)
                    planDescription(plan)
                }

                if plan == .annual, annualSavingsText != nil {
                    annualSavingsBadge
                        .padding(.leading, 38)
                }
            }
        } else {
            HStack(spacing: 14) {
                planSelectionIcon(isSelected: isSelected)
                planDescription(plan)
                Spacer()

                if plan == .annual, annualSavingsText != nil {
                    annualSavingsBadge
                }
            }
        }
    }

    private func planSelectionIcon(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? Color.sekishoVermilion : Color.sekishoSecondaryInk)
    }

    private func planDescription(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(plan == .annual ? "年額プラン" : "月額プラン")
                .font(.headline)

            Text(plan == .annual ? "\(purchaseManager.annualPrice) / 年" : "\(purchaseManager.monthlyPrice) / 月")
                .font(.subheadline)
                .foregroundStyle(Color.sekishoSecondaryInk)
        }
    }

    private var annualSavingsBadge: some View {
        Text(annualSavingsText ?? "")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.sekishoOnAccent)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.sekishoVermilion, in: Capsule())
    }

    private var annualSavingsText: String? {
        purchaseManager.annualSavingsPercentage.map { "年間\($0)%お得" }
    }

    private var purchaseMessageBinding: Binding<Bool> {
        Binding(
            get: { purchaseManager.message != nil },
            set: { isPresented in
                if !isPresented {
                    purchaseManager.message = nil
                }
            }
        )
    }
}

private struct ProBenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.sekishoVermilion)
                .frame(width: 32, height: 32)
                .background(Color.sekishoVermilion.opacity(0.10), in: Circle())

            Text(text)
                .font(.body.weight(.medium))
        }
    }
}

#Preview {
    NavigationStack {
        SekishoProView()
            .environmentObject(PurchaseManager(configureSDK: false))
    }
}
