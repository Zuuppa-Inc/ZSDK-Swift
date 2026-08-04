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
        /// App-wallet path: a plain "processing payment" screen shown the instant
        /// the buyer taps pay, while order creation, the wallet hand-off, and the
        /// confirmation poll all run in the background. Resolves to `.confirmation`
        /// or `.error` — the buyer never sees the QR/deposit screen.
        case walletProcessing
        case confirmation(Confirmation)
        case error(String)
    }

    /// Data needed to render the external-crypto (QR) payment screen.
    struct ExternalCryptoPayment {
        let orderID: String
        let depositAddress: String
        let token: String
        let tokenMint: String?
        let decimals: Int
        let amountBaseUnits: String
    }

    /// Data shown on the success screen.
    struct Confirmation {
        /// Which success screen to show: a ticket purchase/RSVP confirmation, or
        /// the "request sent" screen after an approval-gated join request.
        enum Kind {
            case tickets
            case requestSent
        }

        var kind: Kind = .tickets
        let ticketCount: Int
        let isPending: Bool
    }

    let config: ZuuppaConfig
    let eventID: String

    private let auth: SupabaseAuth
    private let api: ZuuppaAPI

    /// Host-supplied wallet handler. When present, the ticket-selection screen
    /// shows a "Pay with app wallet" button that hands payment off to the host's
    /// own wallet instead of the QR deposit flow.
    private let walletHandler: ZuuppaWalletPaymentHandler?

    private(set) var step: Step = .loading
    private(set) var event: Event?

    /// Whether a host wallet handler is available (gates the wallet button).
    var hasWalletHandler: Bool { walletHandler != nil }

    /// The step to return to when the buyer taps back on the error screen. Nil
    /// when the error came from the initial load (no prior screen — back closes
    /// the whole flow instead).
    private(set) var errorReturnStep: Step?

    /// Buyer's selected quantity per ticket-type id.
    var quantities: [String: Int] = [:]

    /// Selected quantity for a FREE event's single RSVP card. Free RSVP ignores
    /// ticket types entirely (matching the app), so this is a standalone count
    /// seeded to 1 and floored at 1.
    var rsvpQuantity: Int = 1

    /// The signed-in viewer's join-request status for an approval-gated event
    /// (`pending` / `approved` / `declined`), or nil if they haven't requested.
    /// Seeded from the event's `viewer_request` on load.
    private(set) var joinRequestStatus: String?

    /// The signed-in viewer's existing RSVP status (`completed` once they've
    /// RSVP'd), or nil if they haven't. Seeded from the event's `viewer_rsvp` on
    /// load and updated after a successful RSVP, so the CTA can show "RSVP'd".
    private(set) var rsvpStatus: String?

    // Pricing state, loaded from /config/fees and /events/:id/price-quote.
    private(set) var platformFeeBps: Int = 600
    // Processing fee (card/Stripe rail only — the server charges 0 on crypto).
    private(set) var processingFeeBps: Int = 300
    private(set) var processingFeeFixedCents: Int = 30
    private(set) var priceToken: String = "SOL"
    private(set) var tokenPriceUSD: Double?
    private(set) var btcMinPlatformFeeSats: Int?

    init(
        eventID: String,
        config: ZuuppaConfig = .default,
        walletHandler: ZuuppaWalletPaymentHandler? = nil
    ) {
        self.eventID = eventID
        self.config = config
        self.walletHandler = walletHandler
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

    /// Called by the auth screen once the buyer verifies their OTP (or a
    /// signed-in buyer confirms their account). Dispatches to whatever action
    /// the buyer was signing in to perform — checkout or a join request.
    func didAuthenticate() async {
        switch pendingAuthAction {
        case .checkout:
            // Pricing needs auth, so refresh it now that we have a session.
            await loadPricing()
            step = .ticketSelection
        case .requestJoin:
            await performRequestToJoin()
        }
    }

    private func loadEvent() async {
        step = .loading
        do {
            let event = try await api.fetchEvent(id: eventID)
            self.event = event
            joinRequestStatus = event.viewerRequest?.status
            rsvpStatus = event.viewerRsvp?.status
            priceToken = event.paymentTokenOrDefault
            step = .eventDetails
            // Fees + price quote are public, so load them now; the checkout
            // breakdown (fees + crypto conversions) is ready before sign-in.
            await loadPricing()
        } catch {
            // Initial load failed — there's no prior screen, so back closes.
            setError(message(for: error), returnTo: nil)
        }
    }

    /// Loads the platform fee and token price quote. Failures are non-fatal —
    /// the breakdown just omits fees/conversions until it succeeds.
    private func loadPricing() async {
        if let fees = try? await api.fetchFeeConfig() {
            if let bps = fees.platformFeeBps {
                platformFeeBps = min(max(bps, 0), 1_000_000)
            }
            if let bps = fees.processingFeeBps {
                processingFeeBps = min(max(bps, 0), 1_000_000)
            }
            if let fixed = fees.processingFeeFixedCents {
                processingFeeFixedCents = min(max(fixed, 0), 1_000_000)
            }
        }
        if let quote = try? await api.fetchPriceQuote(eventID: eventID) {
            priceToken = quote.token ?? priceToken
            tokenPriceUSD = quote.tokenPriceUSD
            btcMinPlatformFeeSats = quote.bitcoinMinPlatformFeeSats
        }
    }

    // MARK: - Navigation

    /// What the buyer is signing in to do, resolved after the auth step.
    private enum PendingAuthAction {
        case checkout
        case requestJoin
    }
    private var pendingAuthAction: PendingAuthAction = .checkout

    /// Buyer tapped "Buy Tickets" / "RSVP". Always show the auth screen: signed-
    /// out buyers sign in, and signed-in buyers confirm (or switch) the account
    /// they're checking out with before proceeding.
    func showTicketSelection() async {
        pendingAuthAction = .checkout
        step = .auth
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

    /// Total buyer fees in cents, matching the app's `_feesCents()`:
    /// the platform fee (ceil(subtotal * bps / 10000), with a BTC sats floor),
    /// plus the Stripe processing fee when the card rail is enabled.
    var feesCents: Int {
        let subtotal = subtotalCents
        guard subtotal > 0 else { return 0 }
        var platformFee = Int((Double(subtotal) * Double(platformFeeBps) / 10_000).rounded(.up))

        // Bitcoin: fee is the greater of the percentage fee and a fixed sats floor.
        if priceToken == "BTC", let minSats = btcMinPlatformFeeSats,
           let btcPrice = tokenPriceUSD, btcPrice > 0 {
            let floorCents = Int((Double(minSats) * btcPrice / 100_000_000 * 100).rounded(.up))
            platformFee = max(platformFee, floorCents)
        }

        // Card (Stripe) rail: the buyer also pays a processing fee, added on top
        // by the server (checkout_stripe). Crypto rails charge 0, so only include
        // it when card is enabled.
        let processingFee = (event?.isStripeEnabled ?? false) ? processingFeeCents(forSubtotal: subtotal) : 0

        return platformFee + processingFee
    }

    /// Stripe processing fee, matching the server's checkout_stripe:
    /// ceil(subtotal * processing_fee_bps / 10000) + processing_fee_fixed_cents.
    func processingFeeCents(forSubtotal subtotal: Int) -> Int {
        guard subtotal > 0 else { return 0 }
        return Int((Double(subtotal) * Double(processingFeeBps) / 10_000).rounded(.up)) + processingFeeFixedCents
    }

    /// What the buyer pays: subtotal + fees. The app calls this `buyerTotal`.
    var buyerTotalCents: Int { subtotalCents + feesCents }

    var totalTicketCount: Int {
        quantities.values.reduce(0, +)
    }

    /// Free events are always selectable (the RSVP quantity is floored at 1,
    /// matching the app); paid events need at least one ticket picked.
    var hasSelection: Bool {
        if event?.isPaid == false { return rsvpQuantity >= 1 }
        return totalTicketCount > 0
    }

    /// Whether the viewer must be approved before RSVP / checkout is allowed.
    /// True when the event requires approval and the viewer isn't yet approved.
    var needsApproval: Bool {
        event?.requiresApproval == true && joinRequestStatus != "approved"
    }

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

    /// Free RSVP path — no payment. Free events use the dedicated `/rsvp`
    /// endpoint (a bare quantity, no ticket line items — matching the app);
    /// only the rare paid-but-zero-total cart falls back to `/checkout`.
    func checkoutFree() async {
        step = .loading
        do {
            let isFreeEvent = event?.isPaid == false
            let result: FreeCheckoutResponse
            if isFreeEvent {
                result = try await api.rsvp(eventID: eventID, quantity: rsvpQuantity)
            } else {
                result = try await api.freeCheckout(eventID: eventID, items: selectedItems)
            }
            let requested = isFreeEvent ? rsvpQuantity : totalTicketCount
            // Record the RSVP so returning to the details screen shows "RSVP'd".
            if isFreeEvent { rsvpStatus = result.status ?? "completed" }
            step = .confirmation(.init(
                ticketCount: result.ticketCount ?? requested,
                isPending: (result.status ?? "completed") != "completed"
            ))
        } catch {
            setError(message(for: error), returnTo: .ticketSelection)
        }
    }

    // MARK: - Approval

    /// Buyer tapped "Request to Join" on an approval-gated event. Like checkout,
    /// this needs a signed-in account, so route through the auth screen first;
    /// the request itself runs in `performRequestToJoin` once authenticated.
    func requestToJoin() async {
        pendingAuthAction = .requestJoin
        step = .auth
    }

    /// Submits the join request after auth, then shows the "Request Sent"
    /// success screen (mirroring the app's `_submitJoinRequest`, which pushes
    /// `TicketSuccessScreen` with the "REQUEST SENT!" heading). The details CTA
    /// is also updated to "Requested" for when the buyer returns.
    private func performRequestToJoin() async {
        step = .loading
        do {
            let request = try await api.requestJoin(eventID: eventID)
            joinRequestStatus = request.status
            step = .confirmation(.init(kind: .requestSent, ticketCount: 0, isPending: false))
        } catch {
            setError(message(for: error), returnTo: .eventDetails)
        }
    }

    /// Starts the external-crypto flow: creates the order and hands the QR
    /// details to the payment screen.
    func checkoutExternalCrypto() async {
        step = .loading
        do {
            let r = try await api.externalCryptoCheckout(eventID: eventID, items: selectedItems)
            step = .externalCryptoPayment(payment(from: r))
        } catch {
            setError(message(for: error), returnTo: .ticketSelection)
        }
    }

    /// App-wallet flow. Shows a plain "processing payment" screen *immediately*
    /// and does all the real work in the background: create the external-crypto
    /// order, hand its details to the host's wallet to sign+submit, then poll the
    /// order status until tickets are issued. The buyer never sees the QR/deposit
    /// screen — from their side it's just "processing" → success or error.
    ///
    /// The backend matches the payment by the unique deposit address, so the
    /// wallet's returned signature isn't sent anywhere — it's display-only.
    ///
    /// On any failure (order creation, the wallet failing / the buyer cancelling,
    /// or the payment expiring) the flow routes to the error screen; its back
    /// button returns to ticket selection, where the buyer can retry or use the
    /// QR / card buttons instead.
    func payWithAppWallet() {
        guard let walletHandler else { return }   // Button only shows when set.
        // Go straight to the processing screen; everything else is background.
        step = .walletProcessing

        Task { await runWalletPayment(walletHandler) }
    }

    /// The background orchestration behind `.walletProcessing`. Never touches the
    /// QR screen: it either lands on `.confirmation` or `.error`.
    private func runWalletPayment(_ walletHandler: ZuuppaWalletPaymentHandler) async {
        // 1. Create the external-crypto order.
        let payment: ExternalCryptoPayment
        do {
            let r = try await api.externalCryptoCheckout(eventID: eventID, items: selectedItems)
            payment = self.payment(from: r)
        } catch {
            walletPaymentFailed(message(for: error))
            return
        }

        // 2. Hand off to the host wallet to sign + submit the transfer.
        do {
            _ = try await walletHandler(ZuuppaCryptoPaymentRequest(
                orderID: payment.orderID,
                chain: "solana",
                token: payment.token,
                tokenMint: payment.tokenMint,
                decimals: payment.decimals,
                amountBaseUnits: payment.amountBaseUnits,
                depositAddress: payment.depositAddress
            ))
        } catch {
            walletPaymentFailed(L("wallet_payment_cancelled", "The wallet payment was cancelled or couldn't be completed. Please try again."))
            return
        }

        // 3. Funds are en route — poll until the server confirms (tickets issued)
        //    or the payment terminally fails, staying on the processing screen the
        //    whole time.
        await pollWalletPayment(orderID: payment.orderID)
    }

    /// Polls the order status until success or terminal failure. Runs while the
    /// processing screen is shown; transient poll errors are ignored and retried.
    private func pollWalletPayment(orderID: String) async {
        while true {
            // Stop if the buyer navigated away from the processing screen.
            guard case .walletProcessing = step else { return }
            if let res = try? await api.externalCryptoStatus(orderID: orderID) {
                if res.isPaid {
                    step = .confirmation(.init(
                        ticketCount: res.ticketCount ?? totalTicketCount,
                        isPending: res.orderStatus != "completed"
                    ))
                    return
                }
                if res.isFailed {
                    walletPaymentFailed(res.message?.isEmpty == false
                        ? res.message!
                        : L("wallet_payment_not_completed", "The payment could not be completed. You have not been charged for a ticket."))
                    return
                }
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    /// Routes a failed app-wallet payment to the error screen (back → selection).
    private func walletPaymentFailed(_ message: String) {
        setError(message, returnTo: .ticketSelection)
    }

    /// Maps a checkout response into the payment struct the crypto screen needs.
    private func payment(from r: ExternalCryptoCheckoutResponse) -> ExternalCryptoPayment {
        .init(
            orderID: r.orderID,
            depositAddress: r.depositAddress,
            token: r.paymentToken,
            tokenMint: r.tokenMint,
            decimals: r.decimals,
            amountBaseUnits: r.amountBaseUnits
        )
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
            setError(message(for: error), returnTo: .ticketSelection)
        }
    }

    func fail(_ message: String) {
        // Errors surfaced directly by a screen (e.g. Stripe sheet) came from
        // checkout, so back should return to ticket selection.
        setError(message, returnTo: .ticketSelection)
    }

    // MARK: - Error routing

    /// Transitions to the error step, remembering where the back arrow should
    /// return to. Pass `returnTo: nil` for errors with no prior screen (initial
    /// load) — the error's back button then closes the whole flow.
    private func setError(_ message: String, returnTo: Step?) {
        errorReturnStep = returnTo
        step = .error(message)
    }

    /// Returns from the error screen to the screen the buyer came from, if any.
    /// Returns `false` when there's nothing to go back to (the caller should
    /// close the flow instead).
    @discardableResult
    func backFromError() -> Bool {
        guard let errorReturnStep else { return false }
        step = errorReturnStep
        self.errorReturnStep = nil
        return true
    }

    // MARK: - Auth helpers

    /// The currently signed-in buyer's identity, if any — used by the auth
    /// screen to show a "signed in as …" confirmation instead of the entry form.
    func currentIdentity() async -> AuthIdentity? {
        await auth.currentIdentity()
    }

    /// Signs the current buyer out (so they can check out with a different
    /// account). The auth screen then falls back to the sign-in form.
    func signOut() async {
        await auth.signOut()
    }

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
            "settings": { "requires_approval": false },
            "viewer_request": null,
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
