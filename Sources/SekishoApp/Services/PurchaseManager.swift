import Combine
import Foundation
import RevenueCat

@MainActor
final class PurchaseManager: ObservableObject {
    static let premiumEntitlementID = "premium"
    static let sakuraEntitlementID = "mascot_sakura"
    static let mascotOfferingID = "mascots"
    static let monthlyProductID = "com.onikun94.sekisho.pro.monthly"
    static let annualProductID = "com.onikun94.sekisho.pro.annual"
    static let sakuraProductID = "com.onikun94.sekisho.mascot.sakura"

    @Published private(set) var isConfigured = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private var storePremiumEntitlementActive = false
    @Published private(set) var ownsSakura = false
    @Published private(set) var annualPackage: Package?
    @Published private(set) var monthlyPackage: Package?
    @Published private(set) var sakuraPackage: Package?
    @Published private(set) var introEligibilityByProductID: [String: IntroEligibilityStatus] = [:]
    @Published var message: String?

    #if DEBUG || INTERNAL_TESTING
    @Published private var developerPremiumOverride: Bool?
    private static let developerPremiumOverrideKey = "developerPremiumOverride.v1"
    #endif

    private static var didConfigureSDK = false

    init(configureSDK: Bool = true) {
        #if DEBUG || INTERNAL_TESTING
        if UserDefaults.standard.object(forKey: Self.developerPremiumOverrideKey) != nil {
            developerPremiumOverride = UserDefaults.standard.bool(
                forKey: Self.developerPremiumOverrideKey
            )
        } else {
            // Existing internal builds exposed the individual-limit flow from
            // the developer menu. Start those testers in the equivalent Pro
            // state; the new toggle can still switch to the Free behavior.
            developerPremiumOverride = true
        }
        #endif

        guard configureSDK else {
            return
        }

        configureIfPossible()
    }

    var annualPrice: String {
        annualPackage?.storeProduct.localizedPriceString ?? "価格を取得中"
    }

    var monthlyPrice: String {
        monthlyPackage?.storeProduct.localizedPriceString ?? "価格を取得中"
    }

    var sakuraPrice: String {
        sakuraPackage?.storeProduct.localizedPriceString ?? "価格を取得中"
    }

    var annualSavingsPercentage: Int? {
        guard let annualPrice = annualPackage?.storeProduct.price,
              let monthlyPrice = monthlyPackage?.storeProduct.price
        else {
            return nil
        }

        let annual = NSDecimalNumber(decimal: annualPrice).doubleValue
        let monthlyForYear = NSDecimalNumber(decimal: monthlyPrice).doubleValue * 12
        guard monthlyForYear > 0, annual < monthlyForYear else {
            return nil
        }

        return Int(((1 - annual / monthlyForYear) * 100).rounded())
    }

    var canUseSakura: Bool {
        isPremium || ownsSakura
    }

    var isPremium: Bool {
        #if DEBUG || INTERNAL_TESTING
        return developerPremiumOverride ?? storePremiumEntitlementActive
        #else
        return storePremiumEntitlementActive
        #endif
    }

    #if DEBUG || INTERNAL_TESTING
    func setDeveloperPremiumMode(_ isEnabled: Bool) {
        developerPremiumOverride = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.developerPremiumOverrideKey)
    }
    #endif

    func isEligibleForFreeTrial(_ package: Package?) -> Bool {
        guard let package,
              package.storeProduct.introductoryDiscount?.paymentMode == .freeTrial
        else {
            return false
        }

        return introEligibilityByProductID[package.storeProduct.productIdentifier]?.isEligible == true
    }

    func freeTrialPeriodText(_ package: Package?) -> String? {
        guard isEligibleForFreeTrial(package),
              let discount = package?.storeProduct.introductoryDiscount
        else {
            return nil
        }

        let totalUnits = discount.subscriptionPeriod.value * max(discount.numberOfPeriods, 1)
        let unit: String
        switch discount.subscriptionPeriod.unit {
        case .day:
            unit = "日間"
        case .week:
            unit = "週間"
        case .month:
            unit = "か月間"
        case .year:
            unit = "年間"
        @unknown default:
            return nil
        }

        return "\(totalUnits)\(unit)"
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
                            $0.storeProduct.productIdentifier == Self.sakuraProductID
                        })
                    self.refreshIntroEligibility()
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
        storePremiumEntitlementActive = customerInfo.entitlements[Self.premiumEntitlementID]?.isActive == true
        ownsSakura = customerInfo.entitlements[Self.sakuraEntitlementID]?.isActive == true
    }

    private func refreshIntroEligibility() {
        let productIdentifiers = [annualPackage, monthlyPackage]
            .compactMap { $0?.storeProduct.productIdentifier }

        guard !productIdentifiers.isEmpty else {
            introEligibilityByProductID = [:]
            return
        }

        Purchases.shared.checkTrialOrIntroDiscountEligibility(
            productIdentifiers: productIdentifiers
        ) { [weak self] eligibility in
            Task { @MainActor in
                self?.introEligibilityByProductID = eligibility.mapValues(\.status)
            }
        }
    }
}
