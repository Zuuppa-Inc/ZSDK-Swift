import Foundation

/// The buyer's tickets for a single event, grouped together for the list. Mirrors
/// the Flutter app's `_EventTicketGroup`: one card per event, holding all of that
/// event's tickets.
struct MyTicketGroup: Identifiable, Hashable {
    var id: String { eventID }

    let eventID: String
    let eventName: String?
    let venueName: String?
    let coverURL: String?
    let eventStatus: String?
    let startAt: Date?
    let endAt: Date?
    let addressText: String?
    let timezone: String?
    let accentColor: String?
    let hostDisplayName: String?
    let tickets: [MyTicket]

    /// Whether the whole event was cancelled.
    var isEventCanceled: Bool { eventStatus == "canceled" }

    /// Distinct order ids for paid orders (a receipt exists), in first-seen order.
    var paidOrderIDs: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for ticket in tickets {
            guard let orderID = ticket.orderID,
                  (ticket.orderTotalCents ?? 0) > 0,
                  !seen.contains(orderID) else { continue }
            seen.insert(orderID)
            result.append(orderID)
        }
        return result
    }

    /// Tokens of the still-active tickets — the ones worth adding to Wallet.
    var activeTicketTokens: [String] {
        tickets.filter { $0.status == "active" }.map(\.ticketToken)
    }
}

/// Groups a flat list of tickets by event, preserving first-seen order (the
/// server already returns them sorted by event time). Mirrors the Flutter
/// `_groupTickets`, which accumulates into an insertion-ordered map.
func groupTickets(_ tickets: [MyTicket]) -> [MyTicketGroup] {
    var order: [String] = []
    var buckets: [String: [MyTicket]] = [:]

    for ticket in tickets {
        if buckets[ticket.eventID] == nil {
            order.append(ticket.eventID)
            buckets[ticket.eventID] = []
        }
        buckets[ticket.eventID]?.append(ticket)
    }

    return order.compactMap { eventID -> MyTicketGroup? in
        guard let group = buckets[eventID], let first = group.first else { return nil }
        return MyTicketGroup(
            eventID: eventID,
            eventName: first.eventName,
            venueName: first.eventVenueName,
            coverURL: first.eventCoverImageURL,
            eventStatus: first.eventStatus,
            startAt: first.eventStartAt,
            endAt: first.eventEndAt,
            addressText: first.eventAddressText,
            timezone: first.eventTimezone,
            accentColor: first.eventAccentColor,
            hostDisplayName: first.hostDisplayName,
            tickets: group
        )
    }
}
