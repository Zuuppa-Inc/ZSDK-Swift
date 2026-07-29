import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

// Small UI helpers shared across the ticket screens.

extension Int {
    /// Adds thousands separators (e.g. 30000 → "30,000"), matching the app.
    var groupedThousands: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    /// Formats a cents amount as a USD currency string (e.g. 4500 → "$45.00").
    var centsAsUSD: String {
        let dollars = Double(self) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }
}

extension Color {
    /// Parses a "#RRGGBB" hex string; falls back to the provided default.
    init(hex: String?, default fallback: Color) {
        guard let hex else { self = fallback; return }
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else {
            self = fallback
            return
        }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Renders a QR code image for the given string, for the external-crypto
/// deposit address. Uses CoreImage so there's no third-party dependency.
struct QRCodeView: View {
    let string: String
    /// Error-correction level: "L", "M", "Q", or "H". Defaults to "M" (the
    /// deposit-address usage); ticket QR uses "H" for extra scan resilience.
    var correctionLevel: String = "M"

    var body: some View {
        if let image = Self.generate(from: string, correctionLevel: correctionLevel) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Color.white
        }
    }

    private static func generate(from string: String, correctionLevel: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = correctionLevel
        guard let output = filter.outputImage else { return nil }
        // Scale up so the code is crisp when displayed large.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Formats an event date range in the event's timezone, matching the app's
/// `TimeService.formatEventDateRangeInTz`:
/// "Sat, Mar 28 at 7:00 PM - 2:00 AM (PST)".
func formatEventDateRange(start: Date?, end: Date?, timezone: String?) -> String {
    guard let start else { return L("date_tbd", "Date TBD") }
    let tz = timezone.flatMap { TimeZone(identifier: $0) } ?? .current

    let dayMonth = DateFormatter()
    dayMonth.timeZone = tz
    dayMonth.dateFormat = "EEE, MMM d"

    let time = DateFormatter()
    time.timeZone = tz
    time.dateFormat = "h:mm a"

    let abbrev = DateFormatter()
    abbrev.timeZone = tz
    abbrev.dateFormat = "zzz"
    let tzLabel = abbrev.string(from: start)

    let startStr = "\(dayMonth.string(from: start)) at \(time.string(from: start))"
    guard let end else { return "\(startStr) (\(tzLabel))" }
    return "\(startStr) - \(time.string(from: end)) (\(tzLabel))"
}

extension UIApplication {
    /// The top-most view controller of the active foreground scene, for
    /// presenting UIKit controllers (Stripe's sheet, `PKAddPassesViewController`,
    /// `EKEventEditViewController`) from SwiftUI.
    @MainActor
    static func topViewController() -> UIViewController? {
        let scene = shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

/// The group-card date, matching the app's `_buildGroupCard`: parsed to the
/// DEVICE-local timezone and formatted "Aug 15, 2026 • 8:00 PM".
func formatGroupCardDate(_ date: Date?) -> String {
    guard let date else { return "" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.dateFormat = "MMM d, yyyy • h:mm a"
    return formatter.string(from: date)
}

/// The detail-screen event date, matching the app's `formatDateTimeInTz`:
/// in the event's timezone, formatted "Aug 15, 2026 at 8:00 PM".
func formatEventDateTimeInTz(_ date: Date?, timezone: String?) -> String {
    guard let date else { return "" }
    let tz = timezone.flatMap { TimeZone(identifier: $0) } ?? .current
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = tz
    formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
    return formatter.string(from: date)
}

/// A ticket-shaped clip path: a rectangle with CONCAVE (inward-scooped) cutouts
/// at the four corners plus a semicircular notch on the left and right edges at
/// the vertical midpoint. A 1:1 port of the app's `TicketClipper` — the Flutter
/// arcs curve inward, so the corners are scooped, not rounded.
///
/// Traced as a single continuous outline whose corner/notch arcs sweep inward
/// (each centered ON the boundary point), so there's no dependency on the
/// even-odd rule and no outward bumps.
struct TicketClipper: Shape {
    var cornerRadius: CGFloat = 18
    var notchRadius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cr = cornerRadius
        let nr = notchRadius
        let cy = h / 2

        var path = Path()
        path.move(to: CGPoint(x: cr, y: 0))
        path.addLine(to: CGPoint(x: w - cr, y: 0))
        // Top-right corner scoop (centered on the corner point).
        path.addArc(center: CGPoint(x: w, y: 0), radius: cr,
                    startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        path.addLine(to: CGPoint(x: w, y: cy - nr))
        // Right-edge notch.
        path.addArc(center: CGPoint(x: w, y: cy), radius: nr,
                    startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        path.addLine(to: CGPoint(x: w, y: h - cr))
        // Bottom-right corner scoop.
        path.addArc(center: CGPoint(x: w, y: h), radius: cr,
                    startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true)
        path.addLine(to: CGPoint(x: cr, y: h))
        // Bottom-left corner scoop.
        path.addArc(center: CGPoint(x: 0, y: h), radius: cr,
                    startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)
        path.addLine(to: CGPoint(x: 0, y: cy + nr))
        // Left-edge notch.
        path.addArc(center: CGPoint(x: 0, y: cy), radius: nr,
                    startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
        path.addLine(to: CGPoint(x: 0, y: cr))
        // Top-left corner scoop.
        path.addArc(center: CGPoint(x: 0, y: 0), radius: cr,
                    startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// Formats a base-unit crypto amount (e.g. satoshis) into a human string using
/// the token's decimals: "15120000" @ 9 → "0.01512 SOL".
func formatCryptoAmount(baseUnits: String, decimals: Int, token: String) -> String {
    guard let value = Decimal(string: baseUnits) else { return "\(baseUnits) \(token)" }
    let divisor = pow(Decimal(10), decimals)
    let amount = value / divisor
    var rounded = Decimal()
    var mutable = amount
    NSDecimalRound(&rounded, &mutable, decimals, .plain)
    return "\(rounded) \(token)"
}
