import SwiftUI

/// User-selectable highlight colour.
///
/// Deliberately separate from `Theme.signal`. Signal red means exactly one
/// thing — you're slipping — and stays fixed so it never loses its bite. The
/// accent is personality: streak flame, progress fills, selected states,
/// primary actions. Two different jobs, two different colours.
///
/// Every entry carries a light and dark variant, each picked to hold contrast
/// against its ground. That's why this is a curated set rather than a free
/// picker — an unconstrained choice will be illegible in one of the two themes.
enum AppAccent: String, Codable, CaseIterable, Identifiable {
    case ember      // warm orange — default, close to the original cricket red family
    case moss       // deep green
    case ocean      // teal-blue
    case indigo
    case plum
    case clay       // terracotta
    case slate      // near-neutral blue-grey, for people who want almost none
    case gold

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var color: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    private var light: Color {
        switch self {
        case .ember:  return hex(0xC2410C)
        case .moss:   return hex(0x3F6212)
        case .ocean:  return hex(0x0E7490)
        case .indigo: return hex(0x4338CA)
        case .plum:   return hex(0x86198F)
        case .clay:   return hex(0xA16207)
        case .slate:  return hex(0x475569)
        case .gold:   return hex(0x92700E)
        }
    }

    private var dark: Color {
        switch self {
        case .ember:  return hex(0xFB923C)
        case .moss:   return hex(0x84CC16)
        case .ocean:  return hex(0x22D3EE)
        case .indigo: return hex(0x818CF8)
        case .plum:   return hex(0xE879F9)
        case .clay:   return hex(0xFBBF24)
        case .slate:  return hex(0x94A3B8)
        case .gold:   return hex(0xFACC15)
        }
    }

    private func hex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// MARK: - Environment plumbing

private struct AccentColorKey: EnvironmentKey {
    static let defaultValue: AppAccent = .ember
}

extension EnvironmentValues {
    /// Read with `@Environment(\.accent)` so a change in Settings propagates
    /// through the whole tree without any view holding its own copy.
    var accent: AppAccent {
        get { self[AccentColorKey.self] }
        set { self[AccentColorKey.self] = newValue }
    }
}
