import Foundation
import Vision
import UIKit

/// Reads a Nutrition Facts panel with on-device OCR.
///
/// The universal fallback. Barcode lookup needs the product to exist in a
/// crowd-sourced database and photo recognition needs the food to look like
/// something in the vocabulary — but *anything* in a package has a label, and
/// the label is the manufacturer's own number. It also costs nothing: Vision
/// runs locally, so there's no key, no quota, and no network.
///
/// Like the meal classifier, this never keeps the image. Text is extracted in
/// memory and the photo is released.
enum NutritionLabelReader {

    /// What was found on the panel. Every field is optional because OCR on a
    /// crumpled foil pouch genuinely does miss lines — the UI shows what was
    /// read and lets the user fix the rest, rather than pretending to a
    /// completeness it doesn't have.
    struct Reading: Equatable {
        var calories: Double?
        var protein: Double?
        var fat: Double?
        var carbs: Double?
        /// Grams in one serving, when the panel states it.
        var servingGrams: Double?
        /// The panel's own wording, e.g. "2/3 cup (55g)".
        var servingText: String?

        /// Calories are the one field worth blocking on. Without them there's
        /// nothing to log, and showing a form of zeros invites the user to
        /// accept them.
        var isUsable: Bool { (calories ?? 0) > 0 }

        var macros: MacroTargetsLite {
            MacroTargetsLite(
                calories: calories ?? 0,
                proteinG: protein ?? 0,
                fatG: fat ?? 0,
                carbG: carbs ?? 0
            )
        }

        /// Which fields OCR actually filled, so the UI can say so.
        var foundCount: Int {
            [calories, protein, fat, carbs].compactMap { $0 }.count
        }
    }

    enum ReaderError: Error {
        case imageUnusable
    }

    static func read(_ image: UIImage) async throws -> Reading {
        guard let cgImage = image.cgImage else { throw ReaderError.imageUnusable }
        let lines = try await recognizeRows(in: cgImage, orientation: image.cgImageOrientation)
        return parse(rows: lines)
    }

    // MARK: - OCR

