import Foundation
import SwiftUI
import UIKit

final class PDFExportService {

    func exportReceiptPDF(receipt: Receipt) throws -> URL {
        let view = ReceiptPDFView(receipt: receipt)
        return try renderSwiftUIPDF(view: view, filename: "Receipt-\(receipt.id).pdf")
    }

    func exportPeoplePDF(receipt: Receipt) throws -> URL {
        let view = PeoplePDFView(receipt: receipt)
        return try renderSwiftUIPDF(view: view, filename: "People-\(receipt.id).pdf")
    }

    private func renderSwiftUIPDF<V: View>(view: V, filename: String) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()

            let host = UIHostingController(rootView: view)
            host.view.bounds = CGRect(x: 0, y: 0, width: pageRect.width, height: pageRect.height)
            host.view.backgroundColor = .white

            host.view.layer.render(in: ctx.cgContext)
        }

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = dir.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        return url
    }
}

// MARK: - PDF SwiftUI layouts

private struct ReceiptPDFView: View {
    let receipt: Receipt

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(receipt.merchantName ?? "Receipt")
                .font(.system(size: 22, weight: .bold))
            Text(receipt.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 8) {
                ForEach(receipt.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.name)
                                .font(.system(size: 12))
                            Spacer()
                            Text(item.amount.formatted())
                                .font(.system(size: 12, design: .monospaced))
                        }
                        Text(assignedNames(for: item))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
            totals
            Spacer()
        }
        .padding(28)
        .frame(width: 612, height: 792)
        .background(Color.white)
    }

    private var totals: some View {
        let st = receipt.subtotal ?? receipt.computedItemsSum
        let tax = receipt.tax ?? .zero
        let tip = receipt.tip ?? .zero

        return VStack(alignment: .leading, spacing: 6) {
            row("Subtotal", st.formatted())
            if receipt.tax != nil { row("Tax", tax.formatted()) }
            if receipt.tip != nil { row("Tip", tip.formatted()) }
            if let total = receipt.total { row("Total", total.formatted(), bold: true) }
        }
        .padding(.top, 6)
    }

    private func row(_ l: String, _ r: String, bold: Bool = false) -> some View {
        HStack {
            Text(l).font(.system(size: 12))
            Spacer()
            Text(r)
                .font(.system(size: 12, weight: bold ? .semibold : .regular, design: .monospaced))
        }
    }

    private func assignedNames(for item: ReceiptItem) -> String {
        let ids = receipt.assignments[item.id] ?? []
        if ids.isEmpty { return "Unassigned" }
        let names = ids.compactMap { id in receipt.participants.first(where: { $0.id == id })?.name }
        return "Assigned to: " + names.joined(separator: ", ")
    }
}

private struct PeoplePDFView: View {
    let receipt: Receipt

    var body: some View {
        let r = PeopleTotalsCalculator.compute(for: receipt)

        VStack(alignment: .leading, spacing: 12) {
            Text("People Totals")
                .font(.system(size: 22, weight: .bold))
            Text(receipt.merchantName ?? "")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Divider()

            ForEach(r.rows) { p in
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.name)
                        .font(.system(size: 14, weight: .semibold))

                    ForEach(p.items, id: \.self) { line in
                        Text("• \(line)")
                            .font(.system(size: 11))
                    }

                    HStack { Text("Subtotal").font(.system(size: 11)); Spacer()
                        Text(p.subtotal.formatted()).font(.system(size: 11, design: .monospaced))
                    }
                    HStack { Text("Tax").font(.system(size: 11)); Spacer()
                        Text(p.taxShare.formatted()).font(.system(size: 11, design: .monospaced))
                    }
                    HStack { Text("Tip").font(.system(size: 11)); Spacer()
                        Text(p.tipShare.formatted()).font(.system(size: 11, design: .monospaced))
                    }
                    HStack { Text("Total").font(.system(size: 12, weight: .semibold)); Spacer()
                        Text(p.total.formatted()).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }

                    Divider()
                }
            }

            Spacer()

            // Key point: we do NOT “force” totals to match if items are unassigned.
            HStack {
                Text("Sum of assigned totals").font(.system(size: 12))
                Spacer()
                Text(r.sumTotals.formatted()).font(.system(size: 12, design: .monospaced))
            }
            if let receiptTotal = receipt.total {
                HStack {
                    Text("Receipt total").font(.system(size: 12))
                    Spacer()
                    Text(receiptTotal.formatted()).font(.system(size: 12, design: .monospaced))
                }
            }

            if r.unallocatedTotal.cents > 0 {
                Text("Unallocated (unassigned items / tax / tip): \(r.unallocatedTotal.formatted())")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(width: 612, height: 792)
        .background(Color.white)
    }
}
