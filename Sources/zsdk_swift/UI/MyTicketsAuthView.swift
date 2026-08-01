import SwiftUI
import UIKit

/// OTP sign-in gate for the My Tickets screen. Ported from ``AuthView``'s form,
/// but standalone: it talks to ``MyTicketsModel`` instead of the checkout flow,
/// the back arrow closes the whole screen, and there's no "you're signed in"
/// confirm stage (a signed-in buyer skips this view entirely).
///
/// Tickets are tied to the verified Supabase user, so signing in here surfaces
/// exactly the tickets that account owns.
struct MyTicketsAuthView: View {

    let model: MyTicketsModel
    let onBack: () -> Void

    private enum Method {
        case phone
        case email
    }

    @State private var method: Method = .phone
    @State private var otpSent = false
    @State private var contact = ""
    @State private var code = ""
    @State private var isBusy = false
    @State private var errorText: String?
    @FocusState private var focused: Bool

    private let side = ZTheme.sideMargin

    private var channel: OTPChannel {
        method == .email ? .email(contact) : .phone(normalizedContact)
    }

    /// A bare 10-digit US number gets a `+1` prefix (matches the app / AuthView).
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

            wordmark
                .frame(width: 120)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            HStack {
                Button(action: onBack) {
                    MaterialIcon(.arrowBack, size: 24, color: ZTheme.text)
                        .frame(width: 56, height: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("back", "Back"))
                Spacer()
            }
            .padding(.horizontal, 4)

            form
                .padding(.top, 56)
        }
        .onAppear { focused = true }
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 10)

            Text(otpSent ? L("enter_code", "Enter the code") : L("signin_tickets_title", "Sign in to see your tickets"))
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
    }

    private var subtitle: String {
        Lf("we_sent_code", "We sent a code to %@", method == .email ? contact : normalizedContact)
    }

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
                .id(keyboard)
        }
    }

    private var canSubmit: Bool {
        if otpSent { return code.count >= 4 }
        return !contact.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    private func primaryAction() async {
        errorText = nil
        isBusy = true
        defer { isBusy = false }

        do {
            if otpSent {
                try await model.verifyOTP(channel, token: code.trimmingCharacters(in: .whitespaces))
                await model.onAuthenticated()
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
#Preview("My Tickets — auth") {
    MyTicketsAuthView(model: .preview(signedOut: true), onBack: {})
        .preferredColorScheme(.dark)
}
#endif
