import Foundation

enum SekishoShared {
    static let appGroupIdentifier = "group.com.onikun94.sekisho"
    static let shieldSnapshotKey = "shieldSnapshot"
}

enum SharedBarrierState: String, Codable {
    case locked
    case inFocus
    case passed
    case emergencyUsed
}

enum ShieldLockScope: String, Codable {
    case combined
    case individual
}

struct ShieldSnapshot: Codable {
    var barrierState: SharedBarrierState
    var updatedAt: Date
    var lockScope: ShieldLockScope?

    init(
        barrierState: SharedBarrierState,
        updatedAt: Date,
        lockScope: ShieldLockScope? = nil
    ) {
        self.barrierState = barrierState
        self.updatedAt = updatedAt
        self.lockScope = lockScope
    }

    static let fallback = ShieldSnapshot(
        barrierState: .passed,
        updatedAt: Date(),
        lockScope: nil
    )

    func isLockedToday(at date: Date = .now) -> Bool {
        barrierState == .locked && Calendar.current.isDate(updatedAt, inSameDayAs: date)
    }
}

enum SharedShieldStore {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SekishoShared.appGroupIdentifier) ?? .standard
    }

    static func readSnapshot() -> ShieldSnapshot {
        defaults.synchronize()
        guard let data = defaults.data(forKey: SekishoShared.shieldSnapshotKey),
              let snapshot = try? JSONDecoder().decode(ShieldSnapshot.self, from: data)
        else {
            return .fallback
        }

        return snapshot
    }

    static func writeSnapshot(_ snapshot: ShieldSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        defaults.set(data, forKey: SekishoShared.shieldSnapshotKey)
        defaults.synchronize()
    }
}
