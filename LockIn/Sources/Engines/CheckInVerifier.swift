import Foundation
import Vision
import UIKit

/// Ephemeral proof-of-effort for check-ins. The image is classified on-device
/// and then discarded — never written to disk, Photos, or CloudKit.
enum CheckInVerifier {
    enum Result: Equatable {
        case verified(reason: String)
        case unclear(reason: String)
        case failed(reason: String)
    }

    static func expectedProof(for kind: EventKind) -> String {
        switch kind {
        case .workout: return "Snap the gym floor, machine, or yourself mid-session."
        case .meal, .mealPrep: return "Snap the plated meal / weighed food."
        case .weighIn: return "Snap the scale reading."
        default: return "Snap a quick proof photo."
        }
    }

    static func requiresProof(_ kind: EventKind) -> Bool {
        switch kind {
        case .workout, .meal: return true
        default: return false
        }
    }

    /// Runs Vision classification. Caller must drop the UIImage after this returns.
    static func verify(image: UIImage, for kind: EventKind) async -> Result {
        guard let cgImage = image.cgImage else {
            return .failed(reason: "Couldn't read the photo.")
        }

        return await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                if let error {
                    continuation.resume(returning: .failed(reason: error.localizedDescription))
                    return
                }
                let observations = (request.results as? [VNClassificationObservation]) ?? []
                let top = observations.prefix(12).map { ($0.identifier.lowercased(), Double($0.confidence)) }
                let result = evaluate(top: Array(top), kind: kind)
                continuation.resume(returning: result)
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: .failed(reason: error.localizedDescription))
            }
        }
    }

    private static func evaluate(top: [(String, Double)], kind: EventKind) -> Result {
        let labels = top.map(\.0)
        let joined = labels.joined(separator: " ")

        func hit(_ words: [String]) -> Bool {
            words.contains { w in joined.contains(w) }
        }

        switch kind {
        case .meal, .mealPrep:
            if hit(["food", "dish", "meal", "plate", "bowl", "cuisine", "vegetable", "rice", "bread", "salad", "soup"]) {
                return .verified(reason: "Looks like food.")
            }
            return .unclear(reason: "Didn't clearly see a meal — try again or override.")
        case .weighIn:
            if hit(["scale", "meter", "number", "bathroom", "floor", "person", "standing"]) {
                return .verified(reason: "Looks like a weigh-in shot.")
            }
            return .unclear(reason: "Couldn't spot a scale reading — retake or override.")
        case .workout:
            if hit(["person", "gym", "sport", "fitness", "exercise", "dumbbell", "machine", "indoor", "athletic"]) {
                return .verified(reason: "Looks like a training environment.")
            }
            return .unclear(reason: "Didn't clearly see a workout — retake or override.")
        default:
            return .verified(reason: "Captured.")
        }
    }
}
