import Foundation

/// Talks to the Zuuppa API, attaching the buyer's bearer token to every call.
/// Mirrors the endpoints the Flutter app uses for the checkout flow.
actor ZuuppaAPI {

    private let config: ZuuppaConfig
    private let auth: SupabaseAuth
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(config: ZuuppaConfig, auth: SupabaseAuth, urlSession: URLSession = .shared) {
        self.config = config
        self.auth = auth
        self.urlSession = urlSession

        let decoder = JSONDecoder()
        // The server emits ISO-8601 timestamps (with fractional seconds).
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601DateFormatter.zuuppaWithFractional.date(from: string)
                ?? ISO8601DateFormatter.zuuppaPlain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unrecognized date: \(string)"
            )
        }
        self.decoder = decoder
    }

    // MARK: - Endpoints

    /// Event details are public (the server accepts an optional bearer), so this
    /// works signed-out for the details screen.
    func fetchEvent(id: String) async throws -> Event {
        try await get("/events/\(id)", as: Event.self, requiresAuth: false)
    }

    /// Fee config and price quote are public (no auth), so the checkout
    /// breakdown — fees + crypto conversions — is available before sign-in.
    func fetchFeeConfig() async throws -> FeeConfig {
        try await get("/config/fees", as: FeeConfig.self, requiresAuth: false)
    }

    func fetchPriceQuote(eventID: String) async throws -> PriceQuote {
        try await get("/events/\(eventID)/price-quote", as: PriceQuote.self, requiresAuth: false)
    }

    func stripeCheckout(eventID: String, items: [CheckoutItem]) async throws -> StripeCheckoutResponse {
        let body = CheckoutRequest(items: items, provider: "stripe")
        return try await post("/events/\(eventID)/checkout", body: body, as: StripeCheckoutResponse.self)
    }

    func confirmStripe(orderID: String) async throws -> StripeConfirmResponse {
        try await post("/orders/\(orderID)/stripe/confirm", body: EmptyBody(), as: StripeConfirmResponse.self)
    }

    func externalCryptoCheckout(eventID: String, items: [CheckoutItem]) async throws -> ExternalCryptoCheckoutResponse {
        let body = CheckoutRequest(items: items, provider: "external_crypto")
        return try await post("/events/\(eventID)/checkout", body: body, as: ExternalCryptoCheckoutResponse.self)
    }

    func externalCryptoStatus(orderID: String) async throws -> ExternalCryptoStatusResponse {
        try await get("/orders/\(orderID)/external-crypto/status", as: ExternalCryptoStatusResponse.self)
    }

    func freeCheckout(eventID: String, items: [CheckoutItem]) async throws -> FreeCheckoutResponse {
        // The server treats an all-free order as an instant, no-payment checkout.
        let body = CheckoutRequest(items: items, provider: "free")
        return try await post("/events/\(eventID)/checkout", body: body, as: FreeCheckoutResponse.self)
    }

    // MARK: - My Tickets

    /// The signed-in buyer's tickets for one filter tab (upcoming / past /
    /// canceled), paged by cursor. `hostID`, when set, restricts to events
    /// hosted by that user id (server-side).
    func fetchMyTickets(
        filter: String, cursor: String?, limit: Int = 20, hostID: String? = nil
    ) async throws -> MyTicketsResponse {
        var query = [
            URLQueryItem(name: "filter", value: filter),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let hostID { query.append(URLQueryItem(name: "host_id", value: hostID)) }
        return try await get("/tickets/me", query: query, as: MyTicketsResponse.self)
    }

    /// The receipt link (blockchain explorer or Stripe receipt) for an order.
    func fetchReceipt(orderID: String) async throws -> ReceiptResponse {
        try await get("/orders/\(orderID)/receipt", as: ReceiptResponse.self)
    }

    /// The raw `.pkpass` bytes for a ticket, for adding to Apple Wallet. The
    /// body is binary (not JSON), so this bypasses the JSON decoder used by the
    /// other endpoints.
    func fetchApplePass(ticketToken: String) async throws -> Data {
        guard let token = await auth.validAccessToken() else {
            throw ZuuppaError.notAuthenticated
        }
        let url = config.apiBaseURL.appendingPathComponent("/tickets/\(ticketToken)/pass")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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

    // MARK: - Request plumbing

    private func get<T: Decodable>(
        _ path: String, query: [URLQueryItem] = [], as type: T.Type, requiresAuth: Bool = true
    ) async throws -> T {
        try await send(path: path, query: query, method: "GET", body: Optional<EmptyBody>.none, as: type, requiresAuth: requiresAuth)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body, as type: T.Type) async throws -> T {
        try await send(path: path, method: "POST", body: body, as: type)
    }

    private func send<Body: Encodable, T: Decodable>(
        path: String, query: [URLQueryItem] = [], method: String, body: Body?, as type: T.Type, requiresAuth: Bool = true
    ) async throws -> T {
        let token = await auth.validAccessToken()
        if requiresAuth, token == nil {
            throw ZuuppaError.notAuthenticated
        }

        // Build the URL via URLComponents so query items are encoded correctly
        // (appendingPathComponent would percent-encode a "?").
        var components = URLComponents(
            url: config.apiBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw ZuuppaError.unknown }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The server accepts an optional bearer on public endpoints (e.g. event
        // details); attach it when we have one.
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ZuuppaError.unknown }
            guard (200..<300).contains(http.statusCode) else {
                throw ZuuppaError.server(status: http.statusCode, message: Self.errorMessage(from: data))
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw ZuuppaError.decoding("\(error)")
            }
        } catch let error as URLError {
            throw ZuuppaError.network(error)
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (obj["error"] ?? obj["message"] ?? obj["msg"]) as? String
    }

    #if DEBUG
    /// Fetches an event WITHOUT authentication, for SwiftUI previews. The server
    /// serves `GET /events/:id` publicly for live events, so no token is needed.
    /// Not for production use — the real flow always sends a bearer token.
    func fetchEventUnauthenticated(id: String) async throws -> Event {
        let url = config.apiBaseURL.appendingPathComponent("/events/\(id)")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ZuuppaError.unknown }
            guard (200..<300).contains(http.statusCode) else {
                throw ZuuppaError.server(status: http.statusCode, message: Self.errorMessage(from: data))
            }
            do {
                return try decoder.decode(Event.self, from: data)
            } catch {
                throw ZuuppaError.decoding("\(error)")
            }
        } catch let error as URLError {
            throw ZuuppaError.network(error)
        }
    }
    #endif
}

private struct EmptyBody: Codable {}

private extension ISO8601DateFormatter {
    // These formatters are configured once and only read afterward, so sharing
    // them across concurrency domains is safe.
    nonisolated(unsafe) static let zuuppaWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) static let zuuppaPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
