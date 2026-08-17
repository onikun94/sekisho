import Foundation

// MARK: - Request bodies

struct AppleSignInRequest: Codable {
    let identityToken: String
    let authorizationCode: String
    let rawNonce: String
}

struct RefreshRequest: Codable {
    let refreshToken: String
}

struct LogoutRequest: Codable {
    let refreshToken: String
}

// MARK: - Response bodies

struct AuthTokenResponse: Codable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let user: APIUser
}

struct RefreshResponse: Codable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
}

struct APIUser: Codable {
    let id: String
    /// Server-generated anonymous handle for the weekly league. In Phase 1
    /// the backend does not assign handles yet, so this is expected to be
    /// `nil` until that rollout lands.
    let anonymousHandle: String?
}

// MARK: - Error bodies

struct APIErrorPayload: Codable {
    let error: APIErrorBody
}

struct APIErrorBody: Codable {
    let code: String
    let message: String
}

// MARK: - JSON coding

/// Shared JSON coding configuration for the Sekisho backend API. Every
/// request/response body on the wire is camelCase JSON with ISO 8601 dates,
/// so all client code should build its coders through this factory instead of
/// configuring `JSONDecoder`/`JSONEncoder` ad hoc.
enum SekishoJSONCoding {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
