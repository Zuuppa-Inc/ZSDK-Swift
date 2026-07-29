import SwiftUI

/// Plain "processing payment" screen for the app-wallet flow. Shown the instant
/// the buyer taps "Pay with app wallet", while order creation, the wallet
/// hand-off, and the confirmation poll all run in the background (see
/// `TicketFlowModel.payWithAppWallet`).
///
/// Intentionally minimal: it does NOT expose the QR/deposit details or the raw
/// payment status — the buyer's wallet is paying automatically, so surfacing a
/// deposit address would wrongly imply they still need to send funds. It just
/// shows a spinner until the flow resolves to the confirmation or error screen.
struct WalletProcessingView: View {

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ProgressView()
                .progressViewStyle(.circular)
                .tint(ZTheme.primary)
                .scaleEffect(1.4)

            Spacer().frame(height: 28)

            Text(L("processing_payment", "Processing payment"))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ZTheme.text)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 8)

            Text(L("processing_payment_sub", "Confirming your payment and issuing your tickets. This usually takes a few seconds — please keep this screen open."))
                .font(.system(size: 14))
                .foregroundStyle(ZTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(14 * 0.35)
                .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZTheme.background)
    }
}

#if DEBUG
#Preview("Wallet processing") {
    WalletProcessingView()
        .preferredColorScheme(.dark)
}
#endif
