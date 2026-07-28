import SwiftUI
import UIKit

/// Ticket success screen — a 1:1 port of the app's `TicketSuccessScreen`:
/// Zuuppa wordmark, "Got your tickets", event banner, name, location, and date,
/// with a pinned "Done" button. Adds an SDK-only "Download Zuuppa" card (with
/// an App Store button), since an out-of-app buyer accesses tickets in the app.
struct ConfirmationView: View {

    let model: TicketFlowModel
    let confirmation: TicketFlowModel.Confirmation
    let onDone: () -> Void

    private var event: Event? { model.event }
    private let side = ZTheme.sideMargin

    // Zuuppa's App Store listing.
    private let appStoreURL = URL(string: "https://apps.apple.com/us/app/zuuppa-global-ticketing/id6761310448")!

    var body: some View {
        ZStack(alignment: .bottom) {
            ZTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 16)

                    // Zuuppa wordmark (bundled from the app's text-logo). Loaded
                    // by file URL because it's a loose resource, not in an asset
                    // catalog (Image(named:) only searches catalogs).
                    wordmark
                        .frame(width: 80)

                    Spacer().frame(height: 16)

                    Text("GOT YOUR TICKETS!")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(ZTheme.text)
                        .multilineTextAlignment(.center)

                    Spacer().frame(height: 5)

                    banner

                    Spacer().frame(height: 5)

                    if let name = event?.name {
                        Text(name)
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(ZTheme.text)
                            .multilineTextAlignment(.center)
                    }

                    if let location = event?.venueName ?? event?.addressText, !location.isEmpty {
                        Text(location)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(ZTheme.text)
                            .multilineTextAlignment(.center)
                    }

                    if event?.startAt != nil {
                        Text(formatEventDateRange(start: event?.startAt, end: event?.endAt, timezone: event?.timezone))
                            .font(.system(size: 14))
                            .foregroundStyle(ZTheme.text)
                            .multilineTextAlignment(.center)
                    }

                    Spacer().frame(height: 24)

                    downloadCard

                    // Leave room for the pinned Done button.
                    Spacer().frame(height: 80)
                }
                .padding(.horizontal, side)
            }
            .scrollIndicators(.hidden)

            ZButton(label: "Done") { onDone() }
                .padding(.horizontal, side)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Wordmark

    /// The Zuuppa wordmark, loaded from the bundle by file URL and tinted white
    /// (matching the app's `ColorFilter srcIn`).
    @ViewBuilder
    private var wordmark: some View {
        if let url = Bundle.module.url(forResource: "zuuppa-wordmark", withExtension: "png"),
           let ui = UIImage(contentsOfFile: url.path) {
            // Asset is already the white wordmark from the landing's TO_white.svg.
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
        }
    }

    // MARK: - Banner

    @ViewBuilder
    private var banner: some View {
        if let urlString = event?.coverImageURL, let url = URL(string: urlString) {
            // Animated (GIF-capable) banner, capped at half the screen height
            // like the app's ConstrainedBox(maxHeight: size.height * 0.5).
            AnimatedImageView(url: url)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: UIScreen.main.bounds.height * 0.5)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Download card

    private var downloadCard: some View {
        VStack(spacing: 12) {
            Text("Download Zuuppa to access your tickets")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ZTheme.text)
                .multilineTextAlignment(.center)
            Text("Sign in with the same email or phone number you used here, and your tickets will be waiting.")
                .font(.system(size: 13))
                .foregroundStyle(ZTheme.secondaryText)
                .multilineTextAlignment(.center)

            Link(destination: appStoreURL) {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Get it on the App Store")
                        .font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: ZTheme.buttonHeight)
                .background(ZTheme.primary, in: RoundedRectangle(cornerRadius: ZTheme.buttonCornerRadius))
                .foregroundStyle(ZTheme.onPrimary)
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(ZTheme.cardOverlay, in: RoundedRectangle(cornerRadius: 16))
    }
}
