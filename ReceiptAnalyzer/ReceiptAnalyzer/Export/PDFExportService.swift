import Foundation
import UIKit
import CoreText

final class PDFExportService {

    enum ExportError: Error {
        case unableToWritePDF
    }

    // MARK: - Public

    func exportReceiptPDF(receipt: Receipt) throws -> URL {
        let url = makeTempURL(filename: safeFilename("Receipt-\(receipt.merchantName ?? "Receipt")-\(receipt.createdAt.ISO8601Short).pdf"))

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: pdfFormat())
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            fillWhiteBackground(ctx)

            var y = margin

            y = drawTitle("Receipt", in: ctx, y: y)
            y = drawSubtitle(receipt.merchantName ?? "Receipt", in: ctx, y: y)
            y = drawMetaLine("Date: \(receipt.createdAt.formatted(date: .abbreviated, time: .shortened))", in: ctx, y: y)
            y += 10
            y = drawDivider(in: ctx, y: y)

            // Items
            y += 10
            y = drawSectionHeader("Items", in: ctx, y: y)

            for item in receipt.items {
                y = ensureSpace(ctx, y: y, needed: 52)

                let assigned = assignedNames(for: item, receipt: receipt)
                y = drawRow(left: item.name, right: item.amount.formatted(), in: ctx, y: y, boldRight: true)
                y = drawSmall(assigned, in: ctx, y: y + 2)
                y += 10
                y = drawLightDivider(in: ctx, y: y)
                y += 6
            }

            // Totals
            y += 10
            y = ensureSpace(ctx, y: y, needed: 140)
            y = drawSectionHeader("Totals", in: ctx, y: y)

            let itemsSum = receipt.computedItemsSum
            let tax = receipt.tax ?? .zero
            let tip = receipt.tip ?? .zero
            let total = receipt.total ?? (itemsSum + tax + tip)

