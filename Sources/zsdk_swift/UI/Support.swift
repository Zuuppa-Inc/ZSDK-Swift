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

    var body: some View {
        if let image = Self.generate(from: string) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Color.white
        }
    }

    private static func generate(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
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
    guard let start else { return "Date TBD" }
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
