import Foundation

// Models decoded from the Zuuppa API. Field names use the server's snake_case
// via `CodingKeys`. Only the fields the SDK's screens actually read are
// included; unknown fields in the JSON are simply ignored.

/// A purchasable ticket type on an event.
public struct TicketType: Identifiable, Decodable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let priceCents: Int
    public let currency: String?
    public let quantityTotal: Int?
    public let quantitySold: Int?
    public let isActive: Bool?
    public let sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, currency
        case priceCents = "price_cents"
        case quantityTotal = "quantity_total"
        case quantitySold = "quantity_sold"
        case isActive = "is_active"
        case sortOrder = "sort_order"
    }

    /// Whether this ticket type is free.
    public var isFree: Bool { priceCents == 0 }

    /// Remaining inventory, or nil when unlimited.
    public var remaining: Int? {
        guard let total = quantityTotal else { return nil }
        return max(0, total - (quantitySold ?? 0))
    }

    public var isSoldOut: Bool {
        if let remaining { return remaining <= 0 }
        return false
    }
}

/// A Zuuppa event, as returned by `GET /events/{id}`.
public struct Event: Decodable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let startAt: Date?
    public let endAt: Date?
    public let venueName: String?
    public let addressText: String?
    public let coverImageURL: String?
    public let accentColor: String?
    public let timezone: String?
    public let latitude: Double?
    public let longitude: Double?
    public let isPaid: Bool
    public let status: String?
    public let paymentToken: String?
    public let stripeEnabled: Bool?
    public let cryptoEnabled: Bool?
    public let maxTicketsPerOrder: Int?
    public let host: Profile?
    public let cohost: Profile?
    public let ticketTypes: [TicketType]
    /// Event settings; may be null when no settings row exists.
    public let settings: EventSettings?
    /// The signed-in viewer's join-request, when they've made one.
    public let viewerRequest: ViewerRequest?
    /// The signed-in viewer's existing RSVP on this event, when they have one.
    /// Its `status` is `completed` once they've RSVP'd.
    public let viewerRsvp: ViewerRequest?

    enum CodingKeys: String, CodingKey {
        case id, name, description, status, timezone, latitude, longitude, host, cohost, settings
        case startAt = "start_at"
        case endAt = "end_at"
        case venueName = "venue_name"
        case addressText = "address_text"
        case coverImageURL = "cover_image_url"
        case accentColor = "accent_color"
        case isPaid = "is_paid"
        case paymentToken = "payment_token"
        case stripeEnabled = "stripe_enabled"
        case cryptoEnabled = "crypto_enabled"
        case maxTicketsPerOrder = "max_tickets_per_order"
        case ticketTypes = "ticket_types"
        case viewerRequest = "viewer_request"
        case viewerRsvp = "viewer_rsvp"
    }

    /// Ticket types worth showing (active, sorted).
    public var sellableTicketTypes: [TicketType] {
        ticketTypes
            .filter { $0.isActive ?? true }
            .sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
    }

    /// Hosts to show under "HOSTED BY", in order (host first, then cohost).
    public var hosts: [Profile] {
        [host, cohost].compactMap { $0 }
    }

    /// Whether crypto payment is available. Matches the app, which defaults a
    /// missing `crypto_enabled` to `true`.
    public var isCryptoEnabled: Bool {
        cryptoEnabled ?? true
    }

    /// Whether Stripe (card) payment is available. Missing defaults to `false`.
    public var isStripeEnabled: Bool {
        stripeEnabled ?? false
    }

    /// Payment token symbol, defaulting to "SOL" like the app.
    public var paymentTokenOrDefault: String {
        paymentToken ?? "SOL"
    }

    /// Whether the event has map coordinates.
    public var hasCoordinates: Bool {
        latitude != nil && longitude != nil
    }

    /// Whether the host must approve a join request before the viewer can
    /// RSVP / buy. Defaults to false when the event has no settings row.
    public var requiresApproval: Bool {
        settings?.requiresApproval ?? false
    }
}

/// Event-level settings, as nested under `settings` in the event detail payload.
public struct EventSettings: Decodable, Sendable {
    public let requiresApproval: Bool

    enum CodingKeys: String, CodingKey {
        case requiresApproval = "requires_approval"
    }
}

/// The signed-in viewer's join-request on an event: `pending`, `approved`, or
/// `declined`. Present in the event detail payload and returned by
/// `POST /events/{id}/request-join`.
public struct ViewerRequest: Decodable, Sendable {
    public let status: String
}

