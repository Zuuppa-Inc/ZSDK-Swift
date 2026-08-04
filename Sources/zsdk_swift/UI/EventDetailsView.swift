import SwiftUI
import MapKit

/// Event detail screen, ported to match the Flutter app's `EventDetailScreen`:
/// a scrollable layout with a shadowed cover card, large title, hosted-by /
/// location / date lines, DETAILS + TICKETS + LOCATION sections, and a pinned
/// bottom CTA.
struct EventDetailsView: View {

    let model: TicketFlowModel
    /// Invoked by the header's back arrow. On the flow's entry screen this
    /// closes the whole SDK sheet (matching the app's back-to-previous-screen).
    var onBack: () -> Void = {}

    private var event: Event? { model.event }
    private let side = ZTheme.sideMargin

    var body: some View {
        if let event {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        cover(event)

                        VStack(alignment: .leading, spacing: 0) {
                            Spacer().frame(height: 20)
                            title(event)
                            Spacer().frame(height: 6)
                            subtitleBlock(event)

                            if let description = event.description, !description.isEmpty {
                                Spacer().frame(height: 24)
                                section(L("details", "DETAILS"))
                                Spacer().frame(height: 8)
                                Text(description)
                                    .font(.system(size: 15))
                                    .foregroundStyle(ZTheme.text)
                                    .lineSpacing(15 * 0.5)
                            }

                            Spacer().frame(height: 24)
                            ticketsSection(event)

                            if let location = locationSectionText(event) {
                                Spacer().frame(height: 24)
                                section(L("location", "LOCATION"))
                                Spacer().frame(height: 8)
                                Text(location)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(ZTheme.text.opacity(0.7))
                                if event.hasCoordinates {
                                    Spacer().frame(height: 12)
                                    mapView(event)
                                }
                            }

                            Spacer().frame(height: 24)
                        }
                        .padding(.horizontal, side)
                    }
                }
                .scrollIndicators(.hidden)
                .background(ZTheme.background)
                .safeAreaInset(edge: .bottom) { ctaBar(event) }

