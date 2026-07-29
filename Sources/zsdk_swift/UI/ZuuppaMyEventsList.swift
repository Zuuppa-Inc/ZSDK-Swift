import SwiftUI

/// A bare, embeddable list of the events a given user hosts or co-hosts. There
/// is **no** chrome — no header, no search bar — so a host app can drop it into
/// its own screen. Tapping an event opens the Zuuppa event/ticketing flow
/// (``ZuuppaTicketsScreen``) in a full-screen cover.
///
/// The host owns the search input: bind a text field to your own state and pass
/// the trimmed query in via ``search``. The list debounces and refetches.
///
/// ```swift
/// @State private var query = ""
///
/// VStack {
///     TextField("Search events", text: $query)   // your own field
///     ZuuppaMyEventsList(userId: hostUserId, search: query)
/// }
/// ```
public struct ZuuppaMyEventsList: View {

    @State private var model: MyEventsModel
    @State private var openedEventID: String?
    private let search: String

    /// - Parameters:
    ///   - userId: The Supabase user id whose hosted / co-hosted public events
    ///     to list.
    ///   - search: Optional search query. Pass your text field's trimmed value;
    ///     the list debounces changes and refetches. Matches event name + venue.
    ///   - config: Backend configuration. Defaults to production.
    public init(
        userId: String,
        search: String = "",
        config: ZuuppaConfig = .default
    ) {
        _model = State(initialValue: MyEventsModel(userID: userId, config: config))
        self.search = search
    }

    /// Preview-only initializer.
    init(previewModel: MyEventsModel) {
        _model = State(initialValue: previewModel)
        self.search = ""
        self.autoStart = false
    }

    private var autoStart = true

    public var body: some View {
        content
            .task { if autoStart { await model.start() } }
            // React to the host updating the search text.
            .onChange(of: search) { _, newValue in
                model.setSearch(newValue)
            }
            .fullScreenCover(item: $openedEventID) { eventID in
                ZuuppaTicketsScreen(
                    eventId: eventID,
                    config: model.config,
                    onFinish: { openedEventID = nil }
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView()
                .tint(ZTheme.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        } else if model.events.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        // A plain LazyVStack (not a ScrollView) so the host controls scrolling
        // context; wrap it in your own ScrollView if the list is the whole screen.
        LazyVStack(spacing: 0) {
            ForEach(model.events) { event in
                Button {
                    openedEventID = event.id
                } label: {
                    EventListCard(event: event)
                }
                .buttonStyle(.plain)
                .onAppear {
                    if event.id == model.events.last?.id {
                        Task { await model.loadMore() }
                    }
                }
            }

            if model.isLoadingMore {
                ProgressView()
                    .tint(ZTheme.primary)
                    .padding(.vertical, 16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(model.loadError ?? "No events")
                .font(.system(size: 15))
                .foregroundStyle(ZTheme.secondaryText)
                .multilineTextAlignment(.center)
            if model.loadError != nil {
                Button("Try again") { Task { await model.load() } }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ZTheme.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 32)
    }
}

/// Lets a bare `String` event id drive `.fullScreenCover(item:)`.
extension String: @retroactive Identifiable {
    public var id: String { self }
}

#if DEBUG
#Preview("My Events — list") {
    ScrollView {
        ZuuppaMyEventsList(previewModel: .preview())
            .padding(.horizontal, 20)
            .padding(.top, 8)
    }
    .background(ZTheme.background)
    .preferredColorScheme(.dark)
}

#Preview("My Events — empty") {
    ScrollView {
        ZuuppaMyEventsList(previewModel: .preview(empty: true))
            .padding(.horizontal, 20)
    }
    .background(ZTheme.background)
    .preferredColorScheme(.dark)
}

// MARK: - Live preview against real data

/// Enter a real host user id to load their live events from the backend. The
/// endpoint is public, so no sign-in is needed. Also exercises the host-owned
/// search field wiring.
private struct LiveMyEventsPreview: View {
    // Paste a real host user id here to have it pre-filled.
    @State private var userId = ""
    @State private var submittedUserId: String?
    @State private var query = ""

    var body: some View {
        VStack(spacing: 12) {
            TextField("Host user id (UUID)", text: $userId)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { submittedUserId = userId.trimmingCharacters(in: .whitespaces) }

            if let submittedUserId, !submittedUserId.isEmpty {
                TextField("Search events", text: $query)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    // Re-create the list when the id changes by keying on it.
                    ZuuppaMyEventsList(userId: submittedUserId, search: query)
                        .id(submittedUserId)
                }
            } else {
                Text("Enter a user id and press return")
                    .font(.system(size: 14))
                    .foregroundStyle(ZTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .background(ZTheme.background)
        .preferredColorScheme(.dark)
    }
}

#Preview("My Events — live") {
    LiveMyEventsPreview()
}
#endif
