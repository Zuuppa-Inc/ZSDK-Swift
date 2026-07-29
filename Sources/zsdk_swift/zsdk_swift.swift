// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// zsdk_swift — Zuuppa's Swift SDK.
//
// The ticketing SDK lets a host app sell tickets to a Zuuppa event without
// leaving their app. Present the full-screen flow with an event id; it handles
// sign-in, event details, ticket selection, payment (card or crypto), and
// confirmation.
//
//   1. Present the ready-made screen yourself in a `fullScreenCover`:
//
//        .fullScreenCover(isPresented: $showTickets) {
//            ZuuppaTicketsScreen(eventId: "evt-uuid") { showTickets = false }
//        }
//
//   2. Use the convenience modifier, which wires up the cover for you:
//
//        .zuuppaTickets(isPresented: $showTickets, eventId: "evt-uuid")
//
// See `UI/ZuuppaTicketsScreen.swift` for the public entry point.
//
// To let a signed-in user see the tickets they already own, present the
// "My Tickets" screen instead. It gates on the same OTP sign-in, lists the
// user's tickets grouped by event (Upcoming / Past / Cancelled), and opens a
// detail screen with a scannable QR code per ticket:
//
//        .fullScreenCover(isPresented: $showMine) {
//            ZuuppaMyTicketsScreen { showMine = false }
//        }
//
//   …or the convenience modifier:
//
//        .zuuppaMyTickets(isPresented: $showMine)
//
// Customize it with `ZuuppaMyTicketsConfig` (tabs, host filter, detail actions).
// See `UI/ZuuppaMyTicketsScreen.swift`.
//
// To embed a list of the events a user hosts or co-hosts, use the chrome-less
// `ZuuppaMyEventsList` — pass a user id (and optionally your own search text);
// tapping an event opens the ticketing flow above:
//
//        ScrollView { ZuuppaMyEventsList(userId: hostUserId) }
//
// See `UI/ZuuppaMyEventsList.swift`.
