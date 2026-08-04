import SwiftUI
import CoreText

/// The Material Icons the SDK uses, keyed to the exact codepoints the Flutter
/// app renders (from Flutter's `Icons.*` definitions). Using the same font +
/// codepoints makes the glyphs pixel-identical to the app.
enum MIcon: String {
    case confirmationNumOutlined
    case block
    case lockOutline
    case localOfferOutlined
    case add
    case remove
    case locationOn
    case copyRounded
    case checkCircleRounded
    case hourglassTopRounded
    case timelapseRounded
    case timerOffRounded
    case undoRounded
    case errorOutlineRounded
    case cancelOutlined
    case editOutlined
    case arrowBack
    case share            // ios_share — the app's share glyph
    case chevronRight
    case accountBalanceWallet
    case calendarToday
    case mapOutlined
    case receiptLong
    case emailOutlined
    case qrCode
    case search
    case close

    /// Unicode scalar for the glyph in MaterialIcons-Regular.
    var scalar: Unicode.Scalar {
        let code: UInt32
        switch self {
        case .confirmationNumOutlined: code = 0xef75
        case .block: code = 0xe0e1
        case .lockOutline: code = 0xe3b1
        case .localOfferOutlined: code = 0xf184
        case .add: code = 0xe047
        case .remove: code = 0xe516
        case .locationOn: code = 0xe3ab
        case .copyRounded: code = 0xf66c
        case .checkCircleRounded: code = 0xf635
        case .hourglassTopRounded: code = 0xf800
        case .timelapseRounded: code = 0xf0235
        case .timerOffRounded: code = 0xf023b
        case .undoRounded: code = 0xf0261
        case .errorOutlineRounded: code = 0xf712
        case .cancelOutlined: code = 0xef28
        case .editOutlined: code = 0xf00d
        case .arrowBack: code = 0xe092
        case .share: code = 0xe34d
        case .chevronRight: code = 0xe15f
        case .accountBalanceWallet: code = 0xe041
        case .calendarToday: code = 0xe122
        case .mapOutlined: code = 0xf1ae
        case .receiptLong: code = 0xe50d
        case .emailOutlined: code = 0xf018
        case .qrCode: code = 0xe4f5
        case .search: code = 0xe567
        case .close: code = 0xe16a
        }
        return Unicode.Scalar(code)!
    }

    var character: String { String(scalar) }
}

/// Registers and names the bundled Material Icons font once.
enum MaterialFont {
    static let name = "MaterialIcons-Regular"

    /// Registered lazily on first access (runs exactly once).
    static let registered: Bool = {
        guard let url = Bundle.module.url(forResource: "MaterialIcons-Regular", withExtension: "otf") else {
            return false
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return true
    }()

    /// Registers the font with Core Text. Safe to call repeatedly.
    static func registerIfNeeded() {
        _ = registered
    }
}

/// The app's share glyph, rendered from the exact `assets/share.svg` path
/// (Font Awesome Pro, licensed). Drop-in replacement for the header's share
/// button icon, matching `ShareIcon` in the app.
struct ShareIcon: View {
    var size: CGFloat = 20
    var color: Color = ZTheme.text

    // Verbatim `d` and viewBox from the app's assets/share.svg.
    private static let pathData =
        "M64 416c0 17.7 14.3 32 32 32l256 0c17.7 0 32-14.3 32-32l0-96 64 0 0 96c0 53-43 96-96 96L96 512c-53 0-96-43-96-96l0-96 64 0 0 96zM203.8 7.2c12.6-10.3 31.1-9.5 42.8 2.2l150.6 150.6-45.3 45.3-96-96 0 242.7-64 0 0-242.7-96 96-45.2-45.3 150.6-150.6 2.4-2.2z"

    var body: some View {
        SVGPathShape(pathData: Self.pathData, viewBox: CGSize(width: 448, height: 512))
            .fill(color)
            .frame(width: size, height: size)
    }
}

/// A Material Icons glyph, styled like the app's `Icon(...)`.
struct MaterialIcon: View {
    let icon: MIcon
    var size: CGFloat = 24
    var color: Color = ZTheme.text

    init(_ icon: MIcon, size: CGFloat = 24, color: Color = ZTheme.text) {
        self.icon = icon
        self.size = size
        self.color = color
        MaterialFont.registerIfNeeded()
    }

    var body: some View {
        Text(icon.character)
            .font(.custom(MaterialFont.name, size: size))
            .foregroundStyle(color)
    }
}
