import Foundation

/// Localized-string lookup for the SDK. All user-facing copy goes through this,
/// resolving against the bundled `Localizable.strings` for the 7 languages the
/// Zuuppa app supports (en, es, fr, pt, hi, zh, ar). Falls back to the English
/// value baked into each call site if a key is missing.
///
/// Reads from `Bundle.module` (the SDK's own resource bundle) rather than the
/// host app, so the SDK is localized independently of the embedding app.
func L(_ key: String, _ fallback: String) -> String {
    Bundle.module.localizedString(forKey: key, value: fallback, table: nil)
}

/// A localized format string with arguments, e.g.
/// `Lf("order_n", "Order %@ – %@", "1", amount)`.
func Lf(_ key: String, _ fallback: String, _ args: CVarArg...) -> String {
    let format = Bundle.module.localizedString(forKey: key, value: fallback, table: nil)
    return String(format: format, locale: .current, arguments: args)
}

/// Localized ticket-count string with proper plurals (via `.stringsdict`):
/// "1 ticket" / "3 tickets", translated per locale.
func LticketCount(_ count: Int) -> String {
    let format = Bundle.module.localizedString(
        forKey: "ticket_count", value: "%d tickets", table: nil
    )
    return String(format: format, locale: .current, count)
}
