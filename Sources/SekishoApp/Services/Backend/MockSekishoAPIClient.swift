import Foundation

/// In-memory `SekishoAPIClient` used by SwiftUI previews and tests so no real
/// network request is made. `signInWithApple` always succeeds with a fixed
/// user, `refresh` rotates the returned tokens on every call, and
/// `logout`/`deleteAccount` only record that they were invoked.
final class MockSekishoAPIClient: SekishoAPIClient {
    private(set) var loggedOutRefreshTokens: [String] = []
    private(set) var deletedAccountAccessTokens: [String] = []

    // `anonymousHandle` is nil here to mirror the Phase 1 backend, which
    // does not assign handles yet.
    var fixedUser = APIUser(id: "mock-user-id", anonymousHandle: nil)

    private var refreshGeneration = 0

    func signInWithApple(_ request: AppleSignInRequest) async throws -> AuthTokenResponse {
        AuthTokenResponse(
            accessToken: "mock-access-token-0",
            accessTokenExpiresAt: Date().addingTimeInterval(3600),
            refreshToken: "mock-refresh-token-0",
            user: fixedUser
        )
    }

    func refresh(refreshToken: String) async throws -> RefreshResponse {
        refreshGeneration += 1
        return RefreshResponse(
            accessToken: "mock-access-token-\(refreshGeneration)",
            accessTokenExpiresAt: Date().addingTimeInterval(3600),
            refreshToken: "mock-refresh-token-\(refreshGeneration)"
        )
    }

    func logout(refreshToken: String, accessToken: String) async throws {
        loggedOutRefreshTokens.append(refreshToken)
    }

    func deleteAccount(accessToken: String) async throws {
        deletedAccountAccessTokens.append(accessToken)
    }
}
