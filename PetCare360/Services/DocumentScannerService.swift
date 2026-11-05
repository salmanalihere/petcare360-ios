import Foundation
import Vision
import UIKit

/// Candidate fields extracted from a scanned document. Nothing is saved
/// automatically — the user reviews and confirms every field first.
struct ScannedDocumentCandidate {
    var fullText: String = ""
    var category: MedicalCategory = .note
    var petName: String = ""
    var clinic: String = ""
    var documentDate: Date? = nil
    var medicationName: String = ""
    var vaccinationName: String = ""
    var expirationDate: Date? = nil
    var invoiceAmount: Decimal? = nil
}

protocol DocumentScanning {
    func recognizeText(in image: UIImage) async throws -> String
}

/// On-device OCR using Apple's Vision framework. No image ever leaves the device.
final class VisionDocumentScanner: DocumentScanning {
    func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let text = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}

/// Heuristic field extraction from OCR text. Deliberately conservative:
/// it proposes candidates for the review screen, never final records.
enum DocumentTextParser {
    static func parse(_ text: String, knownPetNames: [String] = []) -> ScannedDocumentCandidate {
        var candidate = ScannedDocumentCandidate(fullText: text)
        let lower = text.lowercased()
        if lower.contains("vaccin") {
            candidate.category = .vaccination
            candidate.vaccinationName = firstLine(containing: "vaccin", in: text)
        } else if lower.contains("prescription") || lower.contains("rx") {
            candidate.category = .prescription
        } else if lower.contains("invoice") || lower.contains("total due") {
            candidate.category = .note
            candidate.invoiceAmount = firstCurrencyAmount(in: text)
        } else if lower.contains("lab") || lower.contains("blood") {
            candidate.category = .labResult
        } else if lower.contains("insurance") {
            candidate.category = .insurance
        }
        if let medLine = text.split(separator: "\n").first(where: { $0.lowercased().contains("mg") }) {
            candidate.medicationName = medLine.trimmingCharacters(in: .whitespaces)
        }
        for name in knownPetNames where lower.contains(name.lowercased()) {
            candidate.petName = name
            break
        }
        let dates = extractDates(from: text)
        candidate.documentDate = dates.first
        if dates.count > 1 { candidate.expirationDate = dates.last }
        if let clinicLine = text.split(separator: "\n").first(where: {
            let l = $0.lowercased()
            return l.contains("clinic") || l.contains("veterinary") || l.contains("animal hospital")
        }) {
            candidate.clinic = clinicLine.trimmingCharacters(in: .whitespaces)
        }
        return candidate
    }

    static func firstLine(containing needle: String, in text: String) -> String {
        text.split(separator: "\n").first { $0.lowercased().contains(needle) }
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    static func firstCurrencyAmount(in text: String) -> Decimal? {
        let pattern = #"\$\s?([0-9]+(?:\.[0-9]{2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Decimal(string: String(text[range]))
    }

    static func extractDates(from text: String) -> [Date] {
        let formats = ["MM/dd/yyyy", "yyyy-MM-dd", "MMM d, yyyy", "MMMM d, yyyy"]
        var found: [Date] = []
        let words = text.components(separatedBy: CharacterSet(charactersIn: "\n,"))
        for chunk in words {
            let trimmed = chunk.trimmingCharacters(in: .whitespaces)
            for format in formats {
                let formatter = DateFormatter()
                formatter.dateFormat = format
                formatter.locale = Locale(identifier: "en_US_POSIX")
                if let date = formatter.date(from: trimmed) { found.append(date); break }
            }
        }
        return found.sorted()
    }
}
