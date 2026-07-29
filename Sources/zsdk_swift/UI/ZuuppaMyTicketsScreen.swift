import SwiftUI

/// The public entry point for browsing the signed-in user's own tickets.
///
/// Present this full-screen (typically in a `fullScreenCover`). It gates on
/// sign-in (reusing the same OTP flow as the purchase SDK — a returning buyer
/// who already checked out stays signed in), lists their tickets grouped by
/// event with Upcoming / Past / Cancelled tabs, and opens a detail screen with
/// a scannable QR code per ticket.
///
/// ```swift
/// .fullScreenCover(isPresented: $showTickets) {
///     ZuuppaMyTicketsScreen { showTickets = false }
/// }
/// ```
///
/// Or use the convenience modifier: `.zuuppaMyTickets(isPresented:)`.
///
/// Customize what's shown with ``ZuuppaMyTicketsConfig`` (the `options`
/// parameter): which tabs appear, an optional host filter, and which
/// detail-screen actions are enabled.
public struct ZuuppaMyTicketsScreen: View {

    @State private var model: MyTicketsModel
    private let onFinish: () -> Void

    /// - Parameters:
    ///   - config: Backend configuration. Defaults to Zuuppa production.
    ///   - options: Feature toggles (tabs, host filter, detail actions).
    ///   - onFinish: Called when the user dismisses the screen.
    public init(
        config: ZuuppaConfig = .default,
        options: ZuuppaMyTicketsConfig = .default,
        onFinish: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: MyTicketsModel(config: config, options: options))
        self.onFinish = onFinish
    }

    /// Whether to run the network flow on appear. Previews seed a model directly.
    private var autoStart = true

    public var body: some View {
        NavigationStack {
            content
                .background(ZTheme.background)
                .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task {
            if autoStart { await model.start() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.authState {
        case .checking:
            ZStack(alignment: .top) {
                ProgressView()
                    .tint(ZTheme.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ZTheme.background)
                loadingHeader
            }
        case .signedOut:
            MyTicketsAuthView(model: model, onBack: onFinish)
        case .ready:
            MyTicketsListView(model: model, onBack: onFinish)
        }
    }

    /// A transparent back-arrow header over the initial spinner, so the SDK's
    /// own header is present from the first frame.
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
}

public extension View {
    /// Presents the Zuuppa "My Tickets" screen as a full-screen cover. The screen
    /// sets `isPresented` back to `false` when the user closes it.
    func zuuppaMyTickets(
        isPresented: Binding<Bool>,
        config: ZuuppaConfig = .default,
        options: ZuuppaMyTicketsConfig = .default
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            ZuuppaMyTicketsScreen(config: config, options: options) {
                isPresented.wrappedValue = false
            }
        }
    }
}

#if DEBUG
extension ZuuppaMyTicketsScreen {
    /// Preview-only initializer: renders a pre-seeded model without networking.
    init(previewModel: MyTicketsModel) {
        _model = State(initialValue: previewModel)
        self.onFinish = {}
        self.autoStart = false
    }
}

#Preview("My Tickets — ready") {
    ZuuppaMyTicketsScreen(previewModel: .preview())
}

#Preview("My Tickets — signed out") {
    ZuuppaMyTicketsScreen(previewModel: .preview(signedOut: true))
}

#Preview("My Tickets — empty") {
    ZuuppaMyTicketsScreen(previewModel: .preview(empty: true))
}
#endif
