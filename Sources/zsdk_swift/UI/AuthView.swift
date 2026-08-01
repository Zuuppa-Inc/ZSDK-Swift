import SwiftUI
import UIKit

/// Lightweight OTP sign-in, ported 1:1 from the app's `WelcomeScreen` morphed
/// (form) state: a back arrow top-left, the Zuuppa wordmark top-center tinted
/// the primary color, a title/subtitle that swap once the code is sent, a
/// label-above-filled-box input, an optional "Resend code" link, and a
/// bottom-pinned "Send Code" / "Verify" button.
///
/// No password, no onboarding — a verified user is enough to buy tickets.
/// Tickets are tied to this Supabase user, so signing into the Zuuppa app later
/// with the same email/phone surfaces them.
struct AuthView: View {

    let model: TicketFlowModel

    /// Which contact method the buyer chose. The app defaults to phone.
    private enum Method {
        case phone
        case email
    }

    /// The screen's high-level state. A returning (signed-in) buyer first sees a
    /// confirmation of the account they'll check out with; everyone else goes
    /// straight to the sign-in form.
    private enum Stage {
        case checking      // resolving whether there's a signed-in account
        case confirm       // signed in — confirm or switch account
        case form          // sign-in form (entry / code)
    }

    @State private var stage: Stage = .checking
    @State private var identity: AuthIdentity?
    @State private var method: Method = .phone
    @State private var otpSent = false
    @State private var contact = ""       // phone or email, before code is sent
    @State private var code = ""
    @State private var isBusy = false
    @State private var errorText: String?
    @FocusState private var focused: Bool

    private let side = ZTheme.sideMargin

    /// Preview-only seed: when set, the view starts in the signed-in confirm
    /// stage with this identity instead of resolving the session over the
    /// network (which previews can't do).
    private let previewIdentity: AuthIdentity?

    init(model: TicketFlowModel) {
        self.model = model
        self.previewIdentity = nil
    }

    private var channel: OTPChannel {
        method == .email ? .email(contact) : .phone(normalizedContact)
    }

    /// Phone entry mirrors the app's `_normalizePhone`: a bare 10-digit US
    /// number gets a `+1` prefix.
    private var normalizedContact: String {
        guard method == .phone else { return contact }
        let trimmed = contact.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter(\.isNumber)
        if !trimmed.hasPrefix("+"), digits.count == 10 { return "+1\(digits)" }
        return trimmed
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZTheme.background.ignoresSafeArea()

            // Wordmark, top-center, tinted the primary color (matching the
            // app's morphed logo: target width 120, color animates to primary).
            wordmark
                .frame(width: 120)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            // Back arrow, top-left. Returns to the event details screen (the
            // app pops back to where auth was triggered from).
            HStack {
                Button {
                    model.backToEventDetails()
                } label: {
                    MaterialIcon(.arrowBack, size: 24, color: ZTheme.text)
                        .frame(width: 56, height: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("back", "Back"))
                Spacer()
            }
            .padding(.horizontal, 4)

            // Body below the logo, offset like the app (Positioned top: 35).
            Group {
                switch stage {
                case .checking:
                    ProgressView()
                        .tint(ZTheme.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .confirm:
                    confirmAccount
                case .form:
                    form
                }
            }
            .padding(.top, 56)
        }
        .task {
            // Previews seed an identity directly (no networking).
            if let previewIdentity {
                identity = previewIdentity
                stage = .confirm
                return
            }
            // Resolve the signed-in account once (refreshing the token if
            // needed). Signed-in buyers confirm; everyone else signs in.
            identity = await model.currentIdentity()
            stage = (identity != nil) ? .confirm : .form
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 10)

            Text(otpSent ? L("enter_code", "Enter the code") : L("signin_title", "Sign in or create an account"))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(ZTheme.text)

            if otpSent {
                Spacer().frame(height: 4)
                Text(subtitle)
                    .font(.system(size: ZTheme.fontSize))
                    .foregroundStyle(ZTheme.secondaryText)
            }

            Spacer().frame(height: 16)

            if otpSent {
                labeledField(
                    label: L("verification_code", "Verification Code"),
                    text: $code,
                    keyboard: .numberPad,
                    content: .oneTimeCode
                )

                Spacer().frame(height: 16)
                Button(L("resend_code", "Resend code")) {
                    Task { await resend() }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ZTheme.primary)
                .disabled(isBusy)
            } else {
                labeledField(
                    label: method == .email ? L("email", "Email") : L("phone_number", "Phone Number"),
                    text: $contact,
                    keyboard: method == .email ? .emailAddress : .phonePad,
                    content: method == .email ? .emailAddress : .telephoneNumber
                )

                Spacer().frame(height: 16)
                Button(method == .email ? L("continue_phone", "Continue with Phone") : L("continue_email", "Continue with Email")) {
                    method = method == .email ? .phone : .email
                    contact = ""
                    errorText = nil
                    // The field is rebuilt (its .id changes with the keyboard),
                    // so re-focus on the next runloop once the new field exists.
                    Task { @MainActor in focused = true }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ZTheme.primary)
            }

            if let errorText {
                Spacer().frame(height: 12)
                Text(errorText)
                    .font(.system(size: 13))
                    .foregroundStyle(ZTheme.red)
            }

            Spacer()

            ZButton(
                label: otpSent ? L("verify", "Verify") : L("send_code", "Send Code"),
                isBusy: isBusy,
                isEnabled: canSubmit
            ) {
                Task { await primaryAction() }
            }

            Spacer().frame(height: 12)
        }
        .padding(.horizontal, side)
        .onAppear { focused = true }
    }

