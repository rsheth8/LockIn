import Foundation
import AuthenticationServices
import GoogleSignIn
import Combine
import UIKit

/// Sign in with Apple or Google, with each person's data still living in their
/// own private CloudKit database.
///
/// Privacy posture, unchanged by adding Google: we keep a provider-scoped user
/// identifier and a display name, and nothing else. We request the minimum
/// scope each provider offers — Apple gets `.fullName` only, Google's default
/// profile scope. No contacts, no calendar, no ad identifiers, and no server of
/// ours holding anyone's health data.
///
/// Note on sync: CloudKit's private database is always keyed to the *device's*
/// iCloud account, not to our auth provider. So a Google-signed-in user still
/// syncs through their own iCloud — the Google identity supplies the name and a
/// stable app identity, not the storage.
@MainActor
final class AccountManager: NSObject, ObservableObject {
    @Published private(set) var state: AccountState = .signedOut
    @Published var lastError: String?
    /// Display name captured at sign-in, used to prefill the quiz.
    @Published private(set) var displayName: String?

    enum Provider: String, Codable {
        case apple, google
    }

    enum AccountState: Equatable {
        case signedOut
        case signedIn(provider: Provider, userIdentifier: String)
        /// Using the app without an account — everything stays on this device.
        case local
    }

    private let defaults = UserDefaults.standard
    private let userIDKey = "account.userIdentifier"
    private let providerKey = "account.provider"
    private let displayNameKey = "account.displayName"
    private let localModeKey = "account.localMode"

    override init() {
        super.init()
        displayName = defaults.string(forKey: displayNameKey)
        restore()
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    var currentUserIdentifier: String? {
        if case let .signedIn(_, id) = state { return id }
        return nil
    }

    /// Google sign-in only appears once a client ID is configured, so an
    /// unconfigured build shows Apple + local rather than a button that fails.
    var isGoogleAvailable: Bool { Secrets.googleClientID != nil }

    // MARK: - Restore

    private func restore() {
        if let stored = defaults.string(forKey: userIDKey),
           let raw = defaults.string(forKey: providerKey),
           let provider = Provider(rawValue: raw) {
            state = .signedIn(provider: provider, userIdentifier: stored)
            if provider == .apple {
                // Apple can revoke a credential (user removed the app from their
                // Apple ID). Verify rather than trusting the cached value forever.
                Task { await verifyAppleCredential(stored) }
            }
        } else if defaults.bool(forKey: localModeKey) {
            state = .local
        }
    }

    private func verifyAppleCredential(_ userID: String) async {
        let provider = ASAuthorizationAppleIDProvider()
        let credentialState = try? await provider.credentialState(forUserID: userID)
        if credentialState == .revoked || credentialState == .notFound {
            signOut()
        }
    }

    // MARK: - Apple

    /// `.fullName` only — never `.email`. Apple relays addresses and we have no
    /// use for one.
    func configure(request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    func handle(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            // Apple returns the name only on the very first authorization, so it
            // has to be persisted right then or it's gone for good.
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            persist(provider: .apple, userID: credential.user, name: name.isEmpty ? nil : name)
        case .failure(let error):
            // A user-cancelled flow isn't an error worth surfacing.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            lastError = error.localizedDescription
        }
    }

    // MARK: - Google

    func signInWithGoogle() {
        guard let clientID = Secrets.googleClientID else {
            lastError = "Google sign-in isn't configured yet."
            return
        }
        guard let presenter = Self.topViewController() else { return }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { [weak self] result, error in
            guard let self else { return }
            if let error {
                // -5 is the user cancelling the sheet.
                if (error as NSError).code == -5 { return }
                self.lastError = error.localizedDescription
                return
            }
            guard let user = result?.user, let userID = user.userID else { return }
            self.persist(provider: .google, userID: userID, name: user.profile?.name)
        }
    }

    /// Called from the app's `onOpenURL` so Google can complete its redirect.
    static func handleRedirect(_ url: URL) {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// Restores a previous Google session without showing UI.
    func restoreGoogleSessionIfNeeded() {
        guard case .signedIn(.google, _) = state else { return }
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, _ in
            guard user == nil else { return }
            // The Google session is gone — drop back to signed out rather than
            // pretending we still have an identity.
            self?.signOut()
        }
    }

    // MARK: - Shared

    private func persist(provider: Provider, userID: String, name: String?) {
        defaults.set(userID, forKey: userIDKey)
        defaults.set(provider.rawValue, forKey: providerKey)
        defaults.set(false, forKey: localModeKey)
        if let name, !name.isEmpty {
            defaults.set(name, forKey: displayNameKey)
            displayName = name
        }
        state = .signedIn(provider: provider, userIdentifier: userID)
        lastError = nil
    }

    /// Explicitly continue without an account. Everything stays local to the
    /// device and nothing syncs.
    func continueLocally() {
        defaults.set(true, forKey: localModeKey)
        state = .local
    }

    func signOut() {
        if case .signedIn(.google, _) = state {
            GIDSignIn.sharedInstance.signOut()
        }
        [userIDKey, providerKey, localModeKey, displayNameKey].forEach {
            defaults.removeObject(forKey: $0)
        }
        displayName = nil
        state = .signedOut
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
