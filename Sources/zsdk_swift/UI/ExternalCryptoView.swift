import SwiftUI
import UIKit

/// External-crypto payment screen — a 1:1 port of the app's
/// `ExternalCryptoPaymentScreen`. Owns its polling + live status state so every
/// edge case (waiting / partial-underpaid / paid / expired / refunded /
/// needs-attention) renders exactly like the app.
///
/// Robust against the same real-world cases the app handles:
///  - Lost polls / flaky network: each poll is independent; failures ignored,
///    retried next tick.
///  - Backgrounding: polling pauses in the background and polls immediately on
///    resume, so a payment made while backgrounded is picked up promptly.
///  - Underpayment: switches the hero to "SEND REMAINING" + the shortfall, and
///    keeps polling (sending the remainder can still complete it).
///  - Expiry / refund: terminal failure state with a "Go back" button.
struct ExternalCryptoView: View {

    let model: TicketFlowModel
    let payment: TicketFlowModel.ExternalCryptoPayment

    // Live state — mirrors the app's State fields.
    @State private var paymentStatus = "pending"
    @State private var message = "Waiting for payment…"
    @State private var shortfallBaseUnits: Int?
    @State private var finishing = false

    @State private var pollTask: Task<Void, Never>?
    @State private var toast: String?

    @Environment(\.scenePhase) private var scenePhase

