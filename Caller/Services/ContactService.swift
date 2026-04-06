import FirebaseFirestore
import Foundation

protocol ContactServicing {
    func fetchContacts() async throws -> [AppUser]
    func fetchUser(id: String) async throws -> AppUser?
    func updateUsername(_ username: String, for user: AppUser) async throws -> AppUser
    func searchUser(username: String) async throws -> AppUser?
}

protocol FriendServicing {
    func fetchIncomingRequests() async throws -> [FriendRequest]
    func observeIncomingRequests() -> AsyncStream<[FriendRequest]>
    func fetchOutgoingRequests() async throws -> [OutgoingFriendRequest]
    func observeOutgoingRequests() -> AsyncStream<[OutgoingFriendRequest]>
    func sendFriendRequest(to user: AppUser) async throws
    func acceptFriendRequest(from user: AppUser) async throws
    func declineFriendRequest(from user: AppUser) async throws
    func cancelOutgoingRequest(to user: AppUser) async throws
    func removeFriend(_ user: AppUser) async throws
}

struct MockContactService: ContactServicing {
    func fetchContacts() async throws -> [AppUser] {
        try await Task.sleep(for: .milliseconds(350))
        return [
            AppUser(id: "jordan", displayName: "Jordan Lee", email: "jordan@example.com", avatarSystemName: "person.crop.circle.fill", username: "jordan"),
            AppUser(id: "maya", displayName: "Maya Patel", email: "maya@example.com", avatarSystemName: "person.crop.circle.fill", username: "maya"),
            AppUser(id: "noah", displayName: "Noah Kim", email: "noah@example.com", avatarSystemName: "person.crop.circle.fill", username: "noah"),
            AppUser(id: "amelia", displayName: "Amelia Stone", email: "amelia@example.com", avatarSystemName: "person.crop.circle.fill", username: "amelia")
        ]
    }

    func fetchUser(id: String) async throws -> AppUser? {
        try await fetchContacts().first { $0.id == id }
    }

    func updateUsername(_ username: String, for user: AppUser) async throws -> AppUser {
        AppUser(
            id: user.id,
            displayName: user.displayName,
            email: user.email,
            avatarSystemName: user.avatarSystemName,
            username: username
        )
    }

    func searchUser(username: String) async throws -> AppUser? {
        let normalizedUsername = username.lowercased()
        return try await fetchContacts().first { $0.username?.lowercased() == normalizedUsername }
    }
}

struct MockFriendService: FriendServicing {
    func fetchIncomingRequests() async throws -> [FriendRequest] {
        try await Task.sleep(for: .milliseconds(150))
        return [
            FriendRequest(
                id: "request-amelia",
                fromUser: AppUser(
                    id: "amelia",
                    displayName: "Amelia Stone",
                    email: "amelia@example.com",
                    avatarSystemName: "person.crop.circle.fill",
                    username: "amelia"
                ),
                sentAt: .now
            )
        ]
    }

    func observeIncomingRequests() -> AsyncStream<[FriendRequest]> {
        AsyncStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }

    func fetchOutgoingRequests() async throws -> [OutgoingFriendRequest] {
        []
    }

    func observeOutgoingRequests() -> AsyncStream<[OutgoingFriendRequest]> {
        AsyncStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }

    func sendFriendRequest(to user: AppUser) async throws {
        _ = user
    }

    func acceptFriendRequest(from user: AppUser) async throws {
        _ = user
    }

    func declineFriendRequest(from user: AppUser) async throws {
        _ = user
    }

    func cancelOutgoingRequest(to user: AppUser) async throws {
        _ = user
    }

    func removeFriend(_ user: AppUser) async throws {
        _ = user
    }
}

final class FirebaseSocialGraphService: ContactServicing, FriendServicing {
    let currentUserProvider: () -> AppUser?
    private let db: Firestore

    init(
        db: Firestore = Firestore.firestore(),
        currentUserProvider: @escaping () -> AppUser?
    ) {
        self.db = db
        self.currentUserProvider = currentUserProvider
    }

