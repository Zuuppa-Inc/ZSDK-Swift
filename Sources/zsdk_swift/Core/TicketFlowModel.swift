import SwiftUI

/// Drives the whole ticket-purchase flow: auth → event details → selection →
/// payment → confirmation. The SwiftUI screens observe this and call into it.
@MainActor
@Observable
final class TicketFlowModel {

    /// The high-level step currently on screen.
    enum Step {
        case loading
        case auth
        case eventDetails
        case ticketSelection
        case externalCryptoPayment(ExternalCryptoPayment)
        case confirmation(Confirmation)
        case error(String)
    }

    /// Data needed to render the external-crypto (QR) payment screen.
    struct ExternalCryptoPayment {
        let orderID: String
        let depositAddress: String
        let token: String
        let decimals: Int
        let amountBaseUnits: String
    }

    /// Data shown on the success screen.
    struct Confirmation {
        let ticketCount: Int
        let isPending: Bool
    }

    let config: ZuuppaConfig
    let eventID: String

    private let auth: SupabaseAuth
    private let api: ZuuppaAPI

    private(set) var step: Step = .loading
    private(set) var event: Event?

    /// Buyer's selected quantity per ticket-type id.
    var quantities: [String: Int] = [:]

    // Pricing state, loaded from /config/fees and /events/:id/price-quote.
    private(set) var platformFeeBps: Int = 600
    private(set) var priceToken: String = "SOL"
    private(set) var tokenPriceUSD: Double?
    private(set) var btcMinPlatformFeeSats: Int?

    init(eventID: String, config: ZuuppaConfig = .default) {
        self.eventID = eventID
        self.config = config
        let auth = SupabaseAuth(config: config)
        self.auth = auth
        self.api = ZuuppaAPI(config: config, auth: auth)
    }

    // MARK: - Lifecycle

    /// Called when the flow appears. Event details are public, so we always
    /// load them straight away — auth is only required when the buyer proceeds
    /// to checkout (see `showTicketSelection`).
    func start() async {
        await loadEvent()
    }

    /// Called by the auth screen once the buyer verifies their OTP. Continues
    /// into checkout (auth is only prompted on the way to ticket selection).
    func didAuthenticate() async {
        // Pricing needs auth, so refresh it now that we have a session.
        await loadPricing()
        step = .ticketSelection
    }

    private func loadEvent() async {
        step = .loading
        do {
            let event = try await api.fetchEvent(id: eventID)
            self.event = event
            priceToken = event.paymentTokenOrDefault
            step = .eventDetails
            // Fees + price quote are public, so load them now; the checkout
            // breakdown (fees + crypto conversions) is ready before sign-in.
            await loadPricing()
        } catch {
            step = .error(message(for: error))
        }
    }

    /// Loads the platform fee and token price quote. Failures are non-fatal —
    /// the breakdown just omits fees/conversions until it succeeds.
    private func loadPricing() async {
        if let fees = try? await api.fetchFeeConfig(), let bps = fees.platformFeeBps {
            platformFeeBps = min(max(bps, 0), 1_000_000)
        }
        if let quote = try? await api.fetchPriceQuote(eventID: eventID) {
            priceToken = quote.token ?? priceToken
            tokenPriceUSD = quote.tokenPriceUSD
            btcMinPlatformFeeSats = quote.bitcoinMinPlatformFeeSats
        }
    }

    // MARK: - Navigation

    /// Buyer tapped "Buy Tickets" / "RSVP". Checkout requires a signed-in user,
    /// so prompt for auth first if needed; otherwise load pricing and continue.
    func showTicketSelection() async {
        if await auth.isAuthenticated {
            await loadPricing()
            step = .ticketSelection
        } else {
            step = .auth
        }
    }

    func backToEventDetails() {
        step = .eventDetails
    }

    /// Back arrow on the crypto payment screen returns to checkout (matching
    /// the app, which pops the screen).
    func backToCheckout() {
        step = .ticketSelection
    }

    // MARK: - Derived selection state

    var selectedItems: [CheckoutItem] {
        quantities
            .filter { $0.value > 0 }
            .map { CheckoutItem(ticketTypeID: $0.key, quantity: $0.value) }
    }

