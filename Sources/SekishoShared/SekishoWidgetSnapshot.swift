import Foundation

struct SekishoWidgetSnapshot: Codable, Equatable {
    var barrierState: SharedBarrierState
    var usageLimitMinutes: Int
    var usedMinutes: Int
    var selectedTargetCount: Int
    var isMonitoringActive: Bool
    var updatedAt: Date
    var limitModeRawValue: String?
    var lockedTargetCount: Int?

    init(
        barrierState: SharedBarrierState,
        usageLimitMinutes: Int,
        usedMinutes: Int,
        selectedTargetCount: Int,
        isMonitoringActive: Bool,
        updatedAt: Date,
        limitModeRawValue: String? = nil,
        lockedTargetCount: Int? = nil
    ) {
        self.barrierState = barrierState
        self.usageLimitMinutes = usageLimitMinutes
        self.usedMinutes = usedMinutes
        self.selectedTargetCount = selectedTargetCount
        self.isMonitoringActive = isMonitoringActive
        self.updatedAt = updatedAt
        self.limitModeRawValue = limitModeRawValue
        self.lockedTargetCount = lockedTargetCount
    }

    static let fallback = SekishoWidgetSnapshot(
        barrierState: .passed,
        usageLimitMinutes: 30,
        usedMinutes: 0,
        selectedTargetCount: 0,
        isMonitoringActive: false,
        updatedAt: .now,
        limitModeRawValue: nil,
        lockedTargetCount: nil
    )
}

enum SekishoWidgetSnapshotStore {
    private static let snapshotKey = "sekishoWidgetSnapshot.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SekishoShared.appGroupIdentifier) ?? .standard
    }

    static func read() -> SekishoWidgetSnapshot {
        defaults.synchronize()
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(SekishoWidgetSnapshot.self, from: data)
        else {
            return .fallback
        }

        return snapshot
    }

    static func write(_ snapshot: SekishoWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        defaults.set(data, forKey: snapshotKey)
        defaults.synchronize()
    }

    static func updateBarrierState(_ state: SharedBarrierState, at date: Date = .now) {
        var snapshot = read()
        snapshot.barrierState = state
        snapshot.updatedAt = date
        write(snapshot)
    }

    static func beginDailyInterval(
        usageLimitMinutes: Int,
        barrierState: SharedBarrierState = .passed,
        at date: Date = .now
    ) {
        var snapshot = read()
        let isSameDay = Calendar.current.isDate(snapshot.updatedAt, inSameDayAs: date)
        snapshot.barrierState = barrierState
        snapshot.usageLimitMinutes = usageLimitMinutes
        if !isSameDay {
            snapshot.usedMinutes = 0
        }
        snapshot.isMonitoringActive = true
        snapshot.updatedAt = date
        write(snapshot)
    }

    static func recordUsageProgress(
        usedMinutes: Int,
        at date: Date = .now
    ) {
        var snapshot = read()
        snapshot.usedMinutes = min(
            max(snapshot.usedMinutes, usedMinutes),
            snapshot.usageLimitMinutes
        )
        snapshot.updatedAt = date
        write(snapshot)
    }

    static func recordIndividualProgress(
        usedMinutes: Int,
        limitMinutes: Int,
        lockedTargetCount: Int,
        at date: Date = .now
    ) {
        var snapshot = read()
        snapshot.usageLimitMinutes = max(limitMinutes, 1)
        snapshot.usedMinutes = min(max(usedMinutes, 0), snapshot.usageLimitMinutes)
        snapshot.limitModeRawValue = "individual"
        snapshot.lockedTargetCount = lockedTargetCount
        snapshot.updatedAt = date
        write(snapshot)
    }

    static func updateLimitMode(
        rawValue: String,
        lockedTargetCount: Int,
        at date: Date = .now
    ) {
        var snapshot = read()
        snapshot.limitModeRawValue = rawValue
        snapshot.lockedTargetCount = lockedTargetCount
        snapshot.updatedAt = date
        write(snapshot)
    }
}