    func fetchContacts() async throws -> [AppUser] {
        guard let currentUserID = currentUserProvider()?.id else { return [] }

        let snapshot = try await db
            .collection("users")
            .document(currentUserID)
            .collection("friends")
            .order(by: "displayName")
            .getDocuments()

        return snapshot.documents.compactMap { document in
            let id = (document["id"] as? String) ?? document.documentID

            guard let displayName = document["displayName"] as? String,
                  let email = document["email"] as? String else {
                return nil
            }

            if id == currentUserID {
                return nil
            }

            return AppUser(
                id: id,
                displayName: displayName,
                email: email,
                avatarSystemName: document["avatarSystemName"] as? String ?? "person.crop.circle.fill",
                username: document["username"] as? String
            )
        }
    }

    func fetchUser(id: String) async throws -> AppUser? {
        let document = try await db.collection("users").document(id).getDocument()

        guard let data = document.data(),
              let displayName = data["displayName"] as? String,
              let email = data["email"] as? String else {
            return nil
        }

        return AppUser(
            id: (data["id"] as? String) ?? document.documentID,
            displayName: displayName,
            email: email,
            avatarSystemName: data["avatarSystemName"] as? String ?? "person.crop.circle.fill",
            username: data["username"] as? String
        )
    }

    func fetchIncomingRequests() async throws -> [FriendRequest] {
        guard let currentUserID = currentUserProvider()?.id else { return [] }

        let snapshot = try await db
            .collection("users")
            .document(currentUserID)
            .collection("friendRequests")
            .order(by: "sentAt", descending: true)
            .getDocuments()

        return await makeFriendRequests(from: snapshot.documents)
    }

