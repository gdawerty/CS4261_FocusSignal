import ManagedSettings
import ManagedSettingsUI
import UIKit

final class FocusShieldConfiguration: ShieldConfigurationDataSource {
    private var appearance: ShieldConfiguration {
        let subtitle: ShieldConfiguration.Label
        let secondaryButtonLabel: ShieldConfiguration.Label?
        if #available(iOS 26.4, *) {
            subtitle = .init(text: "Go Back keeps this app blocked. To continue, choose a reason.", color: .secondaryLabel)
            secondaryButtonLabel = .init(text: "Continue", color: .systemIndigo)
        } else {
            subtitle = .init(text: "Go Back keeps this app blocked. End the session in FocusSignal to regain access.", color: .secondaryLabel)
            secondaryButtonLabel = nil
        }
        let common = (
            backgroundBlurStyle: UIBlurEffect.Style.systemMaterial,
            backgroundColor: UIColor.systemBackground,
            icon: UIImage(systemName: "scope"),
            title: ShieldConfiguration.Label(text: "Back to your focus?", color: .label),
            subtitle: subtitle,
            primaryButtonLabel: ShieldConfiguration.Label(text: "Go Back", color: .white),
            primaryButtonBackgroundColor: UIColor.systemIndigo,
            secondaryButtonLabel: secondaryButtonLabel
        )
        if #available(iOS 26.4, *) {
            return ShieldConfiguration(
                backgroundBlurStyle: common.backgroundBlurStyle,
                backgroundColor: common.backgroundColor,
                icon: common.icon,
                title: common.title,
                subtitle: common.subtitle,
                primaryButtonLabel: common.primaryButtonLabel,
                primaryButtonBackgroundColor: common.primaryButtonBackgroundColor,
                secondaryButtonLabel: common.secondaryButtonLabel,
                secondaryButtonSubmenuItems: ["Taking a break", "I need something from this app", "Just browsing"]
            )
        }
        return ShieldConfiguration(
            backgroundBlurStyle: common.backgroundBlurStyle,
            backgroundColor: common.backgroundColor,
            icon: common.icon,
            title: common.title,
            subtitle: common.subtitle,
            primaryButtonLabel: common.primaryButtonLabel,
            primaryButtonBackgroundColor: common.primaryButtonBackgroundColor,
            secondaryButtonLabel: common.secondaryButtonLabel
        )
    }
    override func configuration(shielding application: Application) -> ShieldConfiguration { appearance }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { appearance }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { appearance }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { appearance }
}
