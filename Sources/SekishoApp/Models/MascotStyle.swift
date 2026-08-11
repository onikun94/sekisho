import Foundation

enum MascotStyle: String, CaseIterable, Identifiable {
    case standard
    case sakura

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            "いつもの"
        case .sakura:
            "桜"
        }
    }

    var fullTitle: String {
        switch self {
        case .standard:
            "いつもの番人"
        case .sakura:
            "桜の羽織"
        }
    }

    var assetName: String {
        switch self {
        case .standard:
            "SekishoMascotNormal"
        case .sakura:
            "SekishoMascotSakura"
        }
    }
}
