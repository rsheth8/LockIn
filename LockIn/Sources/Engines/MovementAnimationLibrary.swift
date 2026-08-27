import Foundation
import CoreGraphics

/// Keyframes for the stick figure, one per tempo phase.
///
/// Every animation here has exactly as many keyframes as its movement has tempo
/// phases, so phase *i* animates `keyframes[i] → keyframes[i+1]` and a three
/// second lowering phase takes three seconds on screen. `StickFigureTests`
/// enforces that pairing.
///
/// **Coverage is deliberately partial.** A sagittal stick figure can show a
/// squat or a row honestly; it cannot show transverse-plane rotation (the med
/// ball throw, the bowling action) or a supine drill (the dead bug) without
/// producing a drawing that misleads more than it helps. Those movements get
/// the tempo pacer and the written guide, and no figure. A wrong picture is
/// worse than no picture.
enum MovementAnimationLibrary {

    static func animation(for exerciseName: String) -> MovementAnimation? {
        animations[exerciseName]
    }

    static var allNames: [String] { animations.keys.sorted() }

    private static let animations: [String: MovementAnimation] = [

        // Phases: Lower 2s → Stand up 1s
        "Barbell Back Squat": MovementAnimation(
            keyframes: [
                .grounded(ankleX: 0.46, shin: 4, thigh: -4, torso: 6,
                          upperArm: -45, forearm: -155, load: .barOnBack),
                .grounded(ankleX: 0.46, shin: 36, thigh: -66, torso: 30,
                          upperArm: -45, forearm: -155, load: .barOnBack)
            ],
            viewNote: "Side view"
        ),

        // Phases: Hinge back 3s → Stand tall 1s
        "Romanian Deadlift": MovementAnimation(
            keyframes: [
                .grounded(ankleX: 0.44, shin: 3, thigh: -3, torso: 4,
                          upperArm: 2, forearm: 2, load: .barInHands),
                .grounded(ankleX: 0.44, shin: -8, thigh: -14, torso: 68,
                          upperArm: 6, forearm: 6, load: .barInHands)
            ],
            viewNote: "Side view"
        ),

        // Phases: Sink 2s → Push through 1s
        "Walking Lunge": MovementAnimation(
            keyframes: [
                .grounded(ankleX: 0.38, shin: 6, thigh: -6, torso: 5,
                          upperArm: 0, forearm: 0, rear: (-24, -14), load: .dumbbells),
                .grounded(ankleX: 0.38, shin: 30, thigh: -56, torso: 8,
                          upperArm: 0, forearm: 0, rear: (-8, -122), load: .dumbbells)
            ],
            viewNote: "Side view"
        ),

        // Phases: Lower 3s → Step up 1s
        "Weighted Step-Up": MovementAnimation(
            keyframes: [
                .grounded(ankleX: 0.52, ground: 0.78, shin: 2, thigh: -2, torso: 10,
                          upperArm: 0, forearm: 0, rear: (-16, -10), load: .dumbbells),
                .grounded(ankleX: 0.52, ground: 0.78, shin: 34, thigh: -60, torso: 20,
                          upperArm: 0, forearm: 0, rear: (-30, 6), load: .dumbbells)
            ],
            viewNote: "Side view, working foot on the box",
            platform: .box(minX: 0.30, maxX: 0.98, top: 0.78)
        ),

        // Phases: Chop across 1s → Resist back 3s
        "Cable Woodchop": MovementAnimation(
            keyframes: [
                .grounded(ankleX: 0.46, shin: 4, thigh: -4, torso: -6,
                          upperArm: 148, forearm: 150,
                          load: .cable(anchor: CGPoint(x: 0.95, y: 0.30))),
                .grounded(ankleX: 0.46, shin: 18, thigh: -26, torso: 28,
                          upperArm: 36, forearm: 38,
                          load: .cable(anchor: CGPoint(x: 0.95, y: 0.30)))
            ],
            viewNote: "Side view, cable anchored high"
        ),

        // Phases: Lower 3s → Drive 1s
        "Bulgarian Split Squat": MovementAnimation(
            keyframes: [
                .grounded(ankleX: 0.46, shin: 4, thigh: -4, torso: 8,
                          upperArm: 0, forearm: 0, rear: (-40, -74), load: .dumbbells),
                .grounded(ankleX: 0.46, shin: 18, thigh: -60, torso: 14,
                          upperArm: 0, forearm: 0, rear: (-26, -104), load: .dumbbells)
            ],
            viewNote: "Side view, back foot on a bench",
            platform: .box(minX: 0.02, maxX: 0.30, top: 0.64)
        ),

        // Phases: Lower 3s → Pull 1s. Keyframe 0 is the top, since the tempo
        // starts from a chin-over-bar position.
        "Pull-Up / Lat Pulldown": MovementAnimation(
            keyframes: [
                .free(hip: CGPoint(x: 0.50, y: 0.54), torso: -6, thigh: 16, shin: -115,
                      upperArm: 120, forearm: 230, load: .fixedBar),
                .free(hip: CGPoint(x: 0.50, y: 0.70), torso: -3, thigh: 10, shin: -115,
                      upperArm: 178, forearm: 179, load: .fixedBar)
            ],
            viewNote: "Side view, hanging from the bar",
            showsFloor: false
        ),

        // Phases: Lower 2s → Row 1s
        "Barbell Row": MovementAnimation(
            keyframes: [
                .grounded(ankleX: 0.44, shin: -2, thigh: -12, torso: 66,
                          upperArm: -46, forearm: 6, load: .barInHands),
                .grounded(ankleX: 0.44, shin: -2, thigh: -12, torso: 66,
                          upperArm: 14, forearm: 14, load: .barInHands)
            ],
            viewNote: "Side view"
        ),

        // Phases: Pull apart 1s → Hold 1s → Return 2s
        "Face Pull": MovementAnimation(
            keyframes: [
                .grounded(ankleX: 0.46, shin: 4, thigh: -4, torso: 4,
                          upperArm: 86, forearm: 88,
                          load: .cable(anchor: CGPoint(x: 0.95, y: 0.30))),
                .grounded(ankleX: 0.46, shin: 4, thigh: -4, torso: 4,
                          upperArm: 40, forearm: -30,
                          load: .cable(anchor: CGPoint(x: 0.95, y: 0.30))),
                .grounded(ankleX: 0.46, shin: 4, thigh: -4, torso: 4,
                          upperArm: 40, forearm: -30,
                          load: .cable(anchor: CGPoint(x: 0.95, y: 0.30)))
            ],
            viewNote: "Side view, cable at face height"
        ),

        // Phases: Press out 1s → Resist 3s → Return 1s
        "Pallof Press": MovementAnimation(
            keyframes: [
                .grounded(ankleX: 0.46, shin: 6, thigh: -6, torso: 2,
                          upperArm: 62, forearm: 4,
                          load: .cable(anchor: CGPoint(x: 0.95, y: 0.30))),
                .grounded(ankleX: 0.46, shin: 6, thigh: -6, torso: 2,
                          upperArm: 88, forearm: 90,
                          load: .cable(anchor: CGPoint(x: 0.95, y: 0.30))),
                .grounded(ankleX: 0.46, shin: 6, thigh: -6, torso: 2,
                          upperArm: 88, forearm: 90,
                          load: .cable(anchor: CGPoint(x: 0.95, y: 0.30)))
            ],
            viewNote: "Side view — the cable is pulling you sideways"
        ),

        // Phases: Knee forward 2s → Hold 1s → Return 1s
        "Ankle Dorsiflexion Drill": MovementAnimation(
            keyframes: [
                .grounded(ankleX: 0.46, shin: 6, thigh: -58, torso: 4,
                          upperArm: 40, forearm: 44, rear: (-16, -168)),
                .grounded(ankleX: 0.46, shin: 32, thigh: -78, torso: 8,
                          upperArm: 44, forearm: 48, rear: (-16, -168)),
                .grounded(ankleX: 0.46, shin: 32, thigh: -78, torso: 8,
                          upperArm: 44, forearm: 48, rear: (-16, -168))
            ],
            viewNote: "Half-kneeling, knee driving toward a wall",
            platform: .wall(x: 0.72)
        )
    ]
}