    /// Recognised text, regrouped into visual rows.
    ///
    /// Vision returns each text run separately, and a nutrition panel is a
    /// two-column layout — "Total Fat" and "8g" usually arrive as *different*
    /// observations. Matching them back up by vertical position is what makes
    /// the parse work at all; treating each observation as its own line finds
    /// the labels and loses every number.
    static func recognizeRows(in cgImage: CGImage, orientation: CGImagePropertyOrientation) async throws -> [String] {
        let observations: [VNRecognizedTextObservation] = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: request.results as? [VNRecognizedTextObservation] ?? [])
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false  // "8g" must not become "8a"
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }

        struct Fragment {
            let text: String
            let midY: CGFloat
            let minX: CGFloat
            let height: CGFloat
        }

        let fragments: [Fragment] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return Fragment(text: candidate.string, midY: box.midY, minX: box.minX, height: box.height)
        }
        guard !fragments.isEmpty else { return [] }

        // Group by vertical proximity, scaled to the text's own height so the
        // tolerance holds whether the label fills the frame or sits in a corner.
        let tolerance = max(fragments.map(\.height).reduce(0, +) / CGFloat(fragments.count) * 0.6, 0.005)
        // Vision's origin is bottom-left, so descending Y is top-to-bottom.
        let sorted = fragments.sorted { $0.midY > $1.midY }

        var rows: [[Fragment]] = []
        for fragment in sorted {
            if let index = rows.indices.last, let anchor = rows[index].first,
               abs(anchor.midY - fragment.midY) <= tolerance {
                rows[index].append(fragment)
            } else {
                rows.append([fragment])
            }
        }

        return rows.map { row in
            row.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ")
        }
    }

    // MARK: - Parsing

    static func parse(rows: [String]) -> Reading {
        var reading = Reading()

        for row in rows {
            let line = normalize(row)

            // Calories first and only once, so a stray later mention can't
            // overwrite the real figure.
            //
            // The from-fat clause is deleted rather than used to reject the
            // row. On the pre-2016 label "Calories 140" and "Calories from Fat
            // 30" are printed side by side, so they arrive here as a single
            // row — discarding it would make every legacy panel unreadable,
            // and plenty are still on shelves. Dropping only the clause leaves
            // "calories 140" behind, and a from-fat line standing on its own
            // still reduces to nothing and is ignored as before.
            if reading.calories == nil, line.contains("calorie") {
                let withoutFromFat = line.replacingOccurrences(
                    of: "calories? from fat[^0-9]*[0-9]+",
                    with: " ",
                    options: .regularExpression
                )
                if withoutFromFat.contains("calorie") {
                    reading.calories = firstNumber(in: withoutFromFat, after: "calorie")
                }
            }

            // "Total Fat 8g" — anchored on "total fat" ahead of bare "fat" so
            // "Saturated Fat" and "Trans Fat" can't claim the slot.
            if reading.fat == nil, let value = grams(in: line, labels: ["total fat"]) {
                reading.fat = value
            }
            if reading.carbs == nil,
               let value = grams(in: line, labels: ["total carbohydrate", "total carb", "carbohydrate"]) {
                reading.carbs = value
            }
            if reading.protein == nil, let value = grams(in: line, labels: ["protein"]) {
                reading.protein = value
            }
            if reading.servingText == nil, line.contains("serving size") {
                let text = row.replacingOccurrences(of: "(?i)serving size", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { reading.servingText = text }
                reading.servingGrams = grams(inParenthesesOf: line)
            }
        }

        // A panel that lists no "Total Fat" but does list "Fat" is common
        // outside the US. Only fall back once the strict pass has finished, so
        // a saturated-fat line can't win by appearing first.
        if reading.fat == nil {
            for row in rows {
                let line = normalize(row)
                guard !line.contains("saturat"), !line.contains("trans"), !line.contains("unsaturat") else { continue }
                if let value = grams(in: line, labels: ["fat"]) { reading.fat = value; break }
            }
        }

        return reading
    }

    /// Lowercased, with the OCR confusions that actually bite on these panels
    /// repaired: a zero read as the letter O is by far the most common, and it
    /// turns "0g" of fat into no reading at all.
    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "([0-9])o", with: "$10", options: .regularExpression)
            .replacingOccurrences(of: "\\bo(?=\\s*g\\b)", with: "0", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Grams stated immediately after one of `labels`.
    ///
    /// Requires the unit: a nutrition row ends in a % Daily Value, and matching
    /// a bare number would happily return "10" from "Total Fat 8g 10%".
    private static func grams(in line: String, labels: [String]) -> Double? {
        for label in labels {
            guard let range = line.range(of: label) else { continue }
            let tail = String(line[range.upperBound...])
            guard let match = tail.range(
                of: "^[^0-9%]{0,12}([0-9]+(?:\\.[0-9]+)?)\\s*g\\b",
                options: .regularExpression
            ) else { continue }
            if let number = firstNumber(in: String(tail[match])) { return number }
        }
        return nil
    }

    /// "2/3 cup (55g)" → 55
    private static func grams(inParenthesesOf line: String) -> Double? {
        guard let match = line.range(
            of: "\\(([0-9]+(?:\\.[0-9]+)?)\\s*g\\)",
            options: .regularExpression
        ) else { return nil }
        return firstNumber(in: String(line[match]))
    }

    private static func firstNumber(in line: String, after marker: String? = nil) -> Double? {
        var scope = line
        if let marker, let range = line.range(of: marker) {
            scope = String(line[range.upperBound...])
        }
        guard let match = scope.range(of: "[0-9]+(?:\\.[0-9]+)?", options: .regularExpression) else { return nil }
        return Double(scope[match])
    }
}

extension UIImage {
    /// Vision works on the raw `CGImage` and ignores `UIImage.imageOrientation`,
    /// so a photo taken in portrait arrives sideways and OCR finds nothing.
    var cgImageOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
