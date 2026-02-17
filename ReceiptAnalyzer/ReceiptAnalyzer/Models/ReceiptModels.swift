import Foundation

struct Receipt: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    var merchantName: String?
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