    private let pollInterval: Duration = .seconds(3)

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    label(isUnderpaid ? L("send_remaining", "SEND REMAINING") : L("send", "SEND"))
                    Spacer().frame(height: 10)
                    amount
                    Spacer().frame(height: 36)
                    qrPlate
                    Spacer().frame(height: 24)
                    label(L("to_label", "TO"))
                    Spacer().frame(height: 8)
                    addressRow
                    Spacer().frame(height: 36)
                    statusBlock
                    Spacer().frame(height: 14)
                    Text(L("crypto_keep_open", "Keep this screen open — your payment is detected automatically, usually within seconds."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(ZTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(12.5 * 0.4)

                    if isTerminalFailure {
                        Spacer().frame(height: 28)
                        ZButton(label: L("go_back", "Go back")) { model.backToCheckout() }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(EdgeInsets(top: 12, leading: 24, bottom: 32, trailing: 24))
            }
            .scrollIndicators(.hidden)
        }
        .background(ZTheme.background)
        .overlay(alignment: .bottom) { toastView }
        .onAppear { startPolling() }
        .onDisappear { pollTask?.cancel() }
        .onChange(of: scenePhase) { _, phase in
            // Pause in background; poll immediately + restart on resume.
            switch phase {
            case .active: startPolling()
            case .background, .inactive: pollTask?.cancel()
            @unknown default: break
            }
        }
    }

    // MARK: - Polling (mirrors the app's Timer.periodic + _poll)

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            await poll()
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                if Task.isCancelled { break }
                await poll()
            }
        }
    }

    private func poll() async {
        if finishing { return }
        guard let res = try? await model.externalCryptoStatus(orderID: payment.orderID) else {
            return  // Transient failure — retried next tick.
        }

        // Terminal success: server issued tickets (order completed) or payment
        // is confirmed paid/swept/overpaid.
        let isPaid = res.orderStatus == "completed"
            || ["paid", "swept", "overpaid"].contains(res.paymentStatus)

        paymentStatus = res.paymentStatus
        if let m = res.message, !m.isEmpty { message = m }
        shortfallBaseUnits = res.shortfallAmount

        if isPaid && !finishing {
            finishing = true
            pollTask?.cancel()
            // Brief pause so the buyer sees the "paid" state before navigating.
            try? await Task.sleep(for: .milliseconds(600))
            model.finishExternalCrypto(status: res)
        }
    }

    // MARK: - Derived state (mirrors the app's getters)

    /// Underpaid with a positive remainder still owed.
    private var isUnderpaid: Bool {
        paymentStatus == "underpaid" && (shortfallBaseUnits ?? 0) > 0
    }

    private var isTerminalFailure: Bool {
        ["expired", "refunded", "refund_failed"].contains(paymentStatus)
    }

    /// Amount shown as the hero: remaining when underpaid, else the full order.
    private var displayAmount: String {
        let base: Int64 = isUnderpaid
            ? Int64(shortfallBaseUnits ?? 0)
            : (Int64(payment.amountBaseUnits) ?? 0)
        return formatBaseUnits(base)
    }

    /// Formats raw base units into a decimal string with trailing zeros
    /// trimmed — identical to the app's `_formatBaseUnits`.
    private func formatBaseUnits(_ base: Int64) -> String {
        guard payment.decimals > 0 else { return "\(base)" }
        var divisor: Int64 = 1
        for _ in 0..<payment.decimals { divisor *= 10 }
        let whole = base / divisor
        let fracValue = base % divisor
        var frac = String(fracValue)
        if frac.count < payment.decimals {
            frac = String(repeating: "0", count: payment.decimals - frac.count) + frac
        }
        // Trim trailing zeros.
        while frac.hasSuffix("0") { frac.removeLast() }
        return frac.isEmpty ? "\(whole)" : "\(whole).\(frac)"
    }

    private var shortAddress: String {
        let a = payment.depositAddress
        guard a.count > 16 else { return a }
        return "\(a.prefix(8))...\(a.suffix(8))"
    }

    /// Color / icon / title per payment status — matches the app's `_statusVisual`.
    private var statusVisual: (color: Color, icon: MIcon, title: String) {
        switch paymentStatus {
        case "paid", "swept", "overpaid":
            return (ZTheme.green, .checkCircleRounded, L("pay_received", "Payment received"))
        case "underpaid":
            return (ZTheme.pendingStatus, .timelapseRounded, L("pay_partial", "Partial payment"))
        case "expired":
            return (ZTheme.red, .timerOffRounded, L("pay_expired", "Expired"))
        case "refunded":
            return (ZTheme.red, .undoRounded, L("pay_refunded", "Refunded"))
        case "refund_failed":
            return (ZTheme.red, .errorOutlineRounded, L("pay_attention", "Needs attention"))
        default:
            return (ZTheme.primary, .hourglassTopRounded, L("pay_waiting", "Waiting for payment"))
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text(L("crypto_payment", "Crypto payment"))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ZTheme.text)
            HStack {
                Button { model.backToCheckout() } label: {
                    MaterialIcon(.arrowBack, size: 24, color: ZTheme.text)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("back", "Back"))
                Spacer()
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 56)
    }

    // MARK: - Pieces

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(ZTheme.secondaryText)
    }

    private var amount: some View {
        Button { copy(displayAmount, "Amount") } label: {
            VStack(spacing: 6) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(displayAmount)
                        .font(.system(size: 44, weight: .heavy))
                        .tracking(-1)
                        .foregroundStyle(ZTheme.text)
                    Text(payment.token)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(ZTheme.secondaryText)
                        .padding(.bottom, 6)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.4)

                HStack(spacing: 5) {
                    MaterialIcon(.copyRounded, size: 13, color: ZTheme.primary)
                    Text(L("tap_to_copy", "Tap to copy"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(ZTheme.primary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var qrPlate: some View {
        QRCodeView(string: payment.depositAddress)
            .frame(width: 200, height: 200)
            .padding(18)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
    }

    private var addressRow: some View {
        Button { copy(payment.depositAddress, "Address") } label: {
            HStack(spacing: 8) {
                Text(shortAddress)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ZTheme.text)
                MaterialIcon(.copyRounded, size: 16, color: ZTheme.primary)
            }
        }
        .buttonStyle(.plain)
    }

    /// Flat icon/spinner + title + message. Spinner while active; the status
    /// icon once terminal or finishing — exactly like the app's `_buildStatus`.
    private var statusBlock: some View {
        let v = statusVisual
        return VStack(spacing: 0) {
            Group {
                if !isTerminalFailure && !finishing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(v.color)
                } else {
                    MaterialIcon(v.icon, size: 26, color: v.color)
                }
            }
            .frame(width: 26, height: 26)

            Spacer().frame(height: 10)
            Text(v.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(v.color)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 3)
            Text(message)
                .font(.system(size: 13.5))
                .foregroundStyle(ZTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(13.5 * 0.35)
        }
    }

    // MARK: - Copy + toast (the app shows a SnackBar)

    private func copy(_ value: String, _ label: String) {
        UIPasteboard.general.string = value
        withAnimation { toast = Lf("copied", "%@ copied", label) }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { toast = nil }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ZTheme.onPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(ZTheme.primary, in: Capsule())
                .padding(.bottom, 24)
                .transition(.opacity)
        }
    }
}
