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
    ///   - onFinish: Called when the buyer dismisses the flow.
    public init(
        eventId: String,
        config: ZuuppaConfig = .default,
        onFinish: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: TicketFlowModel(eventID: eventId, config: config))
        self.onFinish = onFinish
    }

    /// Whether to run the network flow on appear. Previews seed a model
    /// directly and skip it.
    private var autoStart = true

    private var accent: Color {
        Color(hex: model.event?.accentColor, default: .accentColor)
    }

    /// Several steps draw their own header (or use a bottom Cancel button), so
    /// they hide the nav bar (matching the app): event details (transparent
    /// header), checkout (Cancel button), and external-crypto (its own
    /// "Crypto payment" header).
    private var showsNavBar: Bool {
        switch model.step {
        // These draw their own header, use a Cancel button, or (confirmation)
        // dismiss via the Done button — so no nav-bar close ✕.
        case .eventDetails, .ticketSelection, .externalCryptoPayment, .confirmation:
            return false
        default:
            return true
        }
    }

    public var body: some View {
        NavigationStack {
            content
                .background(ZTheme.background)
                .toolbar(showsNavBar ? .visible : .hidden, for: .navigationBar)
                .toolbarBackground(ZTheme.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            onFinish()
                        } label: {
                            Image(systemName: "xmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(ZTheme.text)
                        }
                        .accessibilityLabel("Close")
                    }
                }
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
            ProgressView()
                .tint(ZTheme.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ZTheme.background)

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

    private func errorView(_ message: String) -> some View {
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
            ZButton(label: "Close") { onFinish() }
                .padding(.horizontal, 40)
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZTheme.background)
    }
}

public extension View {
    /// Presents the Zuuppa ticketing flow as a full-screen cover for the given
    /// event. The flow sets `isPresented` back to `false` when the buyer closes
    /// it.
    func zuuppaTickets(
        isPresented: Binding<Bool>,
        eventId: String,
        config: ZuuppaConfig = .default
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            ZuuppaTicketsScreen(eventId: eventId, config: config) {
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
