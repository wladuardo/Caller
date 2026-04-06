import AuthenticationServices
import FirebaseAuth
import FirebaseFirestore
import Foundation
import GoogleSignIn

protocol AuthenticationServicing {
    var currentUser: AppUser? { get }
    func signInWithGoogle(idToken: String, accessToken: String) async throws -> AppUser
    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws -> AppUser
    func signOut() async
    func deleteAccount() async throws
}

final class MockAuthenticationService: AuthenticationServicing {
    private(set) var currentUser: AppUser?

    func signInWithGoogle(idToken: String, accessToken: String) async throws -> AppUser {
        _ = idToken
        _ = accessToken
        try await Task.sleep(for: .milliseconds(700))
        let user = AppUser(
            id: UUID().uuidString,
            displayName: "Пользователь Google",
            email: "google.user@example.com",
            avatarSystemName: "person.crop.circle.fill",
            username: nil
        )
        currentUser = user
        return user
    }

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws -> AppUser {
        _ = idToken
        _ = nonce
        _ = fullName
        try await Task.sleep(for: .milliseconds(500))
        let user = AppUser(
            id: UUID().uuidString,
            displayName: "Пользователь Apple",
            email: "apple.user@example.com",
            avatarSystemName: "person.crop.circle.badge.checkmark",
            username: nil
        )
        currentUser = user
        return user
    }

    func signOut() async {
        currentUser = nil
    }

    func deleteAccount() async throws {
        currentUser = nil
    }
}

final class FirebaseAuthenticationService: AuthenticationServicing {
    private(set) var currentUser: AppUser?

    init() {
        if let firebaseUser = Auth.auth().currentUser {
            currentUser = AppUser(firebaseUser: firebaseUser)
        }
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws -> AppUser {
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: accessToken
        )
        let result = try await Auth.auth().signIn(with: credential)
        let user = AppUser(firebaseUser: result.user)
        currentUser = user
        try? await FirebaseUserProfileStore().upsert(user: user)
        return user
    }

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) async throws -> AppUser {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: fullName
        )
        let result = try await Auth.auth().signIn(with: credential)
        let fallbackName = [fullName?.givenName, fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let user = AppUser(
            id: result.user.uid,
            displayName: fallbackName.isEmpty ? (result.user.displayName ?? result.user.email ?? "Пользователь Apple") : fallbackName,
            email: result.user.email ?? "apple.user@example.com",
            avatarSystemName: "person.crop.circle.badge.checkmark",
            username: nil
        )
        currentUser = user
        try? await FirebaseUserProfileStore().upsert(user: user)
        return user
    }

    func signOut() async {
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
        currentUser = nil
    }

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            currentUser = nil
            return
        }

        let db = FirebaseFirestore.Firestore.firestore()
        let userRef = db.collection("users").document(user.uid)
        if let data = try? await userRef.getDocument().data(),
           let usernameLowercased = data["usernameLowercased"] as? String {
            try? await db.collection("usernames").document(usernameLowercased).delete()
        }
        try? await userRef.delete()
        try await user.delete()
        GIDSignIn.sharedInstance.signOut()
        currentUser = nil
    }
}

private struct FirebaseUserProfileStore {
    func upsert(user: AppUser) async throws {
        let db = FirebaseFirestore.Firestore.firestore()
        var data: [String: Any] = [
            "id": user.id,
            "displayName": user.displayName,
            "email": user.email,
            "avatarSystemName": user.avatarSystemName,
            "updatedAt": Timestamp(date: .now)
        ]

        if let username = user.username, !username.isEmpty {
            data["username"] = username
            data["usernameLowercased"] = username.lowercased()
        }

        try await db.collection("users").document(user.id).setData(data, merge: true)
    }
}

extension AppUser {
    init(firebaseUser: FirebaseAuth.User) {
        self.init(
            id: firebaseUser.uid,
            displayName: firebaseUser.displayName ?? firebaseUser.email ?? "Пользователь Caller",
            email: firebaseUser.email ?? "unknown@example.com",
            avatarSystemName: "person.crop.circle.fill",
            username: nil
        )
    }
}
