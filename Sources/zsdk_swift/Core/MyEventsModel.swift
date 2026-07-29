import SwiftUI

/// Drives the "My Events" list: loads the public events hosted (or confirmed-
/// cohosted) by a given user id, with cursor pagination and host-driven search.
///
/// The host app owns the search text field; it just writes the trimmed query to
/// ``search`` (via ``setSearch(_:)``), and the model debounces + refetches.
@MainActor
@Observable
final class MyEventsModel {

    let config: ZuuppaConfig
    let userID: String

    private let auth: SupabaseAuth
    private let api: ZuuppaAPI

    private(set) var events: [HostedEvent] = []
    private(set) var isLoading = true
    private(set) var isLoadingMore = false
    private(set) var loadError: String?

    /// The current search query (trimmed). Set via ``setSearch(_:)``.
    private(set) var search = ""
    private var cursor: String?
    /// Bumped on each search change so a stale in-flight debounce is ignored.
    private var searchToken = 0

    init(userID: String, config: ZuuppaConfig = .default) {
        self.userID = userID
        self.config = config
        let auth = SupabaseAuth(config: config)
        self.auth = auth
        self.api = ZuuppaAPI(config: config, auth: auth)
    }

    // MARK: - Lifecycle

    /// Loads the first page. Safe to call again (e.g. on appear) — it reloads.
    func start() async {
        await load()
    }

    /// Host-driven search entry point: debounces (250ms, matching the app), then
    /// reloads from the first page. Ignores the result if the query changed again
    /// while waiting.
    func setSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed != search else { return }
        search = trimmed
        searchToken &+= 1
        let token = searchToken
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard token == searchToken else { return }
            await load()
        }
    }

    /// Loads (or reloads) the first page for the current search query.
    func load() async {
        isLoading = events.isEmpty
        loadError = nil
        let token = searchToken
        do {
            let response = try await api.fetchHostedEvents(
                userID: userID, search: search, cursor: nil
            )
            // Drop the result if the search moved on while this was in flight.
            guard token == searchToken else { return }
            events = response.events
            cursor = response.nextCursor
            isLoading = false
        } catch {
            guard token == searchToken else { return }
            events = []
            cursor = nil
            isLoading = false
            loadError = (error as? ZuuppaError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Loads the next page, appending. No-op without a cursor or while loading.
    func loadMore() async {
        guard let cursor, !isLoadingMore else { return }
        isLoadingMore = true
        let token = searchToken
        do {
            let response = try await api.fetchHostedEvents(
                userID: userID, search: search, cursor: cursor
            )
            guard token == searchToken else { isLoadingMore = false; return }
            events.append(contentsOf: response.events)
            self.cursor = response.nextCursor
            isLoadingMore = false
        } catch {
            isLoadingMore = false
        }
    }

    var canLoadMore: Bool { cursor != nil }
}

#if DEBUG
extension MyEventsModel {
    /// A model pre-seeded with sample events for previews. Does no networking.
    static func preview(empty: Bool = false) -> MyEventsModel {
        let model = MyEventsModel(userID: "preview-user", config: .default)
        model.isLoading = false
        model.events = empty ? [] : HostedEvent.previewSamples
        return model
    }
}

extension HostedEvent {
    static let previewSamples: [HostedEvent] = {
        let json = """
        [
            {"id": "evt-1", "name": "Sunset Rooftop Party", "cover_image_url": null,
             "start_at": "2026-08-15T20:00:00Z", "venue_name": "The Highline Rooftop",
             "timezone": "America/New_York", "accent_color": "#E04A4A"},
            {"id": "evt-2", "name": "Warehouse Rave", "cover_image_url": null,
             "start_at": "2026-09-02T23:00:00Z", "venue_name": "Warehouse 9",
             "timezone": "America/New_York", "accent_color": "#4A6FE0"},
            {"id": "evt-3", "name": "Jazz Night", "cover_image_url": null,
             "start_at": "2026-09-14T19:30:00Z", "venue_name": "Blue Note",
             "timezone": "America/New_York", "accent_color": "#89E901"}
        ]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HostedEvent].self, from: Data(json.utf8))) ?? []
    }()
}
#endif
