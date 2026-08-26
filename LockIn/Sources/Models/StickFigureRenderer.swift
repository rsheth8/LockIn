import CoreGraphics
import Foundation
#if canImport(ImageIO)
import ImageIO
import UniformTypeIdentifiers
#endif

/// Offline / test renderer for stick-figure clips. Same geometry the in-app
/// `StickFigureCanvas` draws — so a contact sheet of every keyframe is a true
/// preview of what ships, not a separate sketch.
enum StickFigureRenderer {

    struct Style {
        var background: CGColor
        var ink: CGColor
        var inkFaint: CGColor
        var propInk: CGColor
        var shadow: CGColor
        /// Bone width in **rig units**, so the figure keeps the same visual
        /// weight whatever size the sheet is rendered at.
        var boneWidth: CGFloat

        static let sheet = Style(
            background: CGColor(gray: 0.97, alpha: 1),
            ink: CGColor(gray: 0.08, alpha: 1),
            inkFaint: CGColor(gray: 0.08, alpha: 0.5),
            propInk: CGColor(gray: 0.08, alpha: 0.55),
            shadow: CGColor(gray: 0.08, alpha: 0.14),
            boneWidth: 2.3
        )
    }

    /// Renders one phase into a square bitmap.
    static func renderFrame(
        pattern: MovementPattern,
        phase: Double,
        size: Int = 256,
        style: Style = .sheet
    ) -> CGImage? {
        let width = size
        let height = size
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(style.background)
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        // CoreGraphics y grows upward; our rig y grows downward. Flip.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let box = pattern.viewBox
        guard box.width > 0, box.height > 0 else { return ctx.makeImage() }

        let canvas = CGSize(width: CGFloat(width), height: CGFloat(height))
        let (scale, origin) = pattern.layout(in: canvas)

        func pt(_ p: CGPoint) -> CGPoint {
            CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale)
        }

        let bone = max(1.6, style.boneWidth * scale)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for element in pattern.elements(atPhase: phase) {
            switch element {
            case .shadow(let centre, let radii, let strength):
                let c = pt(centre)
                ctx.setFillColor(style.shadow.copy(alpha: min(0.34, (style.shadow.alpha) * strength)) ?? style.shadow)
                ctx.fillEllipse(in: CGRect(x: c.x - radii.width * scale, y: c.y - radii.height * scale,
                                           width: radii.width * 2 * scale, height: radii.height * 2 * scale))
            case .trail(let a, let b, let strength):
                ctx.setStrokeColor(style.ink.copy(alpha: 0.08 + 0.14 * strength) ?? style.inkFaint)
                ctx.setLineWidth(bone * 0.85)
                strokeLine(pt(a), pt(b), in: ctx)
            case .prop(let primitive):
                ctx.setStrokeColor(style.propInk)
                ctx.setLineWidth(bone * 0.8)
                stroke(primitive, in: ctx, transform: pt, background: style.background)
            case .bone(let a, let b, let far):
                ctx.setStrokeColor(far ? style.inkFaint : style.ink)
                ctx.setLineWidth(far ? bone * 0.9 : bone)
                strokeLine(pt(a), pt(b), in: ctx)
            case .head(let centre, let radius):
                let c = pt(centre)
                let r = radius * scale
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                ctx.setFillColor(style.background)
                ctx.fillEllipse(in: rect)
                ctx.setStrokeColor(style.ink)
                ctx.setLineWidth(bone)
                ctx.strokeEllipse(in: rect)
            }
        }

