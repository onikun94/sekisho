import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab = "home"

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView {
                selectedTab = "settings"
            }
            .tabItem {
                Label("ホーム", systemImage: "house")
            }
            .tag("home")

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
                .tag("settings")
        }
        .tint(Color.sekishoVermilion)
        .toolbarBackground(Color.sekishoPaper.opacity(0.96), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .fullScreenCover(isPresented: $model.isFocusSessionPresented) {
            FocusSessionView(durationMinutes: model.focusDurationMinutes)
                .environmentObject(model)
        }
        .onOpenURL { url in
            if url.scheme == "sekisho" {
                selectedTab = "home"
            }
        }
        .task {
            await model.restoreScreenTimeAuthorizationIfNeeded()
            model.refreshUsageLimitState()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    break
                }

                model.refreshBarrierStateIfChanged()
            }
        }
        .alert("確認が必要です", isPresented: errorBinding) {
            Button("閉じる") {
                model.lastErrorMessage = nil
            }
        } message: {
            Text(model.lastErrorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.lastErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.lastErrorMessage = nil
                }
            }
        )
    }
}

#Preview {
    AppRootView()
        .environmentObject(AppModel())
        .environmentObject(PurchaseManager(configureSDK: false))
}
