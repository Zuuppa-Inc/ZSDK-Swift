import UIKit
import PassKit

/// Presents Apple Wallet's "Add Passes" sheet for a set of `.pkpass` payloads.
///
/// `PKAddPassesViewController` requires a delegate that lives until the sheet is
/// dismissed, so this small object retains itself for the duration of the
/// presentation. Adding an existing pass this way needs no special entitlement
/// (that's only for issuing pass types).
@MainActor
final class WalletPassPresenter: NSObject, @MainActor PKAddPassesViewControllerDelegate {

    /// Strong self-reference held while the sheet is on screen.
    private var retained: WalletPassPresenter?
    private var completion: (() -> Void)?

    /// Builds passes from the given `.pkpass` payloads and presents the add sheet.
    /// Returns `false` if none of the payloads produced a valid pass or there's
    /// no view controller to present from.
    @discardableResult
    func present(passData: [Data], completion: (() -> Void)? = nil) -> Bool {
        let passes = passData.compactMap { try? PKPass(data: $0) }
        guard !passes.isEmpty,
              let controller = PKAddPassesViewController(passes: passes),
              let presenter = UIApplication.topViewController() else {
            return false
        }
        controller.delegate = self
        self.completion = completion
        self.retained = self   // keep alive until dismissed
        presenter.present(controller, animated: true)
        return true
    }

    func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
        controller.dismiss(animated: true) { [weak self] in
            self?.completion?()
            self?.completion = nil
            self?.retained = nil
        }
    }
}
