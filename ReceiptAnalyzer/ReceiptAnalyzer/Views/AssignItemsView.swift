import SwiftUI

struct AssignItemsView: View {
    @EnvironmentObject private var store: ReceiptStore
    @Environment(\.dismiss) private var dismiss

    let receiptID: UUID

    @State private var receipt: Receipt?
    @State private var participantDraft: String = ""
    @State private var expandedItemID: UUID? = nil

    enum AssignMode: String, CaseIterable, Identifiable {
        case quick = "Quick"
        case detailed = "Detailed"
        var id: String { rawValue }
    }

    @State private var mode: AssignMode = .quick
    @State private var selectedParticipantID: UUID? = nil

    var body: some View {
        Group {
            if let receipt {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        // Participants + mode controls
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Participants")
                                    .font(.headline)
                                Spacer()
                                Picker("", selection: $mode) {
                                    ForEach(AssignMode.allCases) { m in
                                        Text(m.rawValue).tag(m)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 210)
                            }

                            HStack(spacing: 8) {
                                TextField("Add name (max 10)", text: $participantDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .submitLabel(.done)
                                    .onSubmit { addParticipant() }

                                Button {
                                    addParticipant()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                }
                                .disabled(!canAddParticipant)
                            }

                            if receipt.participants.isEmpty {
                                Text("Add at least one participant.")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            } else {
                                ParticipantChips(
                                    participants: receipt.participants,
                                    selectedID: selectedParticipantID,
                                    mode: mode,
                                    onSelect: { pid in
                                        selectedParticipantID = (selectedParticipantID == pid) ? nil : pid
                                    },
                                    onRemove: { p in removeParticipant(p) }
                                )

                                // Helper text is now BELOW chips (no overlap)
                                if mode == .quick {
                                    if selectedParticipantID == nil {
                                        Text("Quick mode: select a person, then tap items to assign/unassign.")
                                            .foregroundStyle(.secondary)
                                            .font(.footnote)
                                    } else if let name = receipt.participants.first(where: { $0.id == selectedParticipantID })?.name {
                                        Label("Quick assigning as \(name). Tap items to toggle.",
                                              systemImage: "bolt.fill")
                                            .foregroundStyle(.secondary)
                                            .font(.footnote)
                                    }
                                } else {
                                    Text("Detailed mode: tap an item to expand and multi-assign (split).")
                                        .foregroundStyle(.secondary)
                                        .font(.footnote)
                                }
                            }
                        }
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        // Readiness + mismatch warnings
                        VStack(alignment: .leading, spacing: 8) {
                            let st = receipt.subtotal ?? receipt.computedItemsSum
                            let itemSum = receipt.computedItemsSum
                            let tax = receipt.tax ?? .zero
                            let tip = receipt.tip ?? .zero
                            let total = receipt.total

                            HStack {
                                Label(receipt.isFullyAssigned ? "All items assigned" : "Unassigned items remain",
                                      systemImage: receipt.isFullyAssigned ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(receipt.isFullyAssigned ? .green : .orange)
                                Spacer()
                            }

                            if abs(itemSum.cents - st.cents) > 25 {
                                Label("Items sum \(itemSum.formatted()) ≠ subtotal \(st.formatted()). Edit receipt if needed.",
                                      systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                    .font(.subheadline)
                            }

                            if let total {
                                let computed = st + tax + tip
                                if abs(computed.cents - total.cents) > 25 {
                                    Label("Subtotal+tax+tip \(computed.formatted()) ≠ total \(total.formatted()).",
                                          systemImage: "exclamationmark.triangle")
                                        .foregroundStyle(.orange)
                                        .font(.subheadline)
                                }
                            }
                        }
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        // Items
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Assign Items")
                                .font(.headline)

                            ForEach(receipt.items) { item in
                                ItemAssignRow(
                                    item: item,
                                    receipt: receipt,
                                    mode: mode,
                                    selectedParticipantID: selectedParticipantID,
                                    isExpanded: expandedItemID == item.id,
                                    onTapRow: { handleTapItem(item) },
                                    onToggleExpand: {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            expandedItemID = (expandedItemID == item.id) ? nil : item.id
                                        }
                                    },
                                    onToggleAssignee: { pid in
                                        toggleAssignee(itemID: item.id, participantID: pid)
                                    }
                                )
                            }
                        }
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        Button {
                            persist()
                            dismiss()
                        } label: {
                            Text("Done")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)

                        NavigationLink {
                            ReceiptDetailView(receiptID: receiptID)
                        } label: {
                            Text("View Receipt")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.bottom, 30)
                    }
                    .padding()
                }
                .navigationTitle("Assign")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            persist()
                            dismiss()
                        }
                    }
                }
                .onAppear { reloadAndFixSelection() }
                .onChange(of: store.receipts) { _ in reloadAndFixSelection() }
            } else {
                ProgressView().task { reloadAndFixSelection() }
            }
        }
    }

    private func handleTapItem(_ item: ReceiptItem) {
        switch mode {
        case .quick:
            guard let pid = selectedParticipantID else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedItemID = (expandedItemID == item.id) ? nil : item.id
                }
                return
            }
            toggleAssignee(itemID: item.id, participantID: pid)

        case .detailed:
            withAnimation(.easeInOut(duration: 0.15)) {
                expandedItemID = (expandedItemID == item.id) ? nil : item.id
            }
        }
    }

    private var canAddParticipant: Bool {
        guard let receipt else { return false }
        let name = participantDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && receipt.participants.count < 10
    }

    private func reloadAndFixSelection() {
        receipt = store.receipts.first(where: { $0.id == receiptID })
        guard let receipt else { return }

        if let sel = selectedParticipantID,
           receipt.participants.contains(where: { $0.id == sel }) == false {
            selectedParticipantID = nil
        }

        if mode == .quick, selectedParticipantID == nil, receipt.participants.count == 1 {
            selectedParticipantID = receipt.participants.first?.id
        }
    }

    private func persist() {
        guard let receipt else { return }
        store.update(receipt)
    }

    private func addParticipant() {
        guard var r = receipt else { return }
        let name = participantDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, r.participants.count < 10 else { return }

        if r.participants.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            participantDraft = ""
            return
        }

        let p = Participant(name: name)
        r.participants.append(p)
        receipt = r
        participantDraft = ""

        if mode == .quick {
            selectedParticipantID = p.id
        }

        persist()
    }

    private func removeParticipant(_ p: Participant) {
        guard var r = receipt else { return }
        r.participants.removeAll { $0.id == p.id }

        for item in r.items {
            var arr = r.assignments[item.id] ?? []
            arr.removeAll { $0 == p.id }
            r.assignments[item.id] = arr
        }

        receipt = r
        if selectedParticipantID == p.id { selectedParticipantID = nil }
        persist()
    }

    private func toggleAssignee(itemID: UUID, participantID: UUID) {
        guard var r = receipt else { return }
        var arr = r.assignments[itemID] ?? []
        if let idx = arr.firstIndex(of: participantID) {
            arr.remove(at: idx)
        } else {
            arr.append(participantID)
        }
        r.assignments[itemID] = arr
        receipt = r
        persist()
    }
}

