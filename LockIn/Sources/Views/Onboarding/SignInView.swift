import SwiftUI
import AuthenticationServices

/// First screen for a signed-out user. Apple and Google both get you in with
/// one tap and prefill your name so the quiz has less to ask. Continuing
/// locally is a first-class option, not a nag-wall.
///
/// Apple is listed first deliberately: App Store guidelines require Sign in
/// with Apple to be offered wherever a third-party provider is, and it's the
/// option that shares the least about you.
struct SignInView: View {
    @EnvironmentObject var accountManager: AccountManager
    @Environment(\.colorScheme) private var colorScheme
#if DEBUG
    @EnvironmentObject var appState: AppState
#endif

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Wordmark(size: 44)

                Text("Keeps the promises you make to yourself.")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.top, 14)

                Spacer()

                SignInWithAppleButton(.signIn) { request in
                    accountManager.configure(request: request)
                } onCompletion: { result in
                    accountManager.handle(result: result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if accountManager.isGoogleAvailable {
                    Button {
                        Haptics.tap()
                        accountManager.signInWithGoogle()
                    } label: {
                        HStack(spacing: 10) {
                            GoogleGlyph().frame(width: 18, height: 18)
                            Text("Sign in with Google")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.surface)
                        .foregroundStyle(Theme.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.rule, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }

                Button {
                    Haptics.tap()
                    accountManager.continueLocally()
                } label: {
                    Text("Continue without an account")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                Text("Signing in stores your plan in your own private iCloud so it follows you to a new phone. We only ever ask for your name. Your progress photos stay on this device either way.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

#if DEBUG
                Button {
                    Haptics.tap()
                    appState.startDemo()
                } label: {
                    Text("Watch the demo")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.surfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.rule, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
#endif

                if let error = accountManager.lastError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.signal)
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 28)
        }
    }
}

/// Google's mark, drawn inline so the app carries no bundled brand assets and
/// the button renders identically in both themes.
private struct GoogleGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .trim(from: 0.0, to: 0.25)
                    .stroke(Color(red: 0.92, green: 0.26, blue: 0.21), lineWidth: s * 0.26)
                    .rotationEffect(.degrees(-99))
                Circle()
                    .trim(from: 0.0, to: 0.25)
                    .stroke(Color(red: 0.98, green: 0.74, blue: 0.02), lineWidth: s * 0.26)
                    .rotationEffect(.degrees(171))
                Circle()
                    .trim(from: 0.0, to: 0.25)
                    .stroke(Color(red: 0.20, green: 0.66, blue: 0.33), lineWidth: s * 0.26)
                    .rotationEffect(.degrees(81))
                Rectangle()
                    .fill(Color(red: 0.26, green: 0.52, blue: 0.96))
                    .frame(width: s * 0.42, height: s * 0.26)
                    .offset(x: s * 0.16, y: 0)
            }
            .frame(width: s, height: s)
        }
    }
}
