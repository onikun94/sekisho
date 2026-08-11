import DeviceActivity
import ExtensionKit
import SwiftUI

@main
struct SekishoDeviceActivityReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TodayUsageReport { summary in
            TodayUsageReportView(summary: summary)
        }
    }
}
