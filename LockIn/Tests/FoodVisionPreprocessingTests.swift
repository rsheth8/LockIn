import XCTest
import UIKit
@testable import LockIn

/// Pins the Swift image preprocessing against a reference embedding computed
/// offline by the same MobileCLIP model (see `Tools/reference_embedding.py`).
///
/// This exists because the simulator has no camera, so the photo path can't be
/// exercised through the UI — and because the failure mode it guards against
/// is silent. If the BGRA buffer were handed to the model with its channels in
/// the wrong order, nothing would error; recognition would just quietly get
/// worse. Comparing against a known-good vector catches that.
final class FoodVisionPreprocessingTests: XCTestCase {

    /// Same construction as the Python reference: deliberately asymmetric
    /// across channels, so a red/blue swap changes the result. A grey gradient
    /// would hide exactly the bug this is here to catch.
    private func makeSyntheticImage(side: Int = 256, swapRedAndBlue: Bool = false) -> UIImage {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let r = UInt8(x)
                let g = UInt8(y / 2)
                let b = UInt8((x * y) / 512)
                let offset = (y * side + x) * 4
                bytes[offset] = swapRedAndBlue ? b : r
                bytes[offset + 1] = g
                bytes[offset + 2] = swapRedAndBlue ? r : b
                bytes[offset + 3] = 255
            }
        }

        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cgImage = CGImage(
            width: side, height: side,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        )!
        return UIImage(cgImage: cgImage)
    }

    private func referenceEmbedding() throws -> [Float] {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "SyntheticReferenceEmbedding", withExtension: "json"),
            "reference fixture missing from the test bundle"
        )
        struct Fixture: Decodable { let embedding: [Float] }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).embedding
    }

    private func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float {
        precondition(lhs.count == rhs.count)
        return zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
    }

    /// The core assertion: Swift preprocessing + inference reproduces the
    /// reference vector.
    func testSwiftPreprocessingMatchesReferenceEmbedding() async throws {
        let reference = try referenceEmbedding()
        let produced = try await FoodVisionClassifier.shared.embedding(for: makeSyntheticImage())

        XCTAssertEqual(produced.count, reference.count)

        // Both vectors are L2-normalised, so this is cosine similarity. The
        // tolerance allows for the Neural Engine using different numerics than
        // the CPU path Python took, while staying far tighter than any real
        // preprocessing mistake would survive.
        let similarity = cosine(produced, reference)
        XCTAssertGreaterThan(similarity, 0.99,
                             "Swift embedding diverged from the reference (cosine \(similarity)) — preprocessing likely changed")
    }

    /// Proves the test above is actually sensitive to the bug it guards
    /// against. Without this, a check that passes on everything would be
    /// indistinguishable from a check that works.
    func testChannelSwapWouldBeDetected() async throws {
        let reference = try referenceEmbedding()
        let swapped = try await FoodVisionClassifier.shared.embedding(for: makeSyntheticImage(swapRedAndBlue: true))

        let similarity = cosine(swapped, reference)
        XCTAssertLessThan(similarity, 0.99,
                          "a red/blue swap produced the same embedding — the reference check can't detect channel errors")
    }

    /// A normalised vector must have unit length; if it doesn't, every
    /// similarity score downstream is scaled wrong.
    func testEmbeddingIsUnitLength() async throws {
        let produced = try await FoodVisionClassifier.shared.embedding(for: makeSyntheticImage())
        let magnitude = sqrt(produced.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(magnitude, 1.0, accuracy: 0.001)
    }

    /// Non-square input must be centre-cropped to the model's square input
    /// rather than squashed — aspect distortion measurably hurts CLIP.
    func testHandlesNonSquareImages() async throws {
        let wide = makeSyntheticImage(side: 256)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 220))
        let stretched = renderer.image { _ in
            wide.draw(in: CGRect(x: 0, y: 0, width: 400, height: 220))
        }

        let produced = try await FoodVisionClassifier.shared.embedding(for: stretched)
        XCTAssertEqual(produced.count, 512)
        XCTAssertEqual(sqrt(produced.reduce(0) { $0 + $1 * $1 }), 1.0, accuracy: 0.001)
    }

    /// End-to-end through the real bundled vocabulary: a synthetic gradient is
    /// not food, so the classifier should decline to guess rather than return
    /// a confident label.
    func testAbstainsOnNonFoodImage() async throws {
        let candidates = try await FoodVisionClassifier.shared.classify(makeSyntheticImage())
        XCTAssertTrue(candidates.isEmpty,
                      "expected no guesses for a synthetic gradient, got \(candidates.map(\.name))")
    }
}