/// A host / cohost profile summary.
public struct Profile: Decodable, Sendable, Hashable {
    public let userID: String?
    public let fullName: String?
    public let username: String?
    public let profilePhotoURL: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case fullName = "full_name"
        case username
        case profilePhotoURL = "profile_photo_url"
    }

    public var displayName: String { fullName ?? username ?? "Host" }
}

// MARK: - My Tickets

/// One ticket owned by the signed-in buyer, as returned by `GET /tickets/me`.
/// Flattens the event fields the server joins in, so a single object carries
/// everything the list + detail screens need.
public struct MyTicket: Identifiable, Decodable, Sendable, Hashable {
    /// The ticket token doubles as a stable identity (it's unique per ticket).
    public var id: String { ticketToken }

    public let eventID: String
    public let hostID: String?
    public let eventName: String?
    public let eventVenueName: String?
    public let eventCoverImageURL: String?
    public let eventStatus: String?
    public let eventStartAt: Date?
    public let eventEndAt: Date?
    public let eventAddressText: String?
    public let eventTimezone: String?
    public let eventAccentColor: String?
    public let hostDisplayName: String?
    public let ticketToken: String
    public let ticketTypeName: String?
    /// "active", "used", or "canceled".
    public let status: String
    public let orderID: String?
    public let orderTotalCents: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case eventID = "event_id"
        case hostID = "host_id"
        case eventName = "event_name"
        case eventVenueName = "event_venue_name"
        case eventCoverImageURL = "event_cover_image_url"
        case eventStatus = "event_status"
        case eventStartAt = "event_start_at"
        case eventEndAt = "event_end_at"
        case eventAddressText = "event_address_text"
        case eventTimezone = "event_timezone"
        case eventAccentColor = "event_accent_color"
        case hostDisplayName = "host_display_name"
        case ticketToken = "ticket_token"
        case ticketTypeName = "ticket_type_name"
        case orderID = "order_id"
        case orderTotalCents = "order_total_cents"
    }

    /// Whether this ticket has been cancelled (whole-event or individual refund).
    public var isCanceled: Bool { status == "canceled" }
}

/// Response from `GET /tickets/me`.
struct MyTicketsResponse: Decodable {
    let tickets: [MyTicket]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case tickets
        case nextCursor = "next_cursor"
    }
}

/// Response from `GET /orders/{id}/receipt`.
struct ReceiptResponse: Decodable {
    let explorerURL: String?
    let receiptURL: String?

    enum CodingKeys: String, CodingKey {
        case explorerURL = "explorer_url"
        case receiptURL = "receipt_url"
    }

    /// The link to open: the blockchain explorer for crypto orders, else the
    /// Stripe receipt. Matches the app, which prefers `explorer_url`.
    var url: URL? {
        (explorerURL ?? receiptURL).flatMap(URL.init(string:))
    }
}

// MARK: - Pending join requests

/// One of the signed-in user's pending / approved-unpurchased join requests, as
/// returned by `GET /join-requests/me`. Mirrors the app's attendee-side
/// `PendingCompletionsScreen` items: events awaiting host approval, plus
/// approved paid events the user hasn't bought tickets for yet.
public struct PendingJoinRequest: Identifiable, Decodable, Sendable, Hashable {
    /// The event id doubles as identity (one request per event per user).
    public var id: String { eventID }

    public let eventID: String
    public let eventName: String?
    /// `pending` (awaiting approval) or `approved` (approved, buy ticket).
    public let requestStatus: String
    public let coverImageURL: String?
    public let venueName: String?
    public let addressText: String?
    public let startAt: Date?
    public let endAt: Date?
    public let timezone: String?
    public let isPaid: Bool
    public let accentColor: String?

    enum CodingKeys: String, CodingKey {
        case timezone
        case eventID = "event_id"
        case eventName = "event_name"
        case requestStatus = "request_status"
        case coverImageURL = "cover_image_url"
        case venueName = "venue_name"
        case addressText = "address_text"
        case startAt = "start_at"
        case endAt = "end_at"
        case isPaid = "is_paid"
        case accentColor = "accent_color"
    }

    /// Whether the request is still awaiting host approval.
    public var isPending: Bool { requestStatus == "pending" }
}

// MARK: - My Events

/// One event hosted (or confirmed-cohosted) by a user, for the "My Events" list.
/// Returned by `GET /users/{id}/hosted-events`.
public struct HostedEvent: Identifiable, Decodable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let coverImageURL: String?
    public let startAt: Date?
    public let venueName: String?
    public let timezone: String?
    public let accentColor: String?

    enum CodingKeys: String, CodingKey {
        case id, name, timezone
        case coverImageURL = "cover_image_url"
        case startAt = "start_at"
        case venueName = "venue_name"
        case accentColor = "accent_color"
    }
}

