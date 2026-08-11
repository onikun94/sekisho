import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("ホーム", systemImage: "house")
                }

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
        }
        .tint(Color.sekishoVermilion)
        .preferredColorScheme(.light)
        .toolbarBackground(Color.sekishoPaper.opacity(0.96), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .fullScreenCover(isPresented: $model.isFocusSessionPresented) {
            FocusSessionView(durationMinutes: model.focusDurationMinutes)
                .environmentObject(model)
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
