import SwiftUI

/// Drives the "My Tickets" screen: resolves the signed-in buyer, loads their
/// tickets per filter tab (with independent pagination), and exposes the small
/// set of network calls the detail screen needs (Apple Wallet pass, receipt).
///
/// Mirrors ``TicketFlowModel``'s shape — an `@Observable` `@MainActor` class that
/// owns its own ``SupabaseAuth`` + `ZuuppaAPI`.
@MainActor
@Observable
final class MyTicketsModel {

    /// Whether we've resolved a signed-in buyer yet.
    enum AuthState {
        case checking
        case signedOut
        case ready
    }

    /// Per-tab list + pagination state. Each tab loads and pages independently,
    /// matching the app's separate upcoming/past/canceled lists.
    struct TabState {
        var tickets: [MyTicket] = []
        var cursor: String?
        var isLoading = true
        var isLoadingMore = false
        var didLoadOnce = false
        var loadError: String?
    }

    let config: ZuuppaConfig
    let options: ZuuppaMyTicketsConfig

    private let auth: SupabaseAuth
    private let api: ZuuppaAPI

    private(set) var authState: AuthState = .checking
    private(set) var states: [ZuuppaMyTicketsConfig.Tab: TabState] = [:]

    /// The user's pending / approved-unpurchased join requests, backing the
    /// "N pending approvals" banner and the pending-requests screen. Mirrors the
    /// app's `_pendingCount` + `PendingCompletionsScreen`.
    private(set) var pendingRequests: [PendingJoinRequest] = []

    /// The tab currently on screen. Starts on the first configured tab.
    var selectedTab: ZuuppaMyTicketsConfig.Tab

    init(config: ZuuppaConfig = .default, options: ZuuppaMyTicketsConfig = .default) {
        self.config = config
        self.options = options
        self.selectedTab = options.tabs.first ?? .upcoming
        let auth = SupabaseAuth(config: config)
        self.auth = auth
        self.api = ZuuppaAPI(config: config, auth: auth)
    }

    // MARK: - Lifecycle

    /// Called when the screen appears: resolves auth, and if the buyer is signed
    /// in, kicks off a load for every configured tab.
    func start() async {
        let identity = await auth.currentIdentity()
        authState = (identity != nil) ? .ready : .signedOut
        if authState == .ready {
            await loadAllTabs()
            await loadPendingRequests()
        }
    }

    /// Called by the auth gate once the buyer verifies their OTP.
    func onAuthenticated() async {
        authState = .ready
        await loadAllTabs()
        await loadPendingRequests()
    }

    /// Loads every configured tab concurrently (like the app firing all its
    /// loaders in `initState`).
    private func loadAllTabs() async {
        await withTaskGroup(of: Void.self) { group in
            for tab in options.tabs {
                group.addTask { await self.load(tab) }
            }
        }
    }

    // MARK: - Loading

    /// Loads (or reloads) the first page of a tab.
    func load(_ tab: ZuuppaMyTicketsConfig.Tab) async {
        var state = states[tab] ?? TabState()
        if !state.didLoadOnce { state.isLoading = true }
        state.loadError = nil
        states[tab] = state

        do {
            let response = try await api.fetchMyTickets(
                filter: tab.serverFilter, cursor: nil, hostID: options.hostID
            )
            var updated = states[tab] ?? TabState()
            updated.tickets = response.tickets
            updated.cursor = response.nextCursor
            updated.isLoading = false
            updated.didLoadOnce = true
            updated.loadError = nil
            states[tab] = updated
        } catch {
            var updated = states[tab] ?? TabState()
            updated.isLoading = false
            updated.didLoadOnce = true
            updated.loadError = message(for: error)
            states[tab] = updated
        }
    }

    /// Pull-to-refresh: reload the tab from the first page.
    func refresh(_ tab: ZuuppaMyTicketsConfig.Tab) async {
        var state = states[tab] ?? TabState()
        state.didLoadOnce = false   // let `load` show a fresh state if empty
        states[tab] = state
        await load(tab)
        // The app's `_refreshAttending` also refreshes the pending banner count.
        await loadPendingRequests()
    }

    /// Loads the next page of a tab, appending to the existing list. No-op when
    /// there's no cursor or a load is already in flight.
    func loadMore(_ tab: ZuuppaMyTicketsConfig.Tab) async {
        guard var state = states[tab], let cursor = state.cursor, !state.isLoadingMore else {
            return
        }
        state.isLoadingMore = true
        states[tab] = state

        do {
            let response = try await api.fetchMyTickets(
                filter: tab.serverFilter, cursor: cursor, hostID: options.hostID
            )
            var updated = states[tab] ?? TabState()
            updated.tickets.append(contentsOf: response.tickets)
            updated.cursor = response.nextCursor
            updated.isLoadingMore = false
            states[tab] = updated
        } catch {
            // Transient: keep what we have and let the user try scrolling again.
            var updated = states[tab] ?? TabState()
            updated.isLoadingMore = false
            states[tab] = updated
        }
    }

    /// (Re)loads the pending-requests banner count + list. Called on start, and
    /// on pull-to-refresh / after returning from the pending screen (mirroring
    /// the app's `_loadPendingCount`). A failure just leaves the prior list.
    func loadPendingRequests() async {
        if let items = try? await api.fetchMyPendingRequests() {
            pendingRequests = items
        }
    }

    // MARK: - Derived state

    /// The tickets for a tab, grouped by event for the list.
    func groups(for tab: ZuuppaMyTicketsConfig.Tab) -> [MyTicketGroup] {
        groupTickets(states[tab]?.tickets ?? [])
    }