/// Response from `GET /users/{id}/hosted-events`.
struct HostedEventsResponse: Decodable {
    let events: [HostedEvent]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case events
        case nextCursor = "next_cursor"
    }
}

// MARK: - Pricing

/// Response from `GET /config/fees`.
struct FeeConfig: Decodable {
    let platformFeeBps: Int?

    enum CodingKeys: String, CodingKey {
        case platformFeeBps = "platform_fee_bps"
    }
}

/// Response from `GET /events/{id}/price-quote`.
struct PriceQuote: Decodable {
    let token: String?
    let decimals: Int?
    let tokenPriceUSD: Double?
    let bitcoinMinPlatformFeeSats: Int?
    let expiresInSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case token, decimals
        case tokenPriceUSD = "token_price_usd"
        case bitcoinMinPlatformFeeSats = "bitcoin_min_platform_fee_sats"
        case expiresInSeconds = "expires_in_seconds"
    }
}

// MARK: - Checkout

/// One line item in a checkout request.
struct CheckoutItem: Encodable {
    let ticketTypeID: String
    let quantity: Int

    enum CodingKeys: String, CodingKey {
        case ticketTypeID = "ticket_type_id"
        case quantity
    }
}

struct CheckoutRequest: Encodable {
    let items: [CheckoutItem]
    let provider: String
}

/// Body for `POST /events/{id}/rsvp` — the free-event RSVP path, which takes a
/// bare quantity (no ticket line items).
struct RsvpRequest: Encodable {
    let quantity: Int
}

/// Body for `POST /events/{id}/email-tickets`. `lang` localizes the email;
/// `email` is the fallback recipient for accounts with no email on file (created
/// via phone number) — the server ignores it when the account already has one.
struct EmailTicketsRequest: Encodable {
    let lang: String?
    let email: String?
}

/// Response from `POST /events/{id}/email-tickets` — `{ "status": "sent" }`.
struct EmailTicketsResponse: Decodable {
    let status: String
}

/// Response from `POST /events/{id}/checkout` with `provider: "stripe"`.
struct StripeCheckoutResponse: Decodable {
    let orderID: String
    let clientSecret: String
    let publishableKey: String
    let stripeAccountID: String?

    enum CodingKeys: String, CodingKey {
        case orderID = "order_id"
        case clientSecret = "client_secret"
        case publishableKey = "publishable_key"
        case stripeAccountID = "stripe_account_id"
    }
}

/// Response from `POST /orders/{id}/stripe/confirm`.
struct StripeConfirmResponse: Decodable {
    let status: String
    let ticketCount: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case ticketCount = "ticket_count"
    }
}

/// Response from `POST /events/{id}/checkout` with `provider: "external_crypto"`.
struct ExternalCryptoCheckoutResponse: Decodable {
    let orderID: String
    let paymentToken: String
    let tokenMint: String?
    let decimals: Int
    let depositAddress: String
    let amountBaseUnits: String

    enum CodingKeys: String, CodingKey {
        case orderID = "order_id"
        case paymentToken = "payment_token"
        case tokenMint = "token_mint"
        case decimals
        case depositAddress = "deposit_address"
        case amountBaseUnits = "amount_base_units"
    }
}

/// Response from `GET /orders/{id}/external-crypto/status`.
struct ExternalCryptoStatusResponse: Decodable {
    let orderStatus: String
    let paymentStatus: String
    let ticketCount: Int?
    let message: String?
    let shortfallAmount: Int?

    enum CodingKeys: String, CodingKey {
        case orderStatus = "order_status"
        case paymentStatus = "payment_status"
        case ticketCount = "ticket_count"
        case message
        case shortfallAmount = "shortfall_amount"
    }

    /// True once the payment has landed and tickets are (being) issued.
    var isPaid: Bool {
        orderStatus == "completed"
            || ["paid", "swept", "overpaid"].contains(paymentStatus)
    }

    /// True for terminal failure states.
    var isFailed: Bool {
        ["expired", "refunded", "refund_failed"].contains(paymentStatus)
    }
}

/// Response from the free-ticket path of checkout, and `POST /events/{id}/rsvp`.
struct FreeCheckoutResponse: Decodable {
    let orderID: String?
    let status: String?
    let ticketCount: Int?

    enum CodingKeys: String, CodingKey {
        case orderID = "order_id"
        case status
        case ticketCount = "ticket_count"
    }
}
