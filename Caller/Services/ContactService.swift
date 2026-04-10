import FirebaseFirestore
import Foundation
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif
import UIKit

protocol ContactServicing {
    func fetchContacts() async throws -> [AppUser]
    func observeContacts() -> AsyncStream<[AppUser]>
    func fetchUser(id: String) async throws -> AppUser?
    func updateUsername(_ username: String, for user: AppUser) async throws -> AppUser
    func updateAvatar(imageData: Data, for user: AppUser) async throws -> AppUser
    func setNotificationsMuted(_ isMuted: Bool, for mutedUserID: String) async throws -> [String]
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

    func observeContacts() -> AsyncStream<[AppUser]> {
        AsyncStream { continuation in
            Task {
                let contacts = (try? await fetchContacts()) ?? []
                continuation.yield(contacts)
                continuation.finish()
            }
        }
    }

    func updateUsername(_ username: String, for user: AppUser) async throws -> AppUser {
        AppUser(
            id: user.id,
            displayName: user.displayName,
            email: user.email,
            avatarSystemName: user.avatarSystemName,
            avatarURL: user.avatarURL,
            username: username,
            mutedNotificationUserIDs: user.mutedNotificationUserIDs
        )
    }

    func updateAvatar(imageData: Data, for user: AppUser) async throws -> AppUser {
        _ = imageData
        return AppUser(
            id: user.id,
            displayName: user.displayName,
            email: user.email,
            avatarSystemName: user.avatarSystemName,
            avatarURL: user.avatarURL,
            username: user.username,
            mutedNotificationUserIDs: user.mutedNotificationUserIDs
        )
    }

    func setNotificationsMuted(_ isMuted: Bool, for mutedUserID: String) async throws -> [String] {
        _ = isMuted
        _ = mutedUserID
        return []
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

        return makeContacts(from: snapshot.documents, currentUserID: currentUserID)
    }

    func observeContacts() -> AsyncStream<[AppUser]> {
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
                .collection("friends")
                .order(by: "displayName")
                .addSnapshotListener { snapshot, error in
                    if error != nil {
                        continuation.yield([])
                        return
                    }

                    guard let documents = snapshot?.documents else {
                        continuation.yield([])
                        return
                    }

                    continuation.yield(self.makeContacts(from: documents, currentUserID: currentUserID))
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
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
            avatarURL: data["avatarURL"] as? String,
            username: data["username"] as? String,
            mutedNotificationUserIDs: data["mutedNotificationUserIDs"] as? [String] ?? [],
            sharedLocation: nil
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

            var userPayload: [String: Any] = [
                "id": user.id,
                "displayName": user.displayName,
                "email": user.email,
                "avatarSystemName": user.avatarSystemName,
                "username": username,
                "usernameLowercased": normalizedUsername,
                "updatedAt": Timestamp(date: .now)
            ]

            if let avatarURL = user.avatarURL, !avatarURL.isEmpty {
                userPayload["avatarURL"] = avatarURL
            } else {
                userPayload["avatarURL"] = FieldValue.delete()
            }

            transaction.setData(userPayload, forDocument: usersRef, merge: true)

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
            avatarURL: user.avatarURL,
            username: username,
            mutedNotificationUserIDs: user.mutedNotificationUserIDs
        )
    }

    func updateAvatar(imageData: Data, for user: AppUser) async throws -> AppUser {
#if canImport(FirebaseStorage)
        let normalizedData = await normalizedImageDataOffMain(from: imageData)
        let storageRef = Storage.storage().reference().child("avatars/\(user.id)/\(UUID().uuidString).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await storageRef.putDataAsync(normalizedData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()

        let updatedUser = AppUser(
            id: user.id,
            displayName: user.displayName,
            email: user.email,
            avatarSystemName: user.avatarSystemName,
            avatarURL: downloadURL.absoluteString,
            username: user.username,
            mutedNotificationUserIDs: user.mutedNotificationUserIDs
        )

        let usersRef = db.collection("users").document(user.id)
        try await usersRef.setData([
            "avatarURL": downloadURL.absoluteString,
            "updatedAt": Timestamp(date: .now)
        ], merge: true)

        let friendsSnapshot = try await usersRef.collection("friends").getDocuments()
        try await propagateAvatarUpdate(updatedUser, friendIDs: friendsSnapshot.documents.map(\.documentID))

        return updatedUser
#else
        _ = imageData
        throw ContactServiceError.avatarUploadUnavailable
#endif
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
            avatarURL: userData["avatarURL"] as? String,
            username: userData["username"] as? String,
            mutedNotificationUserIDs: userData["mutedNotificationUserIDs"] as? [String] ?? []
        )
    }

