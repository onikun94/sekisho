import CryptoKit
import Foundation

/// Generates the nonce pair required by Sign in with Apple.
///
/// Usage: set `ASAuthorizationAppleIDRequest.nonce` to
/// `AppleSignInNonce.sha256Hex(rawNonce)` before presenting the Apple ID
/// request, then send the original `rawNonce` (never the hash) to the backend
/// alongside the resulting identity token so it can verify the request.
enum AppleSignInNonce {
    private static let allowedCharacters: [Character] = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    )

    static func generateRawNonce(length: Int = 32) -> String {
        var remainingLength = length
        var result = ""

        while remainingLength > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            precondition(status == errSecSuccess, "Unable to generate secure random bytes for the Sign in with Apple nonce.")

            for byte in randomBytes where remainingLength > 0 {
                // Discard bytes that fall outside the alphabet instead of
                // reducing modulo its size, so every character stays equally
                // likely regardless of the alphabet's length.
                if byte < allowedCharacters.count {
                    result.append(allowedCharacters[Int(byte)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    static func sha256Hex(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