    /// Gross ticket subtotal in cents (before fees). The app calls this `gross`.
    var subtotalCents: Int {
        guard let event else { return 0 }
        return event.sellableTicketTypes.reduce(0) { sum, type in
            sum + type.priceCents * (quantities[type.id] ?? 0)
        }
    }

    /// Platform fee in cents, matching the app's `_feesCents()`:
    /// ceil(subtotal * bps / 10000), with a BTC sats floor.
    var feesCents: Int {
        let subtotal = subtotalCents
        guard subtotal > 0 else { return 0 }
        let platformFee = Int((Double(subtotal) * Double(platformFeeBps) / 10_000).rounded(.up))

        // Bitcoin: fee is the greater of the percentage fee and a fixed sats floor.
        if priceToken == "BTC", let minSats = btcMinPlatformFeeSats,
           let btcPrice = tokenPriceUSD, btcPrice > 0 {
            let floorCents = Int((Double(minSats) * btcPrice / 100_000_000 * 100).rounded(.up))
            return max(platformFee, floorCents)
        }
        return platformFee
    }

    /// What the buyer pays: subtotal + fees. The app calls this `buyerTotal`.
    var buyerTotalCents: Int { subtotalCents + feesCents }

    var totalTicketCount: Int {
        quantities.values.reduce(0, +)
    }

    var hasSelection: Bool { totalTicketCount > 0 }

    /// Crypto conversion for a cents amount, matching the app's
    /// `_formatTokenAmount`. Returns nil for card-only events or when no quote.
    func tokenAmount(forCents cents: Int) -> String? {
        guard (event?.isCryptoEnabled ?? false) else { return nil }
        guard cents != 0, let price = tokenPriceUSD, price != 0 else { return nil }
        let usd = Double(cents) / 100.0
        let amount = usd / price

        if priceToken == "BTC" {
            let sats = Int((amount * 100_000_000).rounded())
            return "\(sats.groupedThousands) sats"
        }
        if amount >= 1_000_000 {
            return String(format: "%.2fM %@", amount / 1_000_000, priceToken)
        } else if amount >= 1000 {
            return String(format: "%.0f %@", amount, priceToken)
        } else if amount >= 1 {
            return String(format: "%.2f %@", amount, priceToken)
        } else {
            return String(format: "%.4f %@", amount, priceToken)
        }
    }

    // MARK: - Checkout

    /// Free RSVP path — no payment.
    func checkoutFree() async {
        step = .loading
        do {
            let result = try await api.freeCheckout(eventID: eventID, items: selectedItems)
            step = .confirmation(.init(
                ticketCount: result.ticketCount ?? totalTicketCount,
                isPending: (result.status ?? "completed") != "completed"
            ))
        } catch {
            step = .error(message(for: error))
        }
    }

    /// Starts the external-crypto flow: creates the order and hands the QR
    /// details to the payment screen.
    func checkoutExternalCrypto() async {
        step = .loading
        do {
            let r = try await api.externalCryptoCheckout(eventID: eventID, items: selectedItems)
            step = .externalCryptoPayment(.init(
                orderID: r.orderID,
                depositAddress: r.depositAddress,
                token: r.paymentToken,
                decimals: r.decimals,
                amountBaseUnits: r.amountBaseUnits
            ))
        } catch {
            step = .error(message(for: error))
        }
    }

    /// Fetches the current external-crypto order status. The crypto screen owns
    /// the poll loop + live UI state (matching the app's StatefulWidget), so
    /// this is a thin passthrough.
    func externalCryptoStatus(orderID: String) async throws -> ExternalCryptoStatusResponse {
        try await api.externalCryptoStatus(orderID: orderID)
    }

    /// Called by the crypto screen once payment is confirmed (tickets issued),
    /// transitioning to the confirmation screen.
    func finishExternalCrypto(status: ExternalCryptoStatusResponse) {
        step = .confirmation(.init(
            ticketCount: status.ticketCount ?? totalTicketCount,
            isPending: status.orderStatus != "completed"
        ))
    }

    // MARK: - Stripe

    /// Creates the Stripe order and returns the details the payment sheet needs.
    func beginStripeCheckout() async throws -> StripeCheckoutResponse {
        try await api.stripeCheckout(eventID: eventID, items: selectedItems)
    }

