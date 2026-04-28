import CryptoKit
import FirebaseCore
import FirebaseFirestore
import Foundation
import Security

struct EncryptedChatTextPayload {
    let ciphertextBase64: String
    let encryptionVersion: Int
}

enum ChatEncryptionError: LocalizedError {
    case missingRecipientPublicKey
    case invalidRecipientPublicKey
    case invalidCiphertext
    case decryptionFailed
    case keyPersistenceFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingRecipientPublicKey:
            return "У собеседника пока нет ключа шифрования. Попросите его открыть приложение после обновления."
        case .invalidRecipientPublicKey:
            return "Не удалось проверить ключ шифрования собеседника."
        case .invalidCiphertext:
            return "Сообщение повреждено или сохранено в неподдерживаемом формате."
        case .decryptionFailed:
            return "Не удалось расшифровать сообщение."
        case .keyPersistenceFailed:
            return "Не удалось сохранить ключ шифрования на устройстве."
        }
    }
}

final class ChatEncryptionService {
    static let shared = ChatEncryptionService()

    private let keychainTag = "com.caller.chat.identity.privatekey"
    private let firestore = Firestore.firestore()
    private let encryptionVersion = 1
    private let hkdfSalt = Data("caller.chat.hkdf.v1".utf8)

    private init() {}

    func currentPublicKeyBase64() throws -> String {
        let privateKey = try loadOrCreatePrivateKey()
        return privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    func ensureCurrentUserPublicKeyIsPublished(userID: String) async {
        guard FirebaseApp.app() != nil,
              let publicKeyBase64 = try? currentPublicKeyBase64() else {
            return
        }

        do {
            try await firestore.collection("users").document(userID).setData([
                "chatEncryptionPublicKey": publicKeyBase64,
                "chatEncryptionVersion": encryptionVersion,
                "updatedAt": Timestamp(date: .now)
            ], merge: true)
        } catch {
            Logger().error("Failed to publish chat encryption public key: \(error.localizedDescription)")
        }
    }

    func encryptText(
        _ plaintext: String,
        with recipientPublicKeyBase64: String,
        conversationID: String
    ) throws -> EncryptedChatTextPayload {
        let privateKey = try loadOrCreatePrivateKey()
        let recipientPublicKey = try makePublicKey(from: recipientPublicKeyBase64)
        let symmetricKey = try symmetricKey(
            privateKey: privateKey,
            peerPublicKey: recipientPublicKey,
            conversationID: conversationID
        )
        let sealedBox = try AES.GCM.seal(Data(plaintext.utf8), using: symmetricKey)

        guard let combined = sealedBox.combined else {
            throw ChatEncryptionError.invalidCiphertext
        }

        return EncryptedChatTextPayload(
            ciphertextBase64: combined.base64EncodedString(),
            encryptionVersion: encryptionVersion
        )
    }

    func decryptText(
        _ ciphertextBase64: String,
        with recipientPublicKeyBase64: String,
        conversationID: String
    ) throws -> String {
        let privateKey = try loadOrCreatePrivateKey()
        let recipientPublicKey = try makePublicKey(from: recipientPublicKeyBase64)
        let symmetricKey = try symmetricKey(
            privateKey: privateKey,
            peerPublicKey: recipientPublicKey,
            conversationID: conversationID
        )

        guard let combinedData = Data(base64Encoded: ciphertextBase64) else {
            throw ChatEncryptionError.invalidCiphertext
        }

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
            guard let plaintext = String(data: decryptedData, encoding: .utf8) else {
                throw ChatEncryptionError.decryptionFailed
            }
            return plaintext
        } catch {
            throw ChatEncryptionError.decryptionFailed
        }
    }

    private func symmetricKey(
        privateKey: P256.KeyAgreement.PrivateKey,
        peerPublicKey: P256.KeyAgreement.PublicKey,
        conversationID: String
    ) throws -> SymmetricKey {
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: hkdfSalt,
            sharedInfo: Data(conversationID.utf8),
            outputByteCount: 32
        )
    }

    private func makePublicKey(from base64: String) throws -> P256.KeyAgreement.PublicKey {
        guard let data = Data(base64Encoded: base64) else {
            throw ChatEncryptionError.invalidRecipientPublicKey
        }

        do {
            return try P256.KeyAgreement.PublicKey(rawRepresentation: data)
        } catch {
            throw ChatEncryptionError.invalidRecipientPublicKey
        }
    }

    private func loadOrCreatePrivateKey() throws -> P256.KeyAgreement.PrivateKey {
        if let existingData = try loadPrivateKeyData(),
           let privateKey = try? P256.KeyAgreement.PrivateKey(rawRepresentation: existingData) {
            return privateKey
        }

        let privateKey = P256.KeyAgreement.PrivateKey()
        try storePrivateKeyData(privateKey.rawRepresentation)
        return privateKey
    }

    private func loadPrivateKeyData() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw ChatEncryptionError.keyPersistenceFailed(status)
        }
    }

    private func storePrivateKeyData(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainTag
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw ChatEncryptionError.keyPersistenceFailed(updateStatus)
        }

        var creationAttributes = query
        attributes.forEach { creationAttributes[$0.key] = $0.value }
        let creationStatus = SecItemAdd(creationAttributes as CFDictionary, nil)
        guard creationStatus == errSecSuccess else {
            throw ChatEncryptionError.keyPersistenceFailed(creationStatus)
        }
    }
}
