import RevenueCat
import SwiftUI

struct SekishoProView: View {
    private enum Plan: String, CaseIterable, Identifiable {
        case annual
        case monthly

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
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
                .frame(height: 230)

                Text("自分に合う約束を、もっと丁寧に。")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    ProBenefitRow(icon: "calendar", text: "曜日ごとの細かな制限")
                    ProBenefitRow(icon: "lock.shield", text: "解除しにくい厳格モード")
                    ProBenefitRow(icon: "tshirt", text: "限定の番人と衣装")
                }
                .padding(.top, 24)

                VStack(spacing: 12) {
                    planButton(.annual)
                    planButton(.monthly)
                }
                .padding(.top, 26)

                Button {
                    if purchaseManager.isPremium {
                        return
                    }
                    purchaseManager.purchase(selectedPackage)
                } label: {
                    HStack(spacing: 10) {
                        if purchaseManager.isPurchasing {
                            ProgressView()
                                .tint(Color.sekishoPaper)
                        }

                        Text(purchaseManager.isPremium ? "Proを利用中" : "7日間無料ではじめる")
                    }
                }
                .buttonStyle(WoodenPrimaryButtonStyle())
                .disabled(purchaseManager.isPurchasing || purchaseManager.isPremium)
                .padding(.top, 20)

                Text(trialNote)
                    .font(.caption)
                    .foregroundStyle(Color.sekishoInk.opacity(0.56))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)

                Button("購入を復元") {
                    purchaseManager.restorePurchases()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.sekishoInk.opacity(0.68))
                .frame(minHeight: 44)
                .padding(.top, 4)

                HStack(spacing: 20) {
                    Button("利用規約") {
                        purchaseManager.message = "公開前に利用規約URLを設定してください。"
                    }

                    Button("プライバシー") {
                        purchaseManager.message = "公開前にプライバシーポリシーURLを設定してください。"
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.sekishoInk.opacity(0.52))
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

    private var trialNote: String {
        switch selectedPlan {
        case .annual:
            "無料期間終了後は年額\(purchaseManager.annualPrice)。いつでも解約できます。"
        case .monthly:
            "無料期間終了後は月額\(purchaseManager.monthlyPrice)。いつでも解約できます。"
        }
    }

    private func planButton(_ plan: Plan) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.sekishoVermilion : Color.sekishoInk.opacity(0.34))

                VStack(alignment: .leading, spacing: 3) {
                    Text(plan == .annual ? "年額プラン" : "月額プラン")
                        .font(.headline)

                    Text(plan == .annual ? "\(purchaseManager.annualPrice) / 年" : "\(purchaseManager.monthlyPrice) / 月")
                        .font(.subheadline)
                        .foregroundStyle(Color.sekishoInk.opacity(0.62))
                }

                Spacer()

                if plan == .annual {
                    Text("年間34%お得")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.sekishoPaper)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.sekishoVermilion, in: Capsule())
                }
            }
            .foregroundStyle(Color.sekishoInk)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(Color.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.sekishoVermilion : Color.sekishoInk.opacity(0.13), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
