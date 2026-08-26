import Foundation
import Accelerate

/// The bundled table of food names and their precomputed MobileCLIP text
/// embeddings.
///
/// Embeddings are generated at build time (see `Tools/build_food_vocabulary.py`)
/// because running a text encoder on-device would mean shipping an extra ~85MB
/// model to compute values that never change. Precomputing turns that into a
/// ~700KB float16 table.
struct FoodVocabulary {
    /// Every entry, food first then the non-food decoys.
    let names: [String]
    /// Entries before this index are foods; the rest are non-food classes used
    /// only to let the classifier abstain.
    let foodCount: Int
    /// Entries before this index are composed dishes ("chicken biryani"); the
    /// rest, up to `foodCount`, are single ingredients ("greek yogurt").
    ///
    /// This split decides which nutrition source to try first. Label databases
    /// are built around ingredients and packaged goods, so they answer
    /// "greek yogurt" well and "pad thai" badly — for the latter they return
    /// whatever supermarket ready-meal happens to share the name.
    let dishCount: Int
    let dimensions: Int
    /// Row-major, `names.count` rows of `dimensions` floats, L2-normalised.
    /// Internal rather than private so tests can build a small synthetic
    /// vocabulary and assert ranking behaviour exactly.
    let embeddings: [Float]

    /// Names the user can actually pick, excluding the non-food decoys.
    var foodNames: ArraySlice<String> { names.prefix(foodCount) }

    // MARK: - Loading

    enum LoadError: Error {
        case missingResource
        case malformed
    }

    static func loadBundled(bundle: Bundle = .main) throws -> FoodVocabulary {
        guard let metaURL = bundle.url(forResource: "FoodVocabulary", withExtension: "json"),
              let binURL = bundle.url(forResource: "FoodVocabulary", withExtension: "bin") else {
            throw LoadError.missingResource
        }
        let meta = try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: metaURL))
        let raw = try Data(contentsOf: binURL)

        let expected = meta.names.count * meta.dimensions
        // Stored as half-precision to halve the bundle cost; the precision loss
        // is far below what would reorder a similarity ranking.
        //
        // Sized against UInt16 rather than Swift's `Float16` deliberately —
        // `Float16` doesn't exist on the x86_64 simulator slice, so naming the
        // type here would break that build. vImage only needs the raw bytes.
        let halfSize = MemoryLayout<UInt16>.size
        guard raw.count == expected * halfSize else {
            throw LoadError.malformed
        }

        var floats = [Float](repeating: 0, count: expected)
        raw.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            floats.withUnsafeMutableBufferPointer { destination in
                var source = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: base),
                                           height: 1, width: vImagePixelCount(expected),
                                           rowBytes: expected * halfSize)
                var target = vImage_Buffer(data: destination.baseAddress!,
                                           height: 1, width: vImagePixelCount(expected),
                                           rowBytes: expected * MemoryLayout<Float>.size)
                vImageConvert_Planar16FtoPlanarF(&source, &target, 0)
            }
        }

        return FoodVocabulary(names: meta.names, foodCount: meta.foodCount,
                              dishCount: meta.dishCount, dimensions: meta.dimensions,
                              embeddings: floats)
    }

    private struct Metadata: Decodable {
        let names: [String]
        let foodCount: Int
        let dishCount: Int
        let dimensions: Int
    }

    /// True when the name refers to a composed dish rather than a single
    /// ingredient. Unknown names (free text the user typed) are treated as
    /// dishes, since that's what someone types when logging a meal.
    func isDish(_ name: String) -> Bool {
        guard let index = names.firstIndex(of: name.lowercased()) else { return true }
        return index < dishCount
    }

    // MARK: - Matching

    /// Ranked food matches for an image embedding.
    ///
    /// The non-food rows participate in scoring but are never returned: if a
    /// decoy like "a person" outranks every food, that's the signal the photo
    /// isn't of a meal, and we return nothing rather than a bad guess.
    func bestMatches(for embedding: [Float], limit: Int, minimumScore: Float) -> [FoodVisionClassifier.Candidate] {
        guard embedding.count == dimensions else { return [] }

        var scores = [Float](repeating: 0, count: names.count)
        embeddings.withUnsafeBufferPointer { matrix in
            embedding.withUnsafeBufferPointer { vector in
                // One matrix-vector product for the whole vocabulary — ~700
                // dot products of 512 floats, which Accelerate does in well
                // under a millisecond.
                cblas_sgemv(CblasRowMajor, CblasNoTrans,
                            Int32(names.count), Int32(dimensions), 1.0,
                            matrix.baseAddress, Int32(dimensions),
                            vector.baseAddress, 1, 0.0,
                            &scores, 1)
            }
        }

        let bestNonFood = scores[foodCount...].max() ?? -.infinity
        let ranked = scores[..<foodCount].enumerated()
            .sorted { $0.element > $1.element }
            .prefix(limit)
            .filter { $0.element >= minimumScore && $0.element >= bestNonFood }
            .map { FoodVisionClassifier.Candidate(name: names[$0.offset], score: $0.element) }

        return Array(ranked)
    }

    /// Substring search over the food names, for when the photo guesses are
    /// wrong or the user would rather just type it.
    func search(_ query: String, limit: Int = 20) -> [String] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        // Prefix matches first — typing "chick" should surface "chicken curry"
        // above "korean fried chicken".
        let matches = foodNames.filter { $0.contains(needle) }
        return matches
            .sorted { lhs, rhs in
                let lhsPrefix = lhs.hasPrefix(needle)
                let rhsPrefix = rhs.hasPrefix(needle)
                if lhsPrefix != rhsPrefix { return lhsPrefix }
                return lhs.count < rhs.count
            }
            .prefix(limit)
            .map { $0 }
    }
}
