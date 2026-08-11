import SwiftUI

@main
struct SekishoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()
    @StateObject private var purchaseManager = PurchaseManager()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(model)
                .environmentObject(purchaseManager)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        model.refreshUsageLimitState()
                        purchaseManager.refresh()
                    }
                }
        }
    }
}
