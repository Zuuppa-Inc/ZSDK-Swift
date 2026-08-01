import SwiftUI

/// The attendee-side pending-requests list — a 1:1 port of the app's
/// `PendingCompletionsScreen`. Lists the user's join requests that are either
/// awaiting host approval or approved-but-unpurchased (paid events), each row
/// opening the event's flow. Reached from the "N pending approvals" banner on
/// the My Tickets list.
struct PendingRequestsView: View {

    let model: MyTicketsModel
    /// Invoked by the header's back arrow to pop back to the tickets list.
    let onBack: () -> Void

    private let side = ZTheme.sideMargin

    /// The event the user tapped, presented as the full purchase/RSVP flow.
    @State private var openEvent: OpenEvent?

    /// Identifies the event to open (id + accent) for the presented flow.
    private struct OpenEvent: Identifiable {
        let id: String
        let accentColor: String?
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(ZTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $openEvent, onDismiss: {
            // Returning may have resolved a request (bought / approved) — refresh.
            Task { await model.loadPendingRequests() }
        }) { event in
            ZuuppaTicketsScreen(eventId: event.id, config: model.config, onFinish: {
                openEvent = nil
            })
        }
    }

    // MARK: - Header

    /// Centered "Pending" title (18pt bold) with a back arrow, matching the
    /// app's `ZuuppaScreenHeader` on this screen.
    private var header: some View {
        ZStack {
            Text(L("pending_title", "Pending"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(ZTheme.text)

            HStack {
                Button(action: onBack) {
                    MaterialIcon(.arrowBack, size: 24, color: ZTheme.text)
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel(L("back", "Back"))
                Spacer()
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 4)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let items = model.pendingRequests
        if items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.loadPendingRequests() }
        }
    }

    /// Port of the app's empty state: a 48pt check-circle over "Nothing pending".
    private var emptyState: some View {
        VStack(spacing: 0) {
            MaterialIcon(.checkCircleRounded, size: 48, color: ZTheme.secondaryText)
            Spacer().frame(height: 16)
            Text(L("nothing_pending", "Nothing pending"))
                .font(.system(size: 16))
                .foregroundStyle(ZTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Row

    private func row(_ item: PendingJoinRequest) -> some View {
        Button {
            openEvent = OpenEvent(id: item.eventID, accentColor: item.accentColor)
        } label: {
            HStack(spacing: 12) {
                cover(item)

                VStack(alignment: .leading, spacing: 0) {
                    Text(item.eventName ?? L("event_fallback", "Event"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ZTheme.text)
                        .lineLimit(1)

                    if item.startAt != nil {
                        Spacer().frame(height: 2)
                        Text(formatEventDateRange(start: item.startAt, end: item.endAt, timezone: item.timezone))
                            .font(.system(size: 13))
                            .foregroundStyle(ZTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer().frame(height: 4)
                    statusPill(item)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MaterialIcon(.chevronRight, size: 20, color: ZTheme.secondaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ZTheme.secondaryBackground, in: .rect(cornerRadius: 12))
            .padding(.horizontal, side)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cover(_ item: PendingJoinRequest) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        if let urlString = item.coverImageURL, let url = URL(string: urlString) {
            AnimatedImageView(url: url, contentMode: .fill) {
                coverPlaceholder
            }
            .frame(width: 56, height: 56)
            .clipShape(shape)
        } else {
            coverPlaceholder
                .frame(width: 56, height: 56)
                .clipShape(shape)
        }
    }

    private var coverPlaceholder: some View {
        ZStack {
            ZTheme.divider
            Image(systemName: "calendar")
                .font(.system(size: 22))
                .foregroundStyle(ZTheme.secondaryText)
        }
    }

    /// "Awaiting Approval" (orange) for pending; "Approved — Buy Ticket"
    /// (primary) otherwise. Matches the app's pill exactly.
    private func statusPill(_ item: PendingJoinRequest) -> some View {
        let (label, color): (String, Color) = item.isPending
            ? (L("awaiting_approval", "Awaiting Approval"), ZTheme.orange)
            : (L("approved_buy_ticket", "Approved — Buy Ticket"), ZTheme.primary)
        return Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: .rect(cornerRadius: 4))
    }
}

#if DEBUG
#Preview("Pending — list") {
    NavigationStack {
        PendingRequestsView(model: .preview(pending: true), onBack: {})
    }
    .preferredColorScheme(.dark)
}

#Preview("Pending — empty") {
    NavigationStack {
        PendingRequestsView(model: .preview(), onBack: {})
    }
    .preferredColorScheme(.dark)
}
#endif
