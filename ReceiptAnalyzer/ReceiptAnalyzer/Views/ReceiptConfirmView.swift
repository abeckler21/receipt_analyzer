import SwiftUI

struct ReceiptConfirmView: View {
    let parsed: ReceiptParser.ParsedReceipt
    let onConfirm: (Receipt) -> Void

    struct EditableLineItem: Identifiable, Equatable {
        var id: UUID = UUID()
        var name: String
        var unitPrice: Money
        var quantity: Int
        var originalLine: String?
        var lineTotal: Money { unitPrice * max(quantity, 1) }
    }

    @State private var merchant: String = ""
    @State private var lineItems: [EditableLineItem] = []

    @State private var subtotalText: String = ""
    @State private var taxText: String = ""
    @State private var tipText: String = ""

    @State private var warnings: [String] = []
    @State private var showAdvancedRawText = false

    var body: some View {
        Form {
            if !warnings.isEmpty {
                Section {
                    ForEach(warnings, id: \.self) { w in
                        Label(w, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Receipt") {
                TextField("Merchant (optional)", text: $merchant)
                Text("Edit items and totals until everything looks right. Total is always computed as items sum + tax + tip.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Section("Items") {
                ForEach(lineItems.indices, id: \.self) { idx in
                    itemEditorRow(idx: idx)
                }
                .onDelete(perform: deleteItems)

                Button {
                    addNewItem()
                } label: {
                    Label("Add item", systemImage: "plus")
                }
            }

            Section("Totals") {
                LabeledContent("Items sum") {
                    Text(itemsSum.formatted())
                        .monospacedDigit()
                }

                // Keep subtotal editable if you want it for validation,
                // but it does NOT drive total anymore.
                moneyField("Subtotal", text: $subtotalText)

                moneyField("Tax + Fees", text: $taxText)

                // Tip with a leading dollar sign UI
                tipField()

                // Total is read-only and ALWAYS computed from items sum + tax + tip
                HStack {
                    Text("Total")
                    Spacer()
                    Text(computedTotal.formatted())
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }

                Button("Re-check totals") {
                    recomputeWarnings()
                }
            }

            Section {
                Button {
                    onConfirm(buildReceipt())
                } label: {
                    Text("Confirm & Assign Items")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
            }

            Section {
                Button(showAdvancedRawText ? "Hide OCR Text" : "Show OCR Text (debug)") {
                    showAdvancedRawText.toggle()
                }

                if showAdvancedRawText {
                    Text(parsed.rawText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .onAppear {
            merchant = parsed.merchantName ?? ""
            lineItems = groupParsedItems(parsed.items)

            subtotalText = parsed.subtotal?.formatted() ?? ""
            taxText = parsed.tax?.formatted() ?? ""
            tipText = parsed.tip?.formatted() ?? ""

            warnings = parsed.warnings
            recomputeWarnings()
        }
        .onChange(of: lineItems) { _ in recomputeWarnings() }
        .onChange(of: subtotalText) { _ in recomputeWarnings() }
        .onChange(of: taxText) { _ in recomputeWarnings() }
        .onChange(of: tipText) { _ in recomputeWarnings() }
    }

    // MARK: - UI

    @ViewBuilder
    private func itemEditorRow(idx: Int) -> some View {
        let binding = Binding<EditableLineItem>(
            get: { lineItems[idx] },
            set: { lineItems[idx] = $0 }
        )

        VStack(alignment: .leading, spacing: 10) {
            TextField("Item name", text: binding.name)
                .textInputAutocapitalization(.words)

            HStack(spacing: 12) {
                Stepper(value: binding.quantity, in: 1...99) {
                    Text("Qty \(binding.quantity.wrappedValue)")
                }
                .labelsHidden()

                Text("Qty")
                    .foregroundStyle(.secondary)
                Text("\(binding.quantity.wrappedValue)")
                    .monospacedDigit()
                    .frame(width: 26, alignment: .leading)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    TextField("$0.00", text: Binding(
                        get: { binding.unitPrice.wrappedValue.formatted() },
                        set: { newVal in
                            if let m = Money.parse(newVal) {
                                binding.unitPrice.wrappedValue = m
                            }
                        }
                    ))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(width: 120)

                    Text("Line: \(binding.wrappedValue.lineTotal.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func moneyField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("$0.00", text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(width: 160)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func tipField() -> some View {
        HStack {
            Text("Tip")
            Spacer()

            // Dollar sign prefix + numeric field
            HStack(spacing: 6) {
                TextField("$0.00", text: $tipText)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .monospacedDigit()
                    .frame(width: 120)
            }
            .frame(width: 160, alignment: .trailing)
        }
    }

    // MARK: - Actions

    private func deleteItems(at offsets: IndexSet) {
        lineItems.remove(atOffsets: offsets)
    }

    private func addNewItem() {
        lineItems.append(
            EditableLineItem(
                name: "New item",
                unitPrice: .zero,
                quantity: 1,
                originalLine: nil
            )
        )
    }

    // MARK: - Totals

    private var itemsSum: Money {
        lineItems.reduce(.zero) { $0 + $1.lineTotal }
    }

    /// Per your request: Total ALWAYS equals items sum + tax + tip (subtotal does not affect this).
    private var computedTotal: Money {
        let tx = Money.parse(taxText) ?? .zero
        let tp = Money.parse(tipText) ?? .zero
        return itemsSum + tx + tp
    }

    private func recomputeWarnings() {
        var w: [String] = []

        // Subtotal is optional: warn if it doesn't match items sum (helpful sanity check)
        if let st = Money.parse(subtotalText) {
            if abs(itemsSum.cents - st.cents) > 25 {
                w.append("Items sum \(itemsSum.formatted()) does not match subtotal \(st.formatted()).")
            }
        } else {
            w.append("Subtotal is missing — optional, but recommended for verification.")
        }

        // We can still warn about total mismatch vs OCR-provided total if you ever display it,
        // but since we compute total now, we mainly just ensure tax/tip parsing is sane.
        // If tax/tip are present, computedTotal is definitive.
        warnings = w
    }

    // MARK: - Build Receipt model

    private func buildReceipt() -> Receipt {
        let st = Money.parse(subtotalText)
        let tx = Money.parse(taxText)
        let tp = Money.parse(tipText)

        // Total is always computed from itemsSum + tax + tip
        let tt = computedTotal

        // Expand quantities into separate ReceiptItem entries
        var expanded: [ReceiptItem] = []
        for li in lineItems {
            let qty = max(li.quantity, 1)
            for _ in 0..<qty {
                expanded.append(
                    ReceiptItem(
                        name: li.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        amount: li.unitPrice,
                        originalLine: li.originalLine
                    )
                )
            }
        }

        return Receipt(
            createdAt: Date(),
            merchantName: merchant.isEmpty ? parsed.merchantName : merchant,
            rawText: parsed.rawText,
            items: expanded,
            subtotal: st,
            tax: tx,
            tip: tp,
            total: tt,
            participants: [],
            assignments: [:]
        )
    }

    // MARK: - Grouping duplicates into quantity

    private func groupParsedItems(_ items: [ReceiptItem]) -> [EditableLineItem] {
        var map: [String: EditableLineItem] = [:]
        var order: [String] = []

        for it in items {
            let key = "\(it.name.lowercased())|\(it.amount.cents)"
            if var existing = map[key] {
                existing.quantity += 1
                map[key] = existing
            } else {
                map[key] = EditableLineItem(
                    name: it.name,
                    unitPrice: it.amount,
                    quantity: 1,
                    originalLine: it.originalLine
                )
                order.append(key)
            }
        }

        return order.compactMap { map[$0] }
    }
}
