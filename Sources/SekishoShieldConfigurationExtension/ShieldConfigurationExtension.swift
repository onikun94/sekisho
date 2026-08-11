import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        let snapshot = SharedShieldStore.readSnapshot()
        let subtitle = subtitleText(for: snapshot)
        let ink = UIColor(red: 0.22, green: 0.18, blue: 0.15, alpha: 1)
        let paper = UIColor(red: 250 / 255, green: 243 / 255, blue: 230 / 255, alpha: 0.98)
        let vermilion = UIColor(red: 0.72, green: 0.27, blue: 0.20, alpha: 1)

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialLight,
            backgroundColor: paper,
            icon: UIImage(systemName: "hourglass"),
            title: ShieldConfiguration.Label(text: "関所は閉じています", color: ink),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: ink.withAlphaComponent(0.72)),
            primaryButtonLabel: ShieldConfiguration.Label(text: "少し休む", color: .white),
            primaryButtonBackgroundColor: vermilion,
            secondaryButtonLabel: nil
        )
    }

    private func subtitleText(for snapshot: ShieldSnapshot) -> String {
        switch snapshot.barrierState {
        case .locked:
            "今日の上限に達しました。少し間を置いてみましょう。"
        case .inFocus:
            "集中セッション中です。"
        case .passed:
            "制限は解除されています。反映されない場合はアプリを開いてください。"
        case .emergencyUsed:
            "一時的に解除中です。"
        }
    }
}