                header(event)
            }
        } else {
            ProgressView().tint(ZTheme.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ZTheme.background)
        }
    }

    // MARK: - Transparent header

    /// A transparent overlay row: back arrow (left) + share button (right),
    /// matching the app's `ZuuppaScreenHeader`.
    private func header(_ event: Event) -> some View {
        HStack {
            Button(action: onBack) {
                MaterialIcon(.arrowBack, size: 24, color: ZTheme.text)
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("back", "Back"))
            Spacer()
            ShareLink(item: shareURL) {
                ShareIcon(size: 20, color: ZTheme.text)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel(L("share", "Share"))
        }
        .padding(.horizontal, 4)
        .frame(height: 56)   // kToolbarHeight
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var shareURL: URL {
        URL(string: "https://www.zuuppa.com/e/\(model.eventID)")!
    }

    // MARK: - Cover

    @ViewBuilder
    private func cover(_ event: Event) -> some View {
        let radius: CGFloat = 14
        // The app renders the cover at full width with the image's OWN aspect
        // ratio (fit: cover, no fixed height); 16:9 is only the placeholder.
        Group {
            if let urlString = event.coverImageURL, let url = URL(string: urlString) {
                // Full width, natural aspect ratio (no crop).
                AnimatedImageView(url: url, contentMode: .fit) {
                    placeholderCover.aspectRatio(16.0 / 9.0, contentMode: .fit)
                }
                .frame(maxWidth: .infinity)
            } else {
                placeholderCover.aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)
        .padding(.horizontal, side)
        .padding(.top, 56)   // clear the transparent header row
    }

    private var placeholderCover: some View {
        ZStack {
            ZTheme.divider
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundStyle(ZTheme.secondaryText)
        }
    }

    // MARK: - Header text

    private func title(_ event: Event) -> some View {
        Text(event.name)
            .font(.system(size: 32, weight: .heavy))
            .foregroundStyle(ZTheme.text)
            .lineSpacing(32 * 0.15)
    }

    @ViewBuilder
    private func subtitleBlock(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let location = locationText(event) {
                Text(location)
                    .font(.system(size: 15))
                    .foregroundStyle(ZTheme.text)
                Spacer().frame(height: 2)
            }
            Text(formatEventDateRange(start: event.startAt, end: event.endAt, timezone: event.timezone))
                .font(.system(size: 15))
                .foregroundStyle(ZTheme.text.opacity(0.7))

            if !event.hosts.isEmpty {
                Spacer().frame(height: 10)
                Text(L("hosted_by", "HOSTED BY"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(ZTheme.text.opacity(0.7))
                Spacer().frame(height: 8)
                ForEach(event.hosts, id: \.self) { host in
                    hostRow(host)
                }
            }
        }
    }

    private func hostRow(_ host: Profile) -> some View {
        HStack(spacing: 10) {
            avatar(host)
            Text(host.displayName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ZTheme.text)
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func avatar(_ host: Profile) -> some View {
        let size: CGFloat = 38
        Group {
            if let urlString = host.profilePhotoURL, let url = URL(string: urlString) {
                AnimatedImageView(url: url, contentMode: .fill) {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        ZStack {
            ZTheme.secondaryBackground
            Image(systemName: "person.fill")
                .font(.system(size: 20))
                .foregroundStyle(ZTheme.secondaryText)
        }
    }

    // MARK: - Sections

    private func section(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(ZTheme.text)
    }

    @ViewBuilder
    private func ticketsSection(_ event: Event) -> some View {
        section(L("tickets_section", "TICKETS"))
        Spacer().frame(height: 8)

        if !event.isPaid {
            infoCard {
                HStack(spacing: 12) {
                    MaterialIcon(.confirmationNumOutlined, size: 20, color: ZTheme.text)
                    Text(L("free_rsvp", "FREE RSVP"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ZTheme.text)
                    Spacer()
                }
            }
        } else {
            VStack(spacing: 8) {
                ForEach(event.sellableTicketTypes) { tt in
                    ticketRow(tt)
                }
            }
        }
    }

    private func ticketRow(_ tt: TicketType) -> some View {
        HStack(spacing: 12) {
            MaterialIcon(.confirmationNumOutlined, size: 18, color: ZTheme.text)
            VStack(alignment: .leading, spacing: 0) {
                Text(tt.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ZTheme.text)
            }
            Spacer()
            Text(tt.isFree ? "Free" : tt.priceCents.centsAsUSD)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ZTheme.text)
            if let total = tt.quantityTotal {
                Text("\(tt.quantitySold ?? 0)/\(total)")
                    .font(.system(size: 13))
                    .foregroundStyle(ZTheme.text.opacity(0.7))
            }
        }
        .padding(14)
        .background(ZTheme.cardOverlay, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func mapView(_ event: Event) -> some View {
        if let lat = event.latitude, let lon = event.longitude {
            // Same CartoDB dark tiles + non-interactive style as the app.
            CartoMapView(latitude: lat, longitude: lon, markerColor: ZTheme.text)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .onTapGesture {
                    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                    item.name = event.venueName ?? event.name
                    item.openInMaps()
                }
        }
    }

    private func infoCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ZTheme.cardOverlay, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - CTA

    private func ctaBar(_ event: Event) -> some View {
        // Mirror the app's `_buildRsvpBar` exactly. The button is ALWAYS solid
        // (accent-filled) — the "disabled" states (Requested / Declined /
        // RSVP'd) just get a no-op action, they aren't greyed out.
        let cta = ctaState(event)

        return VStack(spacing: 0) {
            ZButton(
                label: cta.label,
                backgroundColor: ZTheme.primary,
                foregroundColor: ZTheme.onPrimary
            ) {
                switch cta.action {
                case .none: break
                case .requestToJoin: Task { await model.requestToJoin() }
                case .selectTickets: Task { await model.showTicketSelection() }
                }
            }
            .padding(.horizontal, side)
            .padding(.top, 12)
        }
        .background(.clear)
    }

    /// What the CTA does when tapped.
    private enum CTAAction { case none, requestToJoin, selectTickets }

    /// The CTA's label + action, resolved with the SAME precedence as the app's
    /// `_buildRsvpBar`: join-request states first, then approval gating, then
    /// paid vs. an already-completed free RSVP, then a fresh RSVP.
    private func ctaState(_ event: Event) -> (label: String, action: CTAAction) {
        let requestStatus = model.joinRequestStatus
        if requestStatus == "pending" {
            return (L("requested", "Requested"), .none)
        }
        if requestStatus == "declined" {
            return (L("request_declined", "Request Declined"), .none)
        }
        if event.requiresApproval && requestStatus != "approved" {
            return (L("request_to_join", "Request to Join"), .requestToJoin)
        }
        if event.isPaid {
            return (ctaLabel(event), .selectTickets)
        }
        if model.rsvpStatus == "completed" {
            return (L("rsvped", "RSVP'd"), .none)
        }
        return (ctaLabel(event), .selectTickets)
    }

    // MARK: - Helpers

    private func locationText(_ event: Event) -> String? {
        let value = event.venueName ?? event.addressText
        return (value?.isEmpty == false) ? value : nil
    }

    /// The LOCATION section prefers the full address (matching the app, which
    /// uses `addressText` when present and only falls back to the venue name).
    private func locationSectionText(_ event: Event) -> String? {
        if let address = event.addressText, !address.isEmpty { return address }
        if let venue = event.venueName, !venue.isEmpty { return venue }
        return nil
    }

    /// Matches the app's `EventDetailScreen` RSVP-bar label logic.
    private func ctaLabel(_ event: Event) -> String {
        guard event.isPaid else { return L("rsvp", "RSVP") }
        if event.isCryptoEnabled {
            return Lf("buy_ticket_with", "Buy Ticket with %@", event.paymentTokenOrDefault)
        }
        return L("buy_tickets", "Buy Tickets")
    }
}
