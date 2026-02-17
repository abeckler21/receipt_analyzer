import SwiftUI

struct PersonTotalsView: View {
    @EnvironmentObject private var store: ReceiptStore
    let receiptID: UUID

    private var receipt: Receipt? {
        store.receipts.first(where: { $0.id == receiptID })
    }

    var body: some View {
        Group {
            if let receipt {
                let result = PeopleTotalsCalculator.compute(for: receipt)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("People Totals")
                            .font(.largeTitle)
                            .bold()
                            .padding(.top, 6)

                        // Warning / status at top
                        if !receipt.isFullyAssigned {
                            Label("Some items are unassigned. Totals may be incomplete.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.headline)
                                .padding(.bottom, 4)
                        }

                        // Person cards
                        ForEach(result.rows) { row in
                            personCard(row)
                        }

                        // Bottom reconciliation section
                        reconciliationCard(receipt: receipt, result: result)
                            .padding(.top, 10)

                        Spacer(minLength: 30)
                    }
                    .padding()
                }
                .navigationTitle("People Totals")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                Text("Receipt not found.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - UI pieces

    private func personCard(_ row: PeopleTotalsCalculator.PersonRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(row.name)
                .font(.title3)
                .bold()

            if row.items.isEmpty {
                Text("No assigned items")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(row.items, id: \.self) { line in
                        Text(line)
                            .font(.body)
                    }
                }
            }

            Divider().opacity(0.4)

            gridRow("Subtotal", row.subtotal.formatted())
            gridRow("Tax + Fees share", row.taxShare.formatted())
            gridRow("Tip share", row.tipShare.formatted())
            gridRow("Total", row.total.formatted(), bold: true)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func reconciliationCard(receipt: Receipt, result: PeopleTotalsCalculator.Result) -> some View {
        let receiptTotal = receipt.total ?? (receipt.subtotal ?? receipt.computedItemsSum) + (receipt.tax ?? .zero) + (receipt.tip ?? .zero)

        // We only declare "match" if fully assigned AND sums match (within a few cents)
        let sumsMatch = abs(result.sumTotals.cents - receiptTotal.cents) <= 2
        let shouldClaimMatch = receipt.isFullyAssigned && sumsMatch

        return VStack(alignment: .leading, spacing: 10) {
            gridRow("Sum of people totals", result.sumTotals.formatted())
            gridRow("Receipt total", receiptTotal.formatted())

            // Unallocated breakdown (this is the key fix)
            if result.unallocatedTotal.cents != 0 {
                Divider().opacity(0.4)
                Text("Unallocated (from unassigned items)")
                    .font(.headline)

                gridRow("Unallocated subtotal", result.unallocatedSubtotal.formatted())
                gridRow("Unallocated tax + fees", result.unallocatedTax.formatted())
                gridRow("Unallocated tip", result.unallocatedTip.formatted())
                gridRow("Unallocated total", result.unallocatedTotal.formatted(), bold: true)
                    .foregroundStyle(.orange)
            }

            Divider().opacity(0.4)

            if shouldClaimMatch {
                Label("Totals match.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                Label("Totals do not match yet.", systemImage: "xmark.seal.fill")
                    .foregroundStyle(.orange)
                    .font(.headline)

                if !receipt.isFullyAssigned {
                    Text("Assign all items to make totals reconcile.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func gridRow(_ left: String, _ right: String, bold: Bool = false) -> some View {
        HStack {
            Text(left)
                .foregroundStyle(.primary)
            Spacer()
            Text(right)
                .monospacedDigit()
                .fontWeight(bold ? .semibold : .regular)
        }
    }
}
