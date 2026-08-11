import FamilyControls
import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isPickerPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    HandwrittenAssetText(
                        assetName: "HandTitleRules",
                        label: "ルール",
                        height: 50
                    )

                    AirySection(title: "対象") {
                        VStack(spacing: 18) {
                            HStack {
                                Image(systemName: model.selectedTokenCount > 0 ? "checkmark.circle" : "circle.dashed")
                                    .font(.title2)
                                    .foregroundStyle(model.selectedTokenCount > 0 ? Color.sekishoSage : Color.sekishoInk.opacity(0.38))

                                Spacer()

                                Text("\(model.selectedTokenCount)件")
                                    .font(.title3.weight(.semibold))
                                    .monospacedDigit()
                            }

                            Button {
                                isPickerPresented = true
                            } label: {
                                HandwrittenAssetText(
                                    assetName: "HandActionChangeTarget",
                                    label: "対象を変更",
                                    height: 21
                                )
                                .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.sekishoInk)
                            .accessibilityLabel("対象を変更")
                        }
                    }

                    AirySection(title: "上限") {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(model.usageLimitMinutes)")
                                .font(.system(size: 52, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Color.sekishoVermilion)

                            Text("分")
                                .font(.title3.weight(.medium))

                            Spacer()

                            Stepper("", value: $model.usageLimitMinutes, in: 5...240, step: 5)
                                .labelsHidden()
                                .tint(Color.sekishoSage)
                                .frame(minHeight: 44)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)
                .padding(.bottom, 110)
            }
            .foregroundStyle(Color.sekishoInk)
            .background(Color.sekishoPaper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .familyActivityPicker(
                headerText: "制限したいアプリやWebサイトを選びます。",
                footerText: "選択内容は端末内に保存されます。",
                isPresented: $isPickerPresented,
                selection: $model.selectedApps
            )
        }
    }
}

#Preview {
    RulesView()
        .environmentObject(AppModel())
}
