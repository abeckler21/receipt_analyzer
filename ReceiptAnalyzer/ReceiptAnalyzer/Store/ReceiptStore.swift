import Foundation
import Combine
import SwiftUI

@MainActor
final class ReceiptStore: ObservableObject {
    @Published private(set) var receipts: [Receipt] = []

    private let saveURL: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.saveURL = dir.appendingPathComponent("receipts.json")
        load()
    }

    func add(_ receipt: Receipt) {
        receipts.insert(receipt, at: 0)
        save()
    }

    func update(_ receipt: Receipt) {
        guard let idx = receipts.firstIndex(where: { $0.id == receipt.id }) else { return }
        receipts[idx] = receipt
        save()
    }

    func delete(at offsets: IndexSet) {
        receipts.remove(atOffsets: offsets)
        save()
    }

    private func load() {
        do {
            let data = try Data(contentsOf: saveURL)
            let decoded = try JSONDecoder().decode([Receipt].self, from: data)
            receipts = decoded
        } catch {
            receipts = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(receipts)
            try data.write(to: saveURL, options: [.atomic])
        } catch {
            // For a production app: surface an error banner/log
        }
    }
}