    func setNotificationsMuted(_ isMuted: Bool, for mutedUserID: String) async throws -> [String] {
        guard let currentUserID = currentUserProvider()?.id else { return [] }

        let userRef = db.collection("users").document(currentUserID)
        let update: [String: Any] = [
            "mutedNotificationUserIDs": isMuted
                ? FieldValue.arrayUnion([mutedUserID])
                : FieldValue.arrayRemove([mutedUserID]),
            "updatedAt": Timestamp(date: .now)
        ]

        try await userRef.setData(update, merge: true)

        let updatedDocument = try await userRef.getDocument()
        return updatedDocument.data()?["mutedNotificationUserIDs"] as? [String] ?? []
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

        if let avatarURL = user.avatarURL, !avatarURL.isEmpty {
            payload["avatarURL"] = avatarURL
        }

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
                        avatarURL: data["avatarURL"] as? String,
                        username: data["username"] as? String
                    ),
                    sentAt: (document["sentAt"] as? Timestamp)?.dateValue() ?? .now
                )
            )
        }

        return requests
    }

    private func makeContacts(from documents: [QueryDocumentSnapshot], currentUserID: String) -> [AppUser] {
        documents.compactMap { document in
            let id = (document["id"] as? String) ?? document.documentID

            guard let displayName = document["displayName"] as? String,
                  let email = document["email"] as? String,
                  id != currentUserID else {
                return nil
            }

            let sharedLocation: SharedLocation?
            if let rawLocation = document["sharedLocation"] as? [String: Any],
               let latitude = rawLocation["latitude"] as? Double,
               let longitude = rawLocation["longitude"] as? Double {
                sharedLocation = SharedLocation(
                    latitude: latitude,
                    longitude: longitude,
                    updatedAt: (rawLocation["updatedAt"] as? Timestamp)?.dateValue() ?? .now,
                    horizontalAccuracy: rawLocation["horizontalAccuracy"] as? Double
                )
            } else {
                sharedLocation = nil
            }

            return AppUser(
                id: id,
                displayName: displayName,
                email: email,
                avatarSystemName: document["avatarSystemName"] as? String ?? "person.crop.circle.fill",
                avatarURL: document["avatarURL"] as? String,
                username: document["username"] as? String,
                sharedLocation: sharedLocation
            )
        }
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
                        avatarURL: data["avatarURL"] as? String,
                        username: data["username"] as? String
                    ),
                    sentAt: (document["sentAt"] as? Timestamp)?.dateValue() ?? .now
                )
            )
        }

        return requests
    }

    private func propagateAvatarUpdate(_ user: AppUser, friendIDs: [String]) async throws {
        guard !friendIDs.isEmpty else { return }

        for chunkStart in stride(from: 0, to: friendIDs.count, by: 400) {
            let batch = db.batch()
            let chunkEnd = min(chunkStart + 400, friendIDs.count)
            for friendID in friendIDs[chunkStart..<chunkEnd] {
                let friendRef = db
                    .collection("users")
                    .document(friendID)
                    .collection("friends")
                    .document(user.id)
                var payload: [String: Any] = [
                    "updatedAt": Timestamp(date: .now)
                ]
                if let avatarURL = user.avatarURL, !avatarURL.isEmpty {
                    payload["avatarURL"] = avatarURL
                } else {
                    payload["avatarURL"] = FieldValue.delete()
                }
                batch.setData(payload, forDocument: friendRef, merge: true)
            }
            try await batch.commit()
        }
    }

    private func normalizedImageDataOffMain(from imageData: Data) async -> Data {
        await Task.detached(priority: .userInitiated) {
            Self.normalizedImageData(from: imageData)
        }.value
    }

    nonisolated private static func normalizedImageData(from imageData: Data) -> Data {
        let maxUploadBytes = 4_500_000

        guard let image = UIImage(data: imageData) else {
            return imageData
        }

        let preparedImage = resizedImageIfNeeded(image, maxDimension: 1_600) ?? image
        let compressionQualities: [CGFloat] = [0.82, 0.7, 0.58, 0.46, 0.34, 0.24]

        for quality in compressionQualities {
            if let jpegData = preparedImage.jpegData(compressionQuality: quality),
               jpegData.count <= maxUploadBytes {
                return jpegData
            }
        }

        return preparedImage.jpegData(compressionQuality: 0.2) ?? imageData
    }

    nonisolated private static func resizedImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let size = image.size
        let largestSide = max(size.width, size.height)

        guard largestSide > maxDimension else {
            return image
        }

        let scale = maxDimension / largestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

enum ContactServiceError: LocalizedError {
    case usernameTaken
    case usernameUpdateFailed
    case avatarUploadUnavailable

    var errorDescription: String? {
        switch self {
        case .usernameTaken:
            return "Этот никнейм уже занят."
        case .usernameUpdateFailed:
            return "Не удалось сохранить никнейм."
        case .avatarUploadUnavailable:
            return "Загрузка аватара недоступна. Добавьте Firebase Storage в проект."
        }
    }
}
