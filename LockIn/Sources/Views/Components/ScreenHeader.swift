import SwiftUI

/// Shared in-content header for every tab. Replaces the system large-title nav
/// bar, which reserved vertical space the Ledger's layout doesn't want and
/// introduced a second type language on top of the design system.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.top, 6)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

/// The LockIn wordmark.
///
/// Rendered uppercase with wide tracking for a specific reason: in SF Pro the
/// capital "I" is a bare vertical stroke, so mixed-case "LockIn" reads as
/// "Lockln" at a glance. Uppercase removes the collision entirely and suits the
/// ledger's label typography.
struct Wordmark: View {
    var size: CGFloat = 40

    var body: some View {
        Text("LOCK IN")
            .font(.system(size: size, weight: .bold))
            .tracking(size * 0.06)
            .foregroundStyle(Theme.ink)
    }
}
