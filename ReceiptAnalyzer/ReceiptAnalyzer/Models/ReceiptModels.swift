import Foundation

struct Receipt: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    var merchantName: String?

    // User-editable override (persisted)
    var displayName: String? = nil

    var rawText: String = ""

    var items: [ReceiptItem] = []

    // Totals detected from receipt (if present)
    var subtotal: Money?
    var tax: Money?
    var tip: Money?
    var total: Money?

    // Assignments
    var participants: [Participant] = []
    var assignments: [UUID: [UUID]] = [:] // itemID -> [participantID]

    // Derived helpers
    var computedItemsSum: Money {
        items.reduce(.zero) { $0 + $1.amount }
    }

    var isFullyAssigned: Bool {
        // Each item must have >= 1 assignee
        items.allSatisfy { (assignments[$0.id] ?? []).isEmpty == false }
    }

    /// What to show in UI:
    /// displayName (if set) else merchantName else "Receipt"
    var resolvedName: String {
        let dn = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !dn.isEmpty { return dn }

        let mn = (merchantName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !mn.isEmpty { return mn }

        return "Receipt"
    }
}

struct ReceiptItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var amount: Money
    var originalLine: String?
}

struct Participant: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
}