    func state(for tab: ZuuppaMyTicketsConfig.Tab) -> TabState {
        states[tab] ?? TabState()
    }

    // MARK: - Detail-screen passthroughs

    func applePass(ticketToken: String) async throws -> Data {
        try await api.fetchApplePass(ticketToken: ticketToken)
    }

    func receiptURL(orderID: String) async throws -> URL? {
        try await api.fetchReceipt(orderID: orderID).url
    }

    // MARK: - Auth passthroughs (for the sign-in gate)

    func currentIdentity() async -> AuthIdentity? {
        await auth.currentIdentity()
    }

    func signOut() async {
        await auth.signOut()
    }

    func requestOTP(_ channel: OTPChannel) async throws {
        try await auth.requestOTP(channel)
    }

    func verifyOTP(_ channel: OTPChannel, token: String) async throws {
        try await auth.verifyOTP(channel, token: token)
    }

    private func message(for error: Error) -> String {
        (error as? ZuuppaError)?.errorDescription ?? error.localizedDescription
    }
}

#if DEBUG
extension MyTicketsModel {
    /// A model pre-seeded with sample tickets for previews. Does no networking.
    /// `signedOut` renders the auth gate; otherwise the list is ready.
    static func preview(
        signedOut: Bool = false,
        empty: Bool = false,
        pending: Bool = false,
        options: ZuuppaMyTicketsConfig = .default
    ) -> MyTicketsModel {
        let model = MyTicketsModel(config: .default, options: options)
        if signedOut {
            model.authState = .signedOut
            return model
        }
        model.authState = .ready
        let tickets = empty ? [] : MyTicket.previewSamples
        for tab in options.tabs {
            var state = TabState()
            state.tickets = tab == .upcoming ? tickets : []
            state.isLoading = false
            state.didLoadOnce = true
            model.states[tab] = state
        }
        if pending { model.pendingRequests = PendingJoinRequest.previewSamples }
        return model
    }
}

extension PendingJoinRequest {
    /// Sample pending requests for previews: one awaiting approval, one approved
    /// paid event to buy tickets for.
    static let previewSamples: [PendingJoinRequest] = {
        let json = """
        [
            {
                "event_id": "evt-3",
                "event_name": "Underground Warehouse Rave",
                "request_status": "pending",
                "cover_image_url": null,
                "venue_name": "Secret Location",
                "address_text": "Brooklyn, NY",
                "start_at": "2026-08-22T22:00:00Z",
                "end_at": "2026-08-23T04:00:00Z",
                "timezone": "America/New_York",
                "is_paid": false,
                "accent_color": "#9B59B6"
            },
            {
                "event_id": "evt-4",
                "event_name": "Members-Only Wine Tasting",
                "request_status": "approved",
                "cover_image_url": null,
                "venue_name": "The Cellar",
                "address_text": "88 Vine St, Napa, CA",
                "start_at": "2026-09-05T18:00:00Z",
                "end_at": null,
                "timezone": "America/Los_Angeles",
                "is_paid": true,
                "accent_color": "#C0392B"
            }
        ]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PendingJoinRequest].self, from: Data(json.utf8))) ?? []
    }()
}

extension MyTicket {
    /// Decoded sample tickets: two events (grouping), an active + a cancelled
    /// ticket, and a paid order (receipt button).
    static let previewSamples: [MyTicket] = {
        let json = """
        [
            {
                "event_id": "evt-1",
                "host_id": "host-1",
                "event_name": "Sunset Rooftop Party",
                "event_venue_name": "The Highline Rooftop",
                "event_cover_image_url": null,
                "event_status": "live",
                "event_start_at": "2026-08-15T20:00:00Z",
                "event_end_at": "2026-08-16T01:00:00Z",
                "event_address_text": "455 W 37th St, New York, NY",
                "event_timezone": "America/New_York",
                "event_accent_color": "#E04A4A",
                "host_display_name": "Alex Rivera",
                "ticket_token": "tok-ga-1",
                "ticket_type_name": "General Admission",
                "status": "active",
                "order_id": "ord-1",
                "order_total_cents": 4500
            },
            {
                "event_id": "evt-1",
                "host_id": "host-1",
                "event_name": "Sunset Rooftop Party",
                "event_venue_name": "The Highline Rooftop",
                "event_cover_image_url": null,
                "event_status": "live",
                "event_start_at": "2026-08-15T20:00:00Z",
                "event_end_at": "2026-08-16T01:00:00Z",
                "event_address_text": "455 W 37th St, New York, NY",
                "event_timezone": "America/New_York",
                "event_accent_color": "#E04A4A",
                "host_display_name": "Alex Rivera",
                "ticket_token": "tok-ga-2",
                "ticket_type_name": "General Admission",
                "status": "active",
                "order_id": "ord-1",
                "order_total_cents": 4500
            },
            {
                "event_id": "evt-2",
                "host_id": "host-2",
                "event_name": "Jazz Night at the Blue Note",
                "event_venue_name": "Blue Note",
                "event_cover_image_url": null,
                "event_status": "live",
                "event_start_at": "2026-09-14T19:30:00Z",
                "event_end_at": null,
                "event_address_text": "131 W 3rd St, New York, NY",
                "event_timezone": "America/New_York",
                "event_accent_color": "#4A6FE0",
                "host_display_name": "Blue Note",
                "ticket_token": "tok-jazz-1",
                "ticket_type_name": "RSVP",
                "status": "canceled",
                "order_id": null,
                "order_total_cents": 0
            }
        ]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([MyTicket].self, from: Data(json.utf8))) ?? []
    }()
}
#endif
