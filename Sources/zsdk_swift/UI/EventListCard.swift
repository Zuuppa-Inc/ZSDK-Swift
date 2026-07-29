import SwiftUI

/// A single row in the "My Events" list. A 1:1 port of the app's `EventCard`
/// (list mode): an 85×85 cover on the left (8pt radius), then event name (16pt
/// bold), start date, and venue (both 13pt secondary). 16pt gap below each row.
struct EventListCard: View {
    let event: HostedEvent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            cover

            VStack(alignment: .leading, spacing: 0) {
                Text(event.name.isEmpty ? "Untitled Event" : event.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(ZTheme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !dateDisplay.isEmpty {
                    Text(dateDisplay)
                        .font(.system(size: 13))
                        .foregroundStyle(ZTheme.secondaryText)
                }

                if let venue = event.venueName, !venue.isEmpty {
                    Text(venue)
                        .font(.system(size: 13))
                        .foregroundStyle(ZTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var cover: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        if let urlString = event.coverImageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
            .frame(width: 85, height: 85)
            .clipShape(shape)
        } else {
            placeholder
                .frame(width: 85, height: 85)
                .clipShape(shape)
        }
    }

    /// Matches the app's fallback: a calendar glyph on the divider color.
    private var placeholder: some View {
        ZStack {
            ZTheme.divider
            MaterialIcon(.calendarToday, size: 30, color: ZTheme.secondaryText)
        }
    }

    /// "MMM d, yyyy at h:mm a" in the event's timezone, matching the app card.
    private var dateDisplay: String {
        formatEventDateTimeInTz(event.startAt, timezone: event.timezone)
    }
}
