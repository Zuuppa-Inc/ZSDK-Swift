import SwiftUI

/// The My Tickets list: a header, a filter-tab row (Upcoming / Past / Cancelled,
/// per the config), and the tickets for the selected tab grouped by event.
/// Tapping an event pushes ``MyTicketDetailView``.
struct MyTicketsListView: View {

    let model: MyTicketsModel
    let onBack: () -> Void

    private let side = ZTheme.sideMargin

    private var tabs: [ZuuppaMyTicketsConfig.Tab] { model.options.tabs }

    var body: some View {
        VStack(spacing: 0) {
            header
            // The app always shows the sub-tab row (with its own bottom divider).
            tabBar
            content
        }
        .background(ZTheme.background)
        .navigationDestination(for: MyTicketGroup.self) { group in
            MyTicketDetailView(group: group, model: model)
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
                Button(action: onBack) {
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

    // MARK: - Tab bar

    /// Port of the app's `_subTabButton` row: equal-width tabs with a 2pt primary
    /// underline on the selected one, over a 0.5pt divider.
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                let selected = model.selectedTab == tab
                Button {
                    model.selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 14, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? ZTheme.text : ZTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(selected ? ZTheme.primary : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(ZTheme.divider).frame(height: 0.5)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let tab = model.selectedTab
        let state = model.state(for: tab)

        if state.isLoading && !state.didLoadOnce {
            ProgressView()
                .tint(ZTheme.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let groups = model.groups(for: tab)
            if groups.isEmpty {
                emptyState(tab: tab, error: state.loadError)
            } else {
                list(groups: groups, tab: tab, isLoadingMore: state.isLoadingMore)
            }
        }
    }

    private func list(groups: [MyTicketGroup], tab: ZuuppaMyTicketsConfig.Tab, isLoadingMore: Bool) -> some View {
        // Cards carry their own side + vertical margins (like the app's list
        // items), so the list itself only adds the app's top: 8 / bottom inset.
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groups) { group in
                    NavigationLink(value: group) {
                        MyTicketGroupCard(group: group)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        // Paginate when the last card scrolls into view.
                        if group.id == groups.last?.id {
                            Task { await model.loadMore(tab) }
                        }
                    }
                }

                if isLoadingMore {
                    ProgressView()
                        .tint(ZTheme.primary)
                        .padding(.vertical, 16)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh(tab) }
    }

    /// Port of the app's `_buildAttendingEmpty`: an 80pt circle with a 36pt
    /// ticket icon, a bold 20pt title, and a 15pt secondary subtitle.
    private func emptyState(tab: ZuuppaMyTicketsConfig.Tab, error: String?) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(ZTheme.secondaryBackground)
                MaterialIcon(.confirmationNumOutlined, size: 36, color: ZTheme.secondaryText)
            }
            .frame(width: 80, height: 80)

            Spacer().frame(height: 20)

            Text(error != nil ? "Couldn't load tickets" : tab.emptyTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ZTheme.text)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 8)

            Text(error ?? tab.emptySubtitle)
                .font(.system(size: 15))
                .foregroundStyle(ZTheme.secondaryText)
                .multilineTextAlignment(.center)

            if error != nil {
                Spacer().frame(height: 16)
                Button("Try again") {
                    Task { await model.load(tab) }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ZTheme.primary)
            }
        }
        .padding(.horizontal, side)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview("My Tickets — list") {
    NavigationStack {
        MyTicketsListView(model: .preview(), onBack: {})
    }
    .preferredColorScheme(.dark)
}

#Preview("My Tickets — empty") {
    NavigationStack {
        MyTicketsListView(model: .preview(empty: true), onBack: {})
    }
    .preferredColorScheme(.dark)
}
#endif
