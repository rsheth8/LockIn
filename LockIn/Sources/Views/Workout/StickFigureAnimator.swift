import SwiftUI

/// Looping in-app demo of one `MovementPattern`.
///
/// Driven by `TimelineView` + `Canvas` rather than a `Shape` animation: the
/// figure is a full FK skeleton plus props, not a single interpolatable path.
/// Phase → pose → skeleton is computed each frame from the shared model code
/// (`MovementPattern.skeleton(atPhase:)`), so what you see here is exactly
/// what the contact-sheet renderer and geometry tests check.
struct StickFigureAnimator: View {
    let pattern: MovementPattern
    var isPaused: Bool = false
    /// Multiplies the clip's own cycle time. A cue that says "three seconds
    /// down" should be demonstrated at three seconds down, not at the generic
    /// pace every other clip runs at.
    var speed: Double = 1

    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOnScreen = false

    /// Stopped when the caller says so, when the app isn't frontmost, when the
    /// card has scrolled away, or when the user has asked the system for less
    /// motion. A looping decoration has no business burning a redraw every
    /// frame in any of those cases.
    private var isStopped: Bool {
        isPaused || reduceMotion || !isOnScreen || scenePhase != .active
    }

    var body: some View {
        TimelineView(.animation(paused: isStopped)) { context in
            let duration = max(pattern.cycleDuration / max(speed, 0.05), 0.05)
            // Frozen clips hold a pose partway into the rep rather than at
            // keyframe zero: a squat standing bolt upright doesn't show you
            // what a squat is, and Reduce Motion shouldn't cost you the
            // information the animation was carrying.
            let phase = isStopped
                ? pattern.restingPhase
                : Self.phase(at: context.date, duration: duration)
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.surfaceMuted)
                StickFigureCanvas(pattern: pattern, phase: phase, accent: accent.color)
                    .padding(10)
            }
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .accessibilityLabel("\(pattern.title) demonstration")
    }

    static func phase(at date: Date, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
        return elapsed / duration
    }
}

/// Draws one phase of a movement into whatever size the layout gives it.
///
/// Walks `MovementPattern.elements(atPhase:)` and nothing else — the same
/// ordered, back-to-front element list the offline contact-sheet renderer
/// consumes. Draw order, prop layering and head masking are decided once, in
/// the model, so the animation on the card and the sheets a test writes out
/// cannot drift apart.
struct StickFigureCanvas: View {
    let pattern: MovementPattern
    let phase: Double
    /// Tints the near limbs and the motion trails.
    var accent: Color = Theme.signal
    /// Painted behind the figure. The head and the solid parts of props are
    /// knocked out in this colour so limbs passing behind them are masked.
    var background: Color = Theme.surfaceMuted

    var body: some View {
        Canvas { context, size in
            let (scale, origin) = pattern.layout(in: size)
            guard scale > 0 else { return }

            func pt(_ p: CGPoint) -> CGPoint {
                CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale)
            }
            func radius(_ centre: CGPoint, _ r: CGFloat) -> (CGPoint, CGFloat) {
                let c = pt(centre)
                return (c, abs(pt(CGPoint(x: centre.x + r, y: centre.y)).x - c.x))
            }

            let bone = max(1.8, Self.boneWidth * scale)

            for element in pattern.elements(atPhase: phase) {
                switch element {
                case .shadow(let centre, let radii, let strength):
                    let c = pt(centre)
                    let rect = CGRect(x: c.x - radii.width * scale, y: c.y - radii.height * scale,
                                      width: radii.width * 2 * scale, height: radii.height * 2 * scale)
                    context.fill(Path(ellipseIn: rect),
                                 with: .color(Theme.ink.opacity(min(0.34, 0.13 * strength))))

                case .trail(let a, let b, let strength):
                    var path = Path()
                    path.move(to: pt(a))
                    path.addLine(to: pt(b))
                    context.stroke(
                        path,
                        with: .color(accent.opacity(0.07 + 0.13 * strength)),
                        style: StrokeStyle(lineWidth: bone * 0.85, lineCap: .round, lineJoin: .round)
                    )

                case .prop(let primitive):
                    stroke(primitive, context: &context, pt: pt, radius: radius,
                           lineWidth: bone * 0.8, color: Theme.ink.opacity(0.55))

                case .bone(let a, let b, let far):
                    var path = Path()
                    path.move(to: pt(a))
                    path.addLine(to: pt(b))
                    let style = StrokeStyle(lineWidth: far ? bone * 0.9 : bone,
                                            lineCap: .round, lineJoin: .round)
                    context.stroke(path, with: .color(Theme.ink.opacity(far ? 0.42 : 1)), style: style)
                    // The near limbs carry a wash of the app's accent so the
                    // demo reads as part of the product rather than as debug
                    // scaffolding. Laid over the ink rather than replacing it,
                    // which keeps `Theme.ink`'s light/dark adaptivity and stays
                    // legible whichever accent the user picked.
                    if !far {
                        context.stroke(path, with: .color(accent.opacity(0.13)), style: style)
                    }

                case .head(let centre, let r):
                    let (c, rr) = radius(centre, r)
                    let path = Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
                    context.fill(path, with: .color(background))
                    context.stroke(path, with: .color(Theme.ink),
                                   style: StrokeStyle(lineWidth: bone, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Bone width in rig units, so the figure keeps its weight at any card size.
    private static let boneWidth: CGFloat = 2.3

    private func stroke(
        _ primitive: StickFigurePrimitive,
        context: inout GraphicsContext,
        pt: (CGPoint) -> CGPoint,
        radius: (CGPoint, CGFloat) -> (CGPoint, CGFloat),
        lineWidth: CGFloat,
        color: Color
    ) {
        var path = Path()
        switch primitive {
        case .line(let a, let b):
            path.move(to: pt(a))
            path.addLine(to: pt(b))
        case .circle(let centre, let r):
            let (c, rr) = radius(centre, r)
            path.addEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
        case .disc(let centre, let r):
            let (c, rr) = radius(centre, r)
            let rect = CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)
            context.fill(Path(ellipseIn: rect), with: .color(background))
            path.addEllipse(in: rect)
        case .polygon(let points):
            guard let first = points.first else { return }
            path.move(to: pt(first))
            for p in points.dropFirst() { path.addLine(to: pt(p)) }
            path.closeSubpath()
        case .path(let points):
            guard let first = points.first else { return }
            path.move(to: pt(first))
            for p in points.dropFirst() { path.addLine(to: pt(p)) }
        }
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}

#if DEBUG
#Preview("Squat") {
    StickFigureAnimator(pattern: .squat)
        .frame(width: 320, height: 210)
        .padding()
        .background(Theme.ground)
}

#Preview("Sprint") {
    StickFigureAnimator(pattern: .sprint)
        .frame(width: 320, height: 210)
        .padding()
        .background(Theme.ground)
}
#endif
