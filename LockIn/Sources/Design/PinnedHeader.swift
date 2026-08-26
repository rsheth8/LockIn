import SwiftUI

extension View {
    /// Pins `header` above a scrolling screen via `safeAreaInset` instead of
    /// letting it be the first item inside the scroll content. Without this,
    /// scrolling the content up slides it — and whatever follows it — behind
    /// the system status bar with nothing opaque behind the clock/battery
    /// icons to mask it. None of the three tabs use a system nav bar (see
    /// `ScreenHeader`), so nothing else provides that backing by default.
    func pinnedHeader<Header: View>(@ViewBuilder _ header: @escaping () -> Header) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            header()
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Theme.ground)
        }
    }
}
