// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// zsdk_swift — Zuuppa's Swift SDK.
//
// This first component ships a full-screen calculator that a host app can
// present and dismiss. Two ways to use it:
//
//   1. Present the ready-made screen yourself in a `fullScreenCover`:
//
//        .fullScreenCover(isPresented: $showCalculator) {
//            ZuuppaCalculatorScreen()
//        }
//
//   2. Use the convenience modifier, which wires up the cover for you:
//
//        .zuuppaCalculator(isPresented: $showCalculator)
//
import SwiftUI

/// A full-screen calculator screen with a close button.
///
/// Present this from a host app (typically inside a `fullScreenCover`). The
/// user can run calculations and tap the close button to dismiss back to the
/// host app.
public struct ZuuppaCalculatorScreen: View {

    @Environment(\.dismiss) private var dismiss

    /// Optional callback invoked when the user dismisses the screen. Useful for
    /// hosts that manage presentation state themselves instead of relying on
    /// the environment's `dismiss`.
    private let onClose: (() -> Void)?

    public init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with a clearly visible close control, kept inside the
                // safe area so it never hides behind the status bar / notch.
                HStack {
                    Spacer()
                    Button {
                        onClose?()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color(white: 0.3))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close calculator")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                CalculatorView()
            }
        }
    }
}

public extension View {
    /// Presents the Zuuppa calculator as a full-screen cover.
    ///
    /// - Parameter isPresented: Binding that controls presentation. The screen
    ///   sets it back to `false` when the user closes the calculator.
    func zuuppaCalculator(isPresented: Binding<Bool>) -> some View {
        fullScreenCover(isPresented: isPresented) {
            ZuuppaCalculatorScreen { isPresented.wrappedValue = false }
        }
    }
}
