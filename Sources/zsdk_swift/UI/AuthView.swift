import SwiftUI

/// Lightweight OTP sign-in: the buyer enters an email or phone, receives a
/// code, and verifies it. No password, no onboarding — a verified user is
/// enough to buy tickets. Tickets are tied to this Supabase user, so signing
/// into the Zuuppa app later with the same email/phone surfaces them.
struct AuthView: View {

    let model: TicketFlowModel

    private enum Mode: String, CaseIterable {
        case email = "Email"
        case phone = "Phone"
    }

    private enum Stage {
        case entry     // entering email/phone
        case code      // entering the OTP code
    }

    @State private var mode: Mode = .email
    @State private var stage: Stage = .entry
    @State private var contact = ""
    @State private var code = ""
    @State private var isBusy = false
    @State private var errorText: String?
    @FocusState private var focused: Bool

    private var channel: OTPChannel {
        mode == .email ? .email(contact) : .phone(contact)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(stage == .entry ? "Sign in to continue" : "Enter your code")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(ZTheme.text)
                Text(stage == .entry
                     ? "We'll send you a one-time code to verify your identity."
                     : "We sent a code to \(contact).")
                    .font(.system(size: 14))
                    .foregroundStyle(ZTheme.secondaryText)
            }

            if stage == .entry {
                entryFields
            } else {
                codeField
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 13))
                    .foregroundStyle(ZTheme.red)
            }

            ZButton(
                label: stage == .entry ? "Send code" : "Verify",
                isBusy: isBusy,
                isEnabled: canSubmit
            ) {
                Task { await primaryAction() }
            }

            if stage == .code {
                Button("Use a different email or phone") {
                    withAnimation { resetToEntry() }
                }
                .font(.system(size: 13))
                .foregroundStyle(ZTheme.primary)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZTheme.background)
        .onAppear { focused = true }
    }

    // MARK: - Subviews

    private var entryFields: some View {
        VStack(spacing: 16) {
            Picker("Method", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, _ in contact = "" }

            TextField("", text: $contact, prompt: promptText(mode == .email ? "you@example.com" : "+1 555 123 4567"))
                .textContentType(mode == .email ? .emailAddress : .telephoneNumber)
                .keyboardType(mode == .email ? .emailAddress : .phonePad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .foregroundStyle(ZTheme.text)
                .padding()
                .background(ZTheme.cardOverlay, in: .rect(cornerRadius: 12))
        }
    }

    private var codeField: some View {
        TextField("", text: $code, prompt: promptText("123456"))
            .textContentType(.oneTimeCode)
            .keyboardType(.numberPad)
            .focused($focused)
            .foregroundStyle(ZTheme.text)
            .padding()
            .background(ZTheme.cardOverlay, in: .rect(cornerRadius: 12))
    }

    private func promptText(_ text: String) -> Text {
        Text(text).foregroundStyle(ZTheme.secondaryText)
    }

    private var canSubmit: Bool {
        stage == .entry ? !contact.trimmingCharacters(in: .whitespaces).isEmpty
                        : code.count >= 4
    }

    // MARK: - Actions

    private func primaryAction() async {
        errorText = nil
        isBusy = true
        defer { isBusy = false }

        do {
            switch stage {
            case .entry:
                try await model.requestOTP(channel)
                code = ""
                withAnimation { stage = .code }
                focused = true
            case .code:
                try await model.verifyOTP(channel, token: code.trimmingCharacters(in: .whitespaces))
                await model.didAuthenticate()
            }
        } catch {
            errorText = (error as? ZuuppaError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func resetToEntry() {
        stage = .entry
        code = ""
        errorText = nil
        focused = true
    }
}
