import SwiftUI

struct PastReceiptsView: View {
    @EnvironmentObject private var store: ReceiptStore
    @State private var showingScanFlow = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.receipts) { receipt in
                    NavigationLink {
                        ReceiptDetailView(receiptID: receipt.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(receipt.resolvedName)
                                .font(.headline)
                                .foregroundColor(.white)

                            Text(receipt.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let total = receipt.total {
                                Text("Total: \(total.formatted())")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.secondarySystemBackground))
                            .padding(.vertical, 4)
                    )
                }
                .onDelete(perform: store.delete)
            }
            .navigationTitle("Past Receipts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingScanFlow = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingScanFlow) {
                ReceiptScanFlowView()
            }
        }
    }
}
