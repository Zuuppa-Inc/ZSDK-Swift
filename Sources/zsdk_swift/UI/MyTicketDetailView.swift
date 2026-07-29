import SwiftUI
import UIKit
import EventKit
import EventKitUI

/// The ticket detail screen: a swipeable QR carousel (one card per ticket) plus
/// event info and the configured actions (Calendar / Maps / Receipt / Wallet).
/// Ported from the app's `event_tickets_screen.dart`, minus the group chat.
struct MyTicketDetailView: View {

    let group: MyTicketGroup
    let model: MyTicketsModel

    @Environment(\.dismiss) private var dismiss

    @State private var walletBusy = false
    @State private var receiptBusy = false
    @State private var walletPresenter = WalletPassPresenter()
    @State private var actionError: String?
    @State private var showReceiptPicker = false

    private let side = ZTheme.sideMargin
    private var options: ZuuppaMyTicketsConfig { model.options }

    private var isCanceled: Bool { group.isEventCanceled }

    var body: some View {
        // Header fixed on top; only the ticket content scrolls (matches the app).
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 0) {
                    if isCanceled {
                        cancelledBanner
                            .padding(.horizontal, side)
                            .padding(.bottom, 8)
                    }

                    eventInfo
                        .padding(.horizontal, side)
                        .padding(.vertical, 8)

                    Spacer().frame(height: 12)

                    carousel

                    if group.tickets.count > 1 {
                        Text("Swipe for more tickets")
                            .font(.system(size: 12))
                            .foregroundStyle(ZTheme.secondaryText)
                            .padding(.vertical, 8)
                    } else {
                        Spacer().frame(height: 8)
                    }

                    actions
                        .padding(.horizontal, side)

                    if let actionError {
                        Text(actionError)
                            .font(.system(size: 13))
                            .foregroundStyle(ZTheme.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, side)
                            .padding(.top, 8)
                    }

                    Spacer().frame(height: 24)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(ZTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Select Order", isPresented: $showReceiptPicker, titleVisibility: .visible) {
            ForEach(Array(group.paidOrderIDs.enumerated()), id: \.element) { index, orderID in
                Button(orderLabel(index: index, orderID: orderID)) {
                    Task { await openReceipt(orderID: orderID) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header

    /// Centered "Tickets" title with a back arrow, matching `ZuuppaScreenHeader`.
    private var header: some View {
        ZStack {
            Text("Tickets")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ZTheme.text)

            HStack {
                Button { dismiss() } label: {
                    MaterialIcon(.arrowBack, size: 24, color: ZTheme.text)
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel("Back")
                Spacer()
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 4)
    }

    /// "Order N – $X.XX", matching the app's order picker rows.
    private func orderLabel(index: Int, orderID: String) -> String {
        let cents = group.tickets.first { $0.orderID == orderID }?.orderTotalCents ?? 0
        return "Order \(index + 1) – \(cents.centsAsUSD)"
    }

    // MARK: - Cancelled banner

    private var cancelledBanner: some View {
        HStack(spacing: 8) {
            MaterialIcon(.cancelOutlined, size: 20, color: ZTheme.red)
            Text("This event has been cancelled")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ZTheme.red)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZTheme.red.opacity(0.15), in: .rect(cornerRadius: 8))
    }

    // MARK: - Event info

    private var eventInfo: some View {
        HStack(spacing: 12) {
            if group.coverURL?.isEmpty == false {
                cover
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(group.eventName ?? "Event")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ZTheme.text)
                    .lineLimit(2)
                if !dateDisplay.isEmpty {
                    Spacer().frame(height: 4)
                    Text(dateDisplay)
                        .font(.system(size: 13))
                        .foregroundStyle(ZTheme.secondaryText)
                }
                if let venue = group.venueName, !venue.isEmpty {
                    Spacer().frame(height: 2)
                    Text(venue)
                        .font(.system(size: 13))
                        .foregroundStyle(ZTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var cover: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        if let urlString = group.coverURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    ZTheme.secondaryBackground
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(shape)
        } else {
            shape.fill(ZTheme.secondaryBackground).frame(width: 56, height: 56)
        }
    }

    // MARK: - QR carousel

    /// A page carousel with peeking neighbors, matching the app's
    /// `PageView(viewportFraction: 0.88)` inside a `1 / 0.88` AspectRatio.
    private var carousel: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width * 0.88
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(group.tickets) { ticket in
                        ticketCard(ticket)
                            .frame(width: cardWidth)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, (geo.size.width - cardWidth) / 2, for: .scrollContent)
        }
        .aspectRatio(1 / 0.88, contentMode: .fit)
    }

    /// One ticket card: a WHITE card (matching the app's `ticketCardBackground`)
    /// with the dark Zuuppa logo, the QR (or cancelled state), and a footer row.
    private func ticketCard(_ ticket: MyTicket) -> some View {
        VStack(spacing: 0) {
            // Top row: logo left, event name + date right.
            HStack(alignment: .top, spacing: 12) {
                wordmark
                    .frame(height: 20)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(group.eventName ?? "Event")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ZTheme.ticketCardText)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                    if !dateDisplay.isEmpty {
                        Text(dateDisplay)
                            .font(.system(size: 11))
                            .foregroundStyle(ZTheme.ticketCardSubtext)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // QR centered, 70% of the card width (matches FractionallySizedBox 0.7).
            GeometryReader { geo in
                let side = geo.size.width * 0.7
                Group {
                    if ticket.isCanceled {
                        VStack(spacing: 8) {
                            MaterialIcon(.cancelOutlined, size: 48, color: ZTheme.red)
                            Text("Ticket Canceled")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(ZTheme.red)
                        }
                    } else if !ticket.ticketToken.isEmpty {
                        QRCodeView(string: ticket.ticketToken, correctionLevel: "H")
                            .frame(width: side, height: side)
                    } else {
                        MaterialIcon(.qrCode, size: 48, color: ZTheme.ticketCardText.opacity(0.26))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            // Bottom row: status pill left, ticket type right.
            HStack {
                statusPill(ticket.status)
                Spacer()
                Text(ticket.ticketTypeName ?? "Ticket")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ZTheme.ticketCardText)
                    .lineLimit(1)
            }
        }
        .padding(28)
        .background(ZTheme.ticketCardBackground, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func statusPill(_ status: String) -> some View {
        let (label, color): (String, Color) = switch status {
        case "active": ("Active", ZTheme.confirmedStatus)
        case "canceled": ("Canceled", ZTheme.red)
        default: ("Used", ZTheme.secondaryText)
        }
        return Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: .rect(cornerRadius: 6))
    }

    /// The dark Zuuppa wordmark for the white ticket card (template-tinted to
    /// `ticketCardText`, matching the app's `text-logo.svg` with an srcIn filter).
    @ViewBuilder
    private var wordmark: some View {
        if let url = Bundle.module.url(forResource: "zuuppa-wordmark", withExtension: "png"),
           let ui = UIImage(contentsOfFile: url.path)?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .foregroundStyle(ZTheme.ticketCardText)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 8) {
            if options.showAddToAppleWallet && !isCanceled && !group.activeTicketTokens.isEmpty {
                MyTicketActionRow(label: "Add to Apple Wallet", icon: .accountBalanceWallet, isBusy: walletBusy) {
                    Task { await addToWallet() }
                }
            }
            if options.showAddToCalendar && !isCanceled && group.startAt != nil {
                MyTicketActionRow(label: "Add to Calendar", icon: .calendarToday) {
                    addToCalendar()
                }
            }
            if options.showOpenInMaps && !isCanceled && hasLocation {
                MyTicketActionRow(label: "Open in Maps", icon: .mapOutlined) {
                    openInMaps()
                }
            }
            if options.showViewReceipt && !group.paidOrderIDs.isEmpty {
                MyTicketActionRow(label: "View Receipt", icon: .receiptLong, isBusy: receiptBusy) {
                    viewReceipt()
                }
            }
        }
    }

    private var hasLocation: Bool {
        !(group.addressText ?? "").isEmpty || !(group.venueName ?? "").isEmpty
    }

    // MARK: - Action handlers

    private func addToWallet() async {
        actionError = nil
        walletBusy = true
        defer { walletBusy = false }
        do {
            var passes: [Data] = []
            for token in group.activeTicketTokens {
                passes.append(try await model.applePass(ticketToken: token))
            }
            if !walletPresenter.present(passData: passes) {
                actionError = "Couldn't add these tickets to Apple Wallet."
            }
        } catch {
            actionError = (error as? ZuuppaError)?.errorDescription ?? "Couldn't load your Wallet passes."
        }
    }

    private func addToCalendar() {
        guard let start = group.startAt else { return }
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = group.eventName ?? "Event"
        event.startDate = start
        // Default to a 2-hour event when no end time, matching the app.
        event.endDate = group.endAt ?? start.addingTimeInterval(2 * 60 * 60)
        event.location = group.addressText ?? group.venueName
        if let tz = group.timezone.flatMap({ TimeZone(identifier: $0) }) {
            event.timeZone = tz
        }

        let editVC = EKEventEditViewController()
        editVC.eventStore = store
        editVC.event = event
        let delegate = CalendarEditDelegate()
        editVC.editViewDelegate = delegate
        Self.calendarDelegate = delegate   // retain until dismissed
        UIApplication.topViewController()?.present(editVC, animated: true)
    }

    private func openInMaps() {
        let query = group.addressText ?? group.venueName ?? ""
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "http://maps.apple.com/?q=\(encoded)") else {
            return
        }
        UIApplication.shared.open(url)
    }

    private func viewReceipt() {
        // One paid order → open directly; multiple → let the buyer pick.
        if group.paidOrderIDs.count == 1, let orderID = group.paidOrderIDs.first {
            Task { await openReceipt(orderID: orderID) }
        } else {
            showReceiptPicker = true
        }
    }

    private func openReceipt(orderID: String) async {
        actionError = nil
        receiptBusy = true
        defer { receiptBusy = false }
        do {
            if let url = try await model.receiptURL(orderID: orderID) {
                await UIApplication.shared.open(url)
            } else {
                actionError = "No receipt is available for this order."
            }
        } catch {
            actionError = (error as? ZuuppaError)?.errorDescription ?? "Couldn't load the receipt."
        }
    }

    // MARK: - Helpers

    /// "MMM d, yyyy at h:mm a" in the event's timezone, matching the app's
    /// `formatDateTimeInTz` used on this screen.
    private var dateDisplay: String {
        formatEventDateTimeInTz(group.startAt, timezone: group.timezone)
    }

    /// Retains the calendar edit delegate for the lifetime of the presented
    /// edit controller (it's otherwise not held anywhere).
    private static var calendarDelegate: CalendarEditDelegate?
}

/// Dismisses the `EKEventEditViewController` whether the buyer saves or cancels.
@MainActor
private final class CalendarEditDelegate: NSObject, EKEventEditViewDelegate {
    nonisolated func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        MainActor.assumeIsolated {
            controller.dismiss(animated: true)
        }
    }
}

#if DEBUG
#Preview("Detail — multi ticket") {
    let group = groupTickets(MyTicket.previewSamples).first { $0.tickets.count > 1 }!
    return NavigationStack {
        MyTicketDetailView(group: group, model: .preview())
    }
    .preferredColorScheme(.dark)
}

#Preview("Detail — cancelled") {
    let group = groupTickets(MyTicket.previewSamples).first { $0.isEventCanceled || $0.tickets.contains { $0.isCanceled } }!
    return NavigationStack {
        MyTicketDetailView(group: group, model: .preview())
    }
    .preferredColorScheme(.dark)
}
#endif
