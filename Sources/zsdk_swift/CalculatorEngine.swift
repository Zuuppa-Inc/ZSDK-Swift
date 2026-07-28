import Foundation

/// The arithmetic operations the calculator supports.
enum CalculatorOperation {
    case add
    case subtract
    case multiply
    case divide

    func apply(_ lhs: Double, _ rhs: Double) -> Double {
        switch self {
        case .add: return lhs + rhs
        case .subtract: return lhs - rhs
        case .multiply: return lhs * rhs
        case .divide: return rhs == 0 ? .nan : lhs / rhs
        }
    }
}

/// Pure calculator state machine. Holds no UI; the view drives it and reads
/// `display` back. Kept separate so the logic can be unit-tested on its own.
@Observable
final class CalculatorEngine {

    /// The string currently shown on the calculator's screen.
    private(set) var display: String = "0"

    // Value carried over from the last operator press.
    private var accumulator: Double?
    // Operation waiting to be applied when `=` (or a new operator) is pressed.
    private var pendingOperation: CalculatorOperation?
    // True while the next digit should start a fresh number rather than append.
    private var isEnteringNewNumber = true

    // MARK: - Input

    func inputDigit(_ digit: Int) {
        if isEnteringNewNumber {
            display = "\(digit)"
            isEnteringNewNumber = false
        } else if display == "0" {
            display = "\(digit)"
        } else {
            display += "\(digit)"
        }
    }

    func inputDecimalPoint() {
        if isEnteringNewNumber {
            display = "0."
            isEnteringNewNumber = false
        } else if !display.contains(".") {
            display += "."
        }
    }

    func setOperation(_ operation: CalculatorOperation) {
        // Chaining operators (e.g. 2 + 3 +) evaluates the pending one first.
        if pendingOperation != nil && !isEnteringNewNumber {
            calculateResult()
        } else {
            accumulator = currentValue
        }
        pendingOperation = operation
        isEnteringNewNumber = true
    }

    func calculateResult() {
        guard let operation = pendingOperation, let lhs = accumulator else { return }
        let result = operation.apply(lhs, currentValue)
        display = format(result)
        accumulator = result
        pendingOperation = nil
        isEnteringNewNumber = true
    }

    // MARK: - Modifiers

    func clear() {
        display = "0"
        accumulator = nil
        pendingOperation = nil
        isEnteringNewNumber = true
    }

    func toggleSign() {
        guard currentValue != 0 else { return }
        display = format(currentValue * -1)
    }

    func applyPercent() {
        display = format(currentValue / 100)
    }

    // MARK: - Helpers

    private var currentValue: Double {
        Double(display) ?? 0
    }

    /// Formats a result without a trailing ".0" for whole numbers, and shows
    /// "Error" for undefined results (e.g. division by zero).
    private func format(_ value: Double) -> String {
        guard value.isFinite else { return "Error" }
        if value == value.rounded() && abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        return String(value)
    }
}
