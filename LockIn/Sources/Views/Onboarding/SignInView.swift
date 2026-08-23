import SwiftUI
import AuthenticationServices

/// First screen for a signed-out user. Sign in with Apple keeps each person's
/// data in their own private iCloud, which is what makes two people on two
/// phones work without us running a server or mixing anyone's health data.
/// Continuing locally is a first-class option, not a nag-wall.
struct SignInView: View {
    @EnvironmentObject var accountManager: AccountManager
    @Environment(\.colorScheme) private var colorScheme

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

                Text("Signing in stores your plan in your own private iCloud so it follows you to a new phone. Your progress photos always stay on this device either way.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

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
