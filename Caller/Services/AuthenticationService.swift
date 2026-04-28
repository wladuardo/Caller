import AuthenticationServices
import FirebaseAuth
import FirebaseFirestore
import Foundation
import GoogleSignIn
import UIKit

enum AuthenticationServiceError: LocalizedError {
    case recentLoginRequiredForApple
    case googleReauthenticationFailed
    case userDeletionFailed

    var errorDescription: String? {
        switch self {
        case .recentLoginRequiredForApple:
            return "Для удаления аккаунта Apple требуется повторный вход. Выйдите и войдите снова, затем повторите попытку."
        case .googleReauthenticationFailed:
            return "Не удалось подтвердить Google-аккаунт перед удалением. Повторите вход и попробуйте снова."
        case .userDeletionFailed:
            return "Не удалось удалить аккаунт. Попробуйте ещё раз."
        }
    }
}

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
            avatarURL: nil,
            username: nil,
            deviceModel: DeviceModelResolver.currentDeviceModelName()
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
            avatarURL: nil,
            username: nil,
            deviceModel: DeviceModelResolver.currentDeviceModelName()
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
    private let recentLoginThreshold: TimeInterval = 5 * 60

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
        await ChatEncryptionService.shared.ensureCurrentUserPublicKeyIsPublished(userID: user.id)
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
            avatarURL: nil,
            username: nil,
            deviceModel: DeviceModelResolver.currentDeviceModelName()
        )
        currentUser = user
        try? await FirebaseUserProfileStore().upsert(user: user)
        await ChatEncryptionService.shared.ensureCurrentUserPublicKeyIsPublished(userID: user.id)
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

        try await ensureRecentLoginIfNeeded(for: user)

        let db = FirebaseFirestore.Firestore.firestore()
        let userRef = db.collection("users").document(user.uid)
        let batch = db.batch()

        try await deleteSocialGraphReferences(for: user.uid, in: db)

        if let data = try? await userRef.getDocument().data(),
           let usernameLowercased = data["usernameLowercased"] as? String {
            batch.deleteDocument(db.collection("usernames").document(usernameLowercased))
        }

        batch.deleteDocument(userRef)
        try await batch.commit()

        do {
            try await user.delete()
        } catch {
            throw mapDeletionError(error)
        }

        GIDSignIn.sharedInstance.signOut()
        currentUser = nil
    }

    private func ensureRecentLoginIfNeeded(for user: FirebaseAuth.User) async throws {
        if let lastSignInDate = user.metadata.lastSignInDate,
           Date().timeIntervalSince(lastSignInDate) < recentLoginThreshold {
            return
        }

        let providerIDs = Set(user.providerData.map(\.providerID))
        if providerIDs.contains(GoogleAuthProviderID) {
            try await reauthenticateWithGoogle(user: user)
            return
        }

        if providerIDs.contains(AppleAuthProviderID) {
            throw AuthenticationServiceError.recentLoginRequiredForApple
        }
    }

    private func reauthenticateWithGoogle(user: FirebaseAuth.User) async throws {
        let googleUser = try await restorePreviousGoogleUser()
        guard let idToken = googleUser.idToken?.tokenString else {
            throw AuthenticationServiceError.googleReauthenticationFailed
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: googleUser.accessToken.tokenString
        )

        do {
            _ = try await user.reauthenticate(with: credential)
        } catch {
            throw mapDeletionError(error)
        }
    }

    private func restorePreviousGoogleUser() async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: error ?? AuthenticationServiceError.googleReauthenticationFailed)
                }
            }
        }
    }

    private func mapDeletionError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard let authErrorCode = AuthErrorCode(_bridgedNSError: nsError) else {
            return error
        }

        switch authErrorCode.code {
        case .requiresRecentLogin:
            return AuthenticationServiceError.recentLoginRequiredForApple
        case .userNotFound:
            return AuthenticationServiceError.userDeletionFailed
        default:
            return error
        }
    }

    private func deleteSocialGraphReferences(for userID: String, in db: Firestore) async throws {
        let userDocument = db.collection("users").document(userID)

        async let ownFriendsSnapshot = userDocument.collection("friends").getDocuments()
        async let ownIncomingRequestsSnapshot = userDocument.collection("friendRequests").getDocuments()
        async let ownOutgoingRequestsSnapshot = userDocument.collection("outgoingFriendRequests").getDocuments()

        let ownFriends = try await ownFriendsSnapshot.documents
        let ownIncomingRequests = try await ownIncomingRequestsSnapshot.documents
        let ownOutgoingRequests = try await ownOutgoingRequestsSnapshot.documents

        var documentReferences = Set(ownFriends.map(\.reference))
        documentReferences.formUnion(ownIncomingRequests.map(\.reference))
        documentReferences.formUnion(ownOutgoingRequests.map(\.reference))

        for friend in ownFriends {
            documentReferences.insert(
                db.collection("users")
                    .document(friend.documentID)
                    .collection("friends")
                    .document(userID)
            )
        }

        for incomingRequest in ownIncomingRequests {
            documentReferences.insert(
                db.collection("users")
                    .document(incomingRequest.documentID)
                    .collection("outgoingFriendRequests")
                    .document(userID)
            )
        }

        for outgoingRequest in ownOutgoingRequests {
            documentReferences.insert(
                db.collection("users")
                    .document(outgoingRequest.documentID)
                    .collection("friendRequests")
                    .document(userID)
            )
        }

        try await deleteDocuments(Array(documentReferences), in: db)
    }

    private func deleteDocuments(_ references: [DocumentReference], in db: Firestore) async throws {
        guard !references.isEmpty else { return }

        for chunkStart in stride(from: 0, to: references.count, by: 400) {
            let batch = db.batch()
            let chunkEnd = min(chunkStart + 400, references.count)
            for reference in references[chunkStart..<chunkEnd] {
                batch.deleteDocument(reference)
            }
            try await batch.commit()
        }
    }
}

private let GoogleAuthProviderID = "google.com"
private let AppleAuthProviderID = "apple.com"

private struct FirebaseUserProfileStore {
    func upsert(user: AppUser) async throws {
        let db = FirebaseFirestore.Firestore.firestore()
        var data: [String: Any] = [
            "id": user.id,
            "displayName": user.displayName,
            "email": user.email,
            "avatarSystemName": user.avatarSystemName,
            "deviceModel": user.deviceModel ?? DeviceModelResolver.currentDeviceModelName(),
            "updatedAt": Timestamp(date: .now)
        ]

        if let avatarURL = user.avatarURL, !avatarURL.isEmpty {
            data["avatarURL"] = avatarURL
        }

        if let username = user.username, !username.isEmpty {
            data["username"] = username
            data["usernameLowercased"] = username.lowercased()
        }

        if let publicKey = try? ChatEncryptionService.shared.currentPublicKeyBase64() {
            data["chatEncryptionPublicKey"] = publicKey
            data["chatEncryptionVersion"] = 1
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
            avatarURL: nil,
            username: nil,
            deviceModel: DeviceModelResolver.currentDeviceModelName(),
            chatEncryptionPublicKey: nil
        )
    }
}
