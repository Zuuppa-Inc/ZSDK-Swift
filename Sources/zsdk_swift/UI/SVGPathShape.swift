import SwiftUI

/// A SwiftUI `Shape` that renders an SVG path's `d` string, scaled to fit
/// (aspect-preserving, like flutter_svg's default `BoxFit.contain`). Supports
/// the command set used by the app's icon assets: M/m, L/l, H/h, V/v, C/c,
/// Z/z. Filled with `.foregroundStyle`, so it tints like the app's SVGs.
struct SVGPathShape: Shape {

    /// The SVG `d` attribute.
    let pathData: String
    /// The SVG `viewBox` width and height.
    let viewBox: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let commands = Self.parse(pathData)

        var current = CGPoint.zero
        var start = CGPoint.zero

        for command in commands {
            switch command.op {
            case "M", "m":
                let relative = command.op == "m"
                for (i, pair) in command.pairs.enumerated() {
                    var p = CGPoint(x: pair.0, y: pair.1)
                    if relative { p = CGPoint(x: current.x + p.x, y: current.y + p.y) }
                    if i == 0 {
                        path.move(to: p)
                        start = p
                    } else {
                        path.addLine(to: p)
                    }
                    current = p
                }

            case "L", "l":
                let relative = command.op == "l"
                for pair in command.pairs {
                    var p = CGPoint(x: pair.0, y: pair.1)
                    if relative { p = CGPoint(x: current.x + p.x, y: current.y + p.y) }
                    path.addLine(to: p)
                    current = p
                }

            case "H", "h":
                let relative = command.op == "h"
                for value in command.scalars {
                    let x = relative ? current.x + value : value
                    current = CGPoint(x: x, y: current.y)
                    path.addLine(to: current)
                }

            case "V", "v":
                let relative = command.op == "v"
                for value in command.scalars {
                    let y = relative ? current.y + value : value
                    current = CGPoint(x: current.x, y: y)
                    path.addLine(to: current)
                }

            case "C", "c":
                let relative = command.op == "c"
                var i = 0
                while i + 2 < command.pairs.count {
                    func resolve(_ pair: (CGFloat, CGFloat)) -> CGPoint {
                        var p = CGPoint(x: pair.0, y: pair.1)
                        if relative { p = CGPoint(x: current.x + p.x, y: current.y + p.y) }
                        return p
                    }
                    let c1 = resolve(command.pairs[i])
                    let c2 = resolve(command.pairs[i + 1])
                    let end = resolve(command.pairs[i + 2])
                    path.addCurve(to: end, control1: c1, control2: c2)
                    current = end
                    i += 3
                }

            case "Z", "z":
                path.closeSubpath()
                current = start

            default:
                break
            }
        }

        return scaled(path, into: rect)
    }

    /// Scales the raw viewBox-space path to fit `rect`, aspect-preserving.
    private func scaled(_ path: Path, into rect: CGRect) -> Path {
        guard viewBox.width > 0, viewBox.height > 0 else { return path }
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let drawn = CGSize(width: viewBox.width * scale, height: viewBox.height * scale)
        let dx = rect.minX + (rect.width - drawn.width) / 2
        let dy = rect.minY + (rect.height - drawn.height) / 2
        let transform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
        return path.applying(transform)
    }

    // MARK: - Parsing

    private struct Command {
        let op: Character
        let scalars: [CGFloat]
        /// Scalars grouped into coordinate pairs.
        var pairs: [(CGFloat, CGFloat)] {
            var result: [(CGFloat, CGFloat)] = []
            var i = 0
            while i + 1 < scalars.count {
                result.append((scalars[i], scalars[i + 1]))
                i += 2
            }
            return result
        }
    }

    private static func parse(_ d: String) -> [Command] {
        var commands: [Command] = []
        var currentOp: Character?
        var numbers: [CGFloat] = []
        let scalars = Array(d)
        var i = 0

        func flush() {
            if let op = currentOp {
                commands.append(Command(op: op, scalars: numbers))
            }
            numbers = []
        }

        while i < scalars.count {
            let ch = scalars[i]
            if ch.isLetter {
                flush()
                currentOp = ch
                i += 1
            } else if ch == "-" || ch == "." || ch.isNumber {
                // Scan one number (handles "-45.3", ".2", "0-96", "1.5.5").
                var numStr = ""
                var seenDot = false
                if ch == "-" { numStr.append(ch); i += 1 }
                while i < scalars.count {
                    let c = scalars[i]
                    if c.isNumber {
                        numStr.append(c); i += 1
                    } else if c == "." && !seenDot {
                        seenDot = true; numStr.append(c); i += 1
                    } else {
                        break
                    }
                }
                if let value = Double(numStr) { numbers.append(CGFloat(value)) }
            } else {
                // Separator (space or comma).
                i += 1
            }
        }
        flush()
        return commands
    }
}
