import Combine
import Foundation
import RevenueCat

@MainActor
final class PurchaseManager: ObservableObject {
    static let premiumEntitlementID = "premium"
    static let sakuraEntitlementID = "mascot_sakura"
    static let mascotOfferingID = "mascots"

    @Published private(set) var isConfigured = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isPremium = false
    @Published private(set) var ownsSakura = false
    @Published private(set) var annualPackage: Package?
    @Published private(set) var monthlyPackage: Package?
    @Published private(set) var sakuraPackage: Package?
    @Published var message: String?

    private static var didConfigureSDK = false

    init(configureSDK: Bool = true) {
        guard configureSDK else {
            return
        }

        configureIfPossible()
    }

    var annualPrice: String {
        annualPackage?.storeProduct.localizedPriceString ?? "¥3,800"
    }

    var monthlyPrice: String {
        monthlyPackage?.storeProduct.localizedPriceString ?? "¥480"
    }

    var sakuraPrice: String {
        sakuraPackage?.storeProduct.localizedPriceString ?? "¥300"
    }

    var canUseSakura: Bool {
        isPremium || ownsSakura
    }

    func refresh() {
        guard isConfigured else {
            return
        }

        isLoading = true

        Purchases.shared.getOfferings { [weak self] offerings, error in
            Task { @MainActor in
                guard let self else { return }

                if let offerings {
                    self.annualPackage = offerings.current?.annual
                    self.monthlyPackage = offerings.current?.monthly
                    self.sakuraPackage = offerings.all[Self.mascotOfferingID]?
                        .availablePackages
                        .first(where: {
                            $0.storeProduct.productIdentifier == Self.sakuraEntitlementID
                        })
                } else if let error {
                    self.message = error.localizedDescription
                }

                self.isLoading = false
            }
        }

        Purchases.shared.getCustomerInfo { [weak self] customerInfo, error in
            Task { @MainActor in
                guard let self else { return }

                if let customerInfo {
                    self.apply(customerInfo)
                } else if let error {
                    self.message = error.localizedDescription
                }
            }
        }
    }

    func purchase(_ package: Package?) {
        guard isConfigured else {
            message = "RevenueCatの公開APIキーを設定してください。"
            return
        }

        guard let package else {
            message = "商品情報を取得できませんでした。RevenueCatのOffering設定を確認してください。"
            return
        }

        isPurchasing = true

        Purchases.shared.purchase(package: package) { [weak self] _, customerInfo, error, userCancelled in
            Task { @MainActor in
                guard let self else { return }

                self.isPurchasing = false

                if let customerInfo {
                    self.apply(customerInfo)
                }

                if let error, !userCancelled {
                    self.message = error.localizedDescription
                }
            }
        }
    }

    func restorePurchases() {
        guard isConfigured else {
            message = "RevenueCatの公開APIキーを設定してください。"
            return
        }

        isLoading = true

        Purchases.shared.restorePurchases { [weak self] customerInfo, error in
            Task { @MainActor in
                guard let self else { return }

                self.isLoading = false

                if let customerInfo {
                    self.apply(customerInfo)
                    self.message = "購入情報を復元しました。"
                } else if let error {
                    self.message = error.localizedDescription
                }
            }
        }
    }

    private func configureIfPossible() {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String,
              !apiKey.isEmpty,
              !apiKey.contains("$("),
              !apiKey.contains("YOUR_") else {
            return
        }

        if !Self.didConfigureSDK {
            #if DEBUG
            Purchases.logLevel = .debug
            #endif
            Purchases.configure(withAPIKey: apiKey)
            Self.didConfigureSDK = true
        }

        isConfigured = true
        refresh()
    }

    private func apply(_ customerInfo: CustomerInfo) {
        isPremium = customerInfo.entitlements[Self.premiumEntitlementID]?.isActive == true
        ownsSakura = customerInfo.entitlements[Self.sakuraEntitlementID]?.isActive == true
    }
}
