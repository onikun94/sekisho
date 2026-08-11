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

struct ShieldSnapshot: Codable {
    var barrierState: SharedBarrierState
    var updatedAt: Date

    static let fallback = ShieldSnapshot(
        barrierState: .locked,
        updatedAt: Date()
    )
}

enum SharedShieldStore {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SekishoShared.appGroupIdentifier) ?? .standard
    }

    static func readSnapshot() -> ShieldSnapshot {
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
    }
}
