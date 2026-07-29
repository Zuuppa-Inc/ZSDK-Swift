import SwiftUI
import UIKit

/// A ticket-styled card for one event in the My Tickets list. A 1:1 port of the
/// app's `_buildGroupCard`: a 180pt notch-clipped card with a blurred cover
/// background, a 45%-black scrim, the Zuuppa "TO" wordmark top-left, the event
/// name top-right, venue + date bottom-left, and the ticket count bottom-right.
struct MyTicketGroupCard: View {

    let group: MyTicketGroup

    var body: some View {
        // A fixed-size base establishes the 180pt card bounds FIRST, so the cover
        // image (which fills and overflows) and the text overlays all anchor to
        // the real card size — the overflow is clipped by the ticket shape last.
        ZTheme.secondaryBackground
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .overlay { cover }
            .overlay { ZTheme.fixedBlack.opacity(0.45) }
            .overlay(alignment: .top) { topRow }
            .overlay(alignment: .bottom) { bottomRow }
            .clipShape(TicketClipper(notchRadius: 16))
            // Matches the app's list item padding (side margin horizontal, 6 vertical).
            .padding(.horizontal, ZTheme.sideMargin)
            .padding(.vertical, 6)
    }

    // MARK: - Layers

    /// The blurred cover image; when absent, the secondary-background base shows.
    @ViewBuilder
    private var cover: some View {
        if let urlString = group.coverURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill().blur(radius: 10)
                } else {
                    Color.clear
                }
            }
            .clipped()
        }
    }

    /// Top row: "TO" wordmark left, event name right (top: 22, insets: 28).
    private var topRow: some View {
        HStack(alignment: .top, spacing: 12) {
            wordmark
                .frame(height: 26)
            Spacer(minLength: 12)
            Text(group.eventName ?? "Event")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ZTheme.fixedWhite)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
    }

    /// Bottom row: venue + date left, ticket count right (bottom: 22, insets: 28).
    private var bottomRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let venue = group.venueName, !venue.isEmpty {
                    Text(venue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ZTheme.fixedWhite)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if !dateDisplay.isEmpty {
                    Text(dateDisplay)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ZTheme.fixedWhite.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 12)
            Text(ticketCountText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ZTheme.fixedWhite)
                .fixedSize()
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
    }

    // MARK: - Pieces

    /// The Zuuppa wordmark, tinted white to match the app's white `to.svg`.
    @ViewBuilder
    private var wordmark: some View {
        if let url = Bundle.module.url(forResource: "zuuppa-wordmark", withExtension: "png"),
           let ui = UIImage(contentsOfFile: url.path)?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .foregroundStyle(ZTheme.fixedWhite)
        }
    }

    private var ticketCountText: String {
        let count = group.tickets.count
        return count == 1 ? "1 ticket" : "\(count) tickets"
    }

    /// Device-local "MMM d, yyyy • h:mm a", matching the app's group card.
    private var dateDisplay: String {
        formatGroupCardDate(group.startAt)
    }
}