            y = drawRow(left: "Items sum", right: itemsSum.formatted(), in: ctx, y: y)
            y = drawRow(left: "Tax + Fees", right: tax.formatted(), in: ctx, y: y)
            y = drawRow(left: "Tip", right: tip.formatted(), in: ctx, y: y)
            y = drawDivider(in: ctx, y: y + 6)
            y += 12
            _ = drawRow(left: "Total", right: total.formatted(), in: ctx, y: y, boldLeft: true, boldRight: true)
        }

        try data.write(to: url, options: .atomic)
        return url
    }

    func exportPeoplePDF(receipt: Receipt) throws -> URL {
        let url = makeTempURL(filename: safeFilename("PeopleTotals-\(receipt.merchantName ?? "Receipt")-\(receipt.createdAt.ISO8601Short).pdf"))

        let result = PeopleTotalsCalculator.compute(for: receipt)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: pdfFormat())
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            fillWhiteBackground(ctx)

            var y = margin

            y = drawTitle("Totals by Person", in: ctx, y: y)
            y = drawSubtitle(receipt.merchantName ?? "Receipt", in: ctx, y: y)
            y = drawMetaLine("Date: \(receipt.createdAt.formatted(date: .abbreviated, time: .shortened))", in: ctx, y: y)
            y += 10
            y = drawDivider(in: ctx, y: y)

            if !receipt.isFullyAssigned {
                y += 10
                y = drawWarning("Some items are unassigned. Totals may be incomplete.", in: ctx, y: y)
                y += 6
                y = drawLightDivider(in: ctx, y: y)
            }

            for row in result.rows {
                y += 12
                y = ensureSpace(ctx, y: y, needed: 130)

                y = drawSectionHeader(row.name, in: ctx, y: y)

                if row.items.isEmpty {
                    y = drawSmall("No assigned items", in: ctx, y: y + 6)
                    y += 10
                } else {
                    y += 6
                    for line in row.items {
                        y = ensureSpace(ctx, y: y, needed: 18)
                        y = drawBody(line, in: ctx, y: y)
                        y += 2
                    }
                    y += 6
                }

                y = drawLightDivider(in: ctx, y: y)
                y += 8

                y = drawRow(left: "Subtotal", right: row.subtotal.formatted(), in: ctx, y: y)
                y = drawRow(left: "Tax + Fees share", right: row.taxShare.formatted(), in: ctx, y: y)
                y = drawRow(left: "Tip share", right: row.tipShare.formatted(), in: ctx, y: y)
                y = drawRow(left: "Total", right: row.total.formatted(), in: ctx, y: y, boldLeft: true, boldRight: true)
                y += 10
            }

            // Summary
            y += 14
            y = ensureSpace(ctx, y: y, needed: 190)
            y = drawDivider(in: ctx, y: y)
            y += 10
            y = drawSectionHeader("Summary", in: ctx, y: y)

            let itemsSum = receipt.computedItemsSum
            let tax = receipt.tax ?? .zero
            let tip = receipt.tip ?? .zero
            let receiptTotal = receipt.total ?? (itemsSum + tax + tip)

            y = drawRow(left: "Sum of people totals", right: result.sumTotals.formatted(), in: ctx, y: y)
            y = drawRow(left: "Receipt total", right: receiptTotal.formatted(), in: ctx, y: y)

            if result.unallocatedTotal.cents != 0 {
                y += 8
                y = drawLightDivider(in: ctx, y: y)
                y += 10
                y = drawSectionHeader("Unallocated", in: ctx, y: y)
                y = drawSmall("(from unassigned items; should be $0.00 when fully assigned)", in: ctx, y: y + 2)
                y += 10

                y = drawRow(left: "Unallocated subtotal", right: result.unallocatedSubtotal.formatted(), in: ctx, y: y)
                y = drawRow(left: "Unallocated tax + fees", right: result.unallocatedTax.formatted(), in: ctx, y: y)
                y = drawRow(left: "Unallocated tip", right: result.unallocatedTip.formatted(), in: ctx, y: y)
                _ = drawRow(left: "Unallocated total", right: result.unallocatedTotal.formatted(), in: ctx, y: y, boldLeft: true, boldRight: true)
            }
        }

        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Page + layout

    private let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @ 72 dpi
    private let margin: CGFloat = 36
    private var contentWidth: CGFloat { pageRect.width - 2 * margin }

    private func pdfFormat() -> UIGraphicsPDFRendererFormat {
        let f = UIGraphicsPDFRendererFormat()
        f.documentInfo = [
            kCGPDFContextCreator as String: "ReceiptAnalyzer",
            kCGPDFContextAuthor as String: "ReceiptAnalyzer"
        ]
        return f
    }

    private func fillWhiteBackground(_ ctx: UIGraphicsPDFRendererContext) {
        ctx.cgContext.setFillColor(UIColor.white.cgColor)
        ctx.cgContext.fill(pageRect)
    }

    private func ensureSpace(_ ctx: UIGraphicsPDFRendererContext, y: CGFloat, needed: CGFloat) -> CGFloat {
        if y + needed > pageRect.height - margin {
            ctx.beginPage()
            fillWhiteBackground(ctx)
            return margin
        }
        return y
    }

    // MARK: - Fixed PDF colors (never dynamic)

    private let pdfBlack = UIColor.black
    private let pdfGray = UIColor.darkGray
    private let pdfLightGray = UIColor.lightGray

    // MARK: - Text drawing helpers

    @discardableResult
    private func drawTitle(_ text: String, in ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        draw(text, font: .boldSystemFont(ofSize: 24), color: pdfBlack, in: ctx, y: y)
    }

    @discardableResult
    private func drawSubtitle(_ text: String, in ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        draw(text, font: .systemFont(ofSize: 16, weight: .semibold), color: pdfBlack, in: ctx, y: y + 6)
    }

    @discardableResult
    private func drawMetaLine(_ text: String, in ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        draw(text, font: .systemFont(ofSize: 12), color: pdfGray, in: ctx, y: y + 6)
    }

    @discardableResult
    private func drawSectionHeader(_ text: String, in ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        draw(text, font: .systemFont(ofSize: 14, weight: .bold), color: pdfBlack, in: ctx, y: y)
    }

    @discardableResult
    private func drawBody(_ text: String, in ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        draw(text, font: .systemFont(ofSize: 12), color: pdfBlack, in: ctx, y: y)
    }

    @discardableResult
    private func drawSmall(_ text: String, in ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        draw(text, font: .systemFont(ofSize: 11), color: pdfGray, in: ctx, y: y)
    }

    @discardableResult
    private func drawWarning(_ text: String, in ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        // Still print-friendly: black text (no orange)
        draw(text, font: .systemFont(ofSize: 12, weight: .semibold), color: pdfBlack, in: ctx, y: y)
    }

    @discardableResult
    private func drawRow(left: String,
                         right: String,
                         in ctx: UIGraphicsPDFRendererContext,
                         y: CGFloat,
                         boldLeft: Bool = false,
                         boldRight: Bool = false) -> CGFloat {

        let leftFont: UIFont = boldLeft ? .systemFont(ofSize: 12, weight: .semibold) : .systemFont(ofSize: 12)
        let rightFont: UIFont = boldRight ? .systemFont(ofSize: 12, weight: .semibold) : .systemFont(ofSize: 12)

        let leftHeight = draw(left,
                              font: leftFont,
                              color: pdfBlack,
                              rect: CGRect(x: margin, y: y, width: contentWidth * 0.68, height: 10_000),
                              in: ctx)

        let rightHeight = draw(right,
                               font: rightFont,
                               color: pdfBlack,
                               alignment: .right,
                               rect: CGRect(x: margin + contentWidth * 0.70, y: y, width: contentWidth * 0.30, height: 10_000),
                               in: ctx)

        return y + max(leftHeight, rightHeight) + 6
    }

    @discardableResult
    private func drawDivider(in ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: margin, y: y))
        p.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
        pdfLightGray.setStroke()
        p.lineWidth = 1
        p.stroke()
        return y + 1
    }

    @discardableResult
    private func drawLightDivider(in ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: margin, y: y))
        p.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
        pdfLightGray.withAlphaComponent(0.5).setStroke()
        p.lineWidth = 0.8
        p.stroke()
        return y + 1
    }

    @discardableResult
    private func draw(_ text: String,
                      font: UIFont,
                      color: UIColor,
                      in ctx: UIGraphicsPDFRendererContext,
                      y: CGFloat) -> CGFloat {
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: 10_000)
        let h = draw(text, font: font, color: color, rect: rect, in: ctx)
        return y + h
    }

    private func draw(_ text: String,
                      font: UIFont,
                      color: UIColor,
                      alignment: NSTextAlignment = .left,
                      rect: CGRect,
                      in ctx: UIGraphicsPDFRendererContext) -> CGFloat {

        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        para.lineBreakMode = .byWordWrapping

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: para
        ]

        let str = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(str)

        let targetSize = CGSize(width: rect.width, height: rect.height)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: str.length),
            nil,
            targetSize,
            nil
        )

        let drawRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: ceil(suggested.height))
        str.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(suggested.height)
    }

    // MARK: - Assigned names

    private func assignedNames(for item: ReceiptItem, receipt: Receipt) -> String {
        let ids = receipt.assignments[item.id] ?? []
        if ids.isEmpty { return "Unassigned" }
        let names = ids.compactMap { id in
            receipt.participants.first(where: { $0.id == id })?.name
        }
        return "Assigned to: " + names.joined(separator: ", ")
    }

    // MARK: - File URLs

    private func makeTempURL(filename: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    private func safeFilename(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return s.components(separatedBy: invalid).joined(separator: "-")
    }
}

private extension Date {
    var ISO8601Short: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        return f.string(from: self)
    }
}
