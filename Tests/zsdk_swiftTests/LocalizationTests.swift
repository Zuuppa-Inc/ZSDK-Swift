import Testing
import Foundation
@testable import zsdk_swift

/// The 7 languages the SDK ships, matching the Zuuppa app.
private let shipped = ["en", "es", "fr", "pt", "hi", "zh", "ar"]

@Suite("Localization")
struct LocalizationTests {

    /// The core fix: the SDK follows the *device's* preferred languages, not
    /// the host app's declared localizations. This proves the resolver picks
    /// Hindi when Hindi is the device's top language — the exact scenario the
    /// user hit (device set to Hindi, host app not localized).
    @Test("Device language wins, independent of host app")
    func devicePreferenceWins() {
        #expect(resolveSDKLanguage(available: shipped, preferences: ["hi-IN", "en"]) == "hi")
        #expect(resolveSDKLanguage(available: shipped, preferences: ["es-MX"]) == "es")
        #expect(resolveSDKLanguage(available: shipped, preferences: ["fr-CA"]) == "fr")
        #expect(resolveSDKLanguage(available: shipped, preferences: ["pt-BR"]) == "pt")
        #expect(resolveSDKLanguage(available: shipped, preferences: ["ar"]) == "ar")
    }

    /// Region/script variants resolve to the base language we ship. We ship
    /// Simplified Chinese ("zh"), so "zh-Hans-US" matches it; Traditional
    /// ("zh-Hant") is a different script we don't ship, so it falls back.
    @Test("Region and script variants resolve to shipped base")
    func variantsResolve() {
        #expect(resolveSDKLanguage(available: shipped, preferences: ["zh-Hans-US"]) == "zh")
        #expect(resolveSDKLanguage(available: shipped, preferences: ["en-GB"]) == "en")
    }

    /// A language we don't ship falls back to English, never crashes.
    @Test("Unsupported language falls back to English")
    func unsupportedFallsBack() {
        #expect(resolveSDKLanguage(available: shipped, preferences: ["ja", "ko"]) == "en")
        #expect(resolveSDKLanguage(available: shipped, preferences: []) == "en")
    }

    /// Every shipped language actually resolves a translated string from its
    /// own `.lproj` sub-bundle (spot-checking a few known translations).
    @Test("Known translations resolve per language")
    func knownTranslations() {
        func value(_ key: String, _ language: String) -> String {
            guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { return "" }
            return bundle.localizedString(forKey: key, value: "", table: nil)
        }
        #expect(value("tab_upcoming", "es") == "Próximos")
        #expect(value("cancel", "fr") == "Annuler")
        #expect(value("tab_upcoming", "hi") == "आगामी")
        #expect(value("cancel", "ar") == "إلغاء")
    }

    /// Every key present in English must exist in all 6 other languages, so no
    /// language silently falls back to English for individual strings.
    @Test("All languages have every key")
    func allLanguagesHaveEveryKey() throws {
        func keys(_ language: String) throws -> Set<String> {
            let path = try #require(Bundle.module.path(forResource: language, ofType: "lproj"))
            let stringsPath = path + "/Localizable.strings"
            let dict = try #require(NSDictionary(contentsOfFile: stringsPath) as? [String: String])
            return Set(dict.keys)
        }
        let english = try keys("en")
        #expect(!english.isEmpty)
        for language in shipped where language != "en" {
            let missing = english.subtracting(try keys(language))
            #expect(missing.isEmpty, "\(language) is missing keys: \(missing.sorted())")
        }
    }
}
