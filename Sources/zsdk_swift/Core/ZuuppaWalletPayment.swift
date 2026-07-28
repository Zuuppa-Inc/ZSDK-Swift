import Foundation

/// The details a host app's wallet needs to pay for a Zuuppa ticket order.
///
/// The host wallet must send **exactly** `amountBaseUnits` of the token to
/// `depositAddress` on `chain`. `tokenMint == nil` means the chain's native asset
/// (native SOL); otherwise it's the SPL token at that mint. No memo/reference is
/// required — the backend matches the payment purely by the unique per-order
/// deposit address.
public struct ZuuppaCryptoPaymentRequest: Sendable, Equatable {

    /// The Zuuppa order id (for the host's records / logging; not sent on-chain).
    public let orderID: String

    /// The chain to pay on. Currently always `"solana"`.
    public let chain: String

    /// Token symbol, e.g. `"SOL"` or `"USDC"` (display only).
    public let token: String

    /// Base58 SPL mint address, or `nil` for native SOL.
    public let tokenMint: String?

    /// Token decimals, for interpreting `amountBaseUnits`.
    public let decimals: Int

    /// The exact amount to send, as an integer string in the token's base units.
    public let amountBaseUnits: String

    /// The unique per-order destination address to send the funds to.
    public let depositAddress: String

    public init(
        orderID: String,
        chain: String,
        token: String,
        tokenMint: String?,
        decimals: Int,
        amountBaseUnits: String,
        depositAddress: String
    ) {
        self.orderID = orderID
        self.chain = chain
        self.token = token
        self.tokenMint = tokenMint
        self.decimals = decimals
        self.amountBaseUnits = amountBaseUnits
        self.depositAddress = depositAddress
    }
}

/// A handler the host app supplies to pay a crypto ticket order with its own
/// wallet. It should sign and submit a transfer of `request.amountBaseUnits` to
/// `request.depositAddress`, then return.
///
/// - Returns: An optional transaction signature/hash. This is display-only and is
///   **never** sent to Zuuppa — the backend confirms the payment by watching the
///   deposit address. Return `nil` if a signature isn't available.
/// - Throws: If the wallet fails or the buyer cancels. The SDK treats a thrown
///   error as "payment not completed" and returns the buyer to ticket selection
///   with an inline error, so they can retry or use another payment method.
public typealias ZuuppaWalletPaymentHandler =
    @Sendable (ZuuppaCryptoPaymentRequest) async throws -> String?