        return ctx.makeImage()
    }

    /// Contact sheet: one row of keyframes for a pattern (plus mid-lerp samples
    /// so in-betweens get eyeballed too).
    static func renderContactSheet(
        pattern: MovementPattern,
        cellSize: Int = 200,
        samplesPerSegment: Int = 2
    ) -> CGImage? {
        let keyCount = max(pattern.keyframes.count, 1)
        // Sample at keyframe boundaries and evenly between them across one
        // half-cycle (ping-pong outbound) or full cycle.
        var phases: [Double] = []
        let steps = max((keyCount - 1) * samplesPerSegment, keyCount)
        for i in 0...steps {
            phases.append(Double(i) / Double(steps) * (pattern.loop == .cycle ? 1.0 : 0.5))
        }

        let cols = phases.count
        let width = cellSize * cols
        let height = cellSize + 28
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(Style.sheet.background)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for (i, phase) in phases.enumerated() {
            guard let cell = renderFrame(pattern: pattern, phase: phase, size: cellSize) else { continue }
            // `cell` already has the rig's y-down → bitmap mapping baked in.
            // Blit in upright CG space (y grows up): cells sit at the bottom of
            // the sheet, title strip occupies the top 28pt.
            let side = CGFloat(cellSize)
            ctx.draw(cell, in: CGRect(x: CGFloat(i * cellSize), y: 0, width: side, height: side))
        }

        // Title strip along the top of the PNG (high y in CG space).
        drawLabel(pattern.title, in: ctx, at: CGPoint(x: 10, y: CGFloat(height) - 20), width: CGFloat(width - 20))

        return ctx.makeImage()
    }

    /// Writes a PNG for every `MovementPattern` into `directory`.
    @discardableResult
    static func writeAllContactSheets(to directory: URL, cellSize: Int = 180) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for pattern in MovementPattern.allCases {
            guard let image = renderContactSheet(pattern: pattern, cellSize: cellSize) else { continue }
            let url = directory.appendingPathComponent("\(pattern.rawValue).png")
            try writePNG(image, to: url)
            written.append(url)
        }
        return written
    }

    // MARK: - Drawing helpers

    private static func strokeLine(_ a: CGPoint, _ b: CGPoint, in ctx: CGContext) {
        ctx.beginPath()
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
    }

    private static func stroke(
        _ primitive: StickFigurePrimitive,
        in ctx: CGContext,
        transform: (CGPoint) -> CGPoint,
        background: CGColor
    ) {
        func radius(_ centre: CGPoint, _ r: CGFloat) -> (CGPoint, CGFloat) {
            let c = transform(centre)
            return (c, abs(transform(CGPoint(x: centre.x + r, y: centre.y)).x - c.x))
        }
        ctx.beginPath()
        switch primitive {
        case .line(let a, let b):
            ctx.move(to: transform(a))
            ctx.addLine(to: transform(b))
        case .circle(let centre, let r):
            let (c, rr) = radius(centre, r)
            ctx.addEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
        case .disc(let centre, let r):
            let (c, rr) = radius(centre, r)
            let rect = CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)
            // Knock the background out first so the hub reads as solid steel
            // rather than as a ring with the torso showing through it. Every
            // caller sets its own fill colour before filling, so leaving this
            // one behind is safe.
            ctx.setFillColor(background)
            ctx.fillEllipse(in: rect)
            ctx.addEllipse(in: rect)
        case .polygon(let points):
            guard let first = points.first else { return }
            ctx.move(to: transform(first))
            for p in points.dropFirst() { ctx.addLine(to: transform(p)) }
            ctx.closePath()
        case .path(let points):
            guard let first = points.first else { return }
            ctx.move(to: transform(first))
            for p in points.dropFirst() { ctx.addLine(to: transform(p)) }
        }
        ctx.strokePath()
    }

    private static func drawLabel(_ text: String, in ctx: CGContext, at point: CGPoint, width: CGFloat) {
        // Minimal bitmap text without UIKit/AppKit: skip fancy typography; the
        // filename already names the pattern. Keep a thin rule under the strip.
        ctx.setStrokeColor(CGColor(gray: 0.08, alpha: 0.15))
        ctx.setLineWidth(1)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 8, y: point.y - 6))
        ctx.addLine(to: CGPoint(x: width - 8, y: point.y - 6))
        ctx.strokePath()
        _ = text // title is in the filename; Core Text would pull AppKit/UIKit.
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        #if canImport(ImageIO)
        let type = UTType.png.identifier as CFString
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw RenderError.cannotCreateDestination(url)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw RenderError.cannotWrite(url)
        }
        #else
        throw RenderError.imageIOUnavailable
        #endif
    }

    enum RenderError: Error {
        case cannotCreateDestination(URL)
        case cannotWrite(URL)
        case imageIOUnavailable
    }
}
