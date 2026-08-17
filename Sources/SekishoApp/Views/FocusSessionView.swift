import SwiftUI

struct FocusSessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let durationMinutes: Int

    @State private var endDate = Date()
    @State private var now = Date()
    @State private var isCancelConfirmationPresented = false
    @State private var isInterruptedAlertPresented = false
    @State private var didFinish = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(Color.sekishoVermilion)
                        .accessibilityHidden(true)

                    HandwrittenAssetText(
                        assetName: "HandTitleFocus",
                        label: "務めの時間",
                        height: 34
                    )
                }

                Text(timeText)
                    .font(.system(size: 58, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.sekishoInk)
                    .contentTransition(.numericText())
                    .accessibilityLabel("残り \(remainingSeconds / 60)分 \(remainingSeconds % 60)秒")

                ProgressView(value: progress)
                    .tint(Color.sekishoSage)
                    .accessibilityLabel("進捗")

                Spacer()

                Button(role: .destructive) {
                    isCancelConfirmationPresented = true
                } label: {
                    Text("ここでやめる")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .tint(Color.sekishoSecondaryInk)
            }
            .padding(24)
            .background(Color.sekishoPaper)
            .navigationTitle("務め")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        isCancelConfirmationPresented = true
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        .foregroundStyle(Color.sekishoInk)
        .background(Color.sekishoPaper.ignoresSafeArea())
        .onAppear {
            endDate = Date().addingTimeInterval(TimeInterval(max(durationMinutes, 1) * 60))
            now = Date()
        }
        .onReceive(timer) { date in
            now = date
            completeIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard !didFinish else {
                return
            }

            if newPhase == .background {
                model.markFocusInterrupted()
                isInterruptedAlertPresented = true
            }
        }
        .alert("ここでやめますか？", isPresented: $isCancelConfirmationPresented) {
            Button("やめる", role: .destructive) {
                model.markFocusInterrupted()
                dismiss()
            }
            Button("続ける", role: .cancel) {}
        } message: {
            Text("集中セッションを未完了として扱います。")
        }
        .alert("集中は中断されました", isPresented: $isInterruptedAlertPresented) {
            Button("戻る") {
                dismiss()
            }
        } message: {
            Text("アプリを離れたため、集中セッションを未達として扱いました。")
        }
    }

    private var totalSeconds: Int {
        max(durationMinutes, 1) * 60
    }

    private var remainingSeconds: Int {
        max(0, Int(ceil(endDate.timeIntervalSince(now))))
    }

    private var progress: Double {
        1 - (Double(remainingSeconds) / Double(totalSeconds))
    }

    private var timeText: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func completeIfNeeded() {
        guard remainingSeconds == 0, !didFinish else {
            return
        }

        didFinish = true
        model.completeFocusSession()
        dismiss()
    }
}

#Preview {
    FocusSessionView(durationMinutes: 25)
        .environmentObject(AppModel())
}