// MARK: - Row

private struct ItemAssignRow: View {
    let item: ReceiptItem
    let receipt: Receipt

    let mode: AssignItemsView.AssignMode
    let selectedParticipantID: UUID?

    let isExpanded: Bool
    let onTapRow: () -> Void
    let onToggleExpand: () -> Void
    let onToggleAssignee: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            Button(action: onTapRow) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.body)
                            .foregroundStyle(.primary)

                        Text(assignedNames)
                            .font(.caption)
                            .foregroundStyle(assignedNames == "Unassigned" ? .orange : .secondary)
                    }
                    Spacer()

                    if mode == .quick, let pid = selectedParticipantID {
                        let selectedOnThisItem = (receipt.assignments[item.id] ?? []).contains(pid)
                        Image(systemName: selectedOnThisItem ? "bolt.fill" : "bolt")
                            .foregroundStyle(.secondary)
                    }

                    Text(item.amount.formatted())
                        .monospacedDigit()

                    if mode == .detailed || selectedParticipantID == nil {
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(receipt.participants) { p in
                        let selected = (receipt.assignments[item.id] ?? []).contains(p.id)
                        Button {
                            onToggleAssignee(p.id)
                        } label: {
                            HStack {
                                Text(p.name)
                                Spacer()
                                if selected { Image(systemName: "checkmark") }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.top, 2)
            }

            Divider()
        }
        .onLongPressGesture { onToggleExpand() }
    }

    private var assignedNames: String {
        let ids = receipt.assignments[item.id] ?? []
        if ids.isEmpty { return "Unassigned" }
        let names = ids.compactMap { id in receipt.participants.first(where: { $0.id == id })?.name }
        return "Assigned to: " + names.joined(separator: ", ")
    }
}

// MARK: - Chips using a real Flow Layout (no overlap, no gap)

private struct ParticipantChips: View {
    let participants: [Participant]
    let selectedID: UUID?
    let mode: AssignItemsView.AssignMode
    let onSelect: (UUID) -> Void
    let onRemove: (Participant) -> Void

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(participants) { p in
                chip(p)
            }
        }
        .padding(.top, 4)
    }

    private func chip(_ p: Participant) -> some View {
        let isSelected = (mode == .quick && selectedID == p.id)

        return HStack(spacing: 8) {
            Button {
                if mode == .quick { onSelect(p.id) }
            } label: {
                HStack(spacing: 6) {
                    Text(p.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(isSelected ? .white : .primary)

                    if mode == .quick {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(mode != .quick)

            Button { onRemove(p) } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(isSelected ? Color.accentColor : Color(UIColor.secondarySystemBackground))
        .clipShape(Capsule())
    }
}

/// A proper wrapping layout (iOS 16+). This replaces the old GeometryReader alignment-guide hack.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? UIScreen.main.bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            s.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
