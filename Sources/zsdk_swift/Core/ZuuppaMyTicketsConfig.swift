import Foundation

/// Feature toggles for ``ZuuppaMyTicketsScreen``.
///
/// This is distinct from ``ZuuppaConfig`` (which configures the backend URLs and
/// keys): it controls which UI a host app wants to expose. Pass a customized
/// value to show only some filter tabs, scope the list to one host, or hide any
/// of the detail-screen actions.
///
/// ```swift
/// ZuuppaMyTicketsScreen(options: .init(
///     tabs: [.upcoming, .past],
///     hostID: "host-uuid",
///     showAddToAppleWallet: false
/// ))
/// ```
///
/// > Important: The **Add to Calendar** action uses the system calendar. An SPM
/// > library can't declare the required Info.plist usage string, so the
/// > embedding app must add `NSCalendarsWriteOnlyAccessUsageDescription` (iOS
/// > 17+). Without it the app will crash when the buyer taps Add to Calendar.
/// > Set ``showAddToCalendar`` to `false` if the host app can't add that key.
public struct ZuuppaMyTicketsConfig: Sendable {

    /// One of the filter tabs on the list screen.
    public enum Tab: Sendable, CaseIterable, Hashable {
        case upcoming
        case past
        case cancelled

        /// The value the `filter` query param expects. Note the server uses the
        /// American spelling `canceled` — that quirk is isolated here.
        var serverFilter: String {
            switch self {
            case .upcoming: return "upcoming"
            case .past: return "past"
            case .cancelled: return "canceled"
            }
        }

        /// The tab's title in the segmented control.
        var title: String {
            switch self {
            case .upcoming: return L("tab_upcoming", "Upcoming")
            case .past: return L("tab_past", "Past")
            case .cancelled: return L("tab_cancelled", "Cancelled")
            }
        }

        /// The empty-state title shown when the tab has no tickets.
        var emptyTitle: String {
            switch self {
            case .upcoming: return L("no_upcoming", "No upcoming tickets")
            case .past: return L("no_past", "No past tickets")
            case .cancelled: return L("no_cancelled", "No cancelled tickets")
            }
        }

        /// The empty-state subtitle shown under the title.
        var emptySubtitle: String {
            switch self {
            case .upcoming: return L("empty_upcoming_sub", "RSVP to events and your tickets\nwill appear here")
            case .past: return L("empty_past_sub", "Your past event tickets\nwill appear here")
            case .cancelled: return L("empty_cancelled_sub", "Cancelled event tickets\nwill appear here")
            }
        }
    }

    /// Which tabs to show, in order. Defaults to all three.
    public var tabs: [Tab]

    /// When set, the list shows only the buyer's tickets for events hosted by
    /// this user id. Requires backend support (`host_id` query param).
    public var hostID: String?

    /// Whether the detail screen shows the "Add to Calendar" action. See the
    /// type's note about the required Info.plist key.
    public var showAddToCalendar: Bool

    /// Whether the detail screen shows the "Open in Maps" action.
    public var showOpenInMaps: Bool

    /// Whether the detail screen shows the "View Receipt" action (only appears
    /// for paid orders regardless).
    public var showViewReceipt: Bool

    /// Whether the detail screen shows the "Add to Apple Wallet" action.
    public var showAddToAppleWallet: Bool

    public init(
        tabs: [Tab] = Tab.allCases,
        hostID: String? = nil,
        showAddToCalendar: Bool = true,
        showOpenInMaps: Bool = true,
        showViewReceipt: Bool = true,
        showAddToAppleWallet: Bool = true
    ) {
        // Guard against an empty tab set leaving the screen with nothing to show.
        self.tabs = tabs.isEmpty ? Tab.allCases : tabs
        self.hostID = hostID
        self.showAddToCalendar = showAddToCalendar
        self.showOpenInMaps = showOpenInMaps
        self.showViewReceipt = showViewReceipt
        self.showAddToAppleWallet = showAddToAppleWallet
    }

    /// The default configuration: all tabs, all detail actions, no host filter.
    public static let `default` = ZuuppaMyTicketsConfig()
}
