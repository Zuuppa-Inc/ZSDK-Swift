import Foundation

/// Localized-string lookup for the SDK. All user-facing copy goes through this,
/// resolving against the bundled `Localizable.strings` for the 7 languages the
/// Zuuppa app supports (en, es, fr, pt, hi, zh, ar). Falls back to the English
/// value baked into each call site if a key is missing.
///
/// ## Why not read `Bundle.module` directly?
/// `Bundle.module.localizedString(...)` resolves the language the same way the
/// *host app* does: iOS intersects the app's declared localizations with the
/// device's preferred languages and picks a winner, then `Bundle.module`
/// inherits that decision. If the embedding app declares no localizations (which
/// is common — most apps that adopt this SDK aren't themselves localized), that
/// intersection collapses to English and the SDK shows English no matter what
/// language the device is set to.
///
/// To be localized *independently* of the host app, we resolve the language
/// ourselves from `Locale.preferredLanguages` (the device's real language order)
/// against the languages the SDK bundle actually ships, load that specific
/// `<lang>.lproj` sub-bundle once, and read every string from it. The device
/// language now wins regardless of what the host app declares.

/// Picks the best SDK language for a set of preferred languages, considering
/// only the languages the SDK actually ships. Pure (no globals) so tests can
/// prove the choice without changing the device language — e.g. passing
/// `["hi-IN", "en"]` must return `"hi"` even in a non-localized host app.
///
/// Uses `Bundle.preferredLocalizations` for iOS's own region/script-aware
/// matching ("zh-Hans-US" → "zh", "en-GB" → "en"). Defaults to English.
func resolveSDKLanguage(
    available: [String],
    preferences: [String]
) -> String {
    let shipped = available.filter { $0 != "Base" }
    let match = Bundle.preferredLocalizations(
        from: shipped, forPreferences: preferences
    )
    return match.first ?? "en"
}

/// The language the SDK should render in, resolved from the device's preferred
/// languages against what we ship — independent of the host app.
private let sdkLanguage: String = resolveSDKLanguage(
    available: Bundle.module.localizations,
    preferences: Locale.preferredLanguages
)

/// The SDK's localized resource bundle for `sdkLanguage`. Computed once and
/// cached. Falls back to `Bundle.module` itself if the `.lproj` can't be
/// loaded, so lookups always resolve to *something*.
private let sdkBundle: Bundle = {
    let module = Bundle.module
    guard let path = module.path(forResource: sdkLanguage, ofType: "lproj"),
          let bundle = Bundle(path: path)
    else {
        return module
    }
    return bundle
}()

/// The locale matching `sdkLanguage`, used for number/plural formatting so
/// counts render correctly for the resolved language.
private let sdkLocale = Locale(identifier: sdkLanguage)

/// The language code the SDK is currently rendering in (e.g. "es"), for passing
/// to server endpoints that localize their output (like the ticket email).
var currentSDKLanguage: String { sdkLanguage }

func L(_ key: String, _ fallback: String) -> String {
    sdkBundle.localizedString(forKey: key, value: fallback, table: nil)
}

/// A localized format string with arguments, e.g.
/// `Lf("order_n", "Order %@ – %@", "1", amount)`.
func Lf(_ key: String, _ fallback: String, _ args: CVarArg...) -> String {
    let format = sdkBundle.localizedString(forKey: key, value: fallback, table: nil)
    return String(format: format, locale: sdkLocale, arguments: args)
}

/// Localized ticket-count string with proper plurals (via `.stringsdict`):
/// "1 ticket" / "3 tickets", translated per locale.
func LticketCount(_ count: Int) -> String {
    let format = sdkBundle.localizedString(
        forKey: "ticket_count", value: "%d tickets", table: nil
    )
    return String(format: format, locale: sdkLocale, count)
}
