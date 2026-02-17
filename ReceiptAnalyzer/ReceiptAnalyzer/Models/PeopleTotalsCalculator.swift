import Foundation

struct PeopleTotalsCalculator {

    struct PersonRow: Identifiable {
        let id: UUID
        let name: String
        let items: [String]
        let subtotal: Money
        var taxShare: Money
        var tipShare: Money
        var total: Money { subtotal + taxShare + tipShare }
    }

    struct Result {
        let rows: [PersonRow]
        let sumSubtotals: Money
        let sumTax: Money
        let sumTip: Money
        let sumTotals: Money

        let unallocatedSubtotal: Money
        let unallocatedTax: Money
        let unallocatedTip: Money
        let unallocatedTotal: Money
    }

    static func compute(for receipt: Receipt) -> Result {
        // Base for proportional allocation is ALWAYS items sum (pre-tax)
        let receiptSubtotal = receipt.computedItemsSum

        // In your pipeline, receipt.tax already represents "Tax + Fees"
        let receiptTax = receipt.tax ?? .zero
        let receiptTip = receipt.tip ?? .zero

        // 1) Build per-person subtotals from assigned items only
        var personSub: [UUID: Money] = [:]
        var personLines: [UUID: [String]] = [:]

        for item in receipt.items {
            let assignees = receipt.assignments[item.id] ?? []
            guard !assignees.isEmpty else { continue }

            let each = item.amount / assignees.count
            for pid in assignees {
                personSub[pid, default: .zero] = personSub[pid, default: .zero] + each

                let label = assignees.count > 1
                ? "\(item.name) (split) — \(each.formatted())"
                : "\(item.name) — \(each.formatted())"

                personLines[pid, default: []].append(label)
            }
        }

        // 2) Compute shares (rounded) using receiptSubtotal as denominator
        func ratio(for sub: Money) -> Double {
            guard receiptSubtotal.cents > 0 else { return 0 }
            return Double(sub.cents) / Double(receiptSubtotal.cents)
        }

        var rows: [PersonRow] = receipt.participants
            .sorted(by: { $0.name.lowercased() < $1.name.lowercased() })
            .map { p in
                let sub = personSub[p.id] ?? .zero
                let r = ratio(for: sub)

                let taxShare = Money(cents: Int((Double(receiptTax.cents) * r).rounded()))
                let tipShare = Money(cents: Int((Double(receiptTip.cents) * r).rounded()))

                return PersonRow(
                    id: p.id,
                    name: p.name,
                    items: personLines[p.id] ?? [],
                    subtotal: sub,
                    taxShare: taxShare,
                    tipShare: tipShare
                )
            }

        // 3) Compute sums + unallocated (before reconciliation)
        func sums(from rows: [PersonRow]) -> (Money, Money, Money, Money) {
            let sumSub = rows.reduce(.zero) { $0 + $1.subtotal }
            let sumTax = rows.reduce(.zero) { $0 + $1.taxShare }
            let sumTip = rows.reduce(.zero) { $0 + $1.tipShare }
            let sumTot = rows.reduce(.zero) { $0 + $1.total }
            return (sumSub, sumTax, sumTip, sumTot)
        }

        var (sumSub, sumTax, sumTip, sumTot) = sums(from: rows)

        var unallocSub = receiptSubtotal - sumSub
        var unallocTax = receiptTax - sumTax
        var unallocTip = receiptTip - sumTip
        var unallocTotal = unallocSub + unallocTax + unallocTip

        // 4) Exact reconciliation ONLY when all items are assigned:
        // Force tax/tip shares to sum EXACTLY to receiptTax/receiptTip by applying remainder
        // (positive OR negative) to the last alphabetical person.
        if receipt.isFullyAssigned, !rows.isEmpty {
            if unallocSub.cents == 0 {
                let lastIdx = rows.count - 1
                var last = rows[lastIdx]

                // Apply the full remainder (can be negative or positive).
                // This guarantees sumTax == receiptTax and sumTip == receiptTip.
                if unallocTax.cents != 0 {
                    last.taxShare = last.taxShare + unallocTax
                }
                if unallocTip.cents != 0 {
                    last.tipShare = last.tipShare + unallocTip
                }

                rows[lastIdx] = last

                // Recompute after reconciliation
                (sumSub, sumTax, sumTip, sumTot) = sums(from: rows)
                unallocSub = receiptSubtotal - sumSub
                unallocTax = receiptTax - sumTax
                unallocTip = receiptTip - sumTip
                unallocTotal = unallocSub + unallocTax + unallocTip
            }
        }

        return Result(
            rows: rows,
            sumSubtotals: sumSub,
            sumTax: sumTax,
            sumTip: sumTip,
            sumTotals: sumTot,
            unallocatedSubtotal: unallocSub,
            unallocatedTax: unallocTax,
            unallocatedTip: unallocTip,
            unallocatedTotal: unallocTotal
        )
    }
}
