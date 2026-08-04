import SwiftUI

/// A fullscreen page for collecting an email address before emailing tickets.
/// Shown only for accounts created via phone number, which have no email on file
/// — mirrors the app's `EnterEmailScreen` (a fullscreen page with the shared
/// `ZuuppaScreenHeader`: a close button top-left and a centered title). Calls
/// `onSubmit` with the trimmed address and dismisses; dismissing without
/// submitting is a no-op.
struct EmailPromptSheet: View {
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @FocusState private var focused: Bool

    private let side = ZTheme.sideMargin

    /// Lightweight client-side sanity check; the server does the real
    /// validation. Matches the app's `_looksLikeEmail`.
    private var isValid: Bool {
        let value = email.trimmingCharacters(in: .whitespaces)
        guard let at = value.firstIndex(of: "@"), at != value.startIndex,
              !value.contains(" ") else { return false }
        let domain = value[value.index(after: at)...]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 24)

                Text(L("email_tickets_enter_email_prompt",
                       "Your account has no email on file. Enter the address where you'd like your tickets sent."))
                    .font(.system(size: ZTheme.fontSize))
                    .foregroundStyle(ZTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: 24)

                Text(L("email", "Email"))
                    .font(.system(size: 14))
                    .foregroundStyle(ZTheme.secondaryText)
                Spacer().frame(height: 8)
                TextField("", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
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
                    .onSubmit(submit)

                Spacer()

                ZButton(label: L("send", "SEND"), isEnabled: isValid) {
                    submit()
                }

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, side)
        }
        .background(ZTheme.background)
        .onAppear { focused = true }
    }

    // MARK: - Header

    /// Centered "Enter your email" title with a close button, matching
    /// `ZuuppaScreenHeader` (which the app's `EnterEmailScreen` uses).
    private var header: some View {
        ZStack {
            Text(L("enter_your_email", "Enter your email"))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ZTheme.text)

            HStack {
                Button { dismiss() } label: {
                    MaterialIcon(.close, size: 24, color: ZTheme.text)
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel(L("cancel", "Cancel"))
                Spacer()
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 4)
    }

    private func submit() {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard isValid else { return }
        dismiss()
        onSubmit(trimmed)
    }
}