    func observeIncomingRequests() -> AsyncStream<[FriendRequest]> {
        guard let currentUserID = currentUserProvider()?.id else {
            return AsyncStream { continuation in
                continuation.yield([])
                continuation.finish()
            }
        }

        return AsyncStream { continuation in
            let listener = db
                .collection("users")
                .document(currentUserID)
                .collection("friendRequests")
                .order(by: "sentAt", descending: true)
                .addSnapshotListener { [weak self] snapshot, error in
                    guard let self else { return }

                    if error != nil {
                        continuation.yield([])
                        return
                    }

                    guard let documents = snapshot?.documents else {
                        continuation.yield([])
                        return
                    }

                    Task {
                        let requests = await self.makeFriendRequests(from: documents)
                        continuation.yield(requests)
                    }
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func fetchOutgoingRequests() async throws -> [OutgoingFriendRequest] {
        guard let currentUserID = currentUserProvider()?.id else { return [] }

        let snapshot = try await db
            .collection("users")
            .document(currentUserID)
            .collection("outgoingFriendRequests")
            .order(by: "sentAt", descending: true)
            .getDocuments()

        return await makeOutgoingFriendRequests(from: snapshot.documents)
    }

    func observeOutgoingRequests() -> AsyncStream<[OutgoingFriendRequest]> {
        guard let currentUserID = currentUserProvider()?.id else {
            return AsyncStream { continuation in
                continuation.yield([])
                continuation.finish()
            }
        }

        return AsyncStream { continuation in
            let listener = db
                .collection("users")
                .document(currentUserID)
                .collection("outgoingFriendRequests")
                .order(by: "sentAt", descending: true)
                .addSnapshotListener { [weak self] snapshot, error in
                    guard let self else { return }

                    if error != nil {
                        continuation.yield([])
                        return
                    }

                    guard let documents = snapshot?.documents else {
                        continuation.yield([])
                        return
                    }

                    Task {
                        let requests = await self.makeOutgoingFriendRequests(from: documents)
                        continuation.yield(requests)
                    }
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func sendFriendRequest(to user: AppUser) async throws {
        guard let currentUser = currentUserProvider() else { return }

        let sentAt = Timestamp(date: .now)
        let batch = db.batch()

        let incomingRef = db
            .collection("users")
            .document(user.id)
            .collection("friendRequests")
            .document(currentUser.id)
        batch.setData([
            "fromUserID": currentUser.id,
            "sentAt": sentAt
        ], forDocument: incomingRef)

        let outgoingRef = db
            .collection("users")
            .document(currentUser.id)
            .collection("outgoingFriendRequests")
            .document(user.id)
        batch.setData([
            "toUserID": user.id,
            "sentAt": sentAt
        ], forDocument: outgoingRef)

        try await batch.commit()
    }

    func updateUsername(_ username: String, for user: AppUser) async throws -> AppUser {
        let normalizedUsername = username.lowercased()
        let usersRef = db.collection("users").document(user.id)
        let usernameRef = db.collection("usernames").document(normalizedUsername)

        let transactionResult = try await db.runTransaction { transaction, errorPointer in
            let currentProfile: DocumentSnapshot
            do {
                currentProfile = try transaction.getDocument(usersRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            let usernameDocument: DocumentSnapshot
            do {
                usernameDocument = try transaction.getDocument(usernameRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            if let existingUserID = usernameDocument.data()?["userID"] as? String,
               existingUserID != user.id {
                errorPointer?.pointee = ContactServiceError.usernameTaken as NSError
                return nil
            }

            if let existingUsername = currentProfile.data()?["usernameLowercased"] as? String,
               existingUsername != normalizedUsername {
                transaction.deleteDocument(self.db.collection("usernames").document(existingUsername))
            }

            transaction.setData([
                "userID": user.id,
                "username": username,
                "updatedAt": Timestamp(date: .now)
            ], forDocument: usernameRef)

            transaction.setData([
                "id": user.id,
                "displayName": user.displayName,
                "email": user.email,
                "avatarSystemName": user.avatarSystemName,
                "username": username,
                "usernameLowercased": normalizedUsername,
                "updatedAt": Timestamp(date: .now)
            ], forDocument: usersRef, merge: true)

            return true
        }
        guard transactionResult != nil else {
            throw ContactServiceError.usernameUpdateFailed
        }

        return AppUser(
            id: user.id,
            displayName: user.displayName,
            email: user.email,
            avatarSystemName: user.avatarSystemName,
            username: username
        )
    }

    func searchUser(username: String) async throws -> AppUser? {
        guard let currentUserID = currentUserProvider()?.id else { return nil }

        let normalizedUsername = username.lowercased()
        let usernameDocument = try await db.collection("usernames").document(normalizedUsername).getDocument()
        guard let data = usernameDocument.data(),
              let userID = data["userID"] as? String,
              userID != currentUserID else {
            return nil
        }

        let userDocument = db.collection("users").document(userID)
        let currentUserDocument = db.collection("users").document(currentUserID)

        let friendSnapshot = try await currentUserDocument.collection("friends").document(userID).getDocument()
        let incomingSnapshot = try await currentUserDocument.collection("friendRequests").document(userID).getDocument()
        let outgoingSnapshot = try await currentUserDocument.collection("outgoingFriendRequests").document(userID).getDocument()

        if friendSnapshot.exists || incomingSnapshot.exists || outgoingSnapshot.exists {
            return nil
        }

        let userSnapshot = try await userDocument.getDocument()
        guard let userData = userSnapshot.data(),
              let displayName = userData["displayName"] as? String,
              let email = userData["email"] as? String else {
            return nil
        }

        return AppUser(
            id: userID,
            displayName: displayName,
            email: email,
            avatarSystemName: userData["avatarSystemName"] as? String ?? "person.crop.circle.fill",
            username: userData["username"] as? String
        )
    }

    func acceptFriendRequest(from user: AppUser) async throws {
        guard let currentUser = currentUserProvider() else { return }

        let acceptedAt = Timestamp(date: .now)
        let batch = db.batch()

        let currentFriendRef = db
            .collection("users")
            .document(currentUser.id)
            .collection("friends")
            .document(user.id)
        batch.setData(friendPayload(for: user, acceptedAt: acceptedAt), forDocument: currentFriendRef)

        let otherFriendRef = db
            .collection("users")
            .document(user.id)
            .collection("friends")
            .document(currentUser.id)
        batch.setData(friendPayload(for: currentUser, acceptedAt: acceptedAt), forDocument: otherFriendRef)

        let incomingRef = db
            .collection("users")
            .document(currentUser.id)
            .collection("friendRequests")
            .document(user.id)
        batch.deleteDocument(incomingRef)

        let outgoingRef = db
            .collection("users")
            .document(user.id)
            .collection("outgoingFriendRequests")
            .document(currentUser.id)
        batch.deleteDocument(outgoingRef)

        try await batch.commit()
    }

    func declineFriendRequest(from user: AppUser) async throws {
        guard let currentUser = currentUserProvider() else { return }

        let batch = db.batch()

        let incomingRef = db
            .collection("users")
            .document(currentUser.id)
            .collection("friendRequests")
            .document(user.id)
        batch.deleteDocument(incomingRef)

        let outgoingRef = db
            .collection("users")
            .document(user.id)
            .collection("outgoingFriendRequests")
            .document(currentUser.id)
        batch.deleteDocument(outgoingRef)

        try await batch.commit()
    }

    func cancelOutgoingRequest(to user: AppUser) async throws {
        guard let currentUser = currentUserProvider() else { return }

        let batch = db.batch()

        let outgoingRef = db
            .collection("users")
            .document(currentUser.id)
            .collection("outgoingFriendRequests")
            .document(user.id)
        batch.deleteDocument(outgoingRef)

        let incomingRef = db
            .collection("users")
            .document(user.id)
            .collection("friendRequests")
            .document(currentUser.id)
        batch.deleteDocument(incomingRef)

        try await batch.commit()
    }

    func removeFriend(_ user: AppUser) async throws {
        guard let currentUser = currentUserProvider() else { return }

        let batch = db.batch()

        let currentFriendRef = db
            .collection("users")
            .document(currentUser.id)
            .collection("friends")
            .document(user.id)
        batch.deleteDocument(currentFriendRef)

        let otherFriendRef = db
            .collection("users")
            .document(user.id)
            .collection("friends")
            .document(currentUser.id)
        batch.deleteDocument(otherFriendRef)

        try await batch.commit()
    }

    private func friendPayload(for user: AppUser, acceptedAt: Timestamp) -> [String: Any] {
        var payload: [String: Any] = [
            "id": user.id,
            "displayName": user.displayName,
            "email": user.email,
            "avatarSystemName": user.avatarSystemName,
            "acceptedAt": acceptedAt
        ]

        if let username = user.username, !username.isEmpty {
            payload["username"] = username
        }

        return payload
    }

    private func makeFriendRequests(from documents: [QueryDocumentSnapshot]) async -> [FriendRequest] {
        var requests: [FriendRequest] = []

        for document in documents {
            let fromUserID = document.documentID

            guard let userDocument = try? await db.collection("users").document(fromUserID).getDocument(),
                  let data = userDocument.data(),
                  let displayName = data["displayName"] as? String,
                  let email = data["email"] as? String else {
                continue
            }

            requests.append(
                FriendRequest(
                    id: document.documentID,
                    fromUser: AppUser(
                        id: fromUserID,
                        displayName: displayName,
                        email: email,
                        avatarSystemName: data["avatarSystemName"] as? String ?? "person.crop.circle.fill",
                        username: data["username"] as? String
                    ),
                    sentAt: (document["sentAt"] as? Timestamp)?.dateValue() ?? .now
                )
            )
        }

        return requests
    }

    private func makeOutgoingFriendRequests(from documents: [QueryDocumentSnapshot]) async -> [OutgoingFriendRequest] {
        var requests: [OutgoingFriendRequest] = []

        for document in documents {
            let toUserID = document.documentID

            guard let userDocument = try? await db.collection("users").document(toUserID).getDocument(),
                  let data = userDocument.data(),
                  let displayName = data["displayName"] as? String,
                  let email = data["email"] as? String else {
                continue
            }

            requests.append(
                OutgoingFriendRequest(
                    id: document.documentID,
                    toUser: AppUser(
                        id: toUserID,
                        displayName: displayName,
                        email: email,
                        avatarSystemName: data["avatarSystemName"] as? String ?? "person.crop.circle.fill",
                        username: data["username"] as? String
                    ),
                    sentAt: (document["sentAt"] as? Timestamp)?.dateValue() ?? .now
                )
            )
        }

        return requests
    }
}

enum ContactServiceError: LocalizedError {
    case usernameTaken
    case usernameUpdateFailed

    var errorDescription: String? {
        switch self {
        case .usernameTaken:
            return "Этот никнейм уже занят."
        case .usernameUpdateFailed:
            return "Не удалось сохранить никнейм."
        }
    }
}
