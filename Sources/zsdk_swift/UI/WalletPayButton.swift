import SwiftUI

/// "Pay with app wallet" button. Shown only when the embedding app supplied a
/// wallet handler. Tapping it hands off to the model, which switches to the
/// "processing payment" screen immediately and runs the whole flow (create
/// order → sign+submit via the host wallet → confirm) in the background, so this
/// button needs no busy state of its own.
struct WalletPayButton: View {

    let model: TicketFlowModel
    var label: String = "Pay with app wallet"
    var isEnabled: Bool = true

    var body: some View {
        ZButton(label: label, isEnabled: isEnabled) {
            model.payWithAppWallet()   // model owns the step transitions
        }
    }
}