    /// Confirms the Stripe order after the payment sheet succeeds, then shows
    /// the confirmation screen.
    func confirmStripe(orderID: String) async {
        step = .loading
        do {
            let result = try await api.confirmStripe(orderID: orderID)
            step = .confirmation(.init(
                ticketCount: result.ticketCount ?? totalTicketCount,
                isPending: result.status != "completed"
            ))
        } catch {
            step = .error(message(for: error))
        }
    }

    func fail(_ message: String) {
        step = .error(message)
    }

    // MARK: - Auth helpers

    func requestOTP(_ channel: OTPChannel) async throws {
        try await auth.requestOTP(channel)
    }

    func verifyOTP(_ channel: OTPChannel, token: String) async throws {
        try await auth.verifyOTP(channel, token: token)
    }

    private func message(for error: Error) -> String {
        (error as? ZuuppaError)?.errorDescription ?? error.localizedDescription
    }
}

#if DEBUG
extension TicketFlowModel {
    /// Builds a model pre-seeded with a sample event and a chosen step, for
    /// SwiftUI previews. Does no networking.
    static func preview(step: Step = .eventDetails) -> TicketFlowModel {
        let model = TicketFlowModel(eventID: "preview-event", config: .default)
        model.event = .previewSample
        // Seed pricing so previews render the fee line + crypto conversions
        // (the live quote requires auth, which previews don't have).
        model.platformFeeBps = 600
        model.priceToken = model.event?.paymentTokenOrDefault ?? "SOL"
        model.tokenPriceUSD = 165.0
        // Pre-select a ticket so the checkout preview shows the breakdown.
        if case .ticketSelection = step,
           let first = model.event?.sellableTicketTypes.first(where: { !$0.isSoldOut }) {
            model.quantities[first.id] = 2
        }
        model.step = step
        return model
    }

    /// Loads a REAL event from the backend for previews, without auth (the
    /// server serves live events publicly). Selects one of each ticket type so
    /// downstream screens look populated. Falls back to an error step if the
    /// fetch fails (e.g. no network in the preview sandbox).
    func loadPreviewEvent() async {
        do {
            let event = try await api.fetchEvent(id: eventID)
            self.event = event
            priceToken = event.paymentTokenOrDefault
            step = .eventDetails
            // Fees + quote are public now, so the live conversion shows here too.
            await loadPricing()
        } catch {
            step = .error(message(for: error))
        }
    }
}

extension Event {
    /// A decoded sample event for previews.
    static let previewSample: Event = {
        let json = """
        {
            "id": "preview-event",
            "name": "Sunset Rooftop Party",
            "description": "Join us for an unforgettable evening of music, drinks, and skyline views. Doors open at 8pm — arrive early to catch the sunset set.",
            "start_at": "2026-08-15T20:00:00Z",
            "end_at": "2026-08-16T01:00:00Z",
            "venue_name": "The Highline Rooftop",
            "address_text": "455 W 37th St, New York, NY",
            "cover_image_url": null,
            "accent_color": "#E04A4A",
            "timezone": "America/New_York",
            "latitude": 40.7549,
            "longitude": -73.9977,
            "is_paid": true,
            "status": "live",
            "payment_token": "SOL",
            "stripe_enabled": true,
            "crypto_enabled": true,
            "max_tickets_per_order": 10,
            "host": {
                "user_id": "host-1",
                "full_name": "Alex Rivera",
                "username": "alexr",
                "profile_photo_url": null
            },
            "cohost": null,
            "ticket_types": [
                {
                    "id": "tt-ga",
                    "name": "General Admission",
                    "price_cents": 4500,
                    "currency": "USD",
                    "quantity_total": 200,
                    "quantity_sold": 40,
                    "is_active": true,
                    "sort_order": 0
                },
                {
                    "id": "tt-vip",
                    "name": "VIP (open bar)",
                    "price_cents": 12000,
                    "currency": "USD",
                    "quantity_total": 50,
                    "quantity_sold": 50,
                    "is_active": true,
                    "sort_order": 1
                }
            ]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(Event.self, from: Data(json.utf8))
    }()
}
#endif
