import SwiftUI

struct MascotWardrobeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @AppStorage("selectedMascotStyle") private var selectedMascotStyle = MascotStyle.standard.rawValue
    @State private var previewStyle: MascotStyle = .standard

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                WardrobeHeader(title: "番人の着せ替え") {
                    dismiss()
                }

                ZStack {
                    SekishoSceneBackdrop()
                        .padding(.horizontal, 30)

                    AnimatedSekishoMascot(
                        assetName: previewStyle.assetName,
                        accessibilityLabel: "\(previewStyle.fullTitle)を着た関所の番人"
                    )
                    .padding(.horizontal, 48)
                    .padding(.vertical, 16)
                    .id(previewStyle)
                    .transition(.opacity)
                }
                .frame(height: 310)
                .animation(.easeInOut(duration: 0.2), value: previewStyle)

                Text(previewStyle.fullTitle)
                    .font(.title2.weight(.bold))

                Text(styleDescription)
                    .font(.subheadline)
                    .foregroundStyle(Color.sekishoInk.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)

                HStack(spacing: 12) {
                    ForEach(MascotStyle.allCases) { style in
                        MascotStyleCard(
                            style: style,
                            isSelected: previewStyle == style,
                            priceText: priceText(for: style)
                        ) {
                            previewStyle = style
                        }
                    }
                }
                .padding(.top, 24)

                Button(action: primaryAction) {
                    HStack(spacing: 10) {
                        if purchaseManager.isPurchasing {
                            ProgressView()
                                .tint(Color.sekishoPaper)
                        }

                        Text(primaryButtonLabel)
                    }
                }
                .buttonStyle(WoodenPrimaryButtonStyle())
                .disabled(purchaseManager.isPurchasing)
                .padding(.top, 22)

                if previewStyle == .sakura, !purchaseManager.canUseSakura {
                    NavigationLink {
                        SekishoProView()
                    } label: {
                        HStack(spacing: 10) {
                            Image("SekishoMascotSakura")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 42, height: 42)
                                .accessibilityHidden(true)

                            Text("関所Proなら対象衣装も楽しめます")
                                .font(.subheadline.weight(.semibold))

                            Spacer(minLength: 8)

                            Text("見る  ›")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(Color.sekishoVermilion)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.sekishoVermilion.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .accessibilityLabel("関所Proなら対象衣装も楽しめます。関所Proを見る")
                    .padding(.top, 8)
                }

                Button("購入を復元") {
                    purchaseManager.restorePurchases()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.sekishoInk.opacity(0.68))
                .frame(minHeight: 44)
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 44)
        }
        .foregroundStyle(Color.sekishoInk)
        .background(Color.sekishoPaper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            previewStyle = MascotStyle(rawValue: selectedMascotStyle) ?? .standard
            purchaseManager.refresh()
        }
        .onChange(of: purchaseManager.canUseSakura) { _, canUseSakura in
            if canUseSakura, previewStyle == .sakura {
                selectedMascotStyle = MascotStyle.sakura.rawValue
            }
        }
        .alert("お知らせ", isPresented: purchaseMessageBinding) {
            Button("閉じる") {
                purchaseManager.message = nil
            }
        } message: {
            Text(purchaseManager.message ?? "")
        }
    }

    private var styleDescription: String {
        switch previewStyle {
        case .standard:
            "いつも静かに見守ってくれる、関所の番人です。"
        case .sakura:
            "やわらかな桜色の羽織。春らしい買い切り衣装です。"
        }
    }

    private var primaryButtonLabel: String {
        switch previewStyle {
        case .standard:
            return selectedMascotStyle == MascotStyle.standard.rawValue ? "着用中" : "この番人に着替える"
        case .sakura:
            if purchaseManager.canUseSakura {
                return selectedMascotStyle == MascotStyle.sakura.rawValue ? "着用中" : "この衣装に着替える"
            }
            return "\(purchaseManager.sakuraPrice)で購入"
        }
    }

    private func priceText(for style: MascotStyle) -> String {
        switch style {
        case .standard:
            "無料"
        case .sakura:
            purchaseManager.canUseSakura ? "購入済み" : purchaseManager.sakuraPrice
        }
    }

    private func primaryAction() {
        switch previewStyle {
        case .standard:
            selectedMascotStyle = MascotStyle.standard.rawValue
        case .sakura:
            if purchaseManager.canUseSakura {
                selectedMascotStyle = MascotStyle.sakura.rawValue
            } else {
                purchaseManager.purchase(purchaseManager.sakuraPackage)
            }
        }
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

struct WardrobeHeader: View {
    let title: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: dismiss) {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(Color.sekishoInk)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("戻る")

            Text(title)
                .font(.title2.weight(.bold))

            Spacer()
        }
    }
}

private struct MascotStyleCard: View {
    let style: MascotStyle
    let isSelected: Bool
    let priceText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(style.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 82)

                Text(style.title)
                    .font(.subheadline.weight(.bold))

                Text(priceText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        style == .sakura && priceText != "購入済み"
                            ? Color.sekishoVermilion
                            : Color.sekishoInk.opacity(0.58)
                    )
            }
            .foregroundStyle(Color.sekishoInk)
            .frame(maxWidth: .infinity, minHeight: 148)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.26), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        isSelected ? Color.sekishoVermilion : Color.sekishoInk.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.fullTitle)、\(priceText)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack {
        MascotWardrobeView()
            .environmentObject(PurchaseManager(configureSDK: false))
    }
}
