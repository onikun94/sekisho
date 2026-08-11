import Foundation

enum BarrierState: String, Codable {
    case locked
    case inFocus
    case passed
    case emergencyUsed

    var title: String {
        switch self {
        case .locked:
            "制限中"
        case .inFocus:
            "集中中"
        case .passed:
            "利用できます"
        case .emergencyUsed:
            "一時解除中"
        }
    }

    var symbolName: String {
        switch self {
        case .locked:
            "lock.shield.fill"
        case .inFocus:
            "timer"
        case .passed:
            "checkmark.seal.fill"
        case .emergencyUsed:
            "bolt.badge.clock.fill"
        }
    }

    var sharedState: SharedBarrierState {
        switch self {
        case .locked:
            .locked
        case .inFocus:
            .inFocus
        case .passed:
            .passed
        case .emergencyUsed:
            .emergencyUsed
        }
    }

    init(sharedState: SharedBarrierState) {
        switch sharedState {
        case .locked:
            self = .locked
        case .inFocus:
            self = .inFocus
        case .passed:
            self = .passed
        case .emergencyUsed:
            self = .emergencyUsed
        }
    }
}
