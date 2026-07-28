import Foundation

/// Errors surfaced by the auth + API layers.
public enum ZuuppaError: LocalizedError {
    case network(URLError)
    case server(status: Int, message: String?)
    case decoding(String)
    case notAuthenticated
    case unknown

    public var errorDescription: String? {
        switch self {
        case .network:
            return "Network connection failed. Check your internet and try again."
        case .server(_, let message):
            return message ?? "The server returned an error. Please try again."
        case .decoding:
            return "Received an unexpected response from the server."
        case .notAuthenticated:
            return "You need to be signed in to continue."
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }
}

/// How the buyer chooses to receive their one-time code.
public enum OTPChannel: Sendable {
    case email(String)
    case phone(String)
}

/// Minimal Supabase auth client covering exactly what the SDK needs: request an
/// OTP, verify it, and hold onto the resulting session. Talks to Supabase's
/// GoTrue REST API directly so the SDK doesn't need the full Supabase SDK.
///
/// The access token is persisted to the Keychain so a returning buyer skips the
/// sign-in step. We deliberately do NOT force onboarding — a verified OTP user
/// is enough to buy tickets, and the tickets are tied to that Supabase user id.
actor SupabaseAuth {

    private let config: ZuuppaConfig
    private let urlSession: URLSession
    private let keychainKey = "com.zuuppa.sdk.session"

    private var session: StoredSession?

    init(config: ZuuppaConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
        self.session = Self.loadSession(key: keychainKey)
    }

    /// The current access token, if the buyer has a valid (non-expired) session.
    var accessToken: String? {
        guard let session, session.expiresAt > Date().addingTimeInterval(60) else {
            return nil
        }
        return session.accessToken
    }

    var isAuthenticated: Bool { accessToken != nil }

    // MARK: - OTP flow

    /// Requests an OTP code be sent to the given email or phone. Creates the
    /// user if they don't exist (matches the app's behaviour).
    func requestOTP(_ channel: OTPChannel) async throws {
        var body: [String: Any] = ["create_user": true]
        switch channel {
        case .email(let email): body["email"] = email
        case .phone(let phone): body["phone"] = phone
        }
        _ = try await post(path: "/auth/v1/otp", body: body)
    }

    /// Verifies the OTP code and stores the resulting session.
    func verifyOTP(_ channel: OTPChannel, token: String) async throws {
        var body: [String: Any] = ["token": token]
        switch channel {
        case .email(let email):
            body["email"] = email
            body["type"] = "email"
        case .phone(let phone):
            body["phone"] = phone
            body["type"] = "sms"
        }

        let data = try await post(path: "/auth/v1/verify", body: body)
        let decoded = try decodeSession(from: data)
        session = decoded
        Self.saveSession(decoded, key: keychainKey)
    }

    /// Clears the stored session (sign-out).
    func signOut() {
        session = nil
        Self.deleteSession(key: keychainKey)
    }

    // MARK: - HTTP

    private func post(path: String, body: [String: Any]) async throws -> Data {
        let url = config.supabaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ZuuppaError.unknown }
            guard (200..<300).contains(http.statusCode) else {
                throw ZuuppaError.server(status: http.statusCode, message: Self.errorMessage(from: data))
            }
            return data
        } catch let error as URLError {
            throw ZuuppaError.network(error)
        }
    }

    private func decodeSession(from data: Data) throws -> StoredSession {
        struct TokenResponse: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresIn: Int?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
            }
        }
        do {
            let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            let ttl = TimeInterval(decoded.expiresIn ?? 3600)
            return StoredSession(
                accessToken: decoded.accessToken,
                refreshToken: decoded.refreshToken,
                expiresAt: Date().addingTimeInterval(ttl)
            )
        } catch {
            throw ZuuppaError.decoding("\(error)")
        }
    }

    /// Extracts a human-readable error from a Supabase error body.
    private static func errorMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (obj["msg"] ?? obj["error_description"] ?? obj["error"] ?? obj["message"]) as? String
    }
}

// MARK: - Session persistence

/// A stored auth session. `Codable` so it can round-trip through the Keychain.
private struct StoredSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
}

private extension SupabaseAuth {

    static func loadSession(key: String) -> StoredSession? {
        guard let data = Keychain.read(key: key) else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    static func saveSession(_ session: StoredSession, key: String) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        Keychain.write(key: key, data: data)
    }

    static func deleteSession(key: String) {
        Keychain.delete(key: key)
    }
}
