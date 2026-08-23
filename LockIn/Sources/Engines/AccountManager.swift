import Foundation
import AuthenticationServices
import Combine

/// Sign in with Apple, backed by each person's own private CloudKit database.
///
/// Deliberate privacy posture: we store Apple's stable, app-scoped user
/// identifier and nothing else about the account. No email is requested or
/// retained — Apple relays those and we have no use for one. Health, weight,
/// and photo data live in the signed-in user's *private* iCloud database, so
/// two people using this app never share a data store, and there is no server
/// of ours holding anyone's body metrics.
@MainActor
final class AccountManager: NSObject, ObservableObject {
    @Published private(set) var state: AccountState = .signedOut
    @Published var lastError: String?

    enum AccountState: Equatable {
        case signedOut
        case signedIn(userIdentifier: String)
        /// Using the app without an account — everything stays on this device.
        case local
    }

    private let defaults = UserDefaults.standard
    private let userIDKey = "account.appleUserIdentifier"
    private let localModeKey = "account.localMode"

    override init() {
        super.init()
        restore()
    }

    var currentUserIdentifier: String? {
        if case let .signedIn(id) = state { return id }
        return nil
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    // MARK: - Restore

    private func restore() {
        if let stored = defaults.string(forKey: userIDKey) {
            state = .signedIn(userIdentifier: stored)
            // Apple can revoke a credential (user removed the app from their
            // Apple ID). Verify rather than trusting the cached value forever.
            Task { await verifyCredential(stored) }
        } else if defaults.bool(forKey: localModeKey) {
            state = .local
        }
    }

    private func verifyCredential(_ userID: String) async {
        let provider = ASAuthorizationAppleIDProvider()
        let credentialState = try? await provider.credentialState(forUserID: userID)
        if credentialState == .revoked || credentialState == .notFound {
            signOut()
        }
    }

    // MARK: - Sign in

    /// Configures the request. Note we ask for `.fullName` only — a display
    /// name makes the app feel personal — and never `.email`.
    func configure(request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    func handle(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            let userID = credential.user
            defaults.set(userID, forKey: userIDKey)
            defaults.set(false, forKey: localModeKey)
            state = .signedIn(userIdentifier: userID)
            lastError = nil
        case .failure(let error):
            // A user-cancelled flow isn't an error worth surfacing.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            lastError = error.localizedDescription
        }
    }

    /// Explicitly continue without an account. Everything stays local to the
    /// device and nothing syncs.
    func continueLocally() {
        defaults.set(true, forKey: localModeKey)
        state = .local
    }

    func signOut() {
        defaults.removeObject(forKey: userIDKey)
        defaults.removeObject(forKey: localModeKey)
        state = .signedOut
    }

    /// Display name captured at first sign-in, if Apple provided one. Apple
    /// only returns the name on the *very first* authorization for an app, so
    /// it has to be persisted right then or it's gone.
    func storeDisplayName(from credential: ASAuthorizationAppleIDCredential) -> String? {
        guard let components = credential.fullName else { return nil }
        let name = [components.givenName, components.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        return name.isEmpty ? nil : name
    }
}
