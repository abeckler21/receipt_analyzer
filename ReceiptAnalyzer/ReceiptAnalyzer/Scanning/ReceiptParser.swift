import Foundation

/// Best-effort, rule-based receipt parser.
/// Key goals:
/// - Parse item lines with quantities (e.g., "5 Coquito 80.00").
/// - Avoid header/metadata lines (zip code, table, check #, guest count, address).
/// - Treat "Service Fee"/"Service Charge"/"Auto Gratuity" as FEES, not tip.
/// - Combine Tax + Fees into the `tax` field (downstream can label it "Tax + Fees").
final class ReceiptParser {

    struct ParsedReceipt {
        var merchantName: String?
        var items: [ReceiptItem]
        var subtotal: Money?
        var tax: Money?     // tax + fees combined
        var tip: Money?     // optional user-entered tip
        var total: Money?
        var rawText: String
        var warnings: [String]
    }

    // MARK: - Public

    func parse(lines: [String], fullText: String) -> ParsedReceipt {
        var warnings: [String] = []

        let cleaned = normalize(lines)

        // Merchant: first meaningful line (skip logo junk / address / metadata)
        let merchant = cleaned.first(where: { isLikelyMerchantLine($0) })

        // Totals area: find from bottom-up
        let subtotal = findMoney(afterAnyOf: ["subtotal", "sub total"], in: cleaned, preferLast: true)

        // --- Fees handling ---
        // Many restaurants include a "Service Fee", "Service Charge", "Auto Gratuity", etc.
        // We classify these as "fees" and fold them into "tax" so downstream stays simple.
        let fee = findMoney(afterAnyOf: [
            "service fee",
            "service charge",
            "svc fee",
            "auto gratuity",
            "automatic gratuity",
            "gratuity",
            "added gratuity"
        ], in: cleaned, preferLast: true)

        // Tax only
        let taxOnly = findMoney(afterAnyOf: ["tax", "sales tax"], in: cleaned, preferLast: true)

        // Combine into tax+fees
        let taxPlusFees: Money? = {
            switch (taxOnly, fee) {
            case (nil, nil): return nil
            case (let t?, nil): return t
            case (nil, let f?): return f
            case (let t?, let f?): return t + f
            }
        }()

        // Tip: Only actual tip lines (NOT service fee / gratuity which we count as fees).
        // For many receipts, tip isn't present (user adds later).
        let tip = findMoney(afterAnyOf: ["tip"], in: cleaned, preferLast: true)

        // Total: prefer last "total / amount due / balance due"
        var total = findMoney(afterAnyOf: ["amount due", "balance due", "grand total", "total"], in: cleaned, preferLast: true)

        // Items: extract with a stricter “item line” regex.
        // We require:
        // - leading quantity (optional but allowed)
        // - name with letters
        // - trailing money
        // - line must not contain metadata keywords
        var items: [ReceiptItem] = []
        for line in cleaned {
            if isMetadataLine(line) { continue }
            if isTotalsLine(line) { continue }

            guard let parsed = parseItemLine(line) else { continue }

            // Expand qty into separate ReceiptItem entries (as requested)
            let qty = max(parsed.qty, 1)
            let each = parsed.amount / qty
            for _ in 0..<qty {
                items.append(ReceiptItem(name: parsed.name, amount: each, originalLine: line))
            }
        }

        // Dedupe identical (Vision/OCR can repeat)
        items = dedupe(items)

        if items.isEmpty {
            warnings.append("Could not confidently detect line items. Try rescanning with better lighting or edit manually.")
        }

        // Sanity checks
        if let st = subtotal {
            let sum = items.reduce(.zero) { $0 + $1.amount }
            if !within(sum, st, toleranceCents: 50) {
                warnings.append("Items sum \(sum.formatted()) does not match subtotal \(st.formatted()). You may need to edit items.")
            }
        }

        // Total sanity: if a total exists, compare to (subtotal + tax+fees + tip)
        if let st = subtotal, let tot = total {
            let tx = taxPlusFees ?? .zero
            let tp = tip ?? .zero
            let computed = st + tx + tp
            if !within(computed, tot, toleranceCents: 75) {
                // If the detected total looks like subtotal, common OCR confusion; don't override (your confirm UI computes anyway),
                // but do warn.
                warnings.append("Subtotal + tax/fees + tip \(computed.formatted()) does not match total \(tot.formatted()). Verify totals in confirmation.")
            }
        }

        // If total is missing, compute a best guess (still editable in confirmation, but helpful)
        if total == nil, let st = subtotal {
            total = st + (taxPlusFees ?? .zero) + (tip ?? .zero)
            warnings.append("Total missing; using computed total \(total!.formatted()). Verify in confirmation.")
        }

        return ParsedReceipt(
            merchantName: merchant,
            items: items,
            subtotal: subtotal,
            tax: taxPlusFees,
            tip: tip,
            total: total,
            rawText: fullText,
            warnings: warnings
        )
    }

    // MARK: - Item parsing

