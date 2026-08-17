import Foundation

/// Abstraction over the Sekisho backend authentication API. UI and session
/// code should depend on this protocol rather than `LiveSekishoAPIClient`
/// directly, so previews and tests can substitute `MockSekishoAPIClient`.
protocol SekishoAPIClient {
    func signInWithApple(_ request: AppleSignInRequest) async throws -> AuthTokenResponse
    func refresh(refreshToken: String) async throws -> RefreshResponse
    func logout(refreshToken: String, accessToken: String) async throws
    func deleteAccount(accessToken: String) async throws
}

enum SekishoAPIError: Error {
    case invalidResponse
    case server(statusCode: Int, code: String?, message: String?)
    case network(underlying: Error)
    case decoding(underlying: Error)
}

extension SekishoAPIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "サーバーから予期しない応答がありました。"
        case .server(_, _, let message):
            message ?? "サーバーでエラーが発生しました。"
        case .network(let underlying):
            underlying.localizedDescription
        case .decoding:
            "サーバーの応答を解析できませんでした。"
        }
    }
}
