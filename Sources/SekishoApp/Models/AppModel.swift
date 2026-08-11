import FamilyControls
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var authorizationStatus: AuthorizationStatus
    @Published var selectedApps: FamilyActivitySelection {
        didSet {
            FamilyActivitySelectionStore.save(selectedApps)
        }
    }
    @Published var barrierState: BarrierState {
        didSet {
            syncShieldSnapshot()
        }
    }
    @Published var focusDurationMinutes: Int = 25
    @Published var usageLimitMinutes: Int {
        didSet {
            UsageLimitSettingsStore.save(usageLimitMinutes)
            refreshUsageLimitMonitoringIfNeeded()
        }
    }
    @Published var isUsageLimitMonitoringEnabled = false
    @Published private(set) var lastRejectedThresholdDate: Date?
    @Published var isFocusSessionPresented = false
    @Published var lastErrorMessage: String?

    let screenTimeController = ScreenTimeController()

    init() {
        let isMonitoringActive = screenTimeController.isUsageLimitMonitoringActive
        let sharedBarrierState = SharedShieldStore.readSnapshot().barrierState

        authorizationStatus = screenTimeController.authorizationStatus
        selectedApps = FamilyActivitySelectionStore.load()
        usageLimitMinutes = UsageLimitSettingsStore.load()
        isUsageLimitMonitoringEnabled = isMonitoringActive
        barrierState = isMonitoringActive ? BarrierState(sharedState: sharedBarrierState) : .passed
        lastRejectedThresholdDate = UsageLimitMonitoringStateStore.lastRejectedThresholdDate
        UsageLimitSettingsStore.save(usageLimitMinutes)

        if isUsageLimitMonitoringEnabled, UsageLimitMonitoringStateStore.load() == nil {
            try? startUsageLimitMonitoringOnController()
        } else if isScreenTimeAuthorized, selectedTokenCount > 0, !isUsageLimitMonitoringEnabled {
            do {
                try startUsageLimitMonitoringOnController()
                isUsageLimitMonitoringEnabled = true
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }

        syncShieldSnapshot()
    }

    var selectedTokenCount: Int {
        selectedApps.applicationTokens.count + selectedApps.categoryTokens.count + selectedApps.webDomainTokens.count
    }

    var isScreenTimeAuthorized: Bool {
        if authorizationStatus == .approved {
            return true
        }

        if #available(iOS 26.4, *) {
            return authorizationStatus == .approvedWithDataAccess
        }

        return false
    }

    func requestScreenTimeAuthorization() async {
        do {
            try await screenTimeController.requestAuthorization()
            authorizationStatus = screenTimeController.authorizationStatus
            ensureUsageLimitMonitoring()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func updateSelectedApps(_ selection: FamilyActivitySelection) {
        let newTokenCount = selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count

        if isUsageLimitMonitoringEnabled, selectedTokenCount > 0, newTokenCount == 0 {
            lastErrorMessage = "見守り中は、制限する対象を0件にはできません。"
            return
        }

        selectedApps = selection
    }

    func closeBarrier() {
        do {
            try screenTimeController.applyShield(for: selectedApps)
            barrierState = .locked
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func ensureUsageLimitMonitoring() {
        guard isScreenTimeAuthorized, selectedTokenCount > 0 else {
            return
        }

        do {
            if !isUsageLimitMonitoringEnabled {
                barrierState = .passed
            }

            try startUsageLimitMonitoringOnController()
            isUsageLimitMonitoringEnabled = true
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func startFocusSession() {
        barrierState = .inFocus
        isFocusSessionPresented = true
    }

    func completeFocusSession() {
        screenTimeController.clearShield()
        barrierState = .passed
    }

    func markFocusInterrupted() {
        barrierState = .locked
    }

    func refreshUsageLimitState() {
        isUsageLimitMonitoringEnabled = screenTimeController.isUsageLimitMonitoringActive
        lastRejectedThresholdDate = UsageLimitMonitoringStateStore.lastRejectedThresholdDate

        if isUsageLimitMonitoringEnabled {
            barrierState = BarrierState(
                sharedState: SharedShieldStore.readSnapshot().barrierState
            )
        } else {
            barrierState = .passed
        }
    }

    private func refreshUsageLimitMonitoringIfNeeded() {
        guard isUsageLimitMonitoringEnabled else {
            return
        }

        do {
            try startUsageLimitMonitoringOnController()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func startUsageLimitMonitoringOnController() throws {
        try screenTimeController.startUsageLimitMonitoring(
            for: selectedApps,
            thresholdMinutes: usageLimitMinutes
        )

        if barrierState == .locked {
            try screenTimeController.applyShield(for: selectedApps)
        }

        lastRejectedThresholdDate = nil
    }

    private func syncShieldSnapshot() {
        SharedShieldStore.writeSnapshot(
            ShieldSnapshot(
                barrierState: barrierState.sharedState,
                updatedAt: Date()
            )
        )
    }
}