    private var subtitle: String {
        Lf("we_sent_code", "We sent a code to %@", method == .email ? contact : normalizedContact)
    }

    // MARK: - Signed-in confirmation

    /// Shown to a returning buyer: confirms which account they'll check out
    /// with, with the option to continue or sign out and use a different one.
    private var confirmAccount: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 10)

            Text(L("signed_in_title", "You're signed in"))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(ZTheme.text)

            Spacer().frame(height: 4)

            Text(L("signed_in_sub", "Your tickets will be tied to this account. Continue, or switch to a different one."))
                .font(.system(size: ZTheme.fontSize))
                .foregroundStyle(ZTheme.secondaryText)

            Spacer().frame(height: 20)

            // Account card: the email/phone this buyer is signed in as.
            HStack(spacing: 12) {
                Image(systemName: (identity?.email != nil) ? "envelope.fill" : "phone.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ZTheme.primary)
                    .frame(width: 24)
                Text(identity?.displayName ?? L("your_account", "your account"))
                    .font(.system(size: ZTheme.fontSize, weight: .semibold))
                    .foregroundStyle(ZTheme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(ZTheme.secondaryBackground, in: .rect(cornerRadius: 8))

            if let errorText {
                Spacer().frame(height: 12)
                Text(errorText)
                    .font(.system(size: 13))
                    .foregroundStyle(ZTheme.red)
            }

            Spacer()

            ZButton(label: L("continue_", "Continue"), isBusy: isBusy) {
                Task { await continueSignedIn() }
            }

            Spacer().frame(height: 10)

            ZButton(label: L("use_diff_account", "Use a different account"), variant: .bare, foregroundColor: ZTheme.primary) {
                Task { await switchAccount() }
            }

            Spacer().frame(height: 12)
        }
        .padding(.horizontal, side)
    }

    /// A label-above-a-filled-box text field, ported from the app's
    /// `ZTextInput`: 14pt secondary-text label, an 8pt-radius box filled with
    /// the secondary background, 12pt padding, primary-colored focused border.
    @ViewBuilder
    private func labeledField(
        label: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        content: UITextContentType
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(ZTheme.secondaryText)

            TextField("", text: text)
                .textContentType(content)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .foregroundStyle(ZTheme.text)
                .tint(ZTheme.primary)
                .font(.system(size: ZTheme.fontSize))
                .padding(12)
                .background(ZTheme.secondaryBackground, in: .rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(focused ? ZTheme.primary : .clear, lineWidth: 2)
                )
                // SwiftUI won't change a live field's keyboard, so key the field
                // to the keyboard type — switching email/phone rebuilds it with
                // the correct keyboard.
                .id(keyboard)
        }
    }

    private var canSubmit: Bool {
        if otpSent { return code.count >= 4 }
        return !contact.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    /// The signed-in buyer confirmed their account — proceed to checkout.
    private func continueSignedIn() async {
        errorText = nil
        isBusy = true
        defer { isBusy = false }
        await model.didAuthenticate()
    }

    /// The buyer wants a different account — sign out and drop to the sign-in
    /// form.
    private func switchAccount() async {
        await model.signOut()
        identity = nil
        withAnimation {
            stage = .form
            otpSent = false
            contact = ""
            code = ""
            errorText = nil
        }
        focused = true
    }

    private func primaryAction() async {
        errorText = nil
        isBusy = true
        defer { isBusy = false }

        do {
            if otpSent {
                try await model.verifyOTP(channel, token: code.trimmingCharacters(in: .whitespaces))
                await model.didAuthenticate()
            } else {
                try await model.requestOTP(channel)
                code = ""
                withAnimation { otpSent = true }
                focused = true
            }
        } catch {
            errorText = (error as? ZuuppaError)?.errorDescription
                ?? (otpSent ? L("verify_failed_generic", "Verification failed. Try again.") : L("failed_send_code", "Failed to send code. Try again."))
        }
    }

    private func resend() async {
        errorText = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await model.requestOTP(channel)
            code = ""
        } catch {
            errorText = (error as? ZuuppaError)?.errorDescription ?? L("failed_resend", "Failed to resend. Try again.")
        }
    }

    // MARK: - Wordmark

    /// The Zuuppa wordmark, loaded from the bundle by file URL and tinted the
    /// primary color (matching the app's morphed-logo `ColorFilter srcIn`).
    /// The bundled asset is a white wordmark, so template rendering recolors it.
    @ViewBuilder
    private var wordmark: some View {
        if let url = Bundle.module.url(forResource: "zuuppa-wordmark", withExtension: "png"),
           let ui = UIImage(contentsOfFile: url.path)?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .foregroundStyle(ZTheme.text)
        }
    }
}

#if DEBUG
extension AuthView {
    /// Preview initializer that starts in the signed-in confirm stage with a
    /// seeded identity, so the "you're signed in" state renders without a real
    /// session.
    init(model: TicketFlowModel, previewIdentity: AuthIdentity) {
        self.model = model
        self.previewIdentity = previewIdentity
    }
}

#Preview("Auth — signed in") {
    AuthView(model: .preview(step: .auth), previewIdentity: AuthIdentity(email: "buyer@example.com", phone: nil))
        .background(ZTheme.background)
        .preferredColorScheme(.dark)
}
#endif
