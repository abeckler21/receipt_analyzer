import Foundation
import Vision
import UIKit

final class OCRService {
    struct OCRResult {
        let fullText: String
        let lines: [String]
    }

    private struct BoxedLine {
        let text: String
        let bbox: CGRect // normalized
        let centerY: CGFloat
        let minX: CGFloat
    }

    func recognizeText(from images: [UIImage]) async throws -> OCRResult {
        var pageLines: [String] = []
        var fullParts: [String] = []

        for img in images {
            guard let cgImage = img.cgImage else { continue }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.02
            request.recognitionLanguages = ["en_US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            var boxed: [BoxedLine] = []

            for obs in observations {
                guard let top = obs.topCandidates(1).first else { continue }
                let b = obs.boundingBox
                boxed.append(BoxedLine(
                    text: top.string.trimmingCharacters(in: .whitespacesAndNewlines),
                    bbox: b,
                    centerY: b.midY,
                    minX: b.minX
                ))
            }

            // Sort top-to-bottom, then left-to-right
            // Note: Vision bbox origin is lower-left in normalized coords.
            boxed.sort {
                let y1 = $0.centerY
                let y2 = $1.centerY
                if abs(y1 - y2) > 0.015 { // line separation threshold
                    return y1 > y2
                } else {
                    return $0.minX < $1.minX
                }
            }

            // Merge into lines by y proximity
            var merged: [[BoxedLine]] = []
            for entry in boxed where !entry.text.isEmpty {
                if merged.isEmpty {
                    merged.append([entry])
                } else {
                    let lastLine = merged[merged.count - 1]
                    let lastY = lastLine.map(\.centerY).reduce(0, +) / CGFloat(lastLine.count)
                    if abs(entry.centerY - lastY) < 0.015 {
                        merged[merged.count - 1].append(entry)
                    } else {
                        merged.append([entry])
                    }
                }
            }

            let rebuiltLines = merged.map { lineParts -> String in
                // sort left-to-right within a line
                let sorted = lineParts.sorted { $0.minX < $1.minX }
                // join with single spaces, collapse whitespace
                let joined = sorted.map(\.text).joined(separator: " ")
                return joined.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            }

            pageLines.append(contentsOf: rebuiltLines)
            fullParts.append(rebuiltLines.joined(separator: "\n"))
        }

        let full = fullParts.joined(separator: "\n\n")
        let cleanedLines = pageLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return OCRResult(fullText: full, lines: cleanedLines)
    }
}
