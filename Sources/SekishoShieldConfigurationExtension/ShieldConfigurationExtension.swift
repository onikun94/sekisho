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
        let ink = adaptiveColor(
            light: UIColor(red: 0.22, green: 0.18, blue: 0.15, alpha: 1),
            dark: UIColor(red: 0.96, green: 0.91, blue: 0.84, alpha: 1)
        )
        let paper = adaptiveColor(
            light: UIColor(red: 250 / 255, green: 243 / 255, blue: 230 / 255, alpha: 0.98),
            dark: UIColor(red: 0.12, green: 0.10, blue: 0.09, alpha: 0.98)
        )
        let vermilion = adaptiveColor(
            light: UIColor(red: 0.72, green: 0.27, blue: 0.20, alpha: 1),
            dark: UIColor(red: 0.92, green: 0.42, blue: 0.32, alpha: 1)
        )
        let onAccent = adaptiveColor(
            light: UIColor(red: 250 / 255, green: 243 / 255, blue: 230 / 255, alpha: 1),
            dark: UIColor(red: 0.12, green: 0.10, blue: 0.09, alpha: 1)
        )

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: paper,
            icon: mascotIcon(),
            title: ShieldConfiguration.Label(text: "関所は閉じています", color: ink),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: ink.withAlphaComponent(0.72)),
            primaryButtonLabel: ShieldConfiguration.Label(text: "このアプリを閉じる", color: onAccent),
            primaryButtonBackgroundColor: vermilion,
            secondaryButtonLabel: nil
        )
    }

    private func mascotIcon() -> UIImage? {
        guard let url = Bundle(for: ShieldConfigurationExtension.self).url(
            forResource: "sekisho-shield-mascot-limited",
            withExtension: "png"
        ), let image = UIImage(contentsOfFile: url.path) else {
            return UIImage(systemName: "hourglass")
        }

        return image.withRenderingMode(.alwaysOriginal)
    }

    private func subtitleText(for snapshot: ShieldSnapshot) -> String {
        switch snapshot.barrierState {
        case .locked:
            if snapshot.lockScope == .individual {
                "このアプリの上限に達しました。明日 0:00 にまた開きます。"
            } else {
                "今日の上限に達しました。明日 0:00 にまた開きます。"
            }
        case .inFocus:
            "集中セッション中です。終了するとまた開きます。"
        case .passed:
            "制限は解除されています。反映されない場合はアプリを開いてください。"
        case .emergencyUsed:
            "一時的に解除中です。"
        }
    }

    private func adaptiveColor(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }
}
