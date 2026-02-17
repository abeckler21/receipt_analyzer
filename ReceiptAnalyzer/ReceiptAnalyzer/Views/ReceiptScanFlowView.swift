import SwiftUI

struct ReceiptScanFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReceiptStore

    @State private var scanning = true
    @State private var isProcessing = false
    @State private var errorMessage: String?

    @State private var scannedImages: [UIImage] = []
    @State private var parsed: ReceiptParser.ParsedReceipt?

    private let ocr = OCRService()
    private let parser = ReceiptParser()

    var body: some View {
        NavigationStack {
            Group {
                if scanning {
                    DocumentScannerView { result in
                        switch result {
                        case .success(let images):
                            scannedImages = images
                            scanning = false
                            Task { await process() }
                        case .failure(let err):
                            errorMessage = err.localizedDescription
                            scanning = false
                        }
                    }
                    .ignoresSafeArea()
                } else if isProcessing {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Reading receipt…")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else if let parsed {
                    ReceiptConfirmView(parsed: parsed) { confirmedReceipt in
                        store.add(confirmedReceipt)
                        dismiss()
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                        Text(errorMessage ?? "Could not scan receipt.")
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            errorMessage = nil
                            scanning = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Close") { dismiss() }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                }
            }
            .navigationTitle("New Receipt")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func process() async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            let ocrResult = try await ocr.recognizeText(from: scannedImages)
            let parsedReceipt = parser.parse(lines: ocrResult.lines, fullText: ocrResult.fullText)
            parsed = parsedReceipt
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
