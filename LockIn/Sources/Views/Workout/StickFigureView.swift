import SwiftUI

/// Draws one `StickPose` into whatever box it's given.
///
/// A single `Canvas` pass — the figure redraws 20 times a second while the
/// pacer runs, and a stack of shape views at that rate would be wasteful for a
/// dozen straight lines.
struct StickFigureView: View {
    let pose: StickPose
    var platform: StagePlatform = .none
    var showsFloor: Bool = true
    var accent: Color = .orange

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let dx = (size.width - s) / 2
            func p(_ point: CGPoint) -> CGPoint {
                CGPoint(x: dx + point.x * s, y: point.y * s)
            }
            let bone = max(2, s * 0.013)

            // Stage first, so the figure always sits on top of it.
            if showsFloor {
                var floor = Path()
                floor.move(to: CGPoint(x: dx, y: StickPose.Body.ground * s))
                floor.addLine(to: CGPoint(x: dx + s, y: StickPose.Body.ground * s))
                context.stroke(floor, with: .color(Theme.rule), lineWidth: 1)
            }
            drawPlatform(&context, project: p, side: s, dx: dx)

            // Trailing leg thinner, so the working side reads first.
            if let rk = pose.rearKnee, let ra = pose.rearAnkle, let rt = pose.rearToe {
                var rear = Path()
                rear.move(to: p(pose.hip))
                rear.addLine(to: p(rk))
                rear.addLine(to: p(ra))
                rear.addLine(to: p(rt))
                context.stroke(rear, with: .color(Theme.inkMuted),
                               style: StrokeStyle(lineWidth: bone * 0.7, lineCap: .round, lineJoin: .round))
            }

            var body = Path()
            body.move(to: p(pose.neck))
            body.addLine(to: p(pose.hip))
            body.addLine(to: p(pose.knee))
            body.addLine(to: p(pose.ankle))
            body.addLine(to: p(pose.toe))
            body.move(to: p(pose.shoulder))
            body.addLine(to: p(pose.elbow))
            body.addLine(to: p(pose.hand))
            context.stroke(body, with: .color(Theme.ink),
                           style: StrokeStyle(lineWidth: bone, lineCap: .round, lineJoin: .round))

            let r = StickPose.Body.headRadius * s
            let head = p(pose.head)
            context.stroke(
                Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)),
                with: .color(Theme.ink), lineWidth: bone
            )

            drawLoad(&context, project: p, side: s, dx: dx, bone: bone)
        }
    }

    // MARK: - Stage

    private func drawPlatform(_ context: inout GraphicsContext,
                              project p: (CGPoint) -> CGPoint, side s: CGFloat, dx: CGFloat) {
        switch platform {
        case .none:
            return
        case let .box(minX, maxX, top):
            let rect = CGRect(x: dx + minX * s, y: top * s,
                              width: (maxX - minX) * s,
                              height: (StickPose.Body.ground - top) * s)
            context.stroke(Path(rect), with: .color(Theme.inkFaint), lineWidth: 1.5)
        case let .wall(x):
            var path = Path()
            path.move(to: CGPoint(x: dx + x * s, y: s * 0.16))
            path.addLine(to: CGPoint(x: dx + x * s, y: StickPose.Body.ground * s))
            context.stroke(path, with: .color(Theme.inkFaint), lineWidth: 2.5)
        }
    }

    /// The implement, in accent so it reads as the thing being moved.
    private func drawLoad(_ context: inout GraphicsContext,
                          project p: (CGPoint) -> CGPoint, side s: CGFloat,
                          dx: CGFloat, bone: CGFloat) {
        let hand = p(pose.hand)
        var path = Path()

        switch pose.load {
        case .none:
            return
        case .barOnBack:
            let shoulder = p(pose.shoulder)
            path.move(to: CGPoint(x: shoulder.x - s * 0.13, y: shoulder.y))
            path.addLine(to: CGPoint(x: shoulder.x + s * 0.13, y: shoulder.y))
        case .barInHands:
            path.move(to: CGPoint(x: hand.x - s * 0.13, y: hand.y))
            path.addLine(to: CGPoint(x: hand.x + s * 0.13, y: hand.y))
        case .dumbbells:
            let rect = CGRect(x: hand.x - s * 0.032, y: hand.y - s * 0.013,
                              width: s * 0.064, height: s * 0.026)
            context.fill(Path(roundedRect: rect, cornerRadius: s * 0.008), with: .color(accent))
            return
        case .ball:
            let r = s * 0.042
            context.stroke(
                Path(ellipseIn: CGRect(x: hand.x - r, y: hand.y - r, width: r * 2, height: r * 2)),
                with: .color(accent), lineWidth: bone
            )
            return
        case let .cable(anchor):
            path.move(to: hand)
            path.addLine(to: p(anchor))
            context.stroke(path, with: .color(accent), lineWidth: max(1, bone * 0.7))
            return
        case .fixedBar:
            // Fixed in space, not wherever the hands happen to be — the bar
            // doesn't move during a pull-up, you do.
            let y = s * 0.20
            path.move(to: CGPoint(x: dx + s * 0.20, y: y))
            path.addLine(to: CGPoint(x: dx + s * 0.80, y: y))
        }

        context.stroke(path, with: .color(accent),
                       style: StrokeStyle(lineWidth: bone, lineCap: .round))
    }
}
