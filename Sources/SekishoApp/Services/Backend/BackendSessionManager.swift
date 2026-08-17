import Foundation

enum BackendSessionManagerError: Error {
    case notSignedIn
}

extension BackendSessionManagerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "サインインしていません。"
        }
    }
}

/// Owns the backend session lifecycle: restoring credentials from the
/// Keychain, signing in with Apple, keeping the access token fresh, and
/// signing out. UI code does not reference this yet; it will be wired up once
/// the sign-in surface is built.
@MainActor
final class BackendSessionManager: ObservableObject {
    /// Refresh proactively once the access token has less than this much
    /// life left, so a request started right after `validAccessToken()`
    /// returns is unlikely to race the token's real expiry.
    private static let refreshLeadTime: TimeInterval = 60

    @Published private(set) var isSignedIn: Bool = false

    private let apiClient: SekishoAPIClient
    private let tokenStore: KeychainTokenStore
    private var credentials: StoredCredentials?

    init(apiClient: SekishoAPIClient, tokenStore: KeychainTokenStore) {
        self.apiClient = apiClient
        self.tokenStore = tokenStore
    }

    func restore() {
        do {
            credentials = try tokenStore.load()
        } catch {
            // Corrupted or inaccessible Keychain data must not crash restore;
            // fall back to a signed-out state so the user can sign in again.
            credentials = nil
        }

        isSignedIn = credentials != nil
    }

    func signInWithApple(
        identityToken: String,
        authorizationCode: String,
        rawNonce: String
    ) async throws {
        let response = try await apiClient.signInWithApple(
            AppleSignInRequest(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                rawNonce: rawNonce
            )
        )

        try persist(
            accessToken: response.accessToken,
            accessTokenExpiresAt: response.accessTokenExpiresAt,
            refreshToken: response.refreshToken,
            userID: response.user.id
        )
    }

    /// Returns an access token guaranteed to have more than
    /// `refreshLeadTime` left before expiry, refreshing first if needed.
    func validAccessToken() async throws -> String {
        guard let credentials else {
            throw BackendSessionManagerError.notSignedIn
        }

        guard credentials.accessTokenExpiresAt.timeIntervalSinceNow > Self.refreshLeadTime else {
            return try await refreshAccessToken(using: credentials)
        }

        return credentials.accessToken
    }

    func logout() async {
        guard let credentials else {
            return
        }

        do {
            try await apiClient.logout(
                refreshToken: credentials.refreshToken,
                accessToken: credentials.accessToken
            )
        } catch {
            // Local state must be cleared even if the backend call fails
            // (e.g. the refresh token was already revoked server-side).
        }

        clearLocalSession()
    }

    func deleteAccount() async throws {
        guard let credentials else {
            throw BackendSessionManagerError.notSignedIn
        }

        try await apiClient.deleteAccount(accessToken: credentials.accessToken)
        clearLocalSession()
    }

    private func refreshAccessToken(using credentials: StoredCredentials) async throws -> String {
        do {
            let response = try await apiClient.refresh(refreshToken: credentials.refreshToken)
            try persist(
                accessToken: response.accessToken,
                accessTokenExpiresAt: response.accessTokenExpiresAt,
                refreshToken: response.refreshToken,
                userID: credentials.userID
            )
            return response.accessToken
        } catch {
            if case SekishoAPIError.server(let statusCode, _, _) = error, statusCode == 401 {
                // The refresh token itself was rejected; there is no way to
                // recover without a new sign-in, so drop the local session.
                clearLocalSession()
            }
            throw error
        }
    }

    private func persist(
        accessToken: String,
        accessTokenExpiresAt: Date,
        refreshToken: String,
        userID: String
    ) throws {
        let updated = StoredCredentials(
            accessToken: accessToken,
            accessTokenExpiresAt: accessTokenExpiresAt,
            refreshToken: refreshToken,
            userID: userID
        )
        try tokenStore.save(updated)
        credentials = updated
        isSignedIn = true
    }

    private func clearLocalSession() {
        try? tokenStore.clear()
        credentials = nil
        isSignedIn = false
    }
}
