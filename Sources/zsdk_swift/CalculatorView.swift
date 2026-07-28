import SwiftUI

/// A single calculator key description.
private struct CalculatorKey: Identifiable {
    enum Kind {
        case digit(Int)
        case decimal
        case operation(CalculatorOperation)
        case equals
        case clear
        case toggleSign
        case percent
    }

    let id = UUID()
    let label: String
    let kind: Kind
    var span: Int = 1   // How many columns this key occupies (0 = double-wide).
}

/// The calculator screen itself: a display area on top and a grid of keys below.
/// This is UI-only; all arithmetic lives in ``CalculatorEngine``.
public struct CalculatorView: View {

    @State private var engine = CalculatorEngine()

    public init() {}

    // Standard iOS-calculator layout, top row to bottom.
    private let rows: [[CalculatorKey]] = [
        [
            CalculatorKey(label: "AC", kind: .clear),
            CalculatorKey(label: "±", kind: .toggleSign),
            CalculatorKey(label: "%", kind: .percent),
            CalculatorKey(label: "÷", kind: .operation(.divide)),
        ],
        [
            CalculatorKey(label: "7", kind: .digit(7)),
            CalculatorKey(label: "8", kind: .digit(8)),
            CalculatorKey(label: "9", kind: .digit(9)),
            CalculatorKey(label: "×", kind: .operation(.multiply)),
        ],
        [
            CalculatorKey(label: "4", kind: .digit(4)),
            CalculatorKey(label: "5", kind: .digit(5)),
            CalculatorKey(label: "6", kind: .digit(6)),
            CalculatorKey(label: "−", kind: .operation(.subtract)),
        ],
        [
            CalculatorKey(label: "1", kind: .digit(1)),
            CalculatorKey(label: "2", kind: .digit(2)),
            CalculatorKey(label: "3", kind: .digit(3)),
            CalculatorKey(label: "+", kind: .operation(.add)),
        ],
        [
            CalculatorKey(label: "0", kind: .digit(0), span: 2),
            CalculatorKey(label: ".", kind: .decimal),
            CalculatorKey(label: "=", kind: .equals),
        ],
    ]

    public var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 12
            let buttonSize = (geometry.size.width - spacing * 5) / 4

            VStack(spacing: spacing) {
                Spacer(minLength: 0)

                // Display
                Text(engine.display)
                    .font(.system(size: 72, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, spacing)

                // Keypad
                ForEach(rows.indices, id: \.self) { rowIndex in
                    HStack(spacing: spacing) {
                        ForEach(rows[rowIndex]) { key in
                            keyButton(key, buttonSize: buttonSize, spacing: spacing)
                        }
                    }
                }
            }
            .padding(spacing)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
    }

    @ViewBuilder
    private func keyButton(_ key: CalculatorKey, buttonSize: CGFloat, spacing: CGFloat) -> some View {
        let width = key.span == 2 ? buttonSize * 2 + spacing : buttonSize

        Button {
            handle(key)
        } label: {
            Text(key.label)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(foreground(for: key))
                .frame(width: width, height: buttonSize)
                .background(background(for: key))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func handle(_ key: CalculatorKey) {
        switch key.kind {
        case .digit(let value): engine.inputDigit(value)
        case .decimal: engine.inputDecimalPoint()
        case .operation(let op): engine.setOperation(op)
        case .equals: engine.calculateResult()
        case .clear: engine.clear()
        case .toggleSign: engine.toggleSign()
        case .percent: engine.applyPercent()
        }
    }

    private func background(for key: CalculatorKey) -> Color {
        switch key.kind {
        case .operation, .equals:
            return .orange
        case .clear, .toggleSign, .percent:
            return Color(white: 0.65)
        default:
            return Color(white: 0.2)
        }
    }

    private func foreground(for key: CalculatorKey) -> Color {
        switch key.kind {
        case .clear, .toggleSign, .percent:
            return .black
        default:
            return .white
        }
    }
}

// Previews just the keypad (no close button — that lives in the full screen).
#Preview("Keypad") {
    CalculatorView()
}

// Previews the full screen a host app presents, including the close button.
#Preview("Full screen") {
    ZuuppaCalculatorScreen()
}
