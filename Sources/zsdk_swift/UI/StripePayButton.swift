import SwiftUI
import StripePaymentSheet

/// A "Pay with Card" button that runs the full Stripe flow:
/// 1. Create the order on the server → get client_secret + connected account.
/// 2. Present Stripe's PaymentSheet.
/// 3. On success, confirm the order server-side and advance to confirmation.
struct StripePayButton: View {

    let model: TicketFlowModel
    var label: String = "Pay with Card"
    var isEnabled: Bool = true

    @State private var isBusy = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 6) {
            ZButton(label: label, isBusy: isBusy, isEnabled: isEnabled) {
                Task { await pay() }
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 13))
                    .foregroundStyle(ZTheme.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @MainActor
    private func pay() async {
        errorText = nil
        isBusy = true
        defer { isBusy = false }

        do {
            // 1. Create the order.
            let checkout = try await model.beginStripeCheckout()

            // 2. Configure and present the payment sheet on the host's
            //    connected account.
            STPAPIClient.shared.publishableKey = checkout.publishableKey
            if let account = checkout.stripeAccountID {
                STPAPIClient.shared.stripeAccount = account
            }

            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = model.event?.name ?? "Zuuppa"
            configuration.allowsDelayedPaymentMethods = false

            let paymentSheet = PaymentSheet(
                paymentIntentClientSecret: checkout.clientSecret,
                configuration: configuration
            )

            let result = await present(paymentSheet)

            switch result {
            case .completed:
                // 3. Confirm server-side; this issues tickets.
                await model.confirmStripe(orderID: checkout.orderID)
            case .canceled:
                break   // Buyer backed out; stay on selection.
            case .failed(let error):
                errorText = error.localizedDescription
            }
        } catch {
            errorText = (error as? ZuuppaError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Presents the payment sheet from the top-most view controller and awaits
    /// the result.
    @MainActor
    private func present(_ sheet: PaymentSheet) async -> PaymentSheetResult {
        guard let presenter = Self.topViewController() else {
            return .failed(error: ZuuppaError.unknown)
        }
        return await withCheckedContinuation { continuation in
            sheet.present(from: presenter) { result in
                continuation.resume(returning: result)
            }
        }
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
