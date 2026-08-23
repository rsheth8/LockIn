import SwiftUI

/// "The Ledger" design system.
///
/// Design thesis: the interface stays calm, precise and expensive-feeling —
/// the *copy* carries the aggression. A UI that shouts is exhausting by week
/// three; a UI that reads like a serious training log is one you keep opening.
///
/// Colour discipline: monochrome ground + a single signal accent (cricket-ball
/// red). Red means "you're slipping" and nothing else, so it never goes numb.
/// A kept promise is rendered in warm bone, not green — staying in one family
/// keeps the whole thing feeling like one instrument.
enum Theme {

    // MARK: - Colour

    /// Page ground. Near-black in dark, warm paper in light — never pure #000/#FFF,
    /// which read as cheap and fatigue the eye.
    static let ground = adaptive(light: hex(0xFAF9F6), dark: hex(0x0B0B0C))

    /// Raised surfaces (hero card, sheets).
    static let surface = adaptive(light: hex(0xFFFFFF), dark: hex(0x151517))

    /// Surface for the dimmed/secondary rows in the timeline.
    static let surfaceMuted = adaptive(light: hex(0xF1EFEA), dark: hex(0x111113))

    /// Primary text — warm off-white on dark, near-black on light.
    static let ink = adaptive(light: hex(0x16161A), dark: hex(0xF2F0EC))

    /// Secondary text: labels, timestamps, supporting detail.
    static let inkMuted = adaptive(light: hex(0x16161A).opacity(0.55), dark: hex(0xF2F0EC).opacity(0.55))

    /// Tertiary: empty states, unfilled grid squares.
    static let inkFaint = adaptive(light: hex(0x16161A).opacity(0.18), dark: hex(0xF2F0EC).opacity(0.16))

    /// The signal. Cricket-ball red — deep oxblood, not neon. Ties to the sport,
    /// reads serious rather than gym-bro. Brighter in dark mode to hold contrast
    /// against the near-black ground.
    static let signal = adaptive(light: hex(0xA8322A), dark: hex(0xD14436))

    /// A promise kept. Warm bone — brighter than body text so filled squares
    /// carry the eye, but still inside the monochrome family.
    static let kept = adaptive(light: hex(0x16161A).opacity(0.82), dark: hex(0xE8E3D9))

    /// Hairline rules — the ledger's defining texture.
    static let rule = adaptive(light: hex(0x16161A).opacity(0.12), dark: hex(0xF2F0EC).opacity(0.12))

    // MARK: - Type
    //
    // Uppercase micro-labels with wide tracking + monospaced numerals is what
    // sells "instrument". Every number in this app (weights, macros, times,
    // counts) should be monospaced so columns line up and values feel measured.

    /// Small uppercase section label: "NEXT", "TODAY", "STREAK".
    static let label = Font.system(size: 11, weight: .semibold).width(.standard)

    /// Big statement type for the hero event title.
    static let hero = Font.system(size: 32, weight: .bold)

    /// Supporting line under the hero title.
    static let heroSub = Font.system(size: 15, weight: .medium)

    /// Any numeric readout.
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).monospaced()
    }

    /// Coach copy — the line that does the actual hitting.
    static let coach = Font.system(size: 15, weight: .medium).italic()

    // MARK: - Metrics

    static let cardRadius: CGFloat = 18
    static let gutter: CGFloat = 20
    static let labelTracking: CGFloat = 1.3

    // MARK: - Helpers

    private static func hex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private static func adaptive(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

// MARK: - Reusable view treatments

extension View {
    /// The uppercase, wide-tracked micro-label used throughout the ledger.
    func ledgerLabel() -> some View {
        self.font(Theme.label)
            .tracking(Theme.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(Theme.inkMuted)
    }

    /// Raised card treatment for the hero and other primary surfaces.
    func ledgerCard() -> some View {
        self.background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.rule, lineWidth: 1)
            )
    }
}

/// Full-bleed hairline, the ledger's connective tissue.
struct LedgerRule: View {
    var body: some View {
        Rectangle()
            .fill(Theme.rule)
            .frame(height: 1)
    }
}
