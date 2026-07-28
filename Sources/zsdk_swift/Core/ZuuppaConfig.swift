import Foundation

/// Configuration for the Zuuppa SDK.
///
/// All defaults point at Zuuppa's production backend and Supabase project. The
/// Supabase URL and anon key are *publishable* client-side values (the same
/// ones shipped in the Zuuppa app binary), so it is safe to embed them here.
///
/// An embedding app normally never constructs this — it just passes an
/// `eventId` to ``ZuuppaTicketsScreen`` and the shared ``ZuuppaConfig/default``
/// is used. Override only for testing against a different backend.
public struct ZuuppaConfig: Sendable {

    /// Base URL of the Zuuppa API server.
    public var apiBaseURL: URL

    /// Base URL of the Supabase project (used for OTP auth).
    public var supabaseURL: URL

    /// Supabase publishable ("anon") key.
    public var supabaseAnonKey: String

    public init(apiBaseURL: URL, supabaseURL: URL, supabaseAnonKey: String) {
        self.apiBaseURL = apiBaseURL
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
    }

    /// The default production configuration.
    ///
    /// The Supabase project MUST match the one the server validates JWTs
    /// against (server `SUPABASE_URL` = tpnurrihpfwlfepmhqzt). Using a different
    /// project makes the server reject the buyer's token with "Unknown signing
    /// key" during checkout.
    public static let `default` = ZuuppaConfig(
        apiBaseURL: URL(string: "https://zuuppa-gbt.fly.dev")!,
        supabaseURL: URL(string: "https://tpnurrihpfwlfepmhqzt.supabase.co")!,
        supabaseAnonKey: "sb_publishable_C0nQ3r2AcszGUmbzGdkGyg_S1aO6p1V"
    )
}
