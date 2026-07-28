import SwiftUI

/// "Pay with app wallet" button. Shown only when the embedding app supplied a
/// wallet handler. Runs the handler via the model (which owns the whole flow:
/// create order → sign+submit via the host wallet → hand off to the status-poll
/// screen), keeping a local busy state for the brief window before the model
/// swaps the screen out.
struct WalletPayButton: View {

    let model: TicketFlowModel
    var label: String = "Pay with app wallet"
    var isEnabled: Bool = true

    @State private var isBusy = false

    var body: some View {
        ZButton(label: label, isBusy: isBusy, isEnabled: isEnabled) {
            Task {
                isBusy = true
                await model.payWithAppWallet()   // model owns the step transitions
                isBusy = false
            }
        }
    }
}
