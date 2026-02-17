import SwiftUI

struct ReceiptDetailView: View {
    @EnvironmentObject private var store: ReceiptStore
    @Environment(\.dismiss) private var dismiss

    let receiptID: UUID

    @State private var shareURL: URL?
    @State private var shareShowing = false

    // ✅ Derived, not stored in @State (prevents navigation glitches)
    private var receipt: Receipt? {
        store.receipts.first(where: { $0.id == receiptID })
    }

    var body: some View {
        Group {
            if let receipt {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header(receipt)

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(receipt.items) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.name)
                                        Spacer()
                                        Text(item.amount.formatted())
                                            .monospacedDigit()
                                    }
                                    Text(assignedNames(for: item, receipt: receipt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Divider()
                            }
                        }

                        totalsBlock(receipt)

                        if !receipt.isFullyAssigned {
                            Label("Assign all items to enable correct per-person totals.",
                                  systemImage: "info.circle")
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                        }
                    }
                    .padding()
                }
                .navigationTitle(receipt.merchantName ?? "Receipt")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        NavigationLink {
                            AssignItemsView(receiptID: receiptID)
                        } label: {
                            Text("Assign")
                        }

                        NavigationLink {
                            PersonTotalsView(receiptID: receiptID)
                        } label: {
                            Text("People")
                        }

                        Menu {
                            Button("Export Receipt PDF") { exportReceiptPDF(receipt) }
                            Button("Export People Totals PDF") { exportPeoplePDF(receipt) }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                .sheet(isPresented: $shareShowing) {
                    if let shareURL {
                        ShareSheet(activityItems: [shareURL])
                    }
                }

            } else {
                // If the receipt is temporarily missing (rare), show a stable fallback
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading receipt…")
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
    }

    // MARK: - UI helpers

    @ViewBuilder
    private func header(_ receipt: Receipt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(receipt.merchantName ?? "Receipt")
                .font(.title2).bold()
            Text(receipt.createdAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func totalsBlock(_ receipt: Receipt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let st = receipt.subtotal {
                row("Subtotal", st.formatted())
            } else {
                row("Items sum", receipt.computedItemsSum.formatted())
            }
            if let tax = receipt.tax { row("Tax + Fees", tax.formatted()) }
            if let tip = receipt.tip { row("Tip", tip.formatted()) }
            if let total = receipt.total { row("Total", total.formatted(), bold: true) }
        }
        .padding(.top, 10)
    }

    private func row(_ left: String, _ right: String, bold: Bool = false) -> some View {
        HStack {
            Text(left)
            Spacer()
            Text(right)
                .monospacedDigit()
                .fontWeight(bold ? .semibold : .regular)
        }
    }

    private func assignedNames(for item: ReceiptItem, receipt: Receipt) -> String {
        let ids = receipt.assignments[item.id] ?? []
        if ids.isEmpty { return "Unassigned" }
        let names = ids.compactMap { id in receipt.participants.first(where: { $0.id == id })?.name }
        return "Assigned to: " + names.joined(separator: ", ")
    }

    // MARK: - Export

    private func exportReceiptPDF(_ receipt: Receipt) {
        do {
            let url = try PDFExportService().exportReceiptPDF(receipt: receipt)
            shareURL = url
            shareShowing = true
        } catch {
            // In production: show alert
        }
    }

    private func exportPeoplePDF(_ receipt: Receipt) {
        do {
            let url = try PDFExportService().exportPeoplePDF(receipt: receipt)
            shareURL = url
            shareShowing = true
        } catch {
            // In production: show alert
        }
    }
}
