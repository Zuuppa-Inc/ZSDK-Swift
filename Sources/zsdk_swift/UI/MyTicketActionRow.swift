import SwiftUI

/// A full-width action row on the ticket detail screen (Add to Apple Wallet,
/// Add to Calendar, Open in Maps, View Receipt). A 1:1 port of the app's action
/// buttons: a 48pt secondary-background rounded box, label left, a 20pt Material
/// icon (tinted `text`) right, with a spinner in place of the icon while busy.
struct MyTicketActionRow: View {
    let label: String
    let icon: MIcon
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: { if !isBusy { action() } }) {
            HStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ZTheme.text)
                Spacer()
                if isBusy {
                    ProgressView()
                        .tint(ZTheme.text)
                        .scaleEffect(0.8)
                        .frame(width: 20, height: 20)
                } else {
                    MaterialIcon(icon, size: 20, color: ZTheme.text)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .background(ZTheme.secondaryBackground, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}
