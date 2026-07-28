import SwiftUI

/// Colors and sizes ported from the Zuuppa Flutter app's `theme.dart`
/// (`ZuuppaColors` dark scheme + `ZuuppaSizes`), so the SDK's UI matches the
/// app one-to-one. The SDK uses the dark scheme, matching the checkout flow.
enum ZTheme {

    // MARK: - Colors (ZuuppaColorScheme.dark)

    static let background = Color(hex6: 0x141414)
    static let secondaryBackground = Color(hex6: 0x222222)
    static let primary = Color(red: 181/255, green: 204/255, blue: 255/255)
    static let text = Color(hex6: 0xFFFFFF)
    static let secondaryText = Color(hex6: 0xB4B4B4)
    static let onPrimary = Color(hex6: 0x141414)
    static let divider = Color(hex6: 0x333333)
    static let pendingStatus = Color(hex6: 0xF59E0B)
    static let confirmedStatus = Color(hex6: 0x22C55E)

    static let green = Color(hex6: 0x80C080)
    static let red = Color(hex6: 0xFF8080)
    static let orange = Color(hex6: 0xFFD280)

    // MARK: - Sizes (ZuuppaSizes)

    static let sideMargin: CGFloat = 20
    static let fontSize: CGFloat = 16
    static let buttonHeight: CGFloat = 52
    static let buttonCornerRadius: CGFloat = 8
    /// Subtle card overlay: text color at 6% over the background.
    static let cardOverlay = Color.white.opacity(0.06)
}

extension Color {
    /// Builds a `Color` from a 24-bit RGB hex integer (e.g. `0x141414`).
    init(hex6: UInt32) {
        self.init(
            red: Double((hex6 >> 16) & 0xFF) / 255,
            green: Double((hex6 >> 8) & 0xFF) / 255,
            blue: Double(hex6 & 0xFF) / 255
        )
    }
}

// MARK: - ZButton

/// Port of the app's `ZButton`: a full-width button, 52pt tall, 8pt corners.
enum ZButtonVariant {
    case filled
    case outlined
    case bare
}

struct ZButton: View {
    let label: String
    var variant: ZButtonVariant = .filled
    var backgroundColor: Color = ZTheme.primary
    var foregroundColor: Color = ZTheme.onPrimary
    var isBusy: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: { if isEnabled && !isBusy { action() } }) {
            ZStack {
                shape
                if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(foregroundColor)
                        .scaleEffect(0.8)
                } else {
                    Text(label)
                        .font(.system(size: ZTheme.fontSize, weight: .bold))
                        .foregroundStyle(resolvedForeground)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: ZTheme.buttonHeight)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
    }

    @ViewBuilder
    private var shape: some View {
        let rect = RoundedRectangle(cornerRadius: ZTheme.buttonCornerRadius)
        switch variant {
        case .filled:
            rect.fill(isEnabled ? backgroundColor : ZTheme.cardOverlay)
        case .outlined:
            rect.stroke(foregroundColor, lineWidth: 1.5)
        case .bare:
            rect.fill(.clear)
        }
    }

    private var resolvedForeground: Color {
        switch variant {
        case .filled: return isEnabled ? foregroundColor : ZTheme.secondaryText
        case .outlined, .bare: return foregroundColor
        }
    }
}
