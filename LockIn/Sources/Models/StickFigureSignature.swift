import CoreGraphics
import Foundation

/// A tiny perceptual fingerprint of a rendered clip.
///
/// The geometric contracts elsewhere in the suite check that a clip is
/// *correct* — bones keep their length, feet stay on the floor, the head is
/// drawn last. None of them notice a change that is geometrically legal and
/// visually worse: a keyframe nudged until a limb crosses the torso, a prop
/// that stops overlapping the hand, a draw-order edit that unmasks the face.
///
/// This closes that gap the way a human would: render the frame, shrink it
/// until only large-scale structure survives, and compare against a recorded
/// baseline. Coarse on purpose — it has to ignore antialiasing and sub-unit
/// drift while still catching "that limb moved".
enum StickFigureSignature {
    /// Cells per side of the downsampled grid.
    static let grid = 12
    /// Phases sampled per clip.
    static let phases: [Double] = [0.0, 0.25, 0.5, 0.75]

    /// Mean ink coverage per cell, 0...255, for one clip across `phases`.
    static func signature(of pattern: MovementPattern) -> [UInt8] {
        phases.flatMap { cells(of: pattern, atPhase: $0) }
    }

    private static func cells(of pattern: MovementPattern, atPhase phase: Double) -> [UInt8] {
        let side = 96
        guard let image = StickFigureRenderer.renderFrame(
            pattern: pattern, phase: phase, size: side, style: .sheet
        ) else { return Array(repeating: 0, count: grid * grid) }

        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * side)
        guard let ctx = pixels.withUnsafeMutableBytes({ buffer -> CGContext? in
            CGContext(data: buffer.baseAddress, width: side, height: side,
                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { return Array(repeating: 0, count: grid * grid) }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Average luminance per cell, inverted so "more ink" reads as a
        // bigger number.
        var out: [UInt8] = []
        let cell = side / grid
        for row in 0..<grid {
            for col in 0..<grid {
                var total = 0
                for y in (row * cell)..<((row + 1) * cell) {
                    for x in (col * cell)..<((col + 1) * cell) {
                        let i = y * bytesPerRow + x * 4
                        total += (Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / 3
                    }
                }
                let mean = total / (cell * cell)
                out.append(UInt8(max(0, min(255, 255 - mean))))
            }
        }
        return out
    }

    /// How different two signatures are, 0...255.
    ///
    /// Averaged over the **most changed** cells rather than over all of them.
    /// A clip occupies a fraction of its frame, so a plain mean is dominated
    /// by empty background that never changes: moving a knee seven degrees
    /// scored 0.8 out of 255 that way, which is indistinguishable from noise.
    /// Scoring the region that actually moved keeps a local change legible
    /// without letting one antialiased cell trip the whole test.
    static func distance(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        let differences = zip(a, b).map { abs(Int($0) - Int($1)) }.sorted(by: >)
        let considered = max(8, differences.count / 20)
        return Double(differences.prefix(considered).reduce(0, +)) / Double(considered)
    }

    static func encode(_ bytes: [UInt8]) -> String { Data(bytes).base64EncodedString() }
    static func decode(_ text: String) -> [UInt8] { Array(Data(base64Encoded: text) ?? Data()) }
}
