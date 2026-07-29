import SwiftUI

/// Ticket selection screen, ported to match the Flutter app's
/// `TicketSelectionScreen`: a centered event header, ticket rows with pill
/// steppers, a fee/total breakdown, and a stacked pay bar at the bottom.
struct TicketSelectionView: View {

    let model: TicketFlowModel

    private var event: Event? { model.event }
    private let side = ZTheme.sideMargin

    var body: some View {
        if let event {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 8)
                        header(event)
                        Spacer().frame(height: 24)

                        VStack(spacing: 5) {
                            ForEach(event.sellableTicketTypes) { tt in
                                ticketRow(tt, isPaid: event.isPaid)
                            }
                        }
                    }
                    .padding(.horizontal, side)
                }
                .scrollIndicators(.hidden)
                payBar(event)
            }
            .background(ZTheme.background)
        }
    }

    // MARK: - Header

    private func header(_ event: Event) -> some View {
        VStack(spacing: 0) {
            Text(event.name)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(ZTheme.text)
                .multilineTextAlignment(.center)
            if let location = event.venueName ?? event.addressText, !location.isEmpty {
                Spacer().frame(height: 10)
                Text(location)
                    .font(.system(size: 14))
                    .foregroundStyle(ZTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Spacer().frame(height: 6)
            } else {
                Spacer().frame(height: 10)
            }
            Text(formatEventDateRange(start: event.startAt, end: event.endAt, timezone: event.timezone))
                .font(.system(size: 14))
                .foregroundStyle(ZTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Ticket row

    private func ticketRow(_ tt: TicketType, isPaid: Bool) -> some View {
        let quantity = model.quantities[tt.id] ?? 0
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(tt.name)
                    .font(.system(size: 16, weight: .black))
                    .tracking(0.2)
                    .foregroundStyle(ZTheme.text)
                subtitle(tt, isPaid: isPaid)
            }
            Spacer()
            stepper(tt, quantity: quantity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(ZTheme.cardOverlay, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Matches the app: the price line shows the crypto amount in parens when
    /// available (e.g. "$45.00 (0.27 SOL)"), otherwise the availability note. If
    /// both a crypto amount and a note exist, the note drops to a second line.
    @ViewBuilder
    private func subtitle(_ tt: TicketType, isPaid: Bool) -> some View {
        let price = tt.isFree || !isPaid ? "Free" : tt.priceCents.centsAsUSD
        let tokenAmt = tt.isFree ? nil : model.tokenAmount(forCents: tt.priceCents)
        let note = availabilityNote(tt)

        let firstLine: String = {
            if let tokenAmt { return "\(price) (\(tokenAmt))" }
            if let note { return "\(price) (\(note))" }
            return price
        }()

        Text(firstLine)
            .font(.system(size: 14))
            .foregroundStyle(ZTheme.secondaryText)

        // Second line only when the price line already used the token amount.
        if tokenAmt != nil, let note {
            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(ZTheme.secondaryText.opacity(0.7))
        }
    }

    private func availabilityNote(_ tt: TicketType) -> String? {
        if tt.isSoldOut { return L("sold_out", "Sold out") }
        if let remaining = tt.remaining { return Lf("remaining", "%@ remaining", "\(remaining)") }
        return nil
    }

    private func stepper(_ tt: TicketType, quantity: Int) -> some View {
        HStack(spacing: 0) {
            if quantity > 0 {
                stepButton(.remove, enabled: true) { setQuantity(tt, quantity - 1) }
                Text("\(quantity)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ZTheme.text)
                    .frame(minWidth: 20)
                    .padding(.horizontal, 12)
            }
            stepButton(.add, enabled: !tt.isSoldOut && quantity < maxAllowed(tt)) {
                setQuantity(tt, quantity + 1)
            }
        }
    }

    private func stepButton(_ icon: MIcon, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { if enabled { action() } }) {
            MaterialIcon(icon, size: 18, color: enabled ? ZTheme.text : ZTheme.secondaryText.opacity(0.35))
                .padding(8)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Pay bar

    private func payBar(_ event: Event) -> some View {
        VStack(spacing: 0) {
            if model.hasSelection && event.isPaid {
                breakdown(event)
                Spacer().frame(height: 12)
            }
            buttons(event)
        }
        .padding(.horizontal, side)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(ZTheme.background)
    }

    @ViewBuilder
    private func breakdown(_ event: Event) -> some View {
        let tickets = model.totalTicketCount
        // Tickets subtotal line.
        breakdownLine(
            label: LticketCount(tickets),
            value: model.subtotalCents.centsAsUSD
        )

        // Zuuppa fee line (+ crypto conversion underneath), when there's a fee.
        if model.feesCents > 0 {
            Spacer().frame(height: 4)
            HStack(alignment: .top) {
                Text(L("zuuppa_fee", "Zuuppa fee"))
                    .font(.system(size: 14))
                    .foregroundStyle(ZTheme.secondaryText)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(model.feesCents.centsAsUSD)
                        .font(.system(size: 14))
                        .foregroundStyle(ZTheme.secondaryText)
                    if let token = model.tokenAmount(forCents: model.feesCents) {
                        Text(token)
                            .font(.system(size: 12))
                            .foregroundStyle(ZTheme.secondaryText.opacity(0.7))
                    }
                }
            }
        }

        // Total line (bold, with crypto conversion underneath).
        Spacer().frame(height: 4)
        HStack(alignment: .top) {
            Text(L("total", "Total"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(ZTheme.text)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(model.buyerTotalCents.centsAsUSD)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(ZTheme.text)
                if let token = model.tokenAmount(forCents: model.buyerTotalCents) {
                    Text(token)
                        .font(.system(size: 13))
                        .foregroundStyle(ZTheme.secondaryText)
                }
            }
        }
    }

    private func breakdownLine(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
        }
        .font(.system(size: 14))
        .foregroundStyle(ZTheme.secondaryText)
    }

    @ViewBuilder
    private func buttons(_ event: Event) -> some View {
        let enabled = model.hasSelection

        if !event.isPaid || model.buyerTotalCents == 0 {
            ZButton(label: L("confirm_rsvp", "Confirm RSVP"), isEnabled: enabled) {
                Task { await model.checkoutFree() }
            }
        } else {
            if event.isStripeEnabled {
                // Runs the Stripe PaymentSheet flow, styled as the app's ZButton.
                StripePayButton(model: model, label: L("pay_with_card", "Pay with Card"), isEnabled: enabled)
            }
            if event.isCryptoEnabled {
                // When the host app has its own wallet, offer the automatic
                // "Pay with app wallet" path as the primary crypto action; the
                // QR deposit button stays as a fallback below it.
                let walletPay = model.hasWalletHandler
                if walletPay {
                    Spacer().frame(height: 10)
                    WalletPayButton(model: model, isEnabled: enabled)
                }
                Spacer().frame(height: 10)
                ZButton(
                    label: Lf("pay_with_token", "Pay with %@", event.paymentTokenOrDefault),
                    variant: (event.isStripeEnabled || walletPay) ? .outlined : .filled,
                    foregroundColor: (event.isStripeEnabled || walletPay) ? ZTheme.primary : ZTheme.onPrimary,
                    isEnabled: enabled
                ) {
                    Task { await model.checkoutExternalCrypto() }
                }
            }
        }

        // Bare "Cancel" button returns to the event details screen (the app
        // pops this screen).
        Spacer().frame(height: 10)
        ZButton(label: L("cancel", "Cancel"), variant: .bare, foregroundColor: ZTheme.secondaryText) {
            model.backToEventDetails()
        }
    }

    // MARK: - Helpers

    private func setQuantity(_ tt: TicketType, _ value: Int) {
        model.quantities[tt.id] = max(0, min(value, maxAllowed(tt)))
    }

    /// Matches the app: the per-order cap applies only to FREE tickets. Paid
    /// tickets are limited by remaining inventory only (or unlimited).
    private func maxAllowed(_ tt: TicketType) -> Int {
        let perOrder = event?.maxTicketsPerOrder ?? 10
        if tt.isFree {
            if let remaining = tt.remaining { return min(perOrder, remaining) }
            return perOrder
        }
        // Paid: capped by inventory only.
        return tt.remaining ?? Int.max
    }

}
