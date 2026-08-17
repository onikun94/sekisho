import Foundation

/// Points `LiveSekishoAPIClient` at the right backend host for the current
/// build configuration.
struct SekishoBackendConfiguration {
    let baseURL: URL

    static let `default`: SekishoBackendConfiguration = {
        #if DEBUG
        return SekishoBackendConfiguration(baseURL: URL(string: "http://localhost:8787")!)
        #else
        // Placeholder production endpoint. Replace with the real backend
        // domain once it is provisioned.
        return SekishoBackendConfiguration(baseURL: URL(string: "https://api.sekisho.app")!)
        #endif
    }()
}

/// `URLSession`-backed implementation of `SekishoAPIClient`.
final class LiveSekishoAPIClient: SekishoAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder = SekishoJSONCoding.makeDecoder()
    private let encoder = SekishoJSONCoding.makeEncoder()

    init(configuration: SekishoBackendConfiguration = .default, session: URLSession = .shared) {
        self.baseURL = configuration.baseURL
        self.session = session
    }

    func signInWithApple(_ request: AppleSignInRequest) async throws -> AuthTokenResponse {
        let urlRequest = try makeRequest(
            path: "v1/auth/apple",
            method: "POST",
            body: request,
            accessToken: nil
        )
        return try await sendDecoding(urlRequest, as: AuthTokenResponse.self)
    }

    func refresh(refreshToken: String) async throws -> RefreshResponse {
        let urlRequest = try makeRequest(
            path: "v1/auth/refresh",
            method: "POST",
            body: RefreshRequest(refreshToken: refreshToken),
            accessToken: nil
        )
        return try await sendDecoding(urlRequest, as: RefreshResponse.self)
    }

    func logout(refreshToken: String, accessToken: String) async throws {
        let urlRequest = try makeRequest(
            path: "v1/auth/logout",
            method: "POST",
            body: LogoutRequest(refreshToken: refreshToken),
            accessToken: accessToken
        )
        try await sendExpectingNoContent(urlRequest)
    }

    func deleteAccount(accessToken: String) async throws {
        let urlRequest = makeRequest(path: "v1/account", method: "DELETE", accessToken: accessToken)
        try await sendExpectingNoContent(urlRequest)
    }

    // MARK: - Request building

    private func makeRequest(path: String, method: String, accessToken: String?) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func makeRequest<Body: Encodable>(
        path: String,
        method: String,
        body: Body,
        accessToken: String?
    ) throws -> URLRequest {
        var request = makeRequest(path: path, method: method, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return request
    }

    // MARK: - Request sending

    private func sendDecoding<Response: Decodable>(
        _ request: URLRequest,
        as responseType: Response.Type
    ) async throws -> Response {
        let (data, response) = try await perform(request)
        try validate(response, data: data)

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw SekishoAPIError.decoding(underlying: error)
        }
    }

    private func sendExpectingNoContent(_ request: URLRequest) async throws {
        let (data, response) = try await perform(request)
        try validate(response, data: data)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw SekishoAPIError.network(underlying: error)
        }
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SekishoAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw makeServerError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    private func makeServerError(statusCode: Int, data: Data) -> SekishoAPIError {
        guard let payload = try? decoder.decode(APIErrorPayload.self, from: data) else {
            return .server(statusCode: statusCode, code: nil, message: nil)
        }

        return .server(statusCode: statusCode, code: payload.error.code, message: payload.error.message)
    }
}