    /// Parses lines like:
    ///  "5 Coquito 80.00"
    ///  "1 Añejo 18.00"
    ///  "2 Desert Spoon Swizzle 32.00"
    ///
    /// Returns nil if the line does not look like an item.
    private func parseItemLine(_ line: String) -> (qty: Int, name: String, amount: Money)? {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Must have trailing money
        guard let moneyStr = trailingMoneyString(in: s),
              let amt = Money.parse(moneyStr)
        else { return nil }

        // Remove trailing money from left side
        let left = s.replacingOccurrences(of: moneyStr, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Reject if left side is basically just numbers/punctuation
        guard containsLetter(left) else { return nil }

        // Extract optional leading qty
        // Supports "5 Coquito", "5x Coquito", "5  Coquito"
        var qty = 1
        var name = left

        if let match = left.range(of: #"^\s*(\d{1,2})\s*(x|X)?\s+(.+)$"#, options: .regularExpression) {
            let matched = String(left[match])
            // Pull first number
            if let q = Int(matched.split(separator: " ").first?.filter(\.isNumber) ?? "") {
                if q >= 1 && q <= 99 {
                    qty = q
                    // Remove the leading qty token (and optional x)
                    name = left.replacingOccurrences(of: #"^\s*\d{1,2}\s*(x|X)?\s+"#, with: "", options: .regularExpression)
                }
            }
        }

        name = normalizeName(name)

        // Final filters: avoid accidental metadata names
        if isMetadataLine(name) { return nil }
        if isTotalsLine(name) { return nil }

        return (qty, name, amt)
    }

    // MARK: - Totals parsing

    private func findMoney(afterAnyOf keywords: [String], in lines: [String], preferLast: Bool) -> Money? {
        let indexed = lines.enumerated().map { ($0.offset, $0.element) }
        let seq = preferLast ? indexed.reversed() : indexed

        for (_, line) in seq {
            let lower = line.lowercased()
            if keywords.contains(where: { lower.contains($0) }) {
                if let trailing = trailingMoneyString(in: line), let m = Money.parse(trailing) { return m }
                if let embedded = firstMoneyString(in: line), let m = Money.parse(embedded) { return m }
            }
        }
        return nil
    }

    // MARK: - Line classification

    private func isTotalsLine(_ line: String) -> Bool {
        let l = line.lowercased()
        return containsAny(l, [
            "subtotal", "sub total",
            "tax", "sales tax",
            "tip",
            "service fee", "service charge", "svc fee",
            "auto gratuity", "automatic gratuity", "gratuity",
            "total", "grand total", "amount due", "balance due"
        ])
    }

    /// Lines that should never be considered items (even if OCR adds weird spacing).
    private func isMetadataLine(_ line: String) -> Bool {
        let l = line.lowercased()

        // Common metadata keywords
        if containsAny(l, [
            "server", "check", "guest", "table", "ordered", "order", "date", "time",
            "powered by", "toast",
            "address", "ave", "st", "street", "road", "rd", "blvd", "suite",
            "chicago", "il"
        ]) {
            return true
        }

        // Zip code patterns (5 digits, or 5+4)
        if l.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil {
            // BUT don't exclude item lines that happen to include a year like "Ensamble 40" (not 5 digits).
            // This regex is 5 digits so it's safe.
            return true
        }

        // "Check #27" or "#27"
        if l.range(of: #"\bcheck\s*#?\s*\d+\b"#, options: .regularExpression) != nil { return true }
        if l.range(of: #"\btable\s*\d+\b"#, options: .regularExpression) != nil { return true }
        if l.range(of: #"\bguest\s*count\s*:\s*\d+\b"#, options: .regularExpression) != nil { return true }

        // Timestamp like "1/31/26 9:10 PM"
        if l.range(of: #"\b\d{1,2}/\d{1,2}/\d{2,4}\b"#, options: .regularExpression) != nil { return true }
        if containsAny(l, ["am", "pm"]) && l.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression) != nil { return true }

        return false
    }

    private func isLikelyMerchantLine(_ line: String) -> Bool {
        let l = line.lowercased()
        if l.count < 3 { return false }
        if isMetadataLine(l) { return false }
        if isTotalsLine(l) { return false }
        // Avoid lines that look like item lines (they usually have trailing money)
        if trailingMoneyString(in: line) != nil { return false }
        // Prefer lines with letters and without too many digits
        return containsLetter(line) && digitCount(line) <= 2
    }

    // MARK: - Normalization & utilities

    private func normalize(_ lines: [String]) -> [String] {
        lines
            .map { $0.replacingOccurrences(of: "\t", with: " ") }
            .map { $0.replacingOccurrences(of: "  ", with: " ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizeName(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove stray leading punctuation
        out = out.replacingOccurrences(of: #"^[\-\*\•\·]+"#, with: "", options: .regularExpression)
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return out
    }

    private func trailingMoneyString(in line: String) -> String? {
        // Match last token that looks like money; supports "$80.00" or "80.00" or "80"
        // (but we mostly see cents for receipts)
        let pattern = #"(\$?\d{1,6}(?:\.\d{1,2})?)\s*$"#
        guard let r = line.range(of: pattern, options: .regularExpression) else { return nil }
        return String(line[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstMoneyString(in line: String) -> String? {
        let pattern = #"\$?\d{1,6}(\.\d{1,2})?"#
        guard let r = line.range(of: pattern, options: .regularExpression) else { return nil }
        return String(line[r])
    }

    private func containsAny(_ s: String, _ needles: [String]) -> Bool {
        needles.contains(where: { s.contains($0) })
    }

    private func containsLetter(_ s: String) -> Bool {
        s.rangeOfCharacter(from: .letters) != nil
    }

    private func digitCount(_ s: String) -> Int {
        s.filter(\.isNumber).count
    }

    private func within(_ a: Money, _ b: Money, toleranceCents: Int) -> Bool {
        abs(a.cents - b.cents) <= toleranceCents
    }

    private func dedupe(_ items: [ReceiptItem]) -> [ReceiptItem] {
        var seen: Set<String> = []
        var out: [ReceiptItem] = []
        for it in items {
            let key = "\(it.name.lowercased())|\(it.amount.cents)"
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(it)
        }
        return out
    }
}
