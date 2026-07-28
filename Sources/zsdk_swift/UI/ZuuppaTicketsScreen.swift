import SwiftUI

/// The public entry point for the Zuuppa ticketing SDK.
///
/// Present this full-screen (typically in a `fullScreenCover`) with an event
/// id. It runs the complete purchase flow — sign-in, event details, ticket
/// selection, payment (card or crypto), and confirmation — and calls
/// ``onFinish`` when the buyer closes it.
///
/// ```swift
/// .fullScreenCover(isPresented: $show) {
///     ZuuppaTicketsScreen(eventId: "evt-uuid") { show = false }
/// }
/// ```
///
/// Or use the convenience modifier: `.zuuppaTickets(isPresented:eventId:)`.
public struct ZuuppaTicketsScreen: View {

    @State private var model: TicketFlowModel
    private let onFinish: () -> Void

    /// - Parameters:
    ///   - eventId: The Zuuppa event to sell tickets for.
    ///   - config: Backend configuration. Defaults to Zuuppa production.
    ///   - onWalletPayment: Optional. Supply this when the embedding app has its
    ///     own crypto wallet: a "Pay with app wallet" button then appears for
    ///     crypto-enabled events, and this closure is invoked to sign + submit the
    ///     payment. See ``ZuuppaWalletPaymentHandler``.
    ///   - onFinish: Called when the buyer dismisses the flow.
    public init(
        eventId: String,
        config: ZuuppaConfig = .default,
        onWalletPayment: ZuuppaWalletPaymentHandler? = nil,
        onFinish: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: TicketFlowModel(
            eventID: eventId,
            config: config,
            walletHandler: onWalletPayment
        ))
        self.onFinish = onFinish
    }

    /// Whether to run the network flow on appear. Previews seed a model
    /// directly and skip it.
    private var autoStart = true

    private var accent: Color {
        Color(hex: model.event?.accentColor, default: .accentColor)
    }

    public var body: some View {
        NavigationStack {
            content
                .background(ZTheme.background)
                // Every step draws its own header (back arrow / Cancel / Done),
                // so the nav bar stays hidden throughout — no default ✕.
                .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task {
            if autoStart { await model.start() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .loading:
            ZStack(alignment: .top) {
                ProgressView()
                    .tint(ZTheme.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ZTheme.background)
                loadingHeader
            }

        case .auth:
            AuthView(model: model)

        case .eventDetails:
            EventDetailsView(model: model, onBack: onFinish)

        case .ticketSelection:
            TicketSelectionView(model: model)

        case .externalCryptoPayment(let payment):
            ExternalCryptoView(model: model, payment: payment)

        case .confirmation(let confirmation):
            ConfirmationView(
                model: model,
                confirmation: confirmation,
                onDone: onFinish
            )

        case .error(let message):
            errorView(message)
        }
    }

    /// A transparent back-arrow header shown over the initial loading spinner,
    /// so the SDK's own header is present from the first frame (instead of the
    /// default nav-bar ✕ flashing until the event loads).
    private var loadingHeader: some View {
        HStack {
            Button(action: onFinish) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ZTheme.text)
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel("Back")
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func errorView(_ message: String) -> some View {
        ZStack(alignment: .top) {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundStyle(ZTheme.orange)
                Text("Something went wrong")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(ZTheme.text)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(ZTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZTheme.background)

            errorHeader
        }
    }

    /// A transparent header for the error screen: a back arrow (left) that
    /// returns to the screen the buyer came from — or closes the flow if the
    /// error happened on the initial load — and a ✕ (right) that always closes
    /// the whole SDK.
    private var errorHeader: some View {
        HStack {
            Button {
                // Back to the previous screen, or close if there's nowhere to go.
                if !model.backFromError() { onFinish() }
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ZTheme.text)
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel("Back")

            Spacer()

            Button(action: onFinish) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ZTheme.text)
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 4)
    }
}

public extension View {
    /// Presents the Zuuppa ticketing flow as a full-screen cover for the given
    /// event. The flow sets `isPresented` back to `false` when the buyer closes
    /// it.
    func zuuppaTickets(
        isPresented: Binding<Bool>,
        eventId: String,
        config: ZuuppaConfig = .default,
        onWalletPayment: ZuuppaWalletPaymentHandler? = nil
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            ZuuppaTicketsScreen(eventId: eventId, config: config, onWalletPayment: onWalletPayment) {
                isPresented.wrappedValue = false
            }
        }
    }
}

#if DEBUG
extension ZuuppaTicketsScreen {
    /// Preview-only initializer: renders a pre-seeded model without any
    /// networking or auto-start.
    init(previewModel: TicketFlowModel) {
        _model = State(initialValue: previewModel)
        self.onFinish = {}
        self.autoStart = false
    }
}

#Preview("Event details") {
    ZuuppaTicketsScreen(previewModel: .preview(step: .eventDetails))
}

#Preview("Ticket selection") {
    ZuuppaTicketsScreen(previewModel: .preview(step: .ticketSelection))
}

#Preview("Confirmation") {
    ZuuppaTicketsScreen(previewModel: .preview(
        step: .confirmation(.init(ticketCount: 2, isPending: false))
    ))
}

#Preview("Auth") {
    ZuuppaTicketsScreen(previewModel: .preview(step: .auth))
}

#Preview("Loading") {
    ZuuppaTicketsScreen(previewModel: .preview(step: .loading))
}

#Preview("Error") {
    ZuuppaTicketsScreen(previewModel: .preview(
        step: .error("Network connection failed. Check your internet and try again.")
    ))
}

// MARK: - Live preview against a real event

/// Paste a real LIVE event id here to preview the flow against production data.
/// The event is fetched unauthenticated (the server serves live events
/// publicly), so no sign-in is needed just to see the details/selection screens.
//private let kPreviewEventID = "7da38cff-1e05-4c2e-95ee-9bc8528192e8"
private let kPreviewEventID = "5fd62227-4a79-4c28-8172-31b277757d79"

/// Wrapper that loads a real event before showing the screen, so the live
/// preview renders actual backend data.
private struct LiveEventPreview: View {
    @State private var model = TicketFlowModel(eventID: kPreviewEventID)
    var body: some View {
        ZuuppaTicketsScreen(previewModel: model)
            .task { await model.loadPreviewEvent() }
    }
}

#Preview("Live event") {
    LiveEventPreview()
}
#endif
