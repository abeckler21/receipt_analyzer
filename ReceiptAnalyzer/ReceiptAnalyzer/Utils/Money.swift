import Foundation

/// Simple money wrapper using integer cents to avoid floating error.
struct Money: Codable, Equatable, Comparable, Hashable {
    var cents: Int

    static let zero = Money(cents: 0)

    init(cents: Int) { self.cents = cents }

    init(dollars: Double) {
        self.cents = Int((dollars * 100.0).rounded())
    }

    static func < (lhs: Money, rhs: Money) -> Bool { lhs.cents < rhs.cents }

    static func + (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents + rhs.cents) }
    static func - (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents - rhs.cents) }

    static func * (lhs: Money, rhs: Int) -> Money { Money(cents: lhs.cents * rhs) }
    static func / (lhs: Money, rhs: Int) -> Money { Money(cents: lhs.cents / max(rhs, 1)) }

    func formatted() -> String {
        let absCents = abs(cents)
        let dollars = absCents / 100
        let rem = absCents % 100
        let sign = cents < 0 ? "-" : ""
        return "\(sign)$\(dollars).\(String(format: "%02d", rem))"
    }
}

extension Money {
    /// Accepts "$12.34", "12.34", "12", "12.3"
    static func parse(_ s: String) -> Money? {
        let cleaned = s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")

        guard !cleaned.isEmpty else { return nil }

        // If it contains a decimal point:
        if cleaned.contains(".") {
            let parts = cleaned.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let whole = Int(parts[0].filter(\.isNumber)) else { return nil }
            let fracRaw = parts[1].filter(\.isNumber)
            let frac = fracRaw.count == 0 ? 0 :
                       fracRaw.count == 1 ? Int(fracRaw)! * 10 :
                       Int(fracRaw.prefix(2))!
            return Money(cents: whole * 100 + frac)
        } else {
            guard let whole = Int(cleaned.filter(\.isNumber)) else { return nil }
            return Money(cents: whole * 100)
        }
    }
}
