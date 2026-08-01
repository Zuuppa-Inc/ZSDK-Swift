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
            return L("err_network", "Network connection failed. Check your internet and try again.")
        case .server(_, let message):
            return message ?? L("err_server", "The server returned an error. Please try again.")
        case .decoding:
            return L("err_decoding", "Received an unexpected response from the server.")
        case .notAuthenticated:
            return L("err_not_auth", "You need to be signed in to continue.")
        case .unknown:
            return L("err_unknown", "Something went wrong. Please try again.")
        }
    }
}

/// How the buyer chooses to receive their one-time code.
public enum OTPChannel: Sendable {
    case email(String)
    case phone(String)
}

/// The identity of the currently signed-in buyer, for the "signed in as …"
/// confirmation shown before checkout.
public struct AuthIdentity: Sendable, Equatable {
    /// Email if the buyer signed in with email, else nil.
    public let email: String?
    /// Phone if the buyer signed in with phone, else nil.
    public let phone: String?

    /// A human-readable label for the account (email preferred, else phone).
    public var displayName: String { email ?? phone ?? L("your_account", "your account") }
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
        // The Keychain survives app deletion, so a reinstall could otherwise
        // start already signed-in. UserDefaults IS wiped on delete, so we use a
        // first-run flag to clear any stale Keychain session on a fresh install.
        Self.clearSessionOnFirstRun(key: keychainKey)
        self.session = Self.loadSession(key: keychainKey)
    }

    /// A valid access token for the current session, refreshing transparently
    /// when the current one has expired. Returns nil when there's no session, or
    /// when the refresh token has been revoked (the buyer must sign in again).
    ///
    /// This is the token API the rest of the SDK should use — it keeps a
    /// returning buyer signed in for as long as the refresh token lives (weeks),
    /// rather than the ~1h access-token lifetime.
    func validAccessToken() async -> String? {
        guard let session else { return nil }

        // Still valid (with a 60s safety margin) — use it as-is.
        if session.expiresAt > Date().addingTimeInterval(60) {
            return session.accessToken
        }

        // Expired: try to mint a new one from the refresh token.
        guard let refreshToken = session.refreshToken else {
            signOut()
            return nil
        }
        do {
            let refreshed = try await refresh(using: refreshToken)
            self.session = refreshed
            Self.saveSession(refreshed, key: keychainKey)
            return refreshed.accessToken
        } catch ZuuppaError.server {
            // The refresh token was rejected (revoked/expired) — the session is
            // dead, so clear it and force a fresh sign-in.
            signOut()
            return nil
        } catch {
            // Transient failure (e.g. no network) — keep the session so a later
            // attempt can still refresh; just report "no token" for now.
            return nil
        }
    }

    /// Whether the buyer has a usable session (refreshing if needed).
    var isAuthenticated: Bool {
        get async { await validAccessToken() != nil }
    }

    /// The email or phone of the currently signed-in buyer, read from the
    /// session's JWT. Used to show "you're signed in as …" before checkout.
    /// Refreshes the token first so a restored-but-expired session still
    /// resolves an identity (or clears itself if the refresh token is dead).
    func currentIdentity() async -> AuthIdentity? {
        guard let token = await validAccessToken() else { return nil }
        return Self.identity(fromJWT: token)
    }

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

    /// Exchanges a refresh token for a fresh session via GoTrue's
    /// `grant_type=refresh_token`. Throws `ZuuppaError.server` when the token is
    /// rejected (revoked/expired).
    private func refresh(using refreshToken: String) async throws -> StoredSession {
        let data = try await post(
            path: "/auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: ["refresh_token": refreshToken]
        )
        return try decodeSession(from: data)
    }

    /// Clears the stored session (sign-out).
    func signOut() {
        session = nil
        Self.deleteSession(key: keychainKey)
    }

    // MARK: - HTTP

    private func post(path: String, query: [URLQueryItem] = [], body: [String: Any]) async throws -> Data {
        var components = URLComponents(
            url: config.supabaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw ZuuppaError.unknown }

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

    /// Decodes the email/phone claims from a Supabase access token (JWT). Reads
    /// the payload segment only — signature verification happens server-side on
    /// every API call, so this is purely for display.
    private static func identity(fromJWT token: String) -> AuthIdentity? {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }

        // JWT uses base64url without padding; restore both to decode.
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }

        guard let data = Data(base64Encoded: base64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let email = (obj["email"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let phone = (obj["phone"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard email != nil || phone != nil else { return nil }
        return AuthIdentity(email: email, phone: phone)
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

    /// On the very first launch after install, clear any Keychain session left
    /// behind by a previous install (Keychain items survive app deletion, but
    /// UserDefaults does not — so a missing flag means a fresh install).
    static func clearSessionOnFirstRun(key: String) {
        // Xcode Previews run in an ephemeral sandbox where UserDefaults isn't
        // reliably persisted across rebuilds, so the first-run flag reads back
        // as false every time — which would wipe the Keychain session on every
        // preview reload and force a re-sign-in. Skip the clear under previews
        // so a signed-in session survives (runtime is unaffected).
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }

        let flag = "com.zuuppa.sdk.hasLaunched"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: flag) else { return }
        Keychain.delete(key: key)
        defaults.set(true, forKey: flag)
    }
}
