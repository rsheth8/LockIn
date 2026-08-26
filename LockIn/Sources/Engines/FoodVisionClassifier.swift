import Foundation
import CoreML
import UIKit
import Accelerate

/// Identifies food in a photo, entirely on-device.
///
/// Uses Apple's MobileCLIP (s0) image encoder against a bundled table of
/// precomputed text embeddings for ~700 dishes spanning every major cuisine.
/// Because CLIP matches images against *arbitrary text* rather than a fixed
/// set of trained classes, coverage is bounded by the vocabulary we ship — not
/// by what the model was trained to classify — so adding a cuisine is a data
/// change, never a retrain.
///
/// Nothing here touches the network and nothing is written to disk. The photo
/// exists as pixels only long enough to produce a 512-float embedding, then
/// it's released (see `classify`).
actor FoodVisionClassifier {
    static let shared = FoodVisionClassifier()

    /// One ranked guess at what's in the photo.
    struct Candidate: Equatable, Identifiable {
        let name: String
        /// Cosine similarity, roughly 0.1 (unrelated) to 0.4 (confident).
        let score: Float
        var id: String { name }
    }

    enum ClassifierError: Error {
        case modelUnavailable
        case vocabularyUnavailable
        case imageUnusable
    }

    /// Below this, the best food match is weak enough that showing it as a
    /// suggestion does more harm than good. Calibrated against a 21-photo
    /// spread where correct matches scored 0.26–0.35 and the non-food decoys
    /// topped out at 0.19.
    private static let minimumUsableScore: Float = 0.22

    /// MobileCLIP s0 takes 256×256 RGB and bakes the ÷255 scaling into the
    /// model itself, so pixels go in at full 0–255 range with no other
    /// normalisation.
    private static let inputSide = 256

    private var model: MLModel?
    private var vocabulary: FoodVocabulary?

    // MARK: - Public

    /// Ranked guesses for what's on the plate, best first.
    ///
    /// Returns an empty array when nothing scores above the usable threshold —
    /// a photo of a person or an empty table should offer no food guesses at
    /// all rather than a confident wrong one.
    func classify(_ image: UIImage, limit: Int = 5) async throws -> [Candidate] {
        let vocabulary = try loadVocabulary()
        let embedding = try await embedding(for: image)
        return vocabulary.bestMatches(for: embedding, limit: limit,
                                      minimumScore: Self.minimumUsableScore)
    }

    /// The L2-normalised image embedding, before any vocabulary matching.
    ///
    /// Split out from `classify` so tests can pin the preprocessing against a
    /// reference vector computed offline — the simulator has no camera, and a
    /// channel-order mistake here would silently degrade every result rather
    /// than failing outright.
    func embedding(for image: UIImage) async throws -> [Float] {
        let model = try loadModel()

        // Downsize first. Everything downstream works on a 256×256 buffer, so
        // the full-resolution capture (which can be 12MP / ~36MB decoded) is
        // released here rather than being carried through inference.
        guard let pixels = Self.pixelBuffer(from: image, side: Self.inputSide) else {
            throw ClassifierError.imageUnusable
        }

        let input = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: pixels)])
        let output = try await model.prediction(from: input)
        guard let raw = output.featureValue(for: "final_emb_1")?.multiArrayValue else {
            throw ClassifierError.modelUnavailable
        }
        return Self.normalized(raw)
    }

    // MARK: - Loading
    //
    // Both the model and the vocabulary are loaded once and retained by the
    // actor. The vocabulary is ~700KB of float16 and the compiled model is
    // memory-mapped by CoreML, so holding them costs little and avoids paying
    // load latency on every photo.

    private func loadModel() throws -> MLModel {
        if let model { return model }
        guard let url = Bundle.main.url(forResource: "FoodImageEncoder", withExtension: "mlmodelc") else {
            throw ClassifierError.modelUnavailable
        }
        let configuration = MLModelConfiguration()
        // Neural Engine where available, CPU/GPU otherwise — this is a small
        // model and inference should be well under a second either way.
        configuration.computeUnits = .all
        let loaded = try MLModel(contentsOf: url, configuration: configuration)
        model = loaded
        return loaded
    }

    private func loadVocabulary() throws -> FoodVocabulary {
        if let vocabulary { return vocabulary }
        let loaded = try FoodVocabulary.loadBundled()
        vocabulary = loaded
        return loaded
    }

    // MARK: - Image preparation

    /// Centre-crops to a square and scales to the model's input size, drawing
    /// straight into a CoreVideo buffer so there's no intermediate UIImage.
    ///
    /// Centre-crop rather than squash: aspect distortion measurably hurts CLIP,
    /// and food is almost always centred in a photo someone took of their meal.
    nonisolated static func pixelBuffer(from image: UIImage, side: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, side, side,
                                         kCVPixelFormatType_32BGRA,
                                         attributes as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        guard let cgImage = image.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let crop = min(width, height)
        let source = CGRect(x: (width - crop) / 2, y: (height - crop) / 2, width: crop, height: crop)
        guard let cropped = cgImage.cropping(to: source) else { return nil }

        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: side, height: side))
        return buffer
    }

    private static func CGColorSpaceDeviceRGB() -> CGColorSpace {
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    /// L2-normalises the model output so a dot product against the (already
    /// normalised) vocabulary rows is cosine similarity.
    private static func normalized(_ array: MLMultiArray) -> [Float] {
        let count = array.count
        var values = [Float](repeating: 0, count: count)
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: count)
        values.withUnsafeMutableBufferPointer { destination in
            destination.baseAddress?.update(from: pointer, count: count)
        }

        var norm: Float = 0
        vDSP_svesq(values, 1, &norm, vDSP_Length(count))
        norm = sqrt(norm)
        guard norm > 0 else { return values }
        var divisor = norm
        vDSP_vsdiv(values, 1, &divisor, &values, 1, vDSP_Length(count))
        return values
    }
}
